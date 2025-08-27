from qtpy import QtCore, QtWidgets
import pyqtgraph as pg
import logging
import numpy as np
from ..attribute_widgets import BaseAttributeWidget
from .base_module_widget import ReducedModuleWidget, ModuleWidget
from ...pyrpl_utils import get_base_module_class
from ... import APP


class ScanCavity_widget(ModuleWidget):
    """
    A widget to represent a single lockbox input
    """
    def init_gui(self):
        #self.main_layout = QtWidgets.QVBoxLayout(self)
        self.init_main_layout(orientation="vertical")
        self.init_attribute_layout()

    #     self.win = pg.GraphicsWindow(title="Expected signal")
    #     self.plot_item = self.win.addPlot(title='Expected ' + self.module.name)
    #     self.plot_item.showGrid(y=True, x=True, alpha=1.)
    #     self.curve = self.plot_item.plot(pen='y')
    #     self.curve_slope = self.plot_item.plot(pen=pg.mkPen('b', width=5))
    #     self.symbol = self.plot_item.plot(pen='b', symbol='o')
    #     self.main_layout.addWidget(self.win)
    #     self.button_calibrate = QtWidgets.QPushButton('Calibrate')
    #     self.main_layout.addWidget(self.button_calibrate)
    #     self.button_calibrate.clicked.connect(lambda: self.module.calibrate())
    #     self.input_calibrated()

    # def hide_lock(self):
    #     self.curve_slope.setData([], [])
    #     self.symbol.setData([], [])
    #     self.plot_item.enableAutoRange(enable=True)

    # def show_lock(self, stage):
    #     setpoint = stage.setpoint
    #     signal = self.module.expected_signal(setpoint)
    #     slope = self.module.expected_slope(setpoint)
    #     dx = self.module.lockbox.is_locked_threshold
    #     self.plot_item.enableAutoRange(enable=False)
    #     self.curve_slope.setData([setpoint-dx, setpoint+dx],
    #                              [signal-slope*dx, signal+slope*dx])
    #     self.symbol.setData([setpoint], [signal])
    #     self.module._logger.debug("show_lock with sp %f, signal %f",
    #                               setpoint,
    #                               signal)

    # def input_calibrated(self, input=None):
    #     # if input is None, input associated with this widget is used
    #     if input is None:
    #         input = self.module
    #     y = input.expected_signal(input.plot_range)
    #     self.curve.setData(input.plot_range, y)
    #     input._logger.debug('Updated widget for input %s to '
    #                         'show GUI display of expected signal (min at %f)!',
    #                         input.name, input.expected_signal(0))
