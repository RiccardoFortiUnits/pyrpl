from ..attributes import BaseProperty, DynamicInstanceProperty, IntRegister, IntProperty, ArrayRegister, FloatRegister, FloatProperty, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister, ExpandableProperty, ArrayProperty, dualProperty

from ..widgets.module_widgets.ramp_widget import rampWidget, segmentWidget
import numpy as np
from .dsp import DspModule, all_inputs, dsp_addr_base, InputSelectRegister
from ..segmentedFunctionObject import segmentedFunctionObject
from .hk import HK
from ..modules import HardwareModule
from ..module_attributes import SignalLauncher
from qtpy import QtCore
from .sensorFuser import sensor_fuser

class SignalLauncherRampModule(SignalLauncher):
	""" class that takes care of emitting signals to update all possible
	displays"""
	updateRampCurve = QtCore.Signal()  # This signal is emitted when


class rampFunction(ArrayRegister):
	def __init__(self, nOfSegments = 8, timeRegistersBitSize = 28, voltageRegistersBitSize = 14):
		self.nOfSegments = nOfSegments
		self.timeRegistersBitSize = timeRegistersBitSize
		self.voltageRegistersBitSize = voltageRegistersBitSize
		self.startPoint = FloatRegister(0x104, bits=14, norm=2**13, signed = True)
		self.DVs = ArrayRegister(FloatRegister, 
								addresses=[0x108 + i*0xC for i in range(nOfSegments)],
								startBits=[0] * nOfSegments,
								bits=voltageRegistersBitSize + 1,
								norm=2**13,
								doc="difference between the end and start of the ramp")
		self.DTs = ArrayRegister(FloatRegister, 
								addresses=[0x10C + i*0xC for i in range(nOfSegments)],
								startBits=[0] * nOfSegments,
								bits=timeRegistersBitSize,
								norm=125e6,
								signed = False,
								doc="duration of the ramp")
		super().__init__(registers=[self.DVs, self.DTs])
		self.len = 2
		
	def get_value(self, obj):
		
		'''
		try:
			firstUnusedIndex = nOfSteps.index(0) + 1
		except:
			firstUnusedIndex = len(nOfSteps)
		'''
		firstUnusedIndex = obj.usedRamps
		dt = self.DTs.get_value(obj)[:firstUnusedIndex]
		dv = self.DVs.get_value(obj)[:firstUnusedIndex]
		x = np.concatenate((np.zeros(1), np.cumsum(dt)))
		y = np.cumsum(np.concatenate(([self.startPoint.get_value(obj)], dv)))
		return [list(x),list(y)]
	
	def set_value(self, obj, val):
		x,y=val 
		if len(x) > self.nOfSegments + 1:
			raise Exception(f"too many segments! max number of points is {self.nOfSegments+1}")
		edges = np.array(y[:])
		times = np.array(x[1:]) - np.array(x[:-1])
		obj.usedRamps = len(x) - 1

		self.startPoint.set_value(obj, edges[0])
		self.DVs.set_value(obj, edges[1:] - edges[:-1])
		self.DTs.set_value(obj, times)
		obj._emit_signal_by_name("updateRampCurve")

class voltageAndInitialBitShiftProperty(FloatProperty):
	def __init__(self, min=-np.inf, max=np.inf, increment=0, log_increment=False, **kwargs):
		super().__init__(min, max, increment, log_increment, **kwargs)
		self.alreadyUpdating = False

	def set_value(self, obj, val):
		if self.alreadyUpdating:
			return
		self.alreadyUpdating = True
		try:
			ret = super().set_value(obj, val)
			if obj.isExponential:
				tau = obj.tau
				DT = obj.DT
				if obj.exponentialRampSign == "negative":
					obj.normalized_DV = val / (1 - np.exp(-DT / tau))
					obj.initialExponentialShift = 0
				else:
					#let's check how many orders of magnitude will be done
					s = int(np.ceil(np.log2(np.e) * DT / tau))
					obj.normalized_DV = val / (2**-(s+.25) * (np.exp(DT / tau) - 1))
					obj.initialExponentialShift = s
			else:
				obj.normalized_DV = val
			return ret
		finally:
			obj.parent._emit_signal_by_name("updateRampCurve")
			self.alreadyUpdating = False
	def get_value(self, obj):
		return super().get_value(obj)
	# def get_value(self, obj):
	# 	obj : segment = obj
	# 	# ret = super().get_value(obj)
	# 	dv = obj.normalized_DV
	# 	if obj.isExponential:
	# 		tau = obj.tau
	# 		DT = obj.DT
	# 		s = obj.initialExponentialShift
	# 		if obj.exponentialRampSign == "negative":
	# 			return dv * 2**-s * (1 - np.exp(-DT / tau))
	# 		else:
	# 			return dv * (2**-s * (np.exp(DT / tau) - 1))
	# 	else:
	# 		return dv
		

