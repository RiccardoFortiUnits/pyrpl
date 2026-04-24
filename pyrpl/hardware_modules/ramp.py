from ..attributes import IntRegister, IntProperty, ArrayRegister, FloatRegister, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister, ExpandableProperty, ArrayProperty

from ..widgets.module_widgets.ramp_widget import rampWidget
import numpy as np
from .dsp import DspModule, all_inputs, dsp_addr_base, InputSelectRegister
from ..segmentedFunctionObject import segmentedFunctionObject
from .hk import HK
from ..module_attributes import SignalLauncher
from qtpy import QtCore
from .sensorFuser import sensor_fuser

class SignalLauncherRampModule(SignalLauncher):
	""" class that takes care of emitting signals to update all possible
	displays"""
	updateRampCurve = QtCore.Signal(np.ndarray, np.ndarray)  # This signal is emitted when

class idealRampFunction(ArrayProperty):
	def __init__(self, realRamp : segmentedFunctionObject, pre_setting_function, **kwargs):
		super().__init__(len, **kwargs)
		self.realRamp = realRamp
		self.pre_setting_function = pre_setting_function

	def set_value(self, obj, val):
		val = self.pre_setting_function(self, obj, val)
		self.realRamp.set_value(obj, val)
		return super().set_value(obj, val)

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
		obj._emit_signal_by_name("updateRampCurve",np.array(x),np.array(y))

def updateRealRamp(idealRamp, self, value):#declared outside of Ramp. Sometimes Python can be very stupid...
	# if not self.followSensorFuser:
	return value
	ti, yi = value
	sensorFuser : sensor_fuser= self.redpitaya.sensor_fuser
	xs, ys = sensorFuser.o.points()
	xs = np.array(xs)
	ys = np.array(ys)
	xs = (xs - xs[0]) / (xs[-1] - xs[0])
	tr, yr = [0], [np.interp(yi[0], xs, ys)]
	for i in range(len(ti)-1):
		time = ti[i+1] - ti[i]
		edges = yi[i:i+2]
		valueAtEdges = np.interp(edges, xs, ys)
		def positionInsideRange(x, a, b):
			p = (x - a) / (b - a)
			p[np.logical_or(p <= 0, p >= 1)] = -1
			return p
		p = positionInsideRange(xs, *edges)
		indexes = np.where(p != -1)[0]
		p = p[indexes]
		tp = ti[i] + time * p
		tr += list(np.sort(tp))
		yr += list(ys[indexes[np.argsort(p)]])
		tr.append(ti[i+1])
		yr.append(valueAtEdges[1])
	# unique, index = np.unique(tr, return_index=True)
	# return tr[index], yr[index]
	return tr, yr
class Ramp(DspModule, segmentedFunctionObject):
	_widget_class = rampWidget
	_signal_launcher = SignalLauncherRampModule
	_setup_attributes = \
					["output_direct",
					"idleConfiguration",
					"useMultipleTriggers",
					"isRampExponential",
					"exp_taus",
					"defaultValue",
					"usedRamps",
					"external_trigger_pin",
					"rampValues",
					]
						
	_gui_attributes =  _setup_attributes

	nOfSegments = 8

	idleConfiguration = SelectRegister(0x100, startBit=0, options={"defaultValue" : 0, "start" : 1, "end" : 2, "inverseRamp" : 3}, 
			doc="set the value that the output keeps when the ramp is finished, while waiting for a new start trigger. "
			"either use property defaultValue, the value at the start of the function, keep the final value of the function, "
			"or execute a mirror version of the function (finishing at the starting value)")
	
	useMultipleTriggers = IntRegister(0x100, startBit=2, bits=8, doc="if any bit is 1, at the end the corresponding ramp the sequence will be halted, and it will continue only after a new trigger is received."
			"If the trigger arrives before that ramp has ended, the next section will be started immediately.")
	
	defaultValue = FloatRegister(0x104, startBit=14, bits=14, norm= 2 **13, min=-1, max=1, doc="value that the output will keep at the end of the function, if idleConfiguration is set to 'defaultValue'")
	usedRamps = IntRegister(0x100, startBit=2+8, bits = int(np.ceil(np.log2(nOfSegments) + 1)), min=0, max=nOfSegments, default=0, 
			doc="number of ramps used by the function. The values set for the 'exceding' ramps will not be used. If 0, it effectively disables the ramp")
	isRampExponential = IntRegister(0x100, startBit=2+8+int(np.ceil(np.log2(nOfSegments) + 1)), bits=8, doc="if any bit is 1, the corresponding ramp will be exponential, with timing constant given by the corresponding value in ")

	exp_taus = ArrayRegister(
						FloatRegister, 
						[0x110 + 0xC*i for i in range(nOfSegments)], 
						[0] * nOfSegments, 
						28, 
						norm=1/4.6e-8,
						signed = False,
						doc="timing constant of the exponential ramp"
						)
	





	# followSensorFuser = BoolProperty(default=False, doc="select if the ramps should follow the ramps defined in the sensorFuser module. If this property "
	#"is set, each ramp will be divided in multiple ramps, so that, if used in tandem with the sensorFuser module, the output will be linear.")
	def __init__(self, *args, **kwargs):        
		super(Ramp, self).__init__(*args, **kwargs)
# 		self.rampValues = "[[0,1e-3,2e-3,2.5e-3],[0.5,-0.5,0,0.5]]"
	external_trigger_pin = digitalPinRegister(HK.addr_base + 0x28, startBit=8, isAddressStatic = True)

	rampValues = rampFunction(nOfSegments)
	idealRamp = idealRampFunction(rampValues, updateRealRamp)


	def points(self):
		return self.rampValues
		
	def updateFromInterface(self, x, y):
		self.idealRamp = (x,y)

	def addRampToEnd(self, rampDuration, rampEndValue):
		t, y = self.rampValues
		t = np.concatenate((t, [t[-1] + rampDuration]))
		y = np.concatenate((y, [rampEndValue]))
		self.rampValues = [t, y]
	def addHoldToEnd(self, holdDuration):
		self.addRampToEnd(holdDuration, self.rampValues[1][-1])

