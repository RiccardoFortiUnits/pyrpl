"""
The Hk widget allows to change port direction, set the value of output ports,
get the value of input ports
"""
from .base_module_widget import ModuleWidget
from collections import OrderedDict
from qtpy import QtCore, QtWidgets
import pyqtgraph as pg
import numpy as np
import sys
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


    def updateFromSensorFuser(self):
        
        sensorFuser = self.module.redpitaya.sensor_fuser
        xs, ys = sensorFuser.o.points()
        xs = np.array(xs)
        ys = np.array(ys)
        xs = (xs - xs[0]) / (xs[-1] - xs[0]) * 2 - 1
        self.module.function = np.array([xs, ys])