class initialSegment:
	T = 0
	@property
	def VVV(self):
		return self.parent.startPoint
	def __init__(self, parent):
		self.parent = parent
class segment(HardwareModule):	
	'''submodule for the handling of a single segment of a ramp'''
	_gui_attributes = [
					"DV",
					"VVV",
					"DT",
					"T",
					"isExponential",
					"exponentialRampSign",
					"haltsSequence",
					"tau",
					]
	_setup_attributes = _gui_attributes
	_widget_class = segmentWidget

	def __init__(self, parent, prevSegment = None, name=None, index = -1):
		self.addr_base = parent.addr_base + 0x108 + 0xC*index
		super().__init__(parent, name, index)
		if prevSegment is None:
			prevSegment = initialSegment(parent)
		self.prevSegment = prevSegment
	

	#remember, all addreses are shifted accordingly to addr_base
	normalized_DV = FloatRegister(0x0, 15, startBit= 0, norm=2**13, doc="difference between the end and start of the ramp")
	DV = voltageAndInitialBitShiftProperty()
	DV_V = dualProperty(DV, FloatProperty, lambda prop, instance, value : instance.prevSegment.VVV + value, lambda prop, instance, value : value - instance.prevSegment.VVV)
	DV, VVV = DV_V.real, DV_V.virtual
	DT = FloatRegister(0x4, 28, startBit= 0, norm=125e6, doc="difference between the end and start of the ramp")
	DT_T = dualProperty(DT, FloatProperty, lambda prop, instance, value : instance.prevSegment.T + value, lambda prop, instance, value : value - instance.prevSegment.T)
	DT, T = DT_T.real, DT_T.virtual


	def updateDV(self):
		self.DV = self.DV
	isExponential = ExpandableProperty(BoolRegister(0x0, bit = 15), extraFunctionToDoAfterSettingValue=lambda prop, instance, value: instance.updateDV())
	exponentialRampSign = ExpandableProperty(SelectRegister(0x0, startBit=16, options={"negative" : 0, "positive" : 1}), extraFunctionToDoAfterSettingValue=lambda prop, instance, value: instance.updateDV())
	haltsSequence = BoolRegister(0x0, bit = 17)
	initialExponentialShift = ExpandableProperty(IntRegister(0x0, startBit=18, bits = 4, signed= False), extraFunctionToDoAfterSettingValue=lambda prop, instance, value: instance.updateDV())
	tau = ExpandableProperty(FloatRegister(0x8, bits=28, norm=1/4.6e-8, signed = False, doc="timing constant of the exponential ramp"), extraFunctionToDoAfterSettingValue=lambda prop, instance, value: instance.updateDV())
	DT = ExpandableProperty(DT, extraFunctionToDoAfterSettingValue=lambda prop, instance, value: instance.updateDV())
	T = ExpandableProperty(T, extraFunctionToDoAfterSettingValue=lambda prop, instance, value: instance.updateDV())



