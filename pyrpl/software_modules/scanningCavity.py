
from __future__ import division
from collections import OrderedDict
from qtpy import QtCore
import logging
from ..modules import SignalLauncher
from ..module_attributes import ModuleListProperty
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
from ..widgets.module_widgets.scanCavity_widget import ScanCavity_widget


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

class peak():
	def __init__(self, redpitaya, index):
		self.redpitaya = redpitaya
		self.index = index
	
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
		ret = super().set_value(obj, value)
		obj.updateRamp()
		return ret
class inputSelector(SelectProperty):
	def __init__(self, options, **kwargs):
		super().__init__(options, **kwargs)

	def set_value(self, obj, value):
		scope : Scope = obj.mainPitaya.scope
		scope.input1 = value
		ret = super().set_value(obj, value)
		obj.updateScope()
		return ret
	
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

class ScanningCavity(AcquisitionModule):

	_setup_attributes = ["duration"]
	_gui_attributes = ["duration",
					"input1",
					"usedAsg",
					"lowValue", 
					"highValue",
					"trigger_source",
					"output_direct",
					]
	_widget_class = ScanCavity_widget

	def __init__(self, parent, name=None):
		self.setMainPitaya(list(parent.rps.values())[0])
		super().__init__(parent, name)
		self.usedPeaks = []
		self.usedPitayas = []

	def setMainPitaya(self, pitaya):
		self.mainPitaya = pitaya
		self.mainL = peak(pitaya, 0)
		self.mainR = peak(pitaya, 1)
		self.usedPitayas = [pitaya]
		self.duration
	def addPitaya(self, pitaya):
		if pitaya in self.usedPitayas:
			raise Exception("pitaya already used")
		self.usedPitayas.append(pitaya)

	def addPeak(self, newPeak):
		if newPeak in self.usedPeaks:
			raise Exception("peak already used")
		self.usedPeaks.append(newPeak)
	def removePeak(self, peakToRemove):
		self.usedPeaks.remove(peakToRemove)

	def allAvailableSecondaryPeaks(self):
		peaks = []
		for device in self.pyrpl.rps.keys():
			for i in range(nOfSecondaryPeaks):
				peaks.append(peak(device, i+2))
		return peaks
	def allUnusedSecondaryPeaks(self):
		peaks = self.allAvailableSecondaryPeaks()
		return [p for p in peaks if p not in self.usedPeaks]
	

	duration = DynamicInstanceProperty(Scope.duration, lambda scanCavity : scanCavity.mainPitaya.scope)	
	input1 = DynamicInstanceProperty(Scope.input1, lambda scanCavity : scanCavity.mainPitaya.scope)
	
	_usableTriggers = {key : val for key,val in Scope._trigger_sources.items() if "asg" in key}
	usedAsg = asgSelector(_usableTriggers)
	lowValue, highValue = rampVoltageEdge.makeLowerAndUpperEdges(min = -1, max = 1)
	trigger_source = DynamicInstanceProperty(Asg0.trigger_source, lambda scanCavity : scanCavity.asg)
	output_direct = DynamicInstanceProperty(Asg0.output_direct, lambda scanCavity : scanCavity.asg)

	def updateScope(self):
		'''
		setup the scope to have the correct dimensions for the scan
		'''
		scope : Scope = self.mainPitaya.scope
		scope.ch1_active = True
		scope.trigger_delay = scope.duration * .5
		scope.average = False
	@property
	def asg(self):
		return self.mainPitaya.asg0 if self.usedAsg == "asg0" else self.mainPitaya.asg1
	def updateRamp(self):
		asg = self.asg
		asg.waveform = "ramp"
		asg.frequency = 0.5 / self.duration
		ScanningCavity.lowValue.value_updated(self)
		ScanningCavity.highValue.value_updated(self)
		ScanningCavity.trigger_source.value_updated(self)
		ScanningCavity.output_direct.value_updated(self)

		# asg.



	# MIN_DELAY_CONTINUOUS_ROLLING_MS = 20
	# name = 'ScanningCavity'
	
	# _widget_class = LockboxWidget
	# _signal_launcher = SignalLauncherScanningCavity
	# _gui_attributes = ["classname",
	# 				   "default_sweep_output",
	# 				   "auto_lock",
	# 				   "is_locked_threshold",
	# 				   "setpoint_unit"]
	# _setup_attributes = _gui_attributes + [#"auto_lock_interval",
	# 									   "lockstatus_interval",]
	# 									   #"_auto_lock_timeout"]
	
	# lastInputs = [None, None]
	# def __init__(self, parent, name=None, index = 0):
	# 	super(ScanningCavity, self).__init__(parent, name=name)

	# def _from_raw_data_to_numbers(self,data : np.ndarray):
	# 	inputs = [self.input1, self.input2]
	# 	modifications = {
	# 		"out1" : lambda x: x + 1 if self.isDac1Modified else x,
	# 		"out2" : lambda x: x + 1 if self.isDac2Modified else x,
	# 	}
	# 	for ch in [0,1]:
	# 		if inputs[ch] in modifications.keys():
	# 			data[ch] = modifications[inputs[ch]](data[ch])
	# 	#let's save the inputs used for the last data acquisition, in case they are changed later
	# 	Scope.lastInputs = inputs

	# 	return data

	# #____________added controls________________________________________
	# asg0_offset = FloatRegister(address= 0x40200004 - addr_base, 
	# 					   bits=14, startBit=16,
	# 					   norm=2 ** 13, doc="output offset [volts]",
	# 					   increment= 0.05,
	# 					   min=-1., max=1.)
	
	# _PSR = 12  # Register(0x200)
	# _ISR = 32  # Register(0x204)
	# _DSR = 10  # Register(0x208)
	# _GAINBITS = 24  # Register(0x20C)  
	# pid0_setpoint = FloatRegister(dsp_addr_base('pid0') + 0x104 - addr_base,
	# 				bits=14, norm= 2 **13,
	# 				doc="pid setpoint [volts]")

	# pid0_min_voltage = FloatRegister(dsp_addr_base('pid0') + 0x124 - addr_base,
	# 				bits=14, norm= 2 **13,
	# 				doc="minimum output signal [volts]")
	# pid0_max_voltage = FloatRegister(dsp_addr_base('pid0') + 0x128 - addr_base,
	# 				bits=14, norm= 2 **13,
	# 				doc="maximum output signal [volts]")

	# pid0_p = GainRegister(dsp_addr_base('pid0') + 0x108 - addr_base,
	# 				bits=_GAINBITS, norm= 2 **_PSR,
	# 				doc="pid proportional gain [1]")
	# pid0_i = GainRegister(dsp_addr_base('pid0') + 0x10C - addr_base,
	# 				bits=_GAINBITS, norm= 2 **_ISR * 2.0 * np.pi * 8e-9,
	# 				doc="pid integral unity-gain frequency [Hz]")
	
	# ival = IValAttribute(min=-4, max=4, increment= 8. / 2**16, doc="Current "
	# 		"value of the integrator memory (i.e. pid output voltage offset)")
	
	# #__________________________________________________________________
	
	
	
	
	
	
	
	# # running_state last for proper acquisition setup
	# _setup_attributes = _gui_attributes + ["rolling_mode"]
	# # changing these resets the acquisition and autoscale (calls setup())

	# data_length = data_length  # to use it in a list comprehension

	# rolling_mode = BoolProperty(default=True,
	# 							doc="In rolling mode, the curve is "
	# 								"continuously acquired and "
	# 								"translated from the right to the "
	# 								"left of the screen while new "
	# 								"data arrive.",
	# 							call_setup=True)

	# @property
	# def inputs(self):
	# 	return list(all_inputs(self).keys())

	# # the scope inputs and asg outputs have the same dsp id
	# input1 = InputSelectRegister(- addr_base + dsp_addr_base('scope0') + 0x0,
	# 							 options=all_inputs,
	# 							 default='in1',
	# 							 ignore_errors=True,
	# 							 doc="selects the input signal of the module")

	# input2 = InputSelectRegister(- addr_base + dsp_addr_base('scope1') + 0x0,
	# 							 options=all_inputs,
	# 							 default='in2',
	# 							 ignore_errors=True,
	# 							 doc="selects the input signal of the module")

	# _reset_writestate_machine = BoolRegister(0x0, 1,
	# 										 doc="Set to True to reset "
	# 											 "writestate machine. "
	# 											 "Automatically goes back "
	# 											 "to false.")

	# _trigger_armed = BoolRegister(0x0, 0, doc="Set to True to arm trigger")

	# _trigger_sources = sorted_dict({"off": 0,
	# 								"immediately": 1,
	# 								"ch1_positive_edge": 2,
	# 								"ch1_negative_edge": 3,
	# 								"ch2_positive_edge": 4,
	# 								"ch2_negative_edge": 5,
	# 								"ext_positive_edge": 6,  # DIO0_P pin
	# 								"ext_negative_edge": 7,  # DIO0_P pin
	# 								"asg0": 8,
	# 								"asg1": 9,
	# 								"dsp": 10, #dsp trig module trigger
	# 								"adc1_positive_edge": 11,
	# 								"adc1_negative_edge": 12,
	# 								"adc2_positive_edge": 13,
	# 								"adc2_negative_edge": 14,}, 
	# 								sort_by_values=True)

	# trigger_sources = _trigger_sources.keys()  # help for the user

	# _trigger_source_register = SelectRegister(0x4, doc="Trigger source",
	# 										  options=_trigger_sources)

	# trigger_source = SelectProperty(default='immediately',
	# 								options=_trigger_sources.keys(),
	# 								doc="Trigger source for the scope. Use "
	# 									"'immediately' if no "
	# 									"synchronisation is required. "
	# 									"Trigger_source will be ignored in "
	# 									"rolling_mode.",
	# 								call_setup=True)

	# _trigger_debounce = IntRegister(0x90, doc="Trigger debounce time [cycles]")

	# trigger_debounce = FloatRegister(0x90, bits=20, norm=125e6,
	# 								 doc="Trigger debounce time [s]")

	# # same theshold and hysteresis for both channels
	# threshold = FloatRegister(0x8, bits=14, norm=2 ** 13,
	# 							  doc="trigger threshold [volts]")
	# hysteresis = FloatRegister(0x20, bits=14, norm=2 ** 13,
	# 								doc="hysteresis for trigger [volts]")
	
	# external_trigger_pin = digitalPinRegister(- addr_base + HK.addr_base + 0x28, startBit=0)

	# @property
	# def threshold_ch1(self):
	# 	self._logger.warning('The scope attribute "threshold_chx" is deprecated. '
	# 						 'Please use "threshold" instead!')
	# 	return self.threshold
	# @threshold_ch1.setter
	# def threshold_ch1(self, v):
	# 	self._logger.warning('The scope attribute "threshold_chx" is deprecated. '
	# 						 'Please use "threshold" instead!')
	# 	self.threshold = v
	# @property
	# def threshold_ch2(self):
	# 	self._logger.warning('The scope attribute "threshold_chx" is deprecated. '
	# 						 'Please use "threshold" instead!')
	# 	return self.threshold
	# @threshold_ch2.setter
	# def threshold_ch2(self, v):
	# 	self._logger.warning('The scope attribute "threshold_chx" is deprecated. '
	# 						 'Please use "threshold" instead!')
	# 	self.threshold = v
	# @property
	# def hysteresis_ch1(self):
	# 	self._logger.warning('The scope attribute "hysteresis_chx" is deprecated. '
	# 						 'Please use "hysteresis" instead!')
	# 	return self.hysteresis
	# @hysteresis_ch1.setter
	# def hysteresis_ch1(self, v):
	# 	self._logger.warning('The scope attribute "hysteresis_chx" is deprecated. '
	# 						 'Please use "hysteresis" instead!')
	# 	self.hysteresis = v
	# @property
	# def hysteresis_ch2(self):
	# 	self._logger.warning('The scope attribute "hysteresis_chx" is deprecated. '
	# 						 'Please use "hysteresis" instead!')
	# 	return self.hysteresis
	# @hysteresis_ch2.setter
	# def hysteresis_ch2(self, v):
	# 	self._logger.warning('The scope attribute "hysteresis_chx" is deprecated. '
	# 						 'Please use "hysteresis" instead!')
	# 	self.hysteresis = v
	# #threshold_ch1 = FloatRegister(0x8, bits=14, norm=2 ** 13,
	# #                              doc="ch1 trigger threshold [volts]")
	# #threshold_ch2 = FloatRegister(0xC, bits=14, norm=2 ** 13,
	# #                              doc="ch1 trigger threshold [volts]")
	# #hysteresis_ch1 = FloatRegister(0x20, bits=14, norm=2 ** 13,
	# #                               doc="hysteresis for ch1 trigger [volts]")
	# #hysteresis_ch2 = FloatRegister(0x24, bits=14, norm=2 ** 13,
	# #                               doc="hysteresis for ch2 trigger [volts]")

	# _trigger_delay_register = IntRegister(0x10,
	# 							 doc="number of decimated data after trigger "
	# 								 "written into memory [samples]")

	# trigger_delay = FloatProperty(min=-10, # TriggerDelayAttribute
	# 							  max=8e-9 * 2 ** 30,
	# 							  doc="delay between trigger and "
	# 								  "acquisition start.\n"
	# 								  "negative values down to "
	# 								  "-duration are allowed for "
	# 								  "pretrigger. "
	# 								  "In trigger_source='immediately', "
	# 								  "trigger_delay is ignored.",
	# 							  call_setup=True)

	# _trigger_delay_running = BoolRegister(0x0, 2,
	# 									  doc="trigger delay running ("
	# 										  "register adc_dly_do)")

	# _adc_we_keep = BoolRegister(0x0, 3,
	# 							doc="Scope resets trigger automatically ("
	# 								"adc_we_keep)")

	# _adc_we_cnt = IntRegister(0x2C, doc="Number of samles that have passed "
	# 									"since trigger was armed (adc_we_cnt)")

	# current_timestamp = LongRegister(0x15C,
	# 								 bits=64,
	# 								 doc="An absolute counter "
	# 									 + "for the time [cycles]")

	# trigger_timestamp = LongRegister(0x164,
	# 								 bits=64,
	# 								 doc="An absolute counter "
	# 									 + "for the trigger time [cycles]")

	# _decimations = sorted_dict({2 ** n: 2 ** n for n in range(0, 17)},
	# 						   sort_by_values=True)

	# decimations = _decimations.keys()  # help for the user

	# # decimation is the basic register, sampling_time and duration are slaves of it
	# decimation = DecimationRegister(0x14, doc="decimation factor",
	# 								default = 0x2000, # fpga default = 1s duration
	# 								# customized to update duration and
	# 								# sampling_time
	# 								options=_decimations,
	# 								call_setup=True)

	# sampling_times = [8e-9 * dec for dec in decimations]

	# sampling_time = SamplingTimeProperty(options=sampling_times)

	# minTime1 = peakIndexRegister(0x94, default = 0x0, doc = "time after the trigger from which the peak on channel 1 is checked (the peak is searched only between minTime1 and maxTime1)")
	# maxTime1 = peakIndexRegister(0x98, default = 0x2000, doc = "time after the trigger at which the peak on channel 1 is no longer checked")
	# minTime2 = peakIndexRegister(0x9C, default = 0x0, doc = "time after the trigger from which the peak on channel 2 is checked (the peak is searched only between minTime2 and maxTime2)")
	# maxTime2 = peakIndexRegister(0xA0, default = 0x2000, doc = "time after the trigger at which the peak on channel 2 is no longer checked")
	# minTime3 = peakIndexRegister(0xBC, default = 0x0, doc = "time after the trigger from which the peak on channel 3 is checked (the peak is searched only between minTime3 and maxTime3)")
	# maxTime3 = peakIndexRegister(0xC0, default = 0x2000, doc = "time after the trigger at which the peak on channel 3 is no longer checked")

	# peakInputsList = {"adc1" : 0, "adc2" : 1, "ch1" : 2, "ch2" : 3}
	# peak_refL_input =  SelectRegister(0xB0, startBit=0, doc="input used for the first peak search",
	# 										  options=peakInputsList)
	# peak_refR_input =  SelectRegister(0xB0, startBit=2, doc="input used for the first peak search",
	# 										  options=peakInputsList)
	# peak_ctrl_input =  SelectRegister(0xB0, startBit=4, doc="input used for the first peak search",
	# 										  options=peakInputsList)

	# peak_refL_minValue = FloatRegister(0xB4, startBit= 0, bits=14, norm=2 ** 13,
	# 							doc="minimum value for the peak detection. If no value is seen above this, the peak will not be updated, and its valid flag will be set to 0")
	# peak_refR_minValue = FloatRegister(0xB4, startBit= 14, bits=14, norm=2 ** 13,
	# 							doc="minimum value for the peak detection. If no value is seen above this, the peak will not be updated, and its valid flag will be set to 0")
	# peak_ctrl_minValue = FloatRegister(0xCC, startBit= 0, bits=14, norm=2 ** 13,
	# 							doc="minimum value for the peak detection. If no value is seen above this, the peak will not be updated, and its valid flag will be set to 0")

	# peakRangeRegisters = dict(
	# 	minTime1 = minTime1,
	# 	maxTime1 = maxTime1,
	# 	minTime2 = minTime2,
	# 	maxTime2 = maxTime2,
	# 	minTime3 = minTime3,
	# 	maxTime3 = maxTime3,
	# )

	# # list comprehension workaround for python 3 compatibility
	# # cf. http://stackoverflow.com/questions/13905741
	# durations = [st * data_length for st in sampling_times]

	# duration = DurationProperty(options=durations)

	# _write_pointer_current = IntRegister(0x18,
	# 									 doc="current write pointer "
	# 										 "position [samples]")

	# _write_pointer_trigger = IntRegister(0x1C,
	# 									 doc="write pointer when trigger "
	# 										 "arrived [samples]")

	# average = BoolRegister(0x28, 0,
	# 					   doc="Enables averaging during decimation if set "
	# 						   "to True")

	# # equalization filter not implemented here

	# voltage_in1 = FloatRegister(0x154, bits=14, norm=2 ** 13,
	# 							doc="in1 current value [volts]")

	# voltage_in2 = FloatRegister(0x158, bits=14, norm=2 ** 13,
	# 							doc="in2 current value [volts]")

	# voltage_out1 = FloatRegister(0x164, bits=14, norm=2 ** 13,
	# 							 doc="out1 current value [volts]")

	# voltage_out2 = FloatRegister(0x168, bits=14, norm=2 ** 13,
	# 							 doc="out2 current value [volts]")

	# ch1_firstpoint = FloatRegister(0x10000, bits=14, norm=2 ** 13,
	# 							   doc="1 sample of ch1 data [volts]")

	# ch2_firstpoint = FloatRegister(0x20000, bits=14, norm=2 ** 13,
	# 							   doc="1 sample of ch2 data [volts]")

	# pretrig_ok = BoolRegister(0x16c, 0,
	# 						  doc="True if enough data have been acquired "
	# 							  "to fill the pretrig buffer")

	# ch1_active = BoolProperty(default=True,
	# 						  doc="should ch1 be displayed in the gui?")

	# ch2_active = BoolProperty(default=True,
	# 						  doc="should ch2 be displayed in the gui?")

	# ch_math_active = BoolProperty(default=False,
	# 						  doc="should ch_math be displayed in the gui?")

	# math_formula = StringProperty(default='ch1 * ch2',
	# 							  doc="formula for channel math")

	# xy_mode = BoolProperty(default=False,
	# 					   doc="in xy-mode, data are plotted vs the other "
	# 						   "channel (instead of time)")

	# _acquisition_started = BoolProperty(default=False,
	# 									doc="whether a curve acquisition has been "
	# 										"initiated")

	# def _ownership_changed(self, old, new):
	# 	"""
	# 	If the scope was in continuous mode when slaved, it has to stop!!
	# 	"""
	# 	if new is not None:
	# 		self.stop()

	# @property
	# def _rawdata_ch1(self):
	# 	"""raw data from ch1"""
	# 	# return np.array([self.to_pyint(v) for v in self._reads(0x10000,
	# 	# self.data_length)],dtype=np.int32)
	# 	x = np.array(self._reads(0x10000, self.data_length), dtype=np.int16)
	# 	x[x >= 2 ** 13] -= 2 ** 14
	# 	return x

	# @property
	# def _rawdata_ch2(self):
	# 	"""raw data from ch2"""
	# 	# return np.array([self.to_pyint(v) for v in self._reads(0x20000,
	# 	# self.data_length)],dtype=np.int32)
	# 	x = np.array(self._reads(0x20000, self.data_length), dtype=np.int16)
	# 	x[x >= 2 ** 13] -= 2 ** 14
	# 	return x

	# @property
	# def _data_ch1(self):
	# 	""" acquired (normalized) data from ch1"""
	# 	return np.array(
	# 		np.roll(self._rawdata_ch1, - (self._write_pointer_trigger +
	# 									  self._trigger_delay_register + 1)),
	# 		dtype=float) / 2 ** 13

	# @property
	# def _data_ch2(self):
	# 	""" acquired (normalized) data from ch2"""
	# 	return np.array(
	# 		np.roll(self._rawdata_ch2, - (self._write_pointer_trigger +
	# 									  self._trigger_delay_register + 1)),
	# 		dtype=float) / 2 ** 13

	# @property
	# def _data_ch1_current(self):
	# 	""" (unnormalized) data from ch1 while acquisition is still running"""
	# 	return np.array(
	# 		np.roll(self._rawdata_ch1, -(self._write_pointer_current + 1)),
	# 		dtype=float) / 2 ** 13

	# @property
	# def _data_ch2_current(self):
	# 	""" (unnormalized) data from ch2 while acquisition is still running"""
	# 	return np.array(
	# 		np.roll(self._rawdata_ch2, -(self._write_pointer_current + 1)),
	# 		dtype=float) / 2 ** 13

	# @property
	# def times(self):
	# 	# duration = 8e-9*self.decimation*self.data_length
	# 	# endtime = duration*
	# 	duration = self.duration
	# 	trigger_delay = self.trigger_delay
	# 	if self.trigger_source!='immediately':
	# 		return np.linspace(trigger_delay - duration / 2.,
	# 						   trigger_delay + duration / 2.,
	# 						   self.data_length, endpoint=False)
	# 	else:
	# 		return np.linspace(0,
	# 						   duration,
	# 						   self.data_length, endpoint=False)

	# async def wait_for_pretrigger_async(self):
	# 	"""sleeps until scope trigger is ready (buffer has enough new data)"""
	# 	while not self.pretrig_ok:
	# 		await sleep_async(0.001)
	# 	### For some reason, launching the trigger at that point would be too soon...
	# 	await sleep_async(0.1)

	# def wait_for_pretrigger(self):
	# 	"""sleeps until scope trigger is ready (buffer has enough new data)"""
	# 	wait(self.wait_for_pretrigger_async())

	# def curve_ready(self):
	# 	"""
	# 	Returns True if new data is ready for transfer
	# 	"""
	# 	return (not self._trigger_armed) and \
	# 		   (not self._trigger_delay_running) and self._acquisition_started

	# def _curve_acquiring(self):
	# 	"""
	# 	Returns True if data is in the process of being acquired, i.e.
	# 	waiting for trigger event or for acquisition of data after
	# 	trigger event.
	# 	"""
	# 	return (self._trigger_armed or self._trigger_delay_running) \
	# 		and self._acquisition_started

	# def _get_ch(self, ch):
	# 	if ch not in [1, 2]:
	# 		raise ValueError("channel should be 1 or 2, got " + str(ch))
	# 	return self._data_ch1 if ch == 1 else self._data_ch2

	# # Concrete implementation of AcquisitionModule methods
	# # ----------------------------------------------------

	# def _prepare_averaging(self):
	# 	super(Scope, self)._prepare_averaging()
	# 	self.data_x = np.copy(self.times)
	# 	self.data_avg = np.zeros((2, len(self.times)))
	# 	self.current_avg = 0


	# def _get_trace(self):
	# 	"""
	# 	Simply pack together channel 1 and channel 2 curves in a numpy array
	# 	"""
	# 	return np.array((self._get_ch(1), self._get_ch(2)))

	# def _remaining_time(self):
	# 	"""
	# 	:returns curve duration - ellapsed duration since last setup() call.
	# 	"""
	# 	return self.duration - (time() - self._last_time_setup)

	# async def _do_average_continuous_async(self):
	# 	if not self._is_rolling_mode_active():
	# 		await super(Scope, self)._do_average_continuous_async()
	# 	else: # no need to prepare averaging
	# 		self._start_acquisition_rolling_mode()
	# 		while(self.running_state=="running_continuous"):
	# 			await sleep_async(self.MIN_DELAY_CONTINUOUS_ROLLING_MS*0.001)
	# 			self.data_x, self.data_avg = self._get_rolling_curve()
	# 			self._emit_signal_by_name('display_curve', [self.data_x, self.data_avg])

	# def _data_ready(self):
	# 	"""
	# 	:return: True if curve is ready in the hardware, False otherwise.
	# 	"""
	# 	return self.curve_ready()

	# def _start_trace_acquisition(self):
	# 	"""
	# 	Start acquisition of a curve in rolling_mode=False
	# 	"""
	# 	autosave_backup = self._autosave_active
	# 	self._autosave_active = False  # Don't save anything in config file
	# 	# during setup!! # maybe even better in
	# 	# BaseModule ??
	# 	self._acquisition_started = True

	# 	# 0. reset state machine
	# 	self._reset_writestate_machine = True

	# 	# set the trigger delay:
	# 	# 1. in mode "immediately", trace goes from 0 to duration,
	# 	if self.trigger_source == 'immediately':
	# 		self._trigger_delay_register = self.data_length
	# 	else: #  2. triggering on real signal
	# 		#  a. convert float delay into counts
	# 		delay = int(np.round(self.trigger_delay / self.sampling_time)) + \
	# 				self.data_length // 2
	# 		#  b. Do the proper roundings of the trigger delay
	# 		if delay <= 0:
	# 			delay = 1  # bug in scope code: 0 does not work
	# 		elif delay > 2 ** 32 - 1:
	# 			delay = 2 ** 32 - 1
	# 		# c. set the trigger_delay in the right fpga register
	# 		self._trigger_delay_register = delay

	# 	# 4. Arm the trigger: curve acquisition will only start passed this
	# 	self._trigger_armed = True
	# 	# 5. In case immediately, setting again _trigger_source_register
	# 	# will cause a "software_trigger"
	# 	self._trigger_source_register = self.trigger_source

	# 	self._autosave_active = autosave_backup
	# 	self._last_time_setup = time()

	# def _start_acquisition_rolling_mode(self):
	# 	self._start_trace_acquisition()
	# 	self._trigger_source_register = 'off'
	# 	self._trigger_armed = True

	# # Rolling_mode related methods:
	# # -----------------------------

	# #def _start_acquisition_rolling_mode(self):
	# #    self._start_acquisition()
	# #    self._trigger_source_register = 'off'
	# #   self._trigger_armed = True

	# def _rolling_mode_allowed(self):
	# 	"""
	# 	Only if duration larger than 0.1 s
	# 	"""
	# 	return self.duration > 0.1

	# def _is_rolling_mode_active(self):
	# 	"""
	# 	Rolling_mode property evaluates to True and duration larger than 0.1 s
	# 	"""
	# 	return self.rolling_mode and self._rolling_mode_allowed()

	# def _get_ch_no_roll(self, ch):
	# 	if ch not in [1, 2]:
	# 		raise ValueError("channel should be 1 or 2, got " + str(ch))
	# 	return self._rawdata_ch1 * 1. / 2 ** 13 if ch == 1 else \
	# 		self._rawdata_ch2 * 1. / 2 ** 13

	# def _get_rolling_curve(self):
	# 	datas = np.zeros((2, len(self.times)))
	# 	# Rolling mode
	# 	wp0 = self._write_pointer_current  # write pointer
	# 	# before acquisition
	# 	times = self.times
	# 	times -= times[-1]

	# 	for ch, active in (
	# 			(0, self.ch1_active),
	# 			(1, self.ch2_active)):
	# 		if active:
	# 			datas[ch] = self._get_ch_no_roll(ch + 1)
	# 	wp1 = self._write_pointer_current  # write pointer after
	# 	#  acquisition
	# 	for index, active in [(0, self.ch1_active),
	# 						  (1, self.ch2_active)]:
	# 		if active:
	# 			data = datas[index]
	# 			to_discard = (wp1 - wp0) % self.data_length  # remove
	# 			#  data that have been affected during acq.
	# 			data = np.roll(data, self.data_length - wp0)[
	# 				   to_discard:]
	# 			data = np.concatenate([[np.nan] * to_discard, data])
	# 			datas[index] = data
	# 	return times, datas

	# # Custom behavior of AcquisitionModule methods for scope:
	# # -------------------------------------------------------

	# def save_curve(self):
	# 	"""
	# 	Saves the curve(s) that is (are) currently displayed in the gui in
	# 	the db_system. Also, returns the list [curve_ch1, curve_ch2]...
	# 	"""
	# 	d = self.attributes_last_run
	# 	curves = [None, None]
	# 	for ch, active in [(0, self.ch1_active),
	# 					   (1, self.ch2_active)]:
	# 		if active:
	# 			d.update({'ch': ch,
	# 					  'name': self.curve_name + ' ch' + str(ch + 1)})
	# 			curves[ch] = self._save_curve(self.data_x,
	# 										  self.data_avg[ch],
	# 										  **d)
	# 	return curves
	
	# @staticmethod
	# def getLastAcquisition(signalName):
	# 	if signalName in Scope.lastInputs:
	# 		return AcquisitionModule.lastData[Scope.lastInputs.index(signalName)]
	# 	raise Exception(f"signal {signalName} was not used in the last acquisition, do a new acquisition with this signal")