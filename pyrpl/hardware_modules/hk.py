from ..attributes import IntRegister, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister
from ..modules import HardwareModule
from ..widgets.module_widgets.hk_widget import HkWidget
import numpy as np
from .dsp import all_inputs, dsp_addr_base, InputSelectRegister


class ExpansionDirection(BoolProperty):
	def set_value(self, obj, val):
		obj._set_expansion_direction(self.name.strip('_output'), val)

	def get_value(self, obj):
		return obj._get_expansion_direction(self.name.strip('_output'))


class HK(HardwareModule):
	_widget_class = HkWidget

	_setup_attributes = ["led"] + \
						['expansion_P' + str(i) for i in range(8)] + \
						['expansion_P' + str(i) + '_output' for i in range(8)]+ \
						['pinState_P' + str(i) for i in range(8)] + \
						['external_P' + str(i) + "_otherPinSelector" for i in range(8)] + \
						['external_P' + str(i) + "_dspBitSelector" for i in range(8)] + \
						['expansion_N' + str(i) for i in range(8)] + \
						['expansion_N' + str(i) + '_output' for i in range(8)] + \
						['pinState_N' + str(i) for i in range(8)] + \
						['external_N' + str(i) + "_otherPinSelector" for i in range(8)] + \
						['external_N' + str(i) + "_dspBitSelector" for i in range(8)] + \
						['fastSwitch_activeTime'] + \
						['fastSwitch_inactiveTime'] + \
						['fastSwitch_channelsDelay'] + \
						['fastSwitch_triggerPin'] + \
						['pi_blast_inactive_TweezerPi'] + \
						['pi_blast_pi'] + \
						['pi_blast_inactive_PiBlast'] + \
						['pi_blast_blast'] + \
						['pi_blast_inactive_BlastTweezer'] + \
						['piBlast_triggerPin'] + \
						['input1'] + \
						['input2'] +\
						['genericModuleTrigger']
	_gui_attributes =  _setup_attributes
	addr_base = 0x40000000
	# We need all attributes to be there when the interpreter is done reading the class (for metaclass to workout)
	# see http://stackoverflow.com/questions/2265402/adding-class-attributes-using-a-for-loop-in-python
	for i in range(8):
		locals()['expansion_P' + str(i)] = IORegister(0x20, 0x18, 0x10, bit=i,
													  outputmode=True,
													  doc="positive digital io")
		locals()['expansion_P' + str(i) + '_output'] = ExpansionDirection(
													  doc="direction of the "
														  "port")
		locals()['expansion_N' + str(i)] = IORegister(0x24, 0x1C, 0x14, bit=i,
													  outputmode=True,
													  doc="positive digital io")
		locals()['expansion_N' + str(i) + '_output'] = ExpansionDirection(
													  doc="direction of the "
														  "port")

	id = SelectRegister(0x0, doc="device ID", options={"prototype0": 0,
													   "release1": 1})
	digital_loop = IntRegister(0x0C, doc="enables digital loop")
	led = IntRegister(0x30, doc="LED control with bits 1:8", min=0, max=2**8)
	# another option: access led as array of bools
	# led = [BoolRegister(0x30,bit=i,doc="LED "+str(i)) for i in range(8)]
	scopeExternalTrigger = digitalPinRegister(0x28, startBit=0x0, doc="pin that triggers the scope module")
	asgExternalTrigger = digitalPinRegister(0x28, startBit=0x4, doc="pin that triggers the asg modules")
	rampExternalTrigger = digitalPinRegister(0x28, startBit=0x8, doc="pin that triggers the ramp modules")
	genericModuleTrigger = digitalPinRegister(0x28, startBit=0xC, doc="pin that can disable dsp modules, if their 'useGenericTrigger' value is checked")

	def set_expansion_direction(self, index, val):
		"""Sets the output mode of expansion index (both for P and N expansions)"""
		if not index in range(8):
			raise ValueError("Index from 0 to 7 expected")
		for name in ["expansion_P", "expansion_N"]:
			getattr(HK, name + str(index)).direction(self, val)

	def _setup(self): # the function is here for its docstring to be used by the metaclass.
		"""
		Sets the HouseKeeping module of the redpitaya up. (just setting the attributes is OK)
		"""
		pass

	def _set_expansion_direction(self, name, val):
		"""Sets the output mode of expansion index (both for P and N expansions)"""
		#if not index in range(8):
		#    raise ValueError("Index from 0 to 7 expected")
		#for name in ["expansion_P", "expansion_N"]:
		getattr(HK, name).direction(self, val)

	def _get_expansion_direction(self, name):
		"""Sets the output mode of expansion index (both for P and N expansions)"""
		#if not index in range(8):
			#raise ValueError("Index from 0 to 7 expected")
		return getattr(HK, name).outputmode# direction(self,
		# val)
		
		
