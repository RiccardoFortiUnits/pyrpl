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
from qtpy import QtCore, QtGui, QtWidgets
from .sensorFuser_widget import segmentedFunctionLine
from .base_module_widget import ModuleWidget, segmentedFunctionLine

class rampWidget(ModuleWidget):
    """
    Widget for the ramp module
    """

    def init_gui(self):
        super(rampWidget, self).init_gui()
        ##Then remove properties from normal property layout
        ## We will make one where buttons are stack on top of each others by functional column blocks
        
        self.main_layout.removeItem(self.attribute_layout)

        self.total_layout = QtWidgets.QVBoxLayout()
        self.main_layout.addLayout(self.total_layout)

        self.config_layout = QtWidgets.QHBoxLayout()
        self.main_layout.addLayout(self.config_layout)

        self.output_direct = self.attribute_widgets['output_direct']
        self.idleConfig_widget = self.attribute_widgets['idleConfiguration']
        self.useMultTriggers_widget = self.attribute_widgets['useMultipleTriggers']
        self.defaultValue_widget = self.attribute_widgets['defaultValue']
        self.usedRamps_widget = self.attribute_widgets['usedRamps']
        self.external_trigger_widget = self.attribute_widgets['external_trigger_pin']
        # self.followSensorFuser = self.attribute_widgets['followSensorFuser']
        self.usedIdealRamps = self.attribute_widgets['usedIdealRamps']
        self.attribute_layout.removeWidget(self.output_direct)
        self.attribute_layout.removeWidget(self.idleConfig_widget)
        self.attribute_layout.removeWidget(self.useMultTriggers_widget)
        self.attribute_layout.removeWidget(self.defaultValue_widget)
        self.attribute_layout.removeWidget(self.usedRamps_widget)
        self.attribute_layout.removeWidget(self.external_trigger_widget)
        # self.attribute_layout.removeWidget(self.followSensorFuser)
        self.attribute_layout.removeWidget(self.usedIdealRamps)
        self.config_layout.addWidget(self.output_direct)
        self.config_layout.addWidget(self.idleConfig_widget)
        self.config_layout.addWidget(self.useMultTriggers_widget)
        self.config_layout.addWidget(self.defaultValue_widget)
        self.config_layout.addWidget(self.usedRamps_widget)
        self.config_layout.addWidget(self.external_trigger_widget)
        # self.config_layout.addWidget(self.followSensorFuser)
        self.config_layout.addWidget(self.usedIdealRamps)

        self.function=self.attribute_widgets['rampValues']
        self.attribute_layout.removeWidget(self.function)
        self.total_layout.addWidget(self.function)
        
        self.win = pg.GraphicsLayoutWidget(title="ramp")
        self.plot_item = self.win.addPlot(title="ramp")
        self.plot_item.showGrid(y=True, alpha=1.)
        self.viewBox = self.plot_item.getViewBox()
        self.viewBox.setMouseEnabled(y=False)
        self.total_layout.addWidget(self.win, stretch=10)
        
        self.ch_color = ['white', 'red']
        # self.curves = [self.plot_item.plot(pen=(QtGui.QColor(color).red(),
        # 										QtGui.QColor(color).green(),
        # 										QtGui.QColor(color).blue()
        
        x_y = self.module.points()

        self.discreteRamp = segmentedFunctionLine(self.plot_item, self.module, self, QtGui.QColor(self.ch_color[1]))
        self.idealRamp = segmentedFunctionLine(self.plot_item, parentWidget=self, color = QtGui.QColor(self.ch_color[0]), x_y_forIdeal=x_y)
        def updateBothRamps(x, y):
            segmentedFunctionLine.idealRamp.updateFromInterface(self.idealRamp.segmentedFunction, x, y)
            self.discreteRamp.segmentedFunction.updateFromInterface(x, y)
        self.idealRamp.segmentedFunction.updateFromInterface = updateBothRamps
    def updateRampCurve(self, x, y):
        self.discreteRamp.updateLines()