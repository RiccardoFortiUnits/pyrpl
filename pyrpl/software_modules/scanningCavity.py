

from collections import OrderedDict
from qtpy import QtCore
import logging
from ..modules import SignalLauncher
from ..module_attributes import ModuleListProperty, Module
from ..widgets.module_widgets import LockboxWidget
from ..pyrpl_utils import all_subclasses
from . import LockboxModule, LockboxModuleDictProperty
from . import LockboxLoop, LockboxPlotLoop
from ..widgets.module_widgets.lockbox_widget import LockboxSequenceWidget
from pyrpl.async_utils import wait, sleep_async, sleep, ensure_future, Event
import time
from ..acquisition_module import AcquisitionModule, SignalLauncherAcquisitionModule
from ..async_utils import wait, ensure_future, sleep_async
from ..pyrpl_utils import sorted_dict
from ..attributes import *
from ..modules import HardwareModule
from ..pyrpl_utils import time
from ..widgets.module_widgets import ScopeWidget
import asyncio

from ..hardware_modules.scope import Scope, DurationProperty
from ..hardware_modules.asg import Asg0
from ..hardware_modules.pid import Pid
from ..hardware_modules.hk import HK
from ..hardware_modules.dsp import DSP_TRIGGERS
from ..widgets.module_widgets.scanCavity_widget import ScanCavity_widget, peak_widget, secondaryPitaya_widget


nOfSecondaryPeaks = 4

class SignalLauncherPeak(SignalLauncherAcquisitionModule):
	'''combination of the signal launchers for acquisition and pid 
	(to have the ival widget update automatically). It's the same 
	script as the pid signal launcher, but the parent class is 
	SignalLauncherAcquisitionModule instead of SignalLauncher'''
	update_ival = QtCore.Signal()
	# the widget decides at the other hand if it has to be done or not
	# depending on the visibility
	def __init__(self, module):
		super(SignalLauncherPeak, self).__init__(module)
		self.timer_ival = QtCore.QTimer()
		self.timer_ival.setInterval(1000)  # max. refresh rate: 1 Hz
		self.timer_ival.timeout.connect(self.update_ival)
		self.timer_ival.setSingleShot(False)
		self.timer_ival.start()

	def _clear(self):
		"""
		kill all timers
		"""
		self.timer_ival.stop()
		super(SignalLauncherPeak, self)._clear()

class peakValue(FloatProperty):
	'''property to access a specific numeric property of a peak (min time, max time...).'''
	def __init__(self, propertyAccessor = lambda peak: f"minTime{peak.index+1}", **kwargs):
		super().__init__( **kwargs)
		self.propertyAccessor = propertyAccessor
	def set_value(self, obj, val):
		if obj.peakType == "secondary":
			setattr(obj.redpitaya.scope, self.propertyAccessor(obj), val)
		else:
			for pitaya in obj.scanningCavity.usedPitayas:
				setattr(pitaya.scope, self.propertyAccessor(obj), val)
		return super().set_value(obj, val)
	def get_value(self, obj):
		return getattr(obj.redpitaya.scope, self.propertyAccessor(obj))
class peakInput(SelectProperty):
	'''property that specifies the input signal of a peak. It's similar to a peakValue, but it's a select property instead of a float property'''
	def inputName(self, obj):
		return f"{obj.redpitaya.scope.peakNames[obj.index]}_input"
	def set_value(self, obj, val):
		if obj.peakType == "secondary":
			setattr(obj.redpitaya.scope, self.inputName(obj), val)
		else:
			for pitaya in obj.scanningCavity.usedPitayas:
				setattr(pitaya.scope, self.inputName(obj), val)
		return super().set_value(obj, val)
	def get_value(self, obj):
		return getattr(obj.redpitaya.scope, self.inputName(obj))
	def options(self, instance=None):
		return getattr(Scope, self.inputName(instance)).options(instance.redpitaya.scope)

