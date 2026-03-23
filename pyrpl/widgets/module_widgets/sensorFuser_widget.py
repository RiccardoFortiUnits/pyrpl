from qtpy import QtCore, QtWidgets
import pyqtgraph as pg
import logging
import numpy as np
from ..attribute_widgets import ResettableFloatAttributeWidget
from .base_module_widget import ReducedModuleWidget, ModuleWidget
from ...pyrpl_utils import get_base_module_class
from ... import APP
import pyqtgraph as pg
from qtpy import QtCore, QtGui, QtWidgets
import numpy as np
from ...errors import NotReadyError
from .base_module_widget import ModuleWidget
from .acquisition_module_widget import AcquisitionModuleWidget
import networkx as nx
from ...graphCalculator import greedy_clique_partition
import time
import threading


class sensorToBeFused_widget(ModuleWidget):
	pass

	
	

class sensor_fuser_widget(ModuleWidget):
	def init_gui(self):
		self.init_main_layout(orientation="horizontal")
		self.init_attribute_layout()
		aws = self.attribute_widgets
		self.sensors_layout = QtWidgets.QVBoxLayout()
		self.attribute_layout.addLayout(self.sensors_layout)

		self.sensor_a = self.module.sensor_a._create_widget()
		self.sensor_b = self.module.sensor_b._create_widget()
		self.sensors_layout.addWidget(self.sensor_a)
		self.sensors_layout.addWidget(self.sensor_b)

		