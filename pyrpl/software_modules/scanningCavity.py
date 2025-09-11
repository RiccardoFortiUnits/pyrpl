
from __future__ import division, annotations
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
from ..acquisition_module import AcquisitionModule
from ..async_utils import wait, ensure_future, sleep_async
from ..pyrpl_utils import sorted_dict
from ..attributes import *
from ..modules import HardwareModule
from ..pyrpl_utils import time
from ..widgets.module_widgets import ScopeWidget
import asyncio

from ..hardware_modules.scope import Scope, peakIndexRegister
from ..hardware_modules.asg import Asg0
from ..hardware_modules.pid import Pid
from ..hardware_modules.hk import HK
from ..hardware_modules.dsp import DSP_TRIGGERS
from ..widgets.module_widgets.scanCavity_widget import ScanCavity_widget, peak_widget, secondaryPitaya_widget


class SignalLauncherScanningCavity(SignalLauncher):
	"""
	A SignalLauncher for the scanning cavity
	"""
	# output_created = QtCore.Signal(list)
	# output_deleted = QtCore.Signal(list)
	# output_renamed = QtCore.Signal()
	# stage_created = QtCore.Signal(list)
	# stage_deleted = QtCore.Signal(list)
	# stage_renamed = QtCore.Signal()
	# delete_widget = QtCore.Signal()
	# state_changed = QtCore.Signal(list)
	# add_input = QtCore.Signal(list)
	# input_calibrated = QtCore.Signal(list)
	# remove_input = QtCore.Signal(list)
	# update_transfer_function = QtCore.Signal(list)
	# update_lockstatus = QtCore.Signal(list)
	# p_gain_rounded = QtCore.Signal(list)
	# p_gain_ok = QtCore.Signal(list)
	# i_gain_rounded = QtCore.Signal(list)
	# i_gain_ok = QtCore.Signal(list)
nOfSecondaryPeaks = 2

class peakValue(FloatProperty):
	def __init__(self, propertyAccessor = lambda peak: f"minTime{peak.index+1}", **kwargs):
		super().__init__( **kwargs)
		self.propertyAccessor = propertyAccessor
	def set_value(self, obj : peak, val):
		setattr(obj.redpitaya.scope, self.propertyAccessor(obj), val)
		return super().set_value(obj, val)
	def get_value(self, obj : peak):
		return getattr(obj.redpitaya.scope, self.propertyAccessor(obj))
class peakInput(SelectProperty):
	def inputName(self, obj):
		return f"{obj.redpitaya.scope.peakNames[obj.index]}_input"
	def set_value(self, obj : peak, val):
		setattr(obj.redpitaya.scope, self.inputName(obj), val)
		return super().set_value(obj, val)
	def get_value(self, obj : peak):
		return getattr(obj.redpitaya.scope, self.inputName(obj))
	def options(self, instance=None):
		return getattr(Scope, self.inputName(instance)).options(instance.redpitaya.scope)

class peakSetpoint(FloatProperty):
	def get_value(self, obj):
		normalizedSetpointValue = (obj.setpoint + 1) * 0.5
		if obj.index >= 2:
			L, R = self.getMainPeaks(obj)
			return L + (R - L) * normalizedSetpointValue
		duration = obj.scanningCavity.duration
		return normalizedSetpointValue * duration
	def set_value(self, obj : peak, val):
		if obj.index >= 2:
			L, R = self.getMainPeaks(obj)
			if R != L:
				normalizedSetpointValue = (val - L) / (R - L)
				valueBetween_m1_and_1 = normalizedSetpointValue * 2 - 1
				obj.setpoint = valueBetween_m1_and_1
			else:
				obj.setpoint = 0
		else:
			duration = obj.scanningCavity.duration
			normalizedSetpointValue = val / duration
			valueBetween_m1_and_1 = normalizedSetpointValue * 2 - 1
			obj.setpoint = valueBetween_m1_and_1
		return super().set_value(obj, val)
	
	def getMainPeaks(self, obj : peak):
		L = obj.scanningCavity.mainL.timeSetpoint
		R = obj.scanningCavity.mainR.timeSetpoint
		return L, R