class peakSetpoint(FloatProperty):
	'''property that specifies the setpoint of the PID module in charge of locking a peak. 
	Since the PID setpoints are adimensional values, but when acting on peak positions we 
	would like to work with times, this property handles converting the timings into 
	adimensional values, and viceversa. Also, it checks if the current peak is to be 
	normalized, to correctly convert into the correct adimensional range
	
	Usually the setpoint is put in between the left and right edges of the peak'''
	def get_value(self, obj):
		normalizedSetpointValue = (obj.setpoint + 1) * 0.5
		if obj.index >= 2 and obj.normalizeIndex:
			L, R = self.getMainPeaks(obj)
			return L + (R - L) * normalizedSetpointValue
		duration = obj.scanningCavity.duration
		return normalizedSetpointValue * duration
	def set_value(self, obj, val):
		if obj.index >= 2 and obj.normalizeIndex:
			#normalized peak, the setpoint is normalized between the 2 main peaks (so, -1 would mean that the setpoint coincides with the left main peak, 1 means that the setpoint coincides with the right main peak)
			L, R = self.getMainPeaks(obj)
			if R != L:
				normalizedSetpointValue = (val - L) / (R - L)
				valueBetween_m1_and_1 = normalizedSetpointValue * 2 - 1
				obj.setpoint = valueBetween_m1_and_1
			else:
				obj.setpoint = 0
		else:
			#non normalized peak
			duration = obj.scanningCavity.duration
			normalizedSetpointValue = val / duration
			valueBetween_m1_and_1 = normalizedSetpointValue * 2 - 1
			obj.setpoint = valueBetween_m1_and_1
		return super().set_value(obj, val)
	
	def getMainPeaks(self, obj):
		L = obj.scanningCavity.mainL.timeSetpoint
		R = obj.scanningCavity.mainR.timeSetpoint
		return L, R


class asgSelector(SelectProperty):
	'''property that specifies the asg module to be used for the cavity scan. when changed, it updates the input signal of ch1 of the scope, the selected asg (waveform, frequency, offset, amplitude...)'''
	def __init__(self, options, **kwargs):
		super().__init__(options, **kwargs)

	def set_value(self, obj, value):
		scope : Scope = obj.mainPitaya.scope
		scope.trigger_source = value
		oldValues = (obj.output_direct,obj.trigger_source)
		obj.output_direct = "off"
		ret = super().set_value(obj, value)
		obj.updateRamp(oldValues)
		obj.main_acquisitionTrigger = obj.main_acquisitionTrigger

		return ret
	
class mainTriggerSelector(nullableDigitalPinProperty):
	'''this property sets the digital pin of the main pitaya that will trigger the other pitaya's scopes. So, connect pin of the main redPitaya (specified in main_acquisitionTrigger(mainTriggerSelector)) to each selected pin of the secondary redPitayas (acquisitionTrigger(scopeTriggerSelector))'''
	def set_value(self, obj, val):
		val = nullableDigitalPinProperty.pinIndexToString(val)
		if val is None:
			return super().set_value(obj, val)
		ret = super().set_value(obj, val)
		hk : HK = obj.mainPitaya.hk
		selectedAsg = obj.usedAsg
		setattr(hk, f"expansion_{val}_output", 1)
		setattr(hk, f"pinState_{val}", "dsp")
		setattr(hk, f"external_{val}_dspBitSelector", DSP_TRIGGERS[f"{selectedAsg}_trigger"])
		obj.updateAomRamp()
		return ret 

class scopeTriggerSelector(nullableDigitalPinProperty):
	'''this property sets the digital pin that trigger the scope acquisition. Can also be used for the main pitaya, if the ramp trigger is external'''
	def set_value(self, obj, val):
		val = nullableDigitalPinProperty.pinIndexToString(val)
		if val is None:
			return super().set_value(obj, val)
		hk : HK = obj.rp.hk
		setattr(hk, f"expansion_{val}_output", 0)

		scope : Scope = obj.rp.scope
		scope.external_trigger_pin = val
		return super().set_value(obj, val)

class peakActivatingBitSelector(nullableDigitalPinProperty):
	'''this property sets the digital pin that will enable the AOM responsible for shutting down the laser when it is not its turn'''
	def set_value(self, obj, val):
		oldEnabled = obj.enabled
		if obj.isOverlappingWithMainPeaks():
			return False
			raise Exception("cannot enable this peak when its range is overlapping with the main peaks")
		
		if obj.peakType == "main_R":
			print("cannot change main R activating pin")
			return
		oldEnabled = obj.active
		val = nullableDigitalPinProperty.pinIndexToString(val)
		if val is None:
			return super().set_value(obj, val)
		hk : HK = obj.redpitaya.hk
		setattr(hk, f"expansion_{val}_output", 1)
		# setattr(hk, f"pinState_{val}", "dsp" if oldEnabled else "memory")  #already done by obj.active
		# setattr(hk, f"expansion_{val}", 0)
		if obj.peakType == "main_L":
			#this bit turns on when the left or the right peaks are active
			setattr(hk, f"external_{val}_dspBitSelector", DSP_TRIGGERS[f"inPeakRange_1_or_2"])
		else:
			setattr(hk, f"external_{val}_dspBitSelector", DSP_TRIGGERS[f"inPeakRange_{obj.index + 1}"])
		ret = super().set_value(obj, val)
		obj.active = oldEnabled
		return ret

