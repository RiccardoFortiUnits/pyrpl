from ..attributes import IntRegister, ArrayRegister, FloatRegister, SelectRegister, SelectProperty, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister, FloatProperty, ExpandableProperty

from ..module_attributes import ModuleListProperty, Module, SignalLauncher
from ..widgets.module_widgets.sensorFuser_widget import sensor_fuser_widget, sensorToBeFused_widget
import numpy as np
from .dsp import DspModule, all_inputs, dsp_addr_base, InputSelectRegister, all_output_directs
from ..segmentedFunctionObject import segmentedFunctionObject
from .scope import Scope
from .asg import Asg0
import numpy as np
from scipy.optimize import least_squares
from qtpy import QtCore

class SignalLauncherSensorFuserModule(SignalLauncher):
    """ class that takes care of emitting signals to update all possible
    displays"""

    updateExpectedCurves = QtCore.Signal()  # This signal is emitted when

class updateSensorFuserProperty(ExpandableProperty):
	'''whenever this property is updated, the FPGA values of the sensorFuser module are updated'''
	alreadyUpdating = True#let's set it to true at the start, so that we can set all the parameters one at a time from the configuration file, without them interacting with one another (we don't have any calibration acquisition at the start). We will set it to false when a new calibration acquisition is executed
	@staticmethod
	def updateSensorFuser(self, sensorToBeFused, value):
		if updateSensorFuserProperty.alreadyUpdating:
			return
		try:
			updateSensorFuserProperty.alreadyUpdating = True
			other = sensorToBeFused.getOtherProperty(self)
			if other is not None:
				valueForOther = sensorToBeFused.otherSensor.signalAtTime(sensorToBeFused.timeAtsignal(value))
				other._prop.__set__(sensorToBeFused.otherSensor, valueForOther)
			sensorToBeFused.parent.updateFPGA_valuesFromSensorValues()
		finally:
			updateSensorFuserProperty.alreadyUpdating = False

	def __init__(self, prop):
		super().__init__(prop, 
			extraFunctionToDoAfterSettingValue=self.updateSensorFuser
		)

class sensorToBeFused(Module, segmentedFunctionObject):
	'''submodule for the handling of a secondary peak, to set some parameters that involve all the peaks of that same redpitaya'''
	_gui_attributes = [
					"minValue",
					"transitionValue",
					"maxValue"
					]
	_setup_attributes = _gui_attributes
	_widget_class = sensorToBeFused_widget
	def __init__(self, parent, name, otherSensor = None):
		super().__init__(parent, name)
		self.sensor_fuser = parent
		self.otherSensor = otherSensor
		self.op_minValue = None
		self.op_maxValue = None
		self.op_transitionValue = None

	minValue = updateSensorFuserProperty(
		FloatProperty(-1, 1, doc = "min value that the input can have")
	)
	maxValue = updateSensorFuserProperty(
		FloatProperty(-1, 1, doc = "max value that the input can have")
	)
	transitionValue = updateSensorFuserProperty(
		FloatProperty(-1, 1, doc = "value that the input has when the other sensor is at its limit/saturation")
	)
	def getOtherProperty(self, property):
		if(property == sensorToBeFused.minValue):
			return self.op_minValue
		if(property == sensorToBeFused.maxValue):
			return self.op_maxValue
		if(property == sensorToBeFused.transitionValue):
			return self.op_transitionValue
	@property
	def calibrationData(self):
		if self.parent.sensor_a == self:
			return self.parent.a
		return self.parent.b
	
	def signalAtTime(self, value):
		t, s = self.calibrationData
		return np.interp(value, t, s)
	def timeAtsignal(self, value):
		t, s = self.calibrationData
		return np.interp(value, s, t)

	def points(self):
		vals = np.array([self.minValue, self.transitionValue, self.maxValue])
		return self.timeAtsignal(vals), vals
	def updateFromInterface(self, x, y):
		self.minValue = self.signalAtTime(x[0])
		self.transitionValue = self.signalAtTime(x[1])
		self.maxValue = self.signalAtTime(x[2])

	@staticmethod
	def generateSensorCouple(parent, name_a, name_b):
		a = sensorToBeFused(parent, name_a)
		b = sensorToBeFused(parent, name_b, a)
		a.otherSensor = b
		a.op_transitionValue = sensorToBeFused.minValue
		b.op_minValue = sensorToBeFused.transitionValue
		a.op_maxValue = sensorToBeFused.transitionValue
		b.op_transitionValue = sensorToBeFused.maxValue

		return a, b

