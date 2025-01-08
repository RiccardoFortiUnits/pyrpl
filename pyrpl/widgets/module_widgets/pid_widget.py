"""
A widget for pid modules.
"""

from .base_module_widget import ModuleWidget

from qtpy import QtCore, QtWidgets
import numpy as np

class PidWidget(ModuleWidget):
    """
    Widget for a single PID.
    """
    def init_gui(self):
        self.init_main_layout(orientation="vertical")
        #self.main_layout = QtWidgets.QVBoxLayout()
        #self.setLayout(self.main_layout)
        self.init_attribute_layout()
        self.setSetpoint = QtWidgets.QPushButton("set Setpoint")
        self.setSetpoint.clicked.connect(self.setpointToCurrentValue)
        self.attribute_layout.addWidget(self.setSetpoint)
        # input_filter_widget = self.attribute_widgets["inputfilter"]
        # self.attribute_layout.removeWidget(input_filter_widget)
        # self.main_layout.addWidget(input_filter_widget)
        for prop in ['p', 'i']: #, 'd']:
            self.attribute_widgets[prop].widget.set_log_increment()


        self.setpoint_widget = self.attribute_widgets["setpoint"]
        self.inputSignal_widget = self.attribute_widgets["input"]

        # can't avoid timer to update ival
        # self.timer_ival = QtCore.QTimer()
        # self.timer_ival.setInterval(1000)
        # self.timer_ival.timeout.connect(self.update_ival)
        # self.timer_ival.start()

    def setpointToCurrentValue(self):
        #get the last acquisition from the scope and put its average as the new setpoint
        acquisition = self.module.parent.scope.getLastAcquisition(self.inputSignal_widget.attribute_value)
        self.setpoint_widget.attribute_value = np.mean(acquisition)

    def update_ival(self):
        widget = self.attribute_widgets['ival']
        if self.isVisible() and not widget.editing():
            widget.write_attribute_value_to_widget()