class activatePeakProperty(SelectProperty):
	'''this property allows to set the enabling of the AOM responsible for shutting down the laser 
	when it is not its turn'''
	def __init__(self, **kwargs):
		super().__init__({True: True, False: False, "always_active":"always_active"}, **kwargs)
	def set_value(self, obj, val):
		if obj.isOverlappingWithMainPeaks():
			return False
			raise Exception("cannot enable this peak when its range is overlapping with the main peaks")
		index = nullableDigitalPinProperty.pinIndexToString(obj.enablingBit)
		if index is None:
			return super().set_value(obj, val)
		hk = obj.redpitaya.hk
		if isinstance(val, bool):
			setattr(hk, f"pinState_{index}", "dsp" if val else "memory")
			setattr(hk, f"expansion_{index}", 0)
		else:
			setattr(hk, f"pinState_{index}", "memory")
			setattr(hk, f"expansion_{index}", 1)

		# obj.paused = not (obj.locking & val)
		return super().set_value(obj, val)
		
class rampVoltageEdge(FloatProperty):
	'''property to set the low and high edges of an asg signal. Use makeLowerAndUpperEdges() to create 2 
	connected edges, which will not cross each other (for example, trying to set on the lower edge a 
	value higher than the current edge will not be permitted)'''
	@staticmethod
	def makeLowerAndUpperEdges(asgObject, **kwargs):
		return rampVoltageEdge._classGeneric_makeLowerAndUpperEdges(rampVoltageEdge, asgObject, **kwargs)
	@staticmethod
	def _classGeneric_makeLowerAndUpperEdges(cls, asgObject, **kwargs):
		low = cls(asgObject, None, True, **kwargs)
		high = cls(asgObject, low, False, **kwargs)
		low.otherEdge = high
		return low, high
	def __init__(self, asgObject, otherEdge = None, isLowerEdge = True, min=-np.inf, max=np.inf, increment=0, log_increment=False, **kwargs):
		super().__init__(min, max, increment, log_increment, **kwargs)
		self.otherEdge = otherEdge
		self.isLowerEdge = isLowerEdge
		self.asgObject = asgObject

	def validate_and_normalize(self, obj, value):
		if self.isLowerEdge:
			value = min(value, self.otherEdge.get_value(obj))
		else:
			value = max(value, self.otherEdge.get_value(obj))
		return super().validate_and_normalize(obj, value)
	@staticmethod
	def getLowHigFromAmpOffs(amp, offs):
		return offs - amp, offs + amp
	@staticmethod
	def getAmpOffsFromLowHigh(low, high):
		return .5 * (high - low), .5 * (high + low)
	
	def set_value(self, obj, val):
		otherValue = self.otherEdge.get_value(obj)
		lowHigh = (val, otherValue) if self.isLowerEdge else (otherValue, val)
		amp, offs = rampVoltageEdge.getAmpOffsFromLowHigh(*lowHigh)
		asg = getattr(obj, self.asgObject)
		asg.amplitude = amp
		asg.offset = offs
		return super().set_value(obj, val)
	def get_value(self, obj):		
		asg = getattr(obj, self.asgObject)
		amp = asg.amplitude
		offs = asg.offset
		low, high = rampVoltageEdge.getLowHigFromAmpOffs(amp, offs)
		return low if self.isLowerEdge else high
class autoScaleRampVoltageEdge(rampVoltageEdge):
	
	@staticmethod
	def makeLowerAndUpperEdges(asgObject, **kwargs):
		return rampVoltageEdge._classGeneric_makeLowerAndUpperEdges(autoScaleRampVoltageEdge, asgObject, **kwargs)
	def set_value(self, obj, val):
		'''
			we have this correlation between the peak range timings and voltages

			time		0		aT	bT		T
			voltage		v0		va	vb		v1

			we can calculate va as va = v0 + a * (v1-v0)
			
			if now we change the span of the scan, we will have new voltages associated with time 0 and T, namely v2 and v3. but the voltages of the peak range shouldn't change. So we have
			
			time		0		a'T	b'T		T
			voltage		v2		va	vb		v3

			From which we obtain that a' = (v0 - v2 + a * (v1-v0)) / (v3-v2)
		'''
		if obj.autoscale_peaks:
			obj:ScanningCavity=obj
			currentValue = self.get_value(obj)
			otherValue = self.otherEdge.get_value(obj)
			v0, v1 = (currentValue, otherValue) if self.isLowerEdge else (otherValue, currentValue)
			v2, v3 = (val, otherValue) if self.isLowerEdge else (otherValue, val)
			peakRanges = np.array([[p.left, p.right] for p in obj.usedPeaks])
			T = obj.duration
			peakRatios = peakRanges / T#normalize to respect to T
			newPeakRatios = (v0 - v2 + peakRatios * (v1-v0)) / (v3-v2)
			peakRanges_newTimings = np.clip(newPeakRatios,0,1) * T
			for i, p in enumerate(obj.usedPeaks):
				p.setLeftAndRight(*peakRanges_newTimings[i])
		return super().set_value(obj, val)
	