# class HK_noveau(HK):    

	input1 = InputSelectRegister(- addr_base + dsp_addr_base('dig0') + 0x0,
								 options=all_inputs,
								 default='in1',
								 ignore_errors=True,
								 doc="selects the input signal of the module")

	input2 = InputSelectRegister(- addr_base + dsp_addr_base('dig1') + 0x0,
								 options=all_inputs,
								 default='in2',
								 ignore_errors=True,
								 doc="selects the input signal of the module")
	for i in range(8):
		for (sign, j) in [('P', 1), ('N', 0)]:
			#todo: I messed up the order in the fpga. We should put it back in a proper manner 
			locals()[f'pinState_{sign}{i}'] = SelectRegister(0x38 - j*4, startBit = i*3, doc=f"chooses the origin of value set into expansion_{sign}{i}", options={
										"memory": 0,
										"otherPin": 1,
										"dsp": 2,
										"fastSwitch": 3,
										"tweezer_πpulse" : 4
										})
			
			locals()[f'external_{sign}{i}_otherPinSelector'] = digitalPinRegister(0x50 + 4*i, startBit = 0 + (4+5)*j, doc=f"if pinState_{sign}{i} == otherPin, the output of this pin will follow the output of the selected pin")
			locals()[f'external_{sign}{i}_dspBitSelector'] = IntRegister(0x50 + 4*i, startBit = 4 + (4+5)*j, bits=5, doc=f"if pinState_{sign}{j} == dsp, the output of this pin will follow the selected bit of the dsp inputs")
		

		
	#     locals()['expansion_N' + str(i) + "_followTrigger"] = BoolRegister(0x34, bit=i,
	#                                                   doc="if 0, the ouput will follow expansion_N"+str(i)+"_output, otherwise, it will follow the value of fastSwitch_triggerPin")
	#     locals()['expansion_P' + str(i) + "_followTrigger"] = BoolRegister(0x34, bit=i+8,
	#                                                   doc="if 0, the ouput will follow expansion_P"+str(i)+"_output, otherwise, it will follow the value of fastSwitch_triggerPin")
	#     locals()['useFastSwitch' + str(i)] = BoolRegister(0x34,  bit=i+16,
	#                                                   doc=f"if 1, pins N{i} and P{i} will execute an alternate switch")
	
	fastSwitch_activeTime = GainRegister(0x3C, bits=8, startBit=0, norm=125e6, signed = False)
	fastSwitch_inactiveTime = GainRegister(0x3C, bits=8, startBit=8, norm=125e6, signed = False)
	fastSwitch_triggerPin = digitalPinRegister(0x3C, startBit=16)
	fastSwitch_channelsDelay = GainRegister(0x40, bits=8, startBit=0, norm=125e6, signed = True)
	
	def setFastSwitch(self, pin = 0, triggerPin = '1p', activeTime = 1e-6, inactiveTime = 40e-9, channelsDelay = 0):
		self.fastSwitch_triggerPin = triggerPin
		setattr(self, 'useFastSwitch' + str(pin), True)
		setattr(self, 'expansion_P' + str(pin) + "_output", True)
		setattr(self, 'expansion_N' + str(pin) + "_output", True)
		
		self.fastSwitch_activeTime = activeTime
		self.fastSwitch_inactiveTime = inactiveTime
		self.fastSwitch_channelsDelay = channelsDelay

	piBlast_triggerPin = digitalPinRegister(0x3C, startBit=20)
	pi_blast_inactive_TweezerPi = 		GainRegister(0x48, bits=32, startBit=0, norm=125e6, signed = False)	
	pi_blast_pi = 						GainRegister(0x44, bits=8, startBit=24, norm=125e6, signed = False)
	pi_blast_inactive_PiBlast = 		GainRegister(0x44, bits=8, startBit=16, norm=125e6, signed = False)
	pi_blast_blast = 					GainRegister(0x44, bits=8, startBit=8, norm=125e6, signed = False)
	pi_blast_inactive_BlastTweezer = 	GainRegister(0x44, bits=8, startBit=0, norm=125e6, signed = False)
