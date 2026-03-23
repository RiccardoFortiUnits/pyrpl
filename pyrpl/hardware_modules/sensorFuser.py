from ..attributes import IntRegister, ArrayRegister, FloatRegister, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister, FloatProperty, ExpandableProperty

from ..module_attributes import ModuleListProperty, Module
from ..widgets.module_widgets.sensorFuser_widget import sensor_fuser_widget, sensorToBeFused_widget
import numpy as np
from .dsp import DspModule, all_inputs, dsp_addr_base, InputSelectRegister



class sensorToBeFused(Module):
	'''submodule for the handling of a secondary peak, to set some parameters that involve all the peaks of that same redpitaya'''
	_gui_attributes = [
					"minValue",
					"transitionValue",
					"maxValue"
					]
	_setup_attributes = _gui_attributes
	_widget_class = sensorToBeFused_widget
	def __init__(self, parent, name):
		super().__init__(parent, name)
# 		self.addToSubmodules()
		self.sensor_fuser = parent

	minValue = ExpandableProperty(
		FloatProperty(-1, 1, doc = "min value that the input can have"),
		extraFunctionToDoAfterSettingValue=lambda currentProperty, instance, value : instance.parent.updateFPGA_valuesFromSensorValues()
	)
	maxValue = ExpandableProperty(
		FloatProperty(-1, 1, doc = "max value that the input can have"),
		extraFunctionToDoAfterSettingValue=lambda currentProperty, instance, value : instance.parent.updateFPGA_valuesFromSensorValues()
	)
	transitionValue = ExpandableProperty(
		FloatProperty(-1, 1, doc = "value that the input has when the other sensor is at its limit/saturation"),
		extraFunctionToDoAfterSettingValue=lambda currentProperty, instance, value : instance.parent.updateFPGA_valuesFromSensorValues()
	)



class sensor_fuser(DspModule):
	_widget_class = sensor_fuser_widget

	_setup_attributes = ["input",
					  	 "secondInput",
						 "output_direct",
						 "section_low",
						 "section_med",
						 ]

	_gui_attributes =  _setup_attributes

	def __init__(self, rp, name, index=0):
		super().__init__(rp, name, index)
		self.sensor_a : sensorToBeFused = sensorToBeFused(self, f"{self.name}.sensor_a")
		self.sensor_b : sensorToBeFused = sensorToBeFused(self, f"{self.name}.sensor_b")
		self.updatingAllValues = False
		# self.updateSensorValuesFromFPGA()

	secondInput = InputSelectRegister(- dsp_addr_base("sensor_fuser") + dsp_addr_base("sensor_fuser_in1") + 0x0,
									options=all_inputs,
									default='in2',
									ignore_errors=True,
									doc="selects the input signal of the module")
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
		return 1 - self.section_low - self.section_med

	def updateFPGA_valuesFromSensorValues(self):
		if self.updatingAllValues:
			return
		sf = self
		try:
			sf.offset_a_low		= sf.sensor_a.minValue
			sf.offset_a_med		= sf.sensor_a.transitionValue
			sf.offset_b_med		= sf.sensor_b.minValue
			sf.offset_b_high	= sf.sensor_b.transitionValue
			sf.gain_a_low		= sf.section_low / (sf.sensor_a.transitionValue - sf.sensor_a.minValue)
			sf.gain_a_med		= sf.section_med / (sf.sensor_a.maxValue - sf.sensor_a.transitionValue)
			sf.gain_b_med		= sf.section_med / (sf.sensor_b.transitionValue - sf.sensor_b.minValue)
			sf.gain_b_high		= sf.section_high / (sf.sensor_b.maxValue - sf.sensor_b.transitionValue)
		except Exception as e:
			print("set all the values to avoid divisions by 0")
# 			raise(e)
		
	def updateSensorValuesFromFPGA(self):
		self.updatingAllValues = True
		try:
			sf = self
			try:
				sf.sensor_a.minValue = 			sf.offset_a_low
				sf.sensor_a.transitionValue = 	sf.offset_a_med
				sf.sensor_b.minValue = 			sf.offset_b_med
				sf.sensor_b.transitionValue = 	sf.offset_b_high
				sf.sensor_a.maxValue = sf.sensor_a.transitionValue + sf.section_med / sf.gain_a_med
				sf.sensor_b.maxValue = sf.sensor_b.transitionValue + sf.section_high / sf.gain_b_high
			except Exception as e:
				print("set all the values to avoid divisions by 0")
# 				raise(e)
		finally:
			self.updatingAllValues = False