class asgAmplitudeSelector(FloatProperty):
	#since the asg can either be the first or second asg, and since they are treated as different classes, we have to make a custom wrapper to choose the correct asg 
	def __init__(self, **kwargs):
		baseProperty = Asg0.amplitude
		super().__init__(min=baseProperty.min, max=baseProperty.max, increment=baseProperty.increment, log_increment=baseProperty.log_increment, **kwargs)
	def set_value(self, obj, val):
		obj : ScanningCavity = obj
		asg=obj.piezoAsg
		asg.amplitude = val
		return super().set_value(obj, val)
class asgOffsetSelector(FloatProperty):
	#since the asg can either be the first or second asg, and since they are treated as different classes, we have to make a custom wrapper to choose the correct asg 
	def __init__(self, **kwargs):
		baseProperty = Asg0.offset
		super().__init__(min=baseProperty.min, max=baseProperty.max, increment=baseProperty.increment, log_increment=baseProperty.log_increment, **kwargs)
	def set_value(self, obj, val):
		obj : ScanningCavity = obj
		asg=obj.piezoAsg
		asg.offset = val
		return super().set_value(obj, val)


class normalizeIndexProperty(BoolProperty):
	'''this property sets if the selected secondary peak has a normalized setpoint or not. 
	Enable the normalization when the peak should move accordingly to the main peaks (for example 
	if the cavity is locked to a reference laser)'''
	def set_value(self, obj, val):
		if obj.index < 2:
			return False
			raise Exception("cannot set a main peak as normalized")
		if obj.isOverlappingWithMainPeaks(checkIfPeakIsCurrentlyNormalized = False):
			return False
			raise Exception("cannot set this peak to be normalized, because it is overlapping with the main peaks")
		super().set_value(obj, val)
		oldSetpoint = obj.timeSetpoint
		ret = setattr(obj.redpitaya.scope, f"{obj.redpitaya.scope.peakNames[obj.index]}_normalizeIndex", val)
		obj.timeSetpoint = oldSetpoint
		return ret
	
	def get_value(self, obj):
		if obj.index < 2:
			return 0
		return getattr(obj.redpitaya.scope, f"{obj.redpitaya.scope.peakNames[obj.index]}_normalizeIndex"
				 )
class peakEnablingProperty(BoolProperty):
	'''property that calls the function peak.setActiveAndPaused(), to correctly toggle the active and paused properties'''
	def set_value(self, obj, val):
		ret = super().set_value(obj, val)
		obj.setActiveAndPaused()
		return ret
class peakLockingProperty(BoolProperty):
	def set_value(self, obj, val):
		obj.setupPid()
		ret = super().set_value(obj, val)
		obj.setActiveAndPaused()
		return ret

class scanAmplitudeSelectorProperty(SelectProperty):
	def __init__(self, **kwargs):
		super().__init__(options = ["constant", "from mainR control"], **kwargs)
	def set_value(self, obj, value):
		obj : ScanningCavity = obj
		if value == self.get_value(obj):
			return super().set_value(obj, value)
		if value == "constant":
			obj.mainR.locking = False
			obj.scan_ampl = obj.mainR.ival
			obj.piezoAsg.amplitude_source = "from memory"
		else:
			obj.mainR.ival = obj.scan_ampl
			obj.mainR.locking = True
			obj.piezoAsg.amplitude_signal = obj.mainR.pid.name
			obj.piezoAsg.amplitude_source = "from signal"

		return super().set_value(obj, value)