class outputRamp(segmentedFunctionObject):
	def __init__(self, sensorFuser):
		self.sensorFuser = sensorFuser
	def points(self):
		xa, ya = self.sensorFuser.sensor_a.points()
		xb, yb = self.sensorFuser.sensor_b.points()
		y = np.cumsum([0, self.sensorFuser.section_low, self.sensorFuser.section_med, self.sensorFuser.section_high]) * 2 - 1
		x = np.array([xa[0], (xa[1] + xb[0]) / 2, (xa[2] + xb[1]) / 2, xb[2]])
		return x, y
	def pointsForLinearizer(self):
		#If the scan of the intensities was linear, self.sensorFuser.a would be on a straight line 
		# (same for self.sensorFuser.b). But since the overall system is most probably nonlinear. 
		# Let's "linearize" the scan to see the actual ranges of the sensors
		a = self.sensorFuser.a
		b = self.sensorFuser.b
		xa, ya = self.sensorFuser.sensor_a.points()
		xb, yb = self.sensorFuser.sensor_b.points()
		ma, Ma = a[1][0], a[1][-1]
		mb, Mb = b[1][0], b[1][-1]
        #how does this conversion work? Essentially, we assume that a = min(1, b*k), with 
        #the opportune shifts. So, let's first put the two signals in the same scale (the
        #scale of b, since they can both fit correctly inside its range). Then, we will project them in the range [-1,1]
		ya_rescaled = np.interp(ya, [ma, ya[-1]], [mb, yb[-2]])#ma corresponds to mb, ya[-1](=a(x_high)) corresponds to yb[-2](=b(x_high))
		xa = np.interp(ya_rescaled, [mb, Mb], [-1,1])
		xb = np.interp(yb, [mb, Mb], [-1,1])
		y = np.cumsum([0, self.sensorFuser.section_low, self.sensorFuser.section_med, self.sensorFuser.section_high]) * 2 - 1
		x = np.concatenate([[xa[0]], (xa[1:]+xb[:-1])/2, [xb[-1]]])#It's not correct, check again
		return x, y
		
	def updateFromInterface(self, x, y):
		#cannot be modified directly from the interface
		pass

	



class sensor_fuser(DspModule):
	_widget_class = sensor_fuser_widget

	_signal_launcher = SignalLauncherSensorFuserModule
	_setup_attributes = ["input",
					  	 "secondInput",
						 "output_direct",
						 "output_forCalibration",
						 "section_low",
						 "section_med",
						 ]

	_gui_attributes =  _setup_attributes

	def __init__(self, rp, name, index=0):
		super().__init__(rp, name, index)

		self.sensor_a, self.sensor_b = sensorToBeFused.generateSensorCouple(self, f"sensor_a", f"sensor_b")
		self.updatingAllValues = False
		# self.updateSensorValuesFromFPGA()

		#set some dummy values for signals a and b
		self.a=np.array([[-1,0,1], [0,1,1]], dtype=float)
		self.b=np.array([[-1,0,1], [0,.5,1]], dtype=float)

		self.o=outputRamp(self)

	secondInput = InputSelectRegister(- dsp_addr_base("sensor_fuser") + dsp_addr_base("sensor_fuser_in1") + 0x0,
									options=all_inputs,
									default='in2',
									ignore_errors=True,
									doc="selects the input signal of the module")
	output_forCalibration = SelectProperty(options=all_output_directs,
								   doc="selects to which analog output the "
									   "module can generate a ramp for reading the sensor ranges")
	offset_a_low	= FloatRegister(0x100, bits = 14,	startBit=0,		norm = 2**(13),	signed=True)
	offset_a_med	= FloatRegister(0x100, bits = 14,	startBit=14,	norm = 2**(13),	signed=True)
	offset_b_med	= FloatRegister(0x104, bits = 14,	startBit=0,		norm = 2**(13),	signed=True)
	offset_b_high	= FloatRegister(0x104, bits = 14,	startBit=14,	norm = 2**(13),	signed=True)
	gain_a_low		= FloatRegister(0x108, bits = 8,	startBit=0,		norm = 2**(6),	signed=False)
	gain_a_med		= FloatRegister(0x10c, bits = 8,	startBit=0,		norm = 2**(6),	signed=False)
	gain_b_med		= FloatRegister(0x110, bits = 8,	startBit=0,		norm = 2**(6),	signed=False)
	gain_b_high		= FloatRegister(0x114, bits = 8,	startBit=0,		norm = 2**(6),	signed=False)
	
	section_low	= ExpandableProperty(
		FloatRegister(0x118, bits = 4,	startBit=0,		norm = 2**(4),	signed=False, max = .5),
		extraFunctionToDoAfterSettingValue=lambda currentProperty, instance, value : instance.updateFPGA_valuesFromSensorValues()
	)
	section_med	= ExpandableProperty(
		FloatRegister(0x118, bits = 4,	startBit=4,		norm = 2**(4),	signed=False, max = .5),
		extraFunctionToDoAfterSettingValue=lambda currentProperty, instance, value : instance.updateFPGA_valuesFromSensorValues()
	)
	@property
	def section_high(self):
		return np.minimum(1 - self.section_low - self.section_med, .5)
	



	def updateFPGA_valuesFromSensorValues(self):
		if self.updatingAllValues:
			return
		sf = self
		try:
			sf.offset_a_low		= sf.sensor_a.minValue
			sf.offset_a_med		= sf.sensor_a.transitionValue
			sf.offset_b_med		= sf.sensor_b.minValue
			sf.offset_b_high	= sf.sensor_b.transitionValue
			sf.gain_a_low		= sf.section_low / (sf.sensor_a.transitionValue - sf.sensor_a.minValue) if sf.section_low else 0
			sf.gain_a_med		= sf.section_med / (sf.sensor_a.maxValue - sf.sensor_a.transitionValue) if sf.section_med else 0
			sf.gain_b_med		= sf.section_med / (sf.sensor_b.transitionValue - sf.sensor_b.minValue) if sf.section_med else 0
			sf.gain_b_high		= sf.section_high / (sf.sensor_b.maxValue - sf.sensor_b.transitionValue) if sf.section_high else 0
		except Exception as e:
			print("set all the values to avoid divisions by 0")
