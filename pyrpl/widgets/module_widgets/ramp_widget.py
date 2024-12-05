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

        self.idleConfig_widget = self.attribute_widgets['idleConfiguration']
        self.useMultTriggers_widget = self.attribute_widgets['useMultipleTriggers']
        self.defaultValue_widget = self.attribute_widgets['defaultValue']
        self.usedRamps_widget = self.attribute_widgets['usedRamps']
        self.external_trigger_widget = self.attribute_widgets['external_trigger_pin']
        self.attribute_layout.removeWidget(self.idleConfig_widget)
        self.attribute_layout.removeWidget(self.useMultTriggers_widget)
        self.attribute_layout.removeWidget(self.defaultValue_widget)
        self.attribute_layout.removeWidget(self.usedRamps_widget)
        self.attribute_layout.removeWidget(self.external_trigger_widget)
        self.config_layout.addWidget(self.idleConfig_widget)
        self.config_layout.addWidget(self.useMultTriggers_widget)
        self.config_layout.addWidget(self.defaultValue_widget)
        self.config_layout.addWidget(self.usedRamps_widget)
        self.config_layout.addWidget(self.external_trigger_widget)

        self.function=self.attribute_widgets['rampValues']
        self.attribute_layout.removeWidget(self.function)
        self.total_layout.addWidget(self.function)