class peak(Module):
	'''submodule for the handling of a peak detection and lockin. it can be used for both the main peaks and secondary peaks. 
	The peak is specified with the parent redPitaya and the peak index. Index 0 is for the left main peak, 1 for the right 
	main peak, and 2 and above are for the normalizable peaks'''
	_gui_attributes = [
					"enablingBit",
					"alwaysActive",
					"enabled",
					"locking",
					"normalizeIndex",#can be removed by manually by peak_widget, it stays only for the normalizable peaks
					"min_voltage",
					"max_voltage",
					"timeSetpoint",
					"left",
					"right",
					"center",
					"size",
					# "rangeSelector",
					"height",
					"p",
					"i",
					"ival",
					"input",
					"output_direct",
					"enablingBit",
					"alwaysActive",
					"enabled",
					"locking",
					"normalizeIndex",#can be removed by manually by peak_widget, it stays only for the normalizable peaks
					"peakColor",
					]
	_setup_attributes = _gui_attributes
	_widget_class = peak_widget

	_signal_launcher = SignalLauncherPeak
	def __init__(self, redpitaya, index, scanningCavity, name=None):
		super().__init__(redpitaya, name)
		self.scanningCavity = scanningCavity
		self.index = index
		self.pid = redpitaya.pids.all_modules[index % len(redpitaya.pids.all_modules)]
		self.input
		self.addToSubmodules()
	 
	left = peakValue(lambda peak: f"minTime{peak.index+1}", min = 0)
	right = peakValue(lambda peak: f"maxTime{peak.index+1}")
	rangeSelector = rangeProperty([left, right], 'left+right')
	left, right, center, size = (rangeSelector.left, rangeSelector.right, rangeSelector.center, rangeSelector.ampl)
	
	height = peakValue(lambda peak: f"{peak.redpitaya.scope.peakNames[peak.index]}_minValue")
	input = peakInput()
	normalizeIndex = normalizeIndexProperty()
	'''let's talk about "enabling" a peak. There are 3 levels of enabling:
		- always_active: the the pin specified by self.enablingBit is always on (as if the range of the peak was the entire scan)
		- active: the pin specified by self.enablingBit toggles when the peak is in its range of the scan
		- locking: the PI control is running (not paused), so if the parameters are correct, the peak should 	
			follow the setpoint (center of the range). When it's toggled, the PI module should be reset
		the peak can be locking only if it is active. You can use a peak active but not locking when you 
		are adding a new peak to the cavity, and you don't know where it might be
		There are a bunch of "virtual" enabling bits, which indirectly control the 2 physical bits: self.active and self.paused.
		For now, these 2 bits are calculated as follows:
		- active = enabled & inCurrentPeakGroup
		- paused = ! (active & locking)
		inCurrentPeakGroup is a bit controlled by the UI to avoid overlapping between active peaks. If there's 
		no overlap, this flag is always active'''
	enablingBit = peakActivatingBitSelector()
	active = activatePeakProperty()
	enabled = peakEnablingProperty()
	alwaysActive = peakEnablingProperty()
	inCurrentPeakGroup = peakEnablingProperty()
	locking = peakLockingProperty()

	p = DynamicInstanceProperty(Pid.p, lambda peak : peak.pid)
	i = DynamicInstanceProperty(Pid.i, lambda peak : peak.pid)
	paused = DynamicInstanceProperty(Pid.paused, lambda peak : peak.pid)
	ival = DynamicInstanceProperty(Pid.ival, lambda peak : peak.pid)
	min_voltage = DynamicInstanceProperty(Pid.min_voltage, lambda peak : peak.pid)
	max_voltage = DynamicInstanceProperty(Pid.max_voltage, lambda peak : peak.pid)
	output_direct = DynamicInstanceProperty(Pid.output_direct, lambda peak : peak.pid)
	'''setpoint is the actual value of the PID setpoint (value between -1 and 1, 
	where -1 represents the lower timing for the peak, either
		0 for the main peaks or non-normalized secondary peaks
		mainL for the normalized secondary peaks
	and 1 represents either
		mainScope.duration for the main peaks or non-normalized secondary peaks
		mainR for the normalized secondary peaks
	)
	timeSetpoint is the time corresponding to the PID setpoint'''
	setpoint = DynamicInstanceProperty(Pid.setpoint, lambda peak : peak.pid)
	timeSetpoint = peakSetpoint(min = 0)

	peakColor = ColorProperty()

	def setLeftAndRight(self, left, right):
		if self.right < left:
			self.right = right
			self.left = left
		else:
			self.left = left
			self.right = right
	def setActiveAndPaused(self):
		self.active = "always_active" if self.alwaysActive else (self.enabled and self.inCurrentPeakGroup)
		active_boolean = self.active if isinstance(self.active, bool) else True
		self.paused = not (active_boolean & self.locking)
	def isOverlappingWithMainPeaks(self, checkIfPeakIsCurrentlyNormalized = True):
		#checkIfPeakIsCurrentlyNormalized is only used when we are checking if we can set self.normalizeIndex 
		# to True (and so self.normalizeIndex would likely be False at the moment)
		if self.peakType != "secondary" or (checkIfPeakIsCurrentlyNormalized and not self.normalizeIndex):
			return False
		def areIntersecting(peak0, peak1):
			range0 = peak0.left, peak0.right
			range1 = peak1.left, peak1.right
			return (range0[0] < range1[1]) ^ (range0[1] <= range1[0])
		return areIntersecting(self, self.scanningCavity.mainL) and \
				areIntersecting(self, self.scanningCavity.mainR)

	def setupPid(self):
		# self.pid.ival=0
		self.pid.setpoint_source="from memory"
		self.pid.pause_gains="pi"
		self.pid.input = f"peak_idx{self.index+1}"
	
	def togglePID(self):
		'''also returns if the PID was activated or not'''
		if self.locking:
			self._deactivatePID()
		else:
			self._activatePID()
		return self.locking

	def _activatePID(self):
		if self.active:
			if self.isOverlappingWithMainPeaks():
				return False
				raise Exception("cannot enable the secondary peak when its range is overlapping with the main peaks")
			self.setupPid()
			self.locking = True
		else:
			self.locking = False
		# self.paused = not (self.locking & self.active)

	def _deactivatePID(self):
		self.setupPid()
		self.locking = False
		# self.paused = not (self.locking & self.active)

	@staticmethod
	def allUnusedSecondaryPeaks(scanCavity):
		peaks = scanCavity.allAvailableSecondaryPeaks()
		return [p for p in peaks if p not in scanCavity.usedPeaks]
		
	pitaya_n_index = SelectProperty(allUnusedSecondaryPeaks)

	@property
	def peakType(self):
		if self.index < 2:
			return ["main_L", "main_R"][self.index]
		return "secondary"
	def __eq__(self, other):
		if not isinstance(other, peak):
			return NotImplemented
		return self.redpitaya == other.redpitaya and self.index == other.index

	def __hash__(self):
		return hash((self.redpitaya, self.index))
	
	def setLeft(self, newTiming):
		setattr(self.redpitaya.scope, f"minTime{self.index+1}", newTiming)
	def setRight(self, newTiming):
		setattr(self.redpitaya.scope, f"maxTime{self.index+1}", newTiming)
	def setHeight(self, newTiming):
		setattr(self.redpitaya.scope, f"{self.redpitaya.scope.peakNames[self.index]}_minValue", newTiming)

	
	# @staticmethod
	# def getGroupsOfNonOverlapping(peakList):
	# 	ranges = [(p.minTime, p.maxTime) for p in peakList]
	# 	def areIntersecting(range0, range1):
	# 		return (range0[0] < range1[1]) ^ (range0[1] <= range1[0])
	# 	intersections = np.zeros((len(ranges), len(ranges)), dtype=bool)
	# 	for i in range(len(ranges)):
	# 		for j in range(len(ranges)):
	# 			intersections[i,j] = areIntersecting(ranges[i], ranges[j])
	# 	stillFree = np.arange(len(ranges))
	# 	allGroups = []
	# 	while len(stillFree) > 0:
	# 		run = [stillFree[0]]
	# 		addedIndexes = [0]
	# 		for i in range(1, len(stillFree)):
	# 			testedLine = np.repeat(stillFree[i],len(run))
	# 			if not np.any(intersections[testedLine, run]):
	# 				addedIndexes.append(i)
	# 				run.append(stillFree[i])
	# 		stillFree = np.delete(stillFree, addedIndexes)
	# 		allGroups.append(run)
	# 	return allGroups