class commonPeakIndexRegister(peakIndexRegister):
	'''same as peak index register, but the set value will affect all the pitayas of the scanning cavity (since all cavities should have the same values for the main peaks)'''
	def __init__(self, scanCavity, address, norm=1, signed=True, invert=False, **kwargs):
		super().__init__(address, norm, signed, invert, **kwargs)
		self.scanCavity = scanCavity
	@property
	def objects(self):
		return [pitaya.scope for pitaya in self.scanCavity.usedPitayas]

	def set_value(self, obj, value):
		value = value / obj.decimation / 8e-9
		for o in self.objects:
			FloatRegister.set_value(self, o, value)


class asgSelector(SelectProperty):
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
	
class mainTriggerSelector(digitalPinProperty):
	'''this property sets the digital pin of the main pitaya that will trigger the other pitaya's scopes'''
	def set_value(self, obj : ScanningCavity, val):
		val = digitalPinProperty.pinIndexToString(val)
		hk : HK = obj.mainPitaya.hk
		selectedAsg = obj.usedAsg
		setattr(hk, f"expansion_{val}_output", 1)
		setattr(hk, f"pinState_{val}", "dsp")
		setattr(hk, f"external_{val}_dspBitSelector", DSP_TRIGGERS[f"{selectedAsg}_trigger"])

		return super().set_value(obj, val)

class scopeTriggerSelector(digitalPinProperty):
	'''this property sets the digital pin that trigger the scope acquisition. Can also be used for the main pitaya, if the ramp trigger is external'''
	def set_value(self, obj : secondaryPitaya, val):
		val = digitalPinProperty.pinIndexToString(val)
		hk : HK = obj.rp.hk
		setattr(hk, f"expansion_{val}_output", 0)

		scope : Scope = obj.rp.scope
		scope.external_trigger_pin = val
		return super().set_value(obj, val)

class peakEnablerSelector(digitalPinProperty):
	'''this property sets the digital pin that will enable the AOM responsible for shutting down the laser when it is not its turn'''
	def set_value(self, obj : peak, val):
		oldEnabled = obj.enabled
		val = digitalPinProperty.pinIndexToString(val)
		hk : HK = obj.redpitaya.hk
		setattr(hk, f"expansion_{val}_output", 1)
		# setattr(hk, f"pinState_{val}", "dsp" if oldEnabled else "memory")  #already done by obj.enabled
		# setattr(hk, f"expansion_{val}", 0)
		setattr(hk, f"external_{val}_dspBitSelector", DSP_TRIGGERS[f"inPeakRange_{obj.index + 1}"])
		ret = super().set_value(obj, val)
		obj.enabled = oldEnabled
		return ret

class enablePeakProperty(BoolProperty):
	def set_value(self, obj : peak, val):
		index = digitalPinProperty.pinIndexToString(obj.enablingBit)
		hk = obj.redpitaya.hk
		setattr(hk, f"pinState_{index}", "dsp" if val else "memory")
		setattr(hk, f"expansion_{index}", 0)
		obj.paused = not (obj.locking & val)
		return super().set_value(obj, val)
	
class mainInputSelector(BaseProperty):

	def set_value(self, obj, value):
		scope : Scope = obj.mainPitaya.scope
		scope.input1 = value
		ret = super().set_value(obj, value)
		obj.updateScope()
		return ret
	def get_value(self, obj):
		return  obj.mainPitaya.scope.input1
	
