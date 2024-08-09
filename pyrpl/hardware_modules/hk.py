from ..attributes import IntRegister, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister
from ..modules import HardwareModule
from ..widgets.module_widgets.hk_widget import HkWidget
import numpy as np


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
                        ['expansion_N' + str(i) for i in range(8)] + \
                        ['expansion_N' + str(i) + '_output' for i in range(8)] + \
                        ['fastSwitch_activeTime'] + \
                        ['fastSwitch_inactiveTime'] + \
                        ['fastSwitch_triggerPin'] + \
                        ['fastSwitch_channelsDelay'] + \
                        ['useFastSwitch' + str(i) for i in range(8)]
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
    for i in range(8):
        locals()['useFastSwitch' + str(i)] = BoolRegister(0x34,  bit=i+16,
                                                      doc="positive digital io")
    
    fastSwitch_activeTime = GainRegister(0x34, bits=8, startBit=0, norm=125e6, signed = False)
    fastSwitch_inactiveTime = GainRegister(0x34, bits=8, startBit=8, norm=125e6, signed = False)
    fastSwitch_triggerPin = digitalPinRegister(0x34, startBit=24)
    fastSwitch_channelsDelay = GainRegister(0x38, bits=8, startBit=0, norm=125e6, signed = True)
    
    def setFastSwitch(self, pin = 0, triggerPin = '1p', activeTime = 1e-6, inactiveTime = 40e-9, channelsDelay = 0):
        self.fastSwitch_triggerPin = triggerPin
        setattr(self, 'useFastSwitch' + str(pin), True)
        setattr(self, 'expansion_P' + str(pin) + "_output", True)
        setattr(self, 'expansion_N' + str(pin) + "_output", True)
        
        self.fastSwitch_activeTime = activeTime
        self.fastSwitch_inactiveTime = inactiveTime
        self.fastSwitch_channelsDelay = channelsDelay
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        