class secondaryPitaya(Module):
	'''submodule for the handling of a secondary peak, to set some parameters that involve all the peaks of that same redpitaya'''
	_gui_attributes = [
					"input1",
					"acquisitionTrigger"
					]
	_setup_attributes = _gui_attributes
	_widget_class = secondaryPitaya_widget
	def __init__(self,redpitaya, scanningCavity):
		self.rp = redpitaya
		super().__init__(scanningCavity, name=redpitaya.name)
		self.addToSubmodules()
		# self.controlPeak1 = peak(self, 2, scanningCavity, f"{self.rp.name}_controlled1")
		# scanningCavity.usedPeaks += [self.controlPeak1]
	input1 = DynamicInstanceProperty(Scope.input1, lambda secondaryPitaya : secondaryPitaya.rp.scope)
	acquisitionTrigger = scopeTriggerSelector()

class ScanningCavity(AcquisitionModule):

	_setup_attributes = ["duration",
					"input1",
					"ch1_invert",
					"usedAsg",
					"usedScanAmplitude",
					# "lowValue", 
					# "highValue",
					# "asgRange",
					# "autoscale_peaks",
					"scan_ampl",
					"scan_offs",

					"trigger_source",
					"output_direct",
					"main_acquisitionTrigger",
					"threshold",
					"hysteresis",
					# "aom_lowValue",
					# "aom_highValue",
					]
	_gui_attributes = _setup_attributes
	_widget_class = ScanCavity_widget
	_module_attributes = ["mainL","mainR"]
	


	def __init__(self, parent, name=None):
		super().__init__(parent, name)
		self.usedPeaks = []
		self.secondaryPeaks = []
		self.usedPitayas = []
		self.secondaryPitayas = []
		pitayas = list(parent.rps.values())
		self.setMainPitaya(pitayas[0])
		for i in range(1, len(pitayas)):
			self.addPitaya(pitayas[i])

	def setMainPitaya(self, pitaya):
		self.mainPitaya = pitaya
		self.mainL = peak(pitaya, 0, self, "mainL")
		self.mainR = peak(pitaya, 1, self, "mainR")
		self.usedPeaks.append(self.mainL)
		self.usedPeaks.append(self.mainR)
		self.usedPitayas = [pitaya]
		#we won't be able to use 2 secondary peaks on the first pitaya (not enough outputs), so let's just use one, 
		# and let's keep the 2nd pid free for the mainR peak, which does not require a pid, but it can still be useful
		for i in range(0, nOfSecondaryPeaks-2):
			self.addSecondaryPeak(peak(pitaya, i + 2, self, f"{pitaya.name}_secondary{i}"))
		self.mainPitaya.hk.input1 = "alltriggers"
	def addPitaya(self, pitaya):
		if pitaya in self.usedPitayas:
			raise Exception("pitaya already used")
		self.usedPitayas.append(pitaya)
		self.secondaryPitayas.append(secondaryPitaya(pitaya, self))
		for i in range(nOfSecondaryPeaks):
			self.addSecondaryPeak(peak(pitaya, i + 2, self, f"{pitaya.name}_secondary{i}"))
		#the peak detectors require the trigger to be "armed". Let's arm it
		pitaya.scope._start_trace_acquisition()
		pitaya.hk.input1 = "alltriggers"

	def addSecondaryPeak(self, newPeak):
		if newPeak in self.usedPeaks:
			raise Exception("peak already used")
		self.usedPeaks.append(newPeak)
		self.secondaryPeaks.append(newPeak)
	def removeSecondaryPeak(self, peakToRemove):
		self.usedPeaks.remove(peakToRemove)
		self.secondaryPeaks.remove(peakToRemove)

	def allAvailableSecondaryPeaks(self):
		peaks = []
		for device in self.pyrpl.rps.keys():
			for i in range(nOfSecondaryPeaks):
				peaks.append(peak(device, i+2))
		return peaks
	def allUnusedSecondaryPeaks(self):
		peaks = self.allAvailableSecondaryPeaks()
		return [p for p in peaks if p not in self.usedPeaks]	

	duration = MultipleDynamicInstanceProperty(Scope.duration, lambda scanCavity : scanCavity.scopes, lambda self, instance, value : instance.updateScope())
	threshold = MultipleDynamicInstanceProperty(Scope.threshold, lambda scanCavity : scanCavity.scopes)
	hysteresis = MultipleDynamicInstanceProperty(Scope.hysteresis, lambda scanCavity : scanCavity.scopes)
	rolling_mode = MultipleDynamicInstanceProperty(Scope.rolling_mode, lambda scanCavity : scanCavity.scopes)
	#todo move into a redpitaya module
	input1 = DynamicInstanceProperty(Scope.input1, lambda scanCavity : scanCavity.mainPitaya.scope, lambda self, instance, value : instance.updateScope())
	#MultipleDynamicInstanceProperty(Scope.input1, lambda scanCavity : scanCavity.scopes)
	ch1_invert = MultipleDynamicInstanceProperty(Scope.ch1_invert, lambda scanCavity : scanCavity.scopes)

	main_acquisitionTrigger = mainTriggerSelector()
	_usableTriggers = {key : val for key,val in Scope._trigger_sources.items() if "asg" in key}

	usedAsg = asgSelector(_usableTriggers)
	usedScanAmplitude = scanAmplitudeSelectorProperty()

	# offset = DynamicInstanceProperty(Asg0.offset, lambda scanCavity : scanCavity.piezoAsg)
	# amplitude = DynamicInstanceProperty(Asg0.amplitude, lambda scanCavity : scanCavity.piezoAsg)
	# asgRange = rangeProperty([offset, amplitude], 'center+ampl')
	# lowValue, highValue = autoScaleRampVoltageEdge.makeLowerAndUpperEdges("piezoAsg", min = -1, max = 1)
	# asgRange = rangeProperty([lowValue, highValue], 'left+right')
	# lowValue, highValue, center, size = (asgRange.left, asgRange.right, asgRange.center, asgRange.ampl)

	# aom_lowValue, aom_highValue = rampVoltageEdge.makeLowerAndUpperEdges("aomAsg", min = -1, max = 1)
	# autoscale_peaks = BoolProperty(default=True, doc="If true, modifying the lowValue " \
