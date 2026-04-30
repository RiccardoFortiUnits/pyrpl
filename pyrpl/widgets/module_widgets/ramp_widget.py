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
# from ...hardware_modules.ramp import Ramp, segment

def addWidgets(self, names, newLayout):
	widgets = []
	for n in names:
		w = self.attribute_widgets[n]
		self.attribute_layout.removeWidget(w)
		newLayout.addWidget(w)
		widgets.append(w)
	return widgets
class segmentWidget(ModuleWidget):
	def init_gui(self):
		super().init_gui()
		self.vlayout = QtWidgets.QVBoxLayout()
		self.main_layout.addLayout(self.vlayout)
		(self.DV, self.VVV, self.DT, self.T, self.isExponential, self.exponentialRampSign, self.haltsSequence, self.tau,
			) = addWidgets(self, 
		["DV", "VVV", "DT", "T", "isExponential", "exponentialRampSign", "haltsSequence", "tau", ], self.vlayout)
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
		

		self.segmentTabs = QtWidgets.QTabWidget()
		self.main_layout.addWidget(self.segmentTabs)

		def add_new_tab(tab, content, tabTitle):
			new_tab = QtWidgets.QWidget()
			new_tab_layout = QtWidgets.QVBoxLayout()
			new_tab_layout.addWidget(content)
			new_tab.setLayout(new_tab_layout)
			tab.addTab(content, tabTitle)
		
		for i, s in enumerate(self.module.segments):
			sw : segmentWidget = s._create_widget()
			add_new_tab(self.segmentTabs, sw, f"segment {i}")

		(self.startPoint, self.usedRamps, 
   			self.output_direct, self.idleConfiguration, self.defaultValue, 
			self.external_trigger_pin,
		) = addWidgets(self, [
		"startPoint", "usedRamps", 
			"output_direct", "idleConfiguration", "defaultValue", 
			"external_trigger_pin",], self.config_layout)
		
		self.win = pg.GraphicsLayoutWidget(title="ramp")
		self.plot_item = self.win.addPlot(title="ramp")
		self.plot_item.showGrid(y=True, alpha=1.)
		self.viewBox = self.plot_item.getViewBox()
		self.viewBox.setMouseEnabled(y=False)
		self.total_layout.addWidget(self.win, stretch=10)
		
		self.ch_color = ['white']
		# self.curves = [self.plot_item.plot(pen=(QtGui.QColor(color).red(),
		# 										QtGui.QColor(color).green(),
		# 										QtGui.QColor(color).blue()
		
		x_y = self.module.points()

		self.discreteRamp = segmentedFunctionLine(self.plot_item, self.module, self, QtGui.QColor(self.ch_color[0]))
	def updateRampCurve(self):
		self.discreteRamp.updateLines(self.module.points())