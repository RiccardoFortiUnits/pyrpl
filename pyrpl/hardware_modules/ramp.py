from ..attributes import IntRegister, ArrayRegister, FloatRegister, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister

from ..widgets.module_widgets.ramp_widget import rampWidget
import numpy as np
from .dsp import DspModule, all_inputs, dsp_addr_base, InputSelectRegister
from .hk import HK

class rampFunction(ArrayRegister):
    def __init__(self, nOfSegments = 8, timeRegistersBitSize = 24, smallestStepIncrease = 2**-13, smallestTimeStep = 8e-9 * 3):
        self.nOfSegments = nOfSegments
        self.timeRegistersBitSize = timeRegistersBitSize
        self.smallestStepIncrease = smallestStepIncrease
        self.smallestTimeStep = smallestTimeStep

        self.startPoints = ArrayRegister(FloatRegister, 
                                addresses=[0x104 + i*0xC for i in range(nOfSegments)],
                                startBits=[0] * nOfSegments,
                                bits=14,
                                norm=2**13,
                                doc="value at the start of each ramp")
        self.stepIncreases = ArrayRegister(FloatRegister, 
                                addresses=[0x104 + i*0xC for i in range(nOfSegments)],
                                startBits=[14] * nOfSegments,
                                bits=14,
                                norm=2**13,
                                default=smallestStepIncrease,
                                doc="output increment at each time step. Leave it to 2^(-13) for slow ramps, increase it for very fast ramps")
        self.timeSteps = ArrayRegister(FloatRegister, 
                                addresses=[0x108 + i*0xC for i in range(nOfSegments)],
                                startBits=[0] * nOfSegments,
                                bits=timeRegistersBitSize,
                                norm=125e6,
                                signed = False,
                                doc="time between each output increment")
        self.nOfSteps = ArrayRegister(IntRegister, 
                                addresses=[0x10C + i*0xC for i in range(nOfSegments)],
                                startBits=[0] * nOfSegments,
                                bits=14,
                                signed=False,
                                doc="number of steps done before switching to the following ramp. The total time of ramp[i] is equal to "
                                "timeSteps[i] * nOfSteps[i], while the final value of the output is startPoints[i] + stepIncrease[i] * nOfSteps[i]")
        super().__init__(registers=[self.startPoints, self.stepIncreases, self.timeSteps, self.nOfSteps])
        self.len = 2
        
    def get_value(self, obj):
        
        startPoints = self.startPoints.get_value(obj)
        stepIncreases = self.stepIncreases.get_value(obj)
        timeSteps = self.timeSteps.get_value(obj)
        nOfSteps = self.nOfSteps.get_value(obj)

        try:#remove all the "0"s at the end of the list
            listEnd = next(i for i, x in enumerate(nOfSteps) if x == 0)
            startPoints=startPoints[:listEnd]
            stepIncreases=stepIncreases[:listEnd]
            timeSteps=timeSteps[:listEnd]
            nOfSteps=nOfSteps[:listEnd]
        except:#all the s points are on -1 => only the first one is actually used
            pass
        rampTimes = np.array(timeSteps) * np.array(nOfSteps)
        x = np.concatenate((np.zeros(1), np.cumsum(rampTimes)))
        y = np.array(startPoints + [startPoints[-1]+stepIncreases[-1]*nOfSteps[-1]])
        return [list(x),list(y)]
    
    @staticmethod    
    def findBestRatio(r, A, B):
        if r<1:
            best_b, best_a = rampFunction.findBestRatio(1/r, B, A)
            return best_a, best_b
        b = 1
        a = int(r)
        if r > A:
            return a, b
        best = a
        best_a = a
        best_b = b
        for b in range(2,B):
            starting_a = int(a * float(b) / float(b-1))
            if starting_a > A:
                break
            current = starting_a / b
            while current < r:
                starting_a+=1
                prev = current
                current = starting_a / b
            a = starting_a - 1
            if prev >= best:
                best = prev
                best_a = a
                best_b = b
        return best_a, best_b
    
    @staticmethod    
    def findBestRamp(voltage, time, dV, dt, minN = 2):
        # print("started search")
        v = int(voltage / dV)
        t = int(time / dt)
        
        def getError(n, l, m):
            return ((voltage - l*n*dV) + (time - m*n*dt))/(n**2)
        
        n = min(v,t)
        minError = getError(1, v, t)
        bestError = getError(n,0,0)
        while n >= minN and bestError > minError / n:
            l = int(v / n)
            m = int(t / n)
            currentError = getError(n, l, m)
            if currentError < bestError:
                bestError = currentError
                bestN = n
            n-=1
        # actualVoltage = int(v / bestN)*bestN*dV
        # actualTime = int(t / bestN)*bestN*dt
        
        # print(f"search ended, chosen n={bestN}")
        return bestN#, actualVoltage, actualTime
    
    def set_value(self, obj, val):
        x,y=val 
        if len(x) > self.nOfSegments + 1:
            raise Exception(f"too many segments! max number of points is {self.nOfSegments+1}")
        edges = np.array(y[:])
        times = np.array(x[1:]) - np.array(x[:-1])
        self.usedRamps = 0

        list_startPoints = np.zeros(self.nOfSegments)
        list_stepIncreases = np.zeros(self.nOfSegments)
        list_timeSteps = np.zeros(self.nOfSegments)
        list_nOfSteps = np.zeros(self.nOfSegments)

        for i in range(len(times)):
            startValue = edges[i]
            endValue = edges[i+1]
            rampTime = times[i]
            if startValue == endValue:#flat segment
                valueIncrementer = 0
                maxStepTime = 0.10 #should be (2^24 * 8e-9s) = 0.134 s, but let's use a just sligthly lower one
                nOfSteps = np.ceil(times[i] / maxStepTime)#if times[i] < maxStepTime, we'll just use a single long step
            else:
                DV = abs(endValue - startValue)
                dV = self.smallestStepIncrease
                dt = self.smallestTimeStep
                
                nOfSteps = rampFunction.findBestRamp(DV, rampTime, dV, dt)
                valueIncrementer = (endValue - startValue) / nOfSteps
                
            stepTime = rampTime / nOfSteps
                
                # valueIncrementer = self.smallestStepIncrease if startValue < endValue else -self.smallestStepIncrease #let's always use the smallest incrementer possible, to have the highest resolution
                # nOfSteps = int((endValue - startValue) / valueIncrementer)
                
            
            # if stepTime < self.smallestTimeStep:
            #     stepTime = self.smallestTimeStep
            #     nOfSteps = int(rampTime / stepTime)
            #     valueIncrementer = (endValue - startValue) / nOfSteps
            
            list_startPoints[i] = startValue
            list_stepIncreases[i] = valueIncrementer
            list_timeSteps[i] = stepTime
            list_nOfSteps[i] = nOfSteps

        self.startPoints.set_value(obj, list_startPoints)
        self.stepIncreases.set_value(obj, list_stepIncreases)
        self.timeSteps.set_value(obj, list_timeSteps)
        self.nOfSteps.set_value(obj, list_nOfSteps)
      