# 		"and highValue parameters will also modify the peak ranges, so that their position " \
# 		"remains constant compared to the previous scan")
	
	scan_ampl = asgAmplitudeSelector()
	scan_offs = asgOffsetSelector()
	
	trigger_source = DynamicInstanceProperty(Asg0.trigger_source, lambda scanCavity : scanCavity.piezoAsg)
	output_direct = DynamicInstanceProperty(Asg0.output_direct, lambda scanCavity : scanCavity.piezoAsg)

	def updateScope(self):
		'''
		setup the scope to have the correct dimensions for the scan
		'''
		for scope in self.scopes:
			scope : Scope
			scope.ch1_active = True
			scope.trigger_delay = scope.duration * .5
			scope.average = False
			if scope != self.mainPitaya.scope:
				scope.trigger_source = "ext_positive_edge"
			else:
				scope.trigger_source = self.usedAsg
		self.updateRamp()
	@property
	def scopes(self):
		return [pitaya.scope for pitaya in self.usedPitayas]
	@property
	def piezoAsg(self):
		return self.mainPitaya.asg0 if self.usedAsg == "asg0" else self.mainPitaya.asg1
	@property
	def aomAsg(self):
		return self.mainPitaya.asg1 if self.usedAsg == "asg0" else self.mainPitaya.asg0
	def updateRamp(self, oldValues = None):
		asg = self.piezoAsg
		asg.waveform = "ramp"
		asg.frequency = 0.5 / self.duration * .99#let's make the ramp slightly slower, so we are sure that the sope triggers at every period
		if oldValues is not None:
			self.output_direct = oldValues[0]
			self.trigger_source = oldValues[1]
		asg.advanced_trigger_delay = self.duration / 8e-9#let's reduce the asg trigger delay (so that we can keep the synchronization even at high frequencies)

		# ScanningCavity.lowValue.value_updated(self)
		# ScanningCavity.highValue.value_updated(self)
		ScanningCavity.scan_ampl.value_updated(self)
		ScanningCavity.scan_offs.value_updated(self)
		ScanningCavity.trigger_source.value_updated(self)
		ScanningCavity.output_direct.value_updated(self)
		self.updateAomRamp(oldValues)
	def updateAomRamp(self, oldValues = None):
		asg = self.aomAsg
		asg.waveform = "halframp"
		asg.offset = -.5
		asg.frequency = 1 / self.duration
		asg.advanced_trigger_delay = self.duration / 2 / 8e-9
		if oldValues is not None and len(oldValues) > 2:
			self.output_direct = oldValues[2]
		asg.trigger_source = 'ext_positive_edge'
		asg.external_trigger_pin = self.main_acquisitionTrigger
	

			
	def _rolling_mode_allowed(self):
		return False

	def _is_rolling_mode_active(self):
		return False

	'''overwrite of asynchronous functions. They are almost identical to their original versions (defined inside AcquisitionModule), but the actual acquisition is done by the scope module'''
	async def _continuous_async(self):
		"""
		Coroutine to launch a continuous acquisition.
		"""
		s : Scope = self.mainPitaya.scope
		self._running_state = 'running_continuous'
		s._prepare_averaging()  # initializes the table self.data_avg,
		await self._do_average_continuous_async()

	async def _do_average_continuous_async(self):
		"""
		Accumulate averages based on the attributes self.current_avg and
		self.trace_average. This coroutine doesn't take care of
		initializing the data such that the module can go indifferently from
		['paused_single', 'paused_continuous'] into ['running_single',
		'running_continuous'].
		"""
		s : Scope = self.mainPitaya.scope
		while (self.running_state != 'stopped'):
			if self.running_state == 'paused_continuous':
				await s._resume_event.wait()
			s.current_avg = min(s.current_avg + 1, s.trace_average)
			s.data_avg = (s.data_avg * (s.current_avg - 1) + \
							 await s._trace_async(
								 s.MIN_DELAY_CONTINUOUS_MS * 0.001)) / \
							s.current_avg
			self._emit_signal_by_name('display_curve', [s.data_x,
														s.data_avg])

	async def _single_async(self):
		"""
		Coroutine to launch the acquisition of a trace_average traces.
		"""
		s : Scope = self.mainPitaya.scope
		self._running_state = 'running_single'
		s._prepare_averaging()  # initializes the table self.data_avg,
		return await self._do_average_single_async()
	
	async def _do_average_single_async(self):
		"""
		Accumulate averages based on the attributes self.current_avg and
		self.trace_average. This coroutine doesn't take care of
		initializing the data such that the module can go indifferently from
		['paused_single', 'paused_continuous'] into ['running_single',
		'running_continuous'].
		"""
		s : Scope = self.mainPitaya.scope
		while s.current_avg < s.trace_average:
			s.current_avg+=1
			if s.running_state=='paused_single':
				await s._resume_event.wait()
			s.data_avg = (s.data_avg * (s.current_avg-1) + \
							 await s._trace_async(0)) / s.current_avg
			self._emit_signal_by_name('display_curve', [s.data_x,
														s.data_avg])
		self._running_state = 'stopped'
		s._free_up_resources()
		return s.data_avg
	
	def save_curve(self, *args):
		"""
		Saves the curve(s) that is (are) currently displayed in the gui in
		the db_system. Also, returns the list [curve_ch1, curve_ch2]...
		"""
		if len(args) == 0:
			return self.mainPitaya.scope.save_curve()	
		return self._save_curve(*args)