import numpy as np
from ..modules import HardwareModule
from ..attributes import PWMRegister, FloatProperty, BoolRegister, FloatRegister, GainRegister, SelectRegister, digitalPinRegister, IntRegister
import logging

logger = logging.getLogger(name=__name__)


class AMS(HardwareModule):
    """mostly deprecated module (redpitaya has removed adc support).
    only here for dac2 and dac3"""
    addr_base = 0x40300000

    # attention: writing to dac0 and dac1 has no effect
    # only write to dac2 and 3 to set output voltages
    # to modify dac0 and dac1, connect a r.pwm0.input='pid0'
    # and let the pid module determine the voltage
    dac0 = PWMRegister(0x20, doc="PWM output 0 [V]")
    dac1 = PWMRegister(0x24, doc="PWM output 1 [V]")
    dac2 = PWMRegister(0x28, doc="PWM output 2 [V]")
    dac3 = PWMRegister(0x2C, doc="PWM output 3 [V]")

    def _setup(self): # the function is here for its docstring to be used by the metaclass.
        """
        sets up the AMS (just setting the attributes is OK)
        """
        pass



class AmsNouveau(HardwareModule):
    addr_base = 0x40300000
    linearizer_nOfSegments = 8
    ramp_nOfSegments = 8

    outputSource = SelectRegister(0x20, bits=2, startBit=0,options={"static":0,"ramp":1,"copyADC":2},
                                  doc="select the source that will generate the PWM output. \nStatic: PWM will output the value of parameter 'staticValue'; \nramp: the PWM will execute the ramp function (more detaills in the ramp properties);\ncopyADC: the PWM will copy the selected fast ADC. You can even scale and shift the output.")
    ADC_select = IntRegister(0x20,bits = 1, startBit= 2,
                             doc="select wich ADC input will be copied in the output or used as a trigger input for the ramp")
    useLinearizer = BoolRegister(0x20,0x3,
                                 doc="enable/disable a linearizer module (set it with function setLinearizer())")
    TriggerPin = digitalPinRegister(0x20, startBit=0x4)
    staticValue = FloatRegister(0x20, bits=0x8, startBit= 0x10, signed = False, norm = 0xFF / 1.8, max=1.8,min=0,
                                doc="value of the PWM when the outputSource 'static' is selected")
    
    #values normalized (between [0 1], instead of [0 1.8]), the normalization is done by setLinearizer
    for i in range(linearizer_nOfSegments):
        locals()['linearizer_x' + str(i)] = GainRegister(0x40+i*4,bits=8, startBit=0,norm=255, signed=False)
        locals()['linearizer_q' + str(i)] = GainRegister(0x40+i*4,bits=8, startBit=8,norm=255, signed=False)
        locals()['linearizer_m' + str(i)] = GainRegister(0x40+i*4,bits=16, startBit=16,norm=255, signed=True)

    rampTriggerType = SelectRegister(0x60, bits=2, startBit=0,options={"none":0,"now":1,"ADC":2,"digitalPin":3},
                                     doc="select the source that will trigger the ramp function.\nnone: no trigger selected, the ramp won't start;\nnow: the ramp will start as soon as this value is set. After that, the value will automatically go back to 'none';\nADC: the ramp starts whenever the ADC surpasses a certain voltage. You can set the value of this limit and the direction of the edge trigger with 'ramp_ADC_triggerValue' and 'ramp_ADC_triggerEdge' respectively;\ndigitalPin: the ramp starts whenever the pin 'TriggerPin' is high")
    rampIdleConfig = SelectRegister(0x60, bits=2, startBit=2,options={"staticValue":0,"startValue":1,"endValue":2,"invertRamp":3},
                                    doc="select the constant value that the PWM will keep after finishing the ramp.\nstaticValue: use the value of parameter 'staticValue';\nstartValue: use the value of the start of the ramp (i.e., the value of ramp_startValue0);\nendValue: keep the last value that the ramp function reached when it ended;\ninvertRamp:repeat the ramp, by inverting its direction (the idle value will thus be equal to startValue)")

    ramp_ADC_triggerValue = FloatRegister(0x20, bits=14, startBit=0x4, norm= 2 **13,
                                    doc="value that sets the limit for the ramp trigger when 'rampTriggerType'='ADC'. Depending on 'ramp_ADC_triggerEdge', voltages higher or lower than 'ramp_ADC_triggerValue' will trigger the ramp function")
    ramp_ADC_triggerEdge = SelectRegister(0x60, bits=1, startBit=0x12,options={"when_higher":0,"when_lower":1},
                                          doc="the ADC trigger for the ramp function is activated if the value of the ADC input is respectively higher or lower than the value set in parameter 'ramp_ADC_triggerValue'")
    ramp_useMultiTriggers = BoolRegister(0x60,0x13,
                                 doc="if false, one trigger will start the entire ramp function. If true, a trigger will only start one of the segments of the ramp, and thus you'll need 'ramp_numberOfUsedRamps'+1 triggers to finish the entire ramp function. When using multiple triggers, if the current segment is finished but no new trigger has been received yet, the PWM will stay still at the last value reached until a new trigger is received. Instead, if a trigger is received before the current segment is finished, the next segment of the ramp function will start immediately")
    ramp_numberOfUsedRamps = IntRegister(0x60, bits = 10, startBit=0x14,#4 bits are sufficient, but I'm lazy to check if it's true... let's just keep bits = 10
                                         doc="number of ramps that compose the entire ramp function. The max value is 8, but you can also use less ramps")
    
    for i in range(ramp_nOfSegments):
        locals()['ramp_startValue' + str(i)] = GainRegister(0x70+i*8,bits=8, startBit=0,norm=255/1.8, signed=False)
        locals()['ramp_valueStepIncrementer' + str(i)] = IntRegister(0x70+i*8,bits=8, startBit=8, signed = True)
        locals()['ramp_timePerStep' + str(i)] = GainRegister(0x74+i*8,bits=24, startBit=0,norm=125e6, signed = False)
        locals()['ramp_numberOfStep' + str(i)] = IntRegister(0x74+i*8, bits = 8,startBit=24,max=255,min=0)

    def setLLinearizer(self, enable = True, x = [-1, 1], y = [-1, 1]):
        if(len(x) > self._filterMaxCoefficients+1 or len(y) != len(x)):
            logger.error(f"incorrect number of coefficients! max allowed: {self._filterMaxCoefficients}, x and y should have the same length")
            return
        
        def segmentedCoefficient(x,y):
            '''
                transforms the segmented function (x,y) into the list of ramps y[i](x) = q[i] + ((s[i] - x) * m[i]),
                s[i] is the start input value of the ramp
                q[i] is the start output value of the ramp ( y[i](s[i]) = q[i])
                m[i] is the slope of the ramp
            '''
            a = np.array(x[0:len(x)-1])
            b = np.array(x[1:])
            c = np.array(y[0:len(y)-1])
            d = np.array(y[1:])
            
            m = (d-c) / (b-a)
            s = a
            q = c
            return (s,q,m)
        
        (s,q,m) = segmentedCoefficient(x,y)
        
        s = np.append(s,[-1] * (self._filterMaxCoefficients - len(m)))
        q = np.append(q,[0] * (self._filterMaxCoefficients - len(m)))
        m = np.append(m,[0] * (self._filterMaxCoefficients - len(m)))
        
        for i in range(self._filterMaxCoefficients):
            setattr(self,'linearizer_x'+str(i), s[i])
            setattr(self,'linearizer_q'+str(i), q[i])
            setattr(self,'linearizer_m'+str(i), m[i])
            
        self.useLinearizer = enable
    
    def setRamp(self, enable, edges = [0,1.8,1.8,0.5,0], durations = [1e-5,1e-4,2e-5,1e-4], digitalPinTrigger = '0p',
                TriggerType = 'digitalPin', IdleConfig = 'endValue', useMultiTriggers = True):
        
        if(len(durations) != len(edges)-1):
            raise Exception("incorrect sizes for edges and duration, the edges should be one more than the durations")
        if(len(durations) > self.ramp_nOfSegments):
            raise Exception("too many samples!")
            
        for i in range(len(durations)):
            startValue = edges[i]
            endValue = edges[i+1]
            rampTime = durations[i]
            if startValue == endValue:#mantain a constant value
                valueIncrementer = 0
                maxStepTime = 0.10 #should be (2^24 * 8e-9) = 0.134 s, but let's use a just sligthly lower one
                nOfSteps = np.ceil(durations[i] / maxStepTime)#if durations[i] < maxStepTime, we'll just use a single long step
            else:#do a ramp
                valueIncrementer = 1 if startValue < endValue else -1#let's always use the smallest incrementer possible, to have the highest resolution
                nOfSteps = valueIncrementer * int((endValue - startValue)*255/1.8)
                
            stepTime = rampTime / nOfSteps
            setattr(self,'ramp_startValue'+str(i), startValue)
            setattr(self,'ramp_valueStepIncrementer'+str(i), valueIncrementer)
            setattr(self,'ramp_timePerStep'+str(i), stepTime)
            setattr(self,'ramp_numberOfStep'+str(i), nOfSteps)
                    
        # if(TriggerType != 'now'):
        #     self.rampTriggerType = TriggerType
        self.TriggerPin = digitalPinTrigger
        self.rampIdleConfig = IdleConfig
        self.ramp_useMultiTriggers = useMultiTriggers
        self.ramp_numberOfUsedRamps = len(durations)
        self.outputSource = 'ramp' if enable else self.outputSource
            
        self.rampTriggerType = TriggerType
            

    def _setup(self): # the function is here for its docstring to be used by the metaclass.
        """
        sets up the AMS (just setting the attributes is OK)
        """
        pass