class Ramp(DspModule):
    _widget_class = rampWidget

    _setup_attributes = \
                    ["idleConfiguration"] + \
                    ["useMultipleTriggers"] + \
                    ["defaultValue"] + \
                    ["usedRamps"] + \
                    ["external_trigger_pin"] + \
                    ["rampValues"]
                        
    _gui_attributes =  _setup_attributes

    nOfSegments = 8
    timeRegistersBitSize = 24
    smallestStepIncrease = 2**-13
    smallestTimeStep = 8e-9 * 3

    idleConfiguration = SelectRegister(0x100, startBit=0, options={"defaultValue" : 0, "start" : 1, "end" : 2, "inverseRamp" : 3}, 
            doc="set the value that the output keeps when the ramp is finished, while waiting for a new start trigger. "
            "either use property defaultValue, the value at the start of the function, keep the final value of the function, "
            "or execute a mirror version of the function (finishing at the starting value)")
    useMultipleTriggers = BoolRegister(0x100, bit = 2, doc="if True, each section of the ramp function will wait for a new "
            "trigger to arrive before starting (and if a trigger arrives prematurely, the next section will be started sooner). "
            "If False, only one trigger is necessary to start the entire function")
    defaultValue = FloatRegister(0x100, startBit=3, bits=14, doc="value that the output will keep at the end of the function, if idleConfiguration is set to 'defaultValue'")
    usedRamps = IntRegister(0x100, startBit=14+3, bits = int(np.ceil(np.log2(nOfSegments) + 1)), min=0, max=nOfSegments, default=0, 
            doc="number of ramps used by the function. The values set for the 'exceding' ramps will not be used. If 0, it effectively disables the ramp")
    # startPoints = ArrayRegister(FloatRegister, 
    #                             addresses=[0x104 + i*0xC for i in range(nOfSegments)],
    #                             startBits=[0] * nOfSegments,
    #                             bits=14,
    #                             norm=2**13,
    #                             doc="value at the start of each ramp")
    # stepIncreases = ArrayRegister(FloatRegister, 
    #                             addresses=[0x104 + i*0xC for i in range(nOfSegments)],
    #                             startBits=[14] * nOfSegments,
    #                             bits=14,
    #                             norm=2**13,
    #                             default=smallestStepIncrease,
    #                             doc="output increment at each time step. Leave it to 2^(-13) for slow ramps, increase it for very fast ramps")
    # timeSteps = ArrayRegister(FloatRegister, 
    #                             addresses=[0x108 + i*0xC for i in range(nOfSegments)],
    #                             startBits=[0] * nOfSegments,
    #                             bits=timeRegistersBitSize,
    #                             norm=125e6,
    #                             signed = False,
    #                             doc="time between each output increment")
    # nOfSteps = ArrayRegister(IntRegister, 
    #                             addresses=[0x108 + i*0xC for i in range(nOfSegments)],
    #                             startBits=[0] * nOfSegments,
    #                             bits=14,
    #                             signed=False,
    #                             doc="number of steps done before switching to the following ramp. The total time of ramp[i] is equal to "
    #                             "timeSteps[i] * nOfSteps[i], while the final value of the output is startPoints[i] + stepIncrease[i] * nOfSteps[i]")
    
    external_trigger_pin = digitalPinRegister(- dsp_addr_base('ramp') + HK.addr_base + 0x28, startBit=8)


    rampValues = rampFunction(nOfSegments, timeRegistersBitSize, smallestStepIncrease, smallestTimeStep)
    # def updateRamp(self, x, y):
    #     if len(x) > self.nOfSegments + 1:
    #         raise Exception(f"too many segments! max number of points is {self.nOfSegments+1}")
    #     edges = x[:]
    #     times = y[1:] - y[:-1]
    #     self.usedRamps = 0

    #     list_startPoints = np.zeros(self.nOfSegments)
    #     list_stepIncreases = np.zeros(self.nOfSegments)
    #     list_timeSteps = np.zeros(self.nOfSegments)
    #     list_nOfSteps = np.zeros(self.nOfSegments)

    #     for i in range(len(times)):
    #         startValue = edges[i]
    #         endValue = edges[i+1]
    #         rampTime = times[i]
    #         if startValue == endValue:#flat segment
    #             valueIncrementer = 0
    #             maxStepTime = 0.10 #should be (2^24 * 8e-9s) = 0.134 s, but let's use a just sligthly lower one
    #             nOfSteps = np.ceil(times[i] / maxStepTime)#if times[i] < maxStepTime, we'll just use a single long step
    #         else:
    #             valueIncrementer = self.smallestStepIncrease if startValue < endValue else -self.smallestStepIncrease #let's always use the smallest incrementer possible, to have the highest resolution
    #             nOfSteps = int((endValue - startValue) / valueIncrementer)
                
    #         stepTime = int(rampTime / nOfSteps)
            
    #         if stepTime < self.smallestTimeStep:
    #             nOfSteps = int(rampTime / self.smallestTimeStep)
    #             valueIncrementer = (endValue - startValue) / nOfSteps
            
    #         list_startPoints[i] = startValue
    #         list_stepIncreases[i] = valueIncrementer
    #         list_timeSteps[i] = stepTime
    #         list_nOfSteps[i] = nOfSteps

        # self.startPoints = list_startPoints
        # self.stepIncreases = list_stepIncreases
        # self.timeSteps = list_timeSteps
        # self.nOfSteps = list_nOfSteps

        # self.usedRamps = len(times)
 
    
    