class Ramp(DspModule, segmentedFunctionObject):
	_widget_class = rampWidget
	_signal_launcher = SignalLauncherRampModule
	_setup_attributes = \
					["startPoint",
					"usedRamps",
					"output_direct",
					"idleConfiguration",
					"defaultValue",
					"external_trigger_pin",
					]
						
	_gui_attributes =  _setup_attributes

	nOfSegments = 8

	idleConfiguration = SelectRegister(0x100, startBit=0, options={"defaultValue" : 0, "start" : 1, "end" : 2, "inverseRamp" : 3}, 
			doc="set the value that the output keeps when the ramp is finished, while waiting for a new start trigger. "
			"either use property defaultValue, the value at the start of the function, keep the final value of the function, "
			"or execute a mirror version of the function (finishing at the starting value)")
	
	# useMultipleTriggers = IntRegister(0x100, startBit=2, bits=8, doc="if any bit is 1, at the end the corresponding ramp the sequence will be halted, and it will continue only after a new trigger is received."
			# "If the trigger arrives before that ramp has ended, the next section will be started immediately.")
	
	defaultValue = FloatRegister(0x104, startBit=14, bits=14, norm= 2**13, min=-1, max=1, doc="value that the output will keep at the end of the function, if idleConfiguration is set to 'defaultValue'")
	usedRamps = IntRegister(0x100, startBit=2, bits = int(np.ceil(np.log2(nOfSegments) + 1)), min=0, max=nOfSegments, default=0, 
			doc="number of ramps used by the function. The values set for the 'exceding' ramps will not be used. If 0, it effectively disables the ramp")
	
	startPoint = FloatRegister(0x104, bits=14, norm=2**13, signed = True, doc="initial value of the sequence")
	# isRampExponential = IntRegister(0x100, startBit=2+8+int(np.ceil(np.log2(nOfSegments) + 1)), bits=8, doc="if any bit is 1, the corresponding ramp will be exponential, with timing constant given by the corresponding value in ")
	# exponentialDirection = ArrayRegister(
	# 					BoolRegister,
	# 					[0x108 + 0xC*i for i in range(nOfSegments)], 
	# 					[15] * nOfSegments
	# 					)
	
	# initialExponentialShift = ArrayRegister(
	# 					IntRegister,
	# 					[0x108 + 0xC*i for i in range(nOfSegments)], 
	# 					[16] * nOfSegments,
	# 					4
	# 					)

	# exp_taus = ArrayRegister(
	# 					FloatRegister, 
	# 					[0x110 + 0xC*i for i in range(nOfSegments)], 
	# 					[0] * nOfSegments, 
	# 					28, 
	# 					norm=1/4.6e-8,
	# 					signed = False,
	# 					doc="timing constant of the exponential ramp"
	# 					)
	
	def __init__(self, rp, name, index=0):
		super().__init__(rp, name, index)
		self.client = self._client
		prevSegment = None
		self.segments = []
		for i in range(Ramp.nOfSegments):
			prevSegment = segment(self, prevSegment, f"segment_{i}", i)
			self.segments.append(prevSegment)

	external_trigger_pin = digitalPinRegister(HK.addr_base + 0x28, startBit=8, isAddressStatic = True)

	def points(self):
		DVs = [s.DV for s in self.segments[:self.nOfSegments]]
		DTs = [s.DT for s in self.segments[:self.nOfSegments]]
		T = np.cumsum([0]+DTs)
		VVV = np.cumsum([self.startPoint]+DVs)
		return T, VVV
		
	def updateFromInterface(self, x, y):
		DV = np.diff(y)
		DT = np.diff(x)
		self.startPoint = y[0]
		self.usedRamps = len(DV)
		for i in range(len(DV)):
			self.segments[i].DV = DV[i]
			self.segments[i].DT = DT[i]

	def addRampToEnd(self, rampDuration, rampEndValue):
		l = self.usedRamps
		seg = self.segments[l]
		seg.DT = rampDuration
		seg.VVV = rampEndValue
		self.usedRamps = l + 1
	def addHoldToEnd(self, holdDuration):
		self.addRampToEnd(holdDuration, self.segments[self.usedRamps-1])


	#let's overwrite _load_setup_attributes, so that we also load the submodules
	def _load_setup_attributes(self):
		ret = super()._load_setup_attributes()
		for s in self.segments:
			s._load_setup_attributes()
		return ret