class rampVoltageEdge(FloatProperty):
	'''property to set the low and high edge of an asg signal. Use makeLowerAndUpperEdges() to create 2 
	connected edges, which will not cross each other (for example, trying to set on the lower edge a 
	value higher than the current edge will not be permitted)'''
	@staticmethod
	def makeLowerAndUpperEdges(**kwargs):
		low = rampVoltageEdge(None, True, **kwargs)
		high = rampVoltageEdge(low, False, **kwargs)
		low.otherEdge = high
		return low, high
	def __init__(self, otherEdge = None, isLowerEdge = True, min=-np.inf, max=np.inf, increment=0, log_increment=False, **kwargs):
		super().__init__(min, max, increment, log_increment, **kwargs)
		self.otherEdge = otherEdge
		self.isLowerEdge = isLowerEdge

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
		asg = obj.asg
		asg.amplitude = amp
		asg.offset = offs
		return super().set_value(obj, val)
	def get_value(self, obj):		
		asg = obj.asg
		amp = asg.amplitude
		offs = asg.offset
		low, high = rampVoltageEdge.getLowHigFromAmpOffs(amp, offs)
		return low if self.isLowerEdge else high

class normalizeIndexProperty(BoolProperty):
	def set_value(self, obj : peak, val):
		if obj.index < 2:
			return False
			raise Exception("cannot set a main peak as normalized")
		super().set_value(obj, val)
		return setattr(obj.redpitaya.scope, f"{obj.redpitaya.scope.peakNames[obj.index]}_normalizeIndex", val)
	
	def get_value(self, obj : peak):
		if obj.index < 2:
			return 0
		return getattr(obj.redpitaya.scope, f"{obj.redpitaya.scope.peakNames[obj.index]}_normalizeIndex"
				 )
class peak(Module):
	
	_gui_attributes = [
					"min_voltage",
					"max_voltage",
					"timeSetpoint","left",
					"right",
					"height",
					"p",
					"i",
					"input",
					"output_direct",
					"enablingBit",
					"enabled",
					"normalizeIndex",#can be removed by manually by peak_widget, it stays only for the normalizable peaks
					]
	_widget_class = peak_widget

	# @staticmethod
	# def createPeak(redpitaya, index, parent):
	# 	p = peak(parent)
	# 	p.redpitaya = redpitaya
	# 	p.index = index
	# 	return p
	def __init__(self, redpitaya, index, scanningCavity : ScanningCavity, name=None):
		super().__init__(redpitaya, name)
		self.scanningCavity : ScanningCavity = scanningCavity
		self.index = index
		self.pid = redpitaya.pids.all_modules[index - 1 if index >= 2 else 0]
		self.input

	 
	left = peakValue(lambda peak: f"minTime{peak.index+1}", min = 0)
	right = peakValue(lambda peak: f"maxTime{peak.index+1}")
	height = peakValue(lambda peak: f"{peak.redpitaya.scope.peakNames[peak.index]}_minValue")
	input = peakInput()
	enablingBit = peakEnablerSelector()
	enabled = enablePeakProperty()
	normalizeIndex = normalizeIndexProperty()

	'''setpoint is the actual value of the PID setpoint (value between -1 and 1, 
	where -1 represents the lower timing for the peak, either
		0 for the main peaks
		mainL for the secondary peaks
	and 1 represents either
		mainScope.duration for the main peaks
		mainR for the secondary peaks

	timeSetpoint is the time corresponding to the PID setpoint
	)'''
	setpoint = DynamicInstanceProperty(Pid.setpoint, lambda peak : peak.pid)
	timeSetpoint = peakSetpoint(min = 0)
	p = DynamicInstanceProperty(Pid.p, lambda peak : peak.pid)
	i = DynamicInstanceProperty(Pid.i, lambda peak : peak.pid)
	paused = DynamicInstanceProperty(Pid.paused, lambda peak : peak.pid)
	min_voltage = DynamicInstanceProperty(Pid.min_voltage, lambda peak : peak.pid)
	max_voltage = DynamicInstanceProperty(Pid.max_voltage, lambda peak : peak.pid)
	output_direct = DynamicInstanceProperty(Pid.output_direct, lambda peak : peak.pid)

	locking = BoolProperty()
	
	def setupPid(self):
		self.pid.ival=0
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
		if self.enabled:
			self.setupPid()
			self.locking = True
		else:
			self.locking = False
		self.paused = not (self.locking & self.enabled)

	def _deactivatePID(self):
		self.setupPid()
		self.locking = False
		self.paused = not (self.locking & self.enabled)

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

	
	@staticmethod
	def getGroupsOfNonOverlapping(peakList):
		ranges = [(p.minTime, p.maxTime) for p in peakList]
		def areIntersecting(range0, range1):
			return (range0[0] < range1[1]) ^ (range0[1] <= range1[0])
		intersections = np.zeros((len(ranges), len(ranges)), dtype=bool)
		for i in range(len(ranges)):
			for j in range(len(ranges)):
				intersections[i,j] = areIntersecting(ranges[i], ranges[j])
		stillFree = np.arange(len(ranges))
		allGroups = []
		while len(stillFree) > 0:
			run = [stillFree[0]]
			addedIndexes = [0]
			for i in range(1, len(stillFree)):
				testedLine = np.repeat(stillFree[i],len(run))
				if not np.any(intersections[testedLine, run]):
					addedIndexes.append(i)
					run.append(stillFree[i])
			stillFree = np.delete(stillFree, addedIndexes)
			allGroups.append(run)
		return allGroups

class secondaryPitaya(Module):
	_gui_attributes = [
					"input1",
					"acquisitionTrigger"
					]
	_widget_class = secondaryPitaya_widget
	def __init__(self,redpitaya, scanningCavity):
		self.rp = redpitaya
		super().__init__(scanningCavity, name=None)
		# self.controlPeak1 = peak(self, 2, scanningCavity, f"{self.rp.name}_controlled1")
		# scanningCavity.usedPeaks += [self.controlPeak1]
	input1 = DynamicInstanceProperty(Scope.input1, lambda secondaryPitaya : secondaryPitaya.rp.scope)
	acquisitionTrigger = scopeTriggerSelector()

class ScanningCavity(AcquisitionModule):

	_gui_attributes = ["duration",
					"input1",
					"usedAsg",
					"lowValue", 
					"highValue",
					"trigger_source",
					"output_direct",
					"main_acquisitionTrigger",
					"threshold",
					"hysteresis",
					]
	_widget_class = ScanCavity_widget


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
		self.usedPitayas = [pitaya]
		for i in range(nOfSecondaryPeaks):
			self.addSecondaryPeak(peak(pitaya, i + 2, self, f"{pitaya.name}_secondary{i}"))
		self.mainPitaya.hk.input1 = "alltriggers"
	def addPitaya(self, pitaya):
		if pitaya in self.usedPitayas:
			raise Exception("pitaya already used")
		self.usedPitayas.append(pitaya)
		self.secondaryPitayas.append(secondaryPitaya(pitaya, self))
		for i in range(nOfSecondaryPeaks):
			self.addSecondaryPeak(peak(pitaya, i + 2, self, f"{pitaya.name}_secondary{i}"))
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
	
	main_acquisitionTrigger = mainTriggerSelector()
	_usableTriggers = {key : val for key,val in Scope._trigger_sources.items() if "asg" in key}
	usedAsg = asgSelector(_usableTriggers)
	lowValue, highValue = rampVoltageEdge.makeLowerAndUpperEdges(min = -1, max = 1)
	trigger_source = DynamicInstanceProperty(Asg0.trigger_source, lambda scanCavity : scanCavity.asg)
	output_direct = DynamicInstanceProperty(Asg0.output_direct, lambda scanCavity : scanCavity.asg)

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
	def asg(self):
		return self.mainPitaya.asg0 if self.usedAsg == "asg0" else self.mainPitaya.asg1
	def updateRamp(self, oldValues = None):
		asg = self.asg
		asg.waveform = "ramp"
		asg.frequency = 0.5 / self.duration
		if oldValues is not None:
			self.output_direct = oldValues[0]
			self.trigger_source = oldValues[1]

		ScanningCavity.lowValue.value_updated(self)
		ScanningCavity.highValue.value_updated(self)
		ScanningCavity.trigger_source.value_updated(self)
		ScanningCavity.output_direct.value_updated(self)
	
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