# 			raise(e)
		self._emit_signal_by_name('updateExpectedCurves')
		
	def updateSensorValuesFromFPGA(self):
		self.updatingAllValues = True
		try:
			sf = self
			try:
				sf.sensor_a.minValue = 			sf.offset_a_low
				sf.sensor_a.transitionValue = 	sf.offset_a_med
				sf.sensor_b.minValue = 			sf.offset_b_med
				sf.sensor_b.transitionValue = 	sf.offset_b_high
				sf.sensor_a.maxValue = sf.sensor_a.transitionValue + (sf.section_med / sf.gain_a_med if sf.section_med else 0)
				sf.sensor_b.maxValue = sf.sensor_b.transitionValue + (sf.section_high / sf.gain_b_high if sf.section_high else 0)
			except Exception as e:
				print("set all the values to avoid divisions by 0")
# 				raise(e)
		finally:
			self.updatingAllValues = False

	def AskScopeForAnAcquisition(self, timeout = 5):
		s : Scope = self.redpitaya.scope
		a = self.redpitaya.asg0

		try:
			s.owner = self
			a.owner = self
			s.trigger_source = "asg0"
			s.trigger_delay = .5 * s.duration
			s.ch1_active = True
			s.ch2_active = True
			s.input1 = self.input
			s.input2 = self.secondInput
			a.frequency = .5 / s.duration
			a.waveform = "ramp"
			a.output_direct = self.output_forCalibration
			a.trigger_source = "immediately"

			s.single(timeout=timeout)
			return s.data_avg
		finally:
			s.free()
			a.free()
			
	def getCurvesFromScope(self):
		'''
		get the last curves obtained from the scope and fit the two sensor limits
		'''
		# '''# uncomment this line to have some debug signals
		a, b = self.AskScopeForAnAcquisition()
		'''
		t = np.linspace(0,1,400)
		b = np.arctan(t*10-5)/np.pi 
		a = np.minimum((b-b[0]) * 5 - 1,1) + np.random.randn(len(t))*.001
		b += np.random.randn(len(t))*.004
		#'''
		self.a, self.b = sensor_fuser.smoothCurveExpectingMonotone(a), sensor_fuser.smoothCurveExpectingMonotone(b)
	
	@staticmethod
	def _maxOfCurve(signal):
		if signal[-1] < signal[0]:
			return - sensor_fuser._maxOfCurve(-signal)
		y_monotone = np.maximum.accumulate(signal)
		return y_monotone
	@staticmethod
	def smoothCurveExpectingMonotone(signal, inputRange = [-1,1]):
		y_max = sensor_fuser._maxOfCurve(signal)
		y_min = (-sensor_fuser._maxOfCurve(-signal[::-1]))[::-1]
		y = (y_min + y_max) / 2
		x = np.linspace(*inputRange, len(y))
		y, i = np.unique(y, return_index=True)
		return x[np.sort(i)], y[np.argsort(i)]
		
		# from sklearn.isotonic import IsotonicRegression
		# import numpy as np
		# x = np.arange(len(signal))         # sampling indices
		# y = np.array(signal)               # your noisy values

		# iso = IsotonicRegression(increasing=True)
		# y_iso = iso.fit_transform(x, y)
	def _load_setup_attributes(self):
		ret = super()._load_setup_attributes()
		self.sensor_a._load_setup_attributes()
		self.sensor_b._load_setup_attributes()
		return ret

# 		t=np.arange(len(a))
# 		#todo: filter a bit
# 		def residualsWithExpected_a(elbow):
# 			ramp_t = [0, elbow]
# 			ramp_x = [a[0], a[int(elbow * len(a))]]
# 			return a - np.interp(t, ramp_t, ramp_x)
# 		
# 		sol_a = least_squares(residualsWithExpected_a, .5)
# 		elbow_a = sol_a.x

# 		a_min = a[0]
# 		a_high = a[elbow_a]

