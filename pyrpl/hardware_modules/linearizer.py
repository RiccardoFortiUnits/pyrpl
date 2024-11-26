from ..attributes import IntRegister, ArrayRegister, FloatRegister, SelectRegister, IORegister, BoolProperty, BoolRegister, GainRegister, digitalPinRegister

from ..widgets.module_widgets.linearizer_widget import linearizerWidget
import numpy as np
from .dsp import DspModule, all_inputs, dsp_addr_base, InputSelectRegister

class segmentedFunction(ArrayRegister):
    def __init__(self, nOfSegments = 8, coefficienBitSize=20, coefficientNorm = 2**14):
        self.nOfSegments = nOfSegments
        self.edgePoints = ArrayRegister(FloatRegister, 
                addresses=[0x100 + 8*i for i in range(nOfSegments)],
                startBits=[0] * nOfSegments,
                bits=14,
                norm = 2**13)
        self.q = ArrayRegister(FloatRegister, 
                    addresses=[0x100 + 8*i for i in range(nOfSegments)],
                    startBits=[14] * nOfSegments,
                    bits=14,
                    norm = 2**13)
        self.m = ArrayRegister(FloatRegister, 
                    addresses=[0x104 + 8*i for i in range(nOfSegments)],
                    startBits=[0] * nOfSegments,
                    bits=coefficienBitSize,
                    norm = coefficientNorm)
        super().__init__(registers=[self.edgePoints, self.q, self.m])
        self.len = 2
    
    @staticmethod    
    def segmentedCoefficient(x,y):
        '''
            transforms the segmented function (x,y) into the list of ramps y[i](x) = q[i] + (s[i] - x * m[i]),
            s[i] is the start input value of the ramp
            q[i] is the start output value of the ramp ( y[i](s[i]) = q[i])
            m[i] is the slope of the ramp
        '''
        a = x[0:len(x)-1]
        b = x[1:]
        c = y[0:len(y)-1]
        d = y[1:]
        
        m = (d-c) / (b-a)
        s = a
        q = c
        return (s,q,m)
            
    def get_value(self, obj):    
        s = self.edgePoints.get_value(obj)
        q = self.q.get_value(obj)
        m = self.m.get_value(obj)
        try:#remove all the "-1"s at the end of the list
            listEnd = len(s) - next(i for i, x in enumerate(reversed(s)) if x != -1)
        except:#all the s points are on -1 => only the first one is actually used
            listEnd = 1
        s=s[:listEnd]
        q=q[:listEnd]
        m=m[:listEnd]
        x = np.array(list(s) + [1])
        y = np.array(q + [q[-1]+m[-1]*(x[-1]-x[-2])])
        return [list(x),list(y)]

    def set_value(self, obj, val):
        x,y=val 
        if len(x) > self.nOfSegments + 1:
            raise Exception(f"too many segments! max number of points is {self.nOfSegments+1}")
        
        (s,q,m) = self.segmentedCoefficient(np.array(x),np.array(y))
        
        s = np.append(s,[-1] * (self.nOfSegments - len(m)))
        q = np.append(q,[0] * (self.nOfSegments - len(m)))
        m = np.append(m,[0] * (self.nOfSegments - len(m)))

        self.edgePoints.set_value(obj, s)
        self.q.set_value(obj, q)
        self.m.set_value(obj, m)     

class linearizer(DspModule):
    _widget_class = linearizerWidget

    _setup_attributes = ["function",
                         "input",
                         "output_direct"]#["led"] + \
                        
    _gui_attributes =  _setup_attributes

    nOfSegments = 8

    function = segmentedFunction(nOfSegments, 20, 2**14)
    
    