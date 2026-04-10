"""
The Hk widget allows to change port direction, set the value of output ports,
get the value of input ports
"""
from .base_module_widget import ModuleWidget, segmentedFunctionLine
from qtpy import QtCore, QtGui, QtWidgets
from collections import OrderedDict
import pyqtgraph as pg
import numpy as np
import sys
from scipy.optimize import least_squares
from ... import APP


class linearizerWidget(ModuleWidget):
    """
    Widget for the linearizer module
    """

    def init_gui(self):
        super(linearizerWidget, self).init_gui()
        ##Then remove properties from normal property layout
        ## We will make one where buttons are stack on top of each others by functional column blocks
        
        self.main_layout.removeItem(self.attribute_layout)
        self.main_lay = QtWidgets.QVBoxLayout()
        self.main_layout.addLayout(self.main_lay)

        self.function=self.attribute_widgets['function']
        self.input=self.attribute_widgets['input']
        self.output=self.attribute_widgets['output_direct']
        self.attribute_layout.removeWidget(self.function)
        self.attribute_layout.removeWidget(self.input)
        self.attribute_layout.removeWidget(self.output)
        self.main_lay.addWidget(self.function)
        self.main_lay.addWidget(self.input)
        self.main_lay.addWidget(self.output)
    #     self.main_lay = QtWidgets.QVBoxLayout()
    #     self.lay_h1 = QtWidgets.QHBoxLayout()
        
    #     self.lay_h1.addWidget(self.attribute_widgets['led'])
    #     self.lay_h1.addWidget(self.attribute_widgets['input1'])
    #     self.lay_h1.addWidget(self.attribute_widgets['input2'])
    #     self.refresh_button = QtWidgets.QPushButton("Refresh")
    #     self.refresh_button.clicked.connect(self.refresh)
    #     self.lay_h1.addWidget(self.refresh_button)
    #     self.main_lay.addLayout(self.lay_h1)
    #     
        self.main_lay.addLayout(self.attribute_layout)

        self.updateFromSensorFuser_button = QtWidgets.QPushButton("Update from SensorFuser")
        self.main_lay.addWidget(self.updateFromSensorFuser_button)
        self.updateFromSensorFuser_button.clicked.connect(self.updateFromSensorFuser)

        self.switch_xy_button = QtWidgets.QPushButton("switch the x and y axes")
        self.main_lay.addWidget(self.switch_xy_button)
        self.switch_xy_button.clicked.connect(self.switch_xy)

    @staticmethod
    def optimizeSegmentedFunction(x, y, nOfPoints):
        def error(xy_s):
            xo = np.concatenate(([-1], xy_s[:nOfPoints-2], [1]))
            yo = xy_s[nOfPoints-2:]
            return y - np.interp(x, xo, yo)
        xo_0 = np.linspace(x[0], x[-1], nOfPoints)
        yo_0 = np.interp(xo_0, x, y)
        xo_0 = xo_0[1:-1]
        sol = least_squares(error, np.array((*xo_0, *yo_0)), bounds=[np.repeat([-1], nOfPoints*2-2), np.repeat([1], nOfPoints*2-2)])
        xo = np.concatenate(([-1], sol.x[:nOfPoints-2], [1]))
        yo = sol.x[nOfPoints-2:]
        return xo, yo

    # def updateFromSensorFuser(self):
        
    #     sensorFuser = self.module.redpitaya.sensor_fuser
    #     ts, ys = sensorFuser.o.points()
    #     (ta, a), (tb, b) = sensorFuser.a, sensorFuser.b#the "time" arrays are in the range [-1,1]
    #     ts = np.array(ts)
    #     ys = np.array(ys)
    #     ts = (ts - ts[0]) / (ts[-1] - ts[0]) * 2 - 1
    #     #linearize a for inputs between ts[0] and ts[1], (a+b)/2 for inputs between ts[1] and ts[2], and b for inputs between ts[2] and ts[3]
    #     t = np.linspace(-1,1,(len(ta)+len(tb))//2)
    #     tc = [ta, tb]
    #     c = [a, b]
    #     y = np.zeros_like(t)
    #     for cIndex, startIndex, multiplier in [(0, 0, 1), (0, 1, .5), (1, 1, .5), (1, 2, 1)]:
    #         start = ts[startIndex]
    #         end = ts[startIndex+1]
    #         modifiedRange = np.logical_and(tc[cIndex] >= start, tc[cIndex] < end)
    #         cc = c[cIndex][modifiedRange]
    #         outputModifiedRange = np.logical_and(t >= start, t <= end)
    #         if len(cc) > 2:
    #             cc = (cc - cc[0]) / (cc[-1] - cc[0])
    #             cc = cc * (ys[startIndex+1] - ys[startIndex]) + ys[startIndex]
    #             y[outputModifiedRange] += np.interp(t[outputModifiedRange], tc[cIndex][modifiedRange], cc * multiplier)
    #         else:
    #             y[outputModifiedRange] = -1
    #     ramp = np.array(self.optimizeSegmentedFunction(t, y, self.module.nOfSegments + 1))
    #     inverseRamp = ramp[::-1]
    #     self.module.function = inverseRamp

    def updateFromSensorFuser(self):
        
        sensorFuser = self.module.redpitaya.sensor_fuser
        xs, ys = sensorFuser.o.pointsForLinearizer()
        xs = np.array(xs)
        ys = np.array(ys)
        xs = (xs - xs[0]) / (xs[-1] - xs[0]) * 2 - 1
        self.module.function = np.array([ys, xs])
    def switch_xy(self):
        x,y = self.module.function
        self.module.function = np.array([y, x])
