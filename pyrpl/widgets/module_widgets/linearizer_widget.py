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
    #     self.lay_h1.setStretch(0,0)
    #     self.lay_h1.addStretch(1)

    #     self.layout_vs = []
    #     for i in range(8):
    #         lay = QtWidgets.QVBoxLayout()
    #         self.layout_vs.append(lay)
    #         self.attribute_layout.addLayout(lay)
    #         for sign in ['P', 'N']:
    #             val_widget = self.attribute_widgets['expansion_' + sign + str(i)]
    #             direction_widget = self.attribute_widgets['expansion_' + sign +
    #                                                       str(i) + '_output']
    #             pinState_widget = self.attribute_widgets['pinState_' + sign + str(i)]
    #             otherPin_widget = self.attribute_widgets['external_' + sign + str(i) + "_otherPinSelector"]
    #             dspPin_widget = self.attribute_widgets['external_' + sign + str(i) + "_dspBitSelector"]
    #             self.attribute_layout.removeWidget(val_widget)
    #             self.attribute_layout.removeWidget(direction_widget)
    #             self.attribute_layout.removeWidget(pinState_widget)
    #             self.attribute_layout.removeWidget(otherPin_widget)
    #             self.attribute_layout.removeWidget(dspPin_widget)
    #             lay.addWidget(val_widget)
    #             lay.addWidget(direction_widget)
    #             lay.addWidget(pinState_widget)
    #             lay.addWidget(otherPin_widget)
    #             lay.addWidget(dspPin_widget)

    #     self.attribute_layout.setStretch(0,0)
    #     self.attribute_layout.addStretch(1)

    #     self.lay_h2 = QtWidgets.QHBoxLayout()
    #     self.main_lay.addLayout(self.lay_h2)
    #     for el in  ['fastSwitch_activeTime', 'fastSwitch_inactiveTime', 'fastSwitch_triggerPin', 'fastSwitch_channelsDelay']:
    #         widget = self.attribute_widgets[el]
    #         self.attribute_layout.removeWidget(widget)
    #         self.lay_h2.addWidget(widget)
    #     self.lay_h2.setStretch(0,0)
    #     self.lay_h2.addStretch(1)
        


    # def refresh(self):
    #     for i in range(8):
    #         for sign in ['P', 'N']:
    #             name = 'expansion_' + sign + str(i)
    #             self.attribute_widgets[name].write_attribute_value_to_widget()