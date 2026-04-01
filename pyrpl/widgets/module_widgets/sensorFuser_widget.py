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
from .base_module_widget import ModuleWidget, segmentedFunctionLine
from .acquisition_module_widget import AcquisitionModuleWidget
import networkx as nx
from ...graphCalculator import greedy_clique_partition
import time
import threading

from pyqtgraph.Qt import QtCore, QtGui
import numpy as np
from ...segmentedFunctionObject import segmentedFunctionObject



class segmentedFunctionLine_triedMyself_butCopilotIsBetterAtThis(QtWidgets.QGraphicsItem):
	def __init__(self, parent, segmentedFunction, parentWidget, color = QtCore.Qt.red):
		super().__init__(parent)
		self.parent = parent
		self.segmentedFunction = segmentedFunction
		# parent.addItem(self)
		self.color = color
		self.lines = []
		self.nodes = []
		# self.centerLine = QtWidgets.QGraphicsLineItem(0.0, 0, 0.001, 0, parent=parent)
		# parent.addItem(self.centerLine)
		# self.leftEdgeLine = PeakBorderLine(parent, self)
		# parent.addItem(self.leftEdgeLine)
		# self.rightEdgeLine = PeakBorderLine(parent, self)
		# parent.addItem(self.rightEdgeLine)
		# self.targetLine = QtWidgets.QGraphicsLineItem(0.0, 0, 0.0005, 0, parent=parent)
		# parent.addItem(self.targetLine)
		# self.parent = parent
		# self.isSetpointActive = False
		self.setupLines()

	def setupLines(self):
		for line in self.lines:
			self.parent.removeItem(line)
		for node in self.nodes:
			self.parent.removeItem(node)
		self.node = []
		self.lines = []
		x, y = self.segmentedFunction.points()
		
		for i in range(1, len(x)):
			line = QtWidgets.QGraphicsLineItem(x[i-1], y[i-1], x[i], y[i], parent=self.parent)
			self.parent.addItem(line)
			self.lines.append(line)
		for i in range(len(x)):
			#add togglablePoint
			node = dot(x[i], y[i], .1, self, self.parent)
			self.parent.addItem(node)
			self.nodes.append(node)

		# self.updateLines((x,y))
		self.updateSizes()

	def updateLines(self, x_y = None):
		if x_y == None:
			x, y = self.segmentedFunction.points()
		else:
			x, y = x_y
		for i in range(len(x)):
			self.nodes[i].set(x[i], y[i])
			if i > 0:
				self.lines[i-1].setLine(x[i-1], y[i-1], x[i], y[i])

	@property
	def lineWidth(self):
		left, bottom, right, top = self.parent.viewRect().getCoords()
		return (top - bottom) * 0.05
	@property
	def dotWidth(self):
		left, bottom, right, top = self.parent.viewRect().getCoords()
		return (right - left) * 0.01

	def updateSizes(self):
		pen = QtGui.QPen(self.color, self.lineWidth)
		pen.setCapStyle(QtCore.Qt.FlatCap)
		for line in self.lines:
			line.setPen(pen)
		brush = QtGui.QBrush(self.color)
		for node in self.nodes:
			node.setBrush(brush)
			node.setWidth(self.dotWidth)
	def updateSegmentedFunctionFromLine(self):
		x=[]
		y=[]
		for node in self.nodes:
			x.append(node.xCenter())
			y.append(node.yCenter())
		self.segmentedFunction.updateFromInterface(x, y)

	def boundingRect(self):
		if not self.nodes:
			return QtCore.QRectF()

		x_coords = [node.xCenter() for node in self.nodes]
		y_coords = [node.yCenter() for node in self.nodes]

		x_min, x_max = min(x_coords), max(x_coords)
		y_min, y_max = min(y_coords), max(y_coords)

		padding = self.dotWidth / 2
		return QtCore.QRectF(x_min - padding, y_min - padding, 
							 x_max - x_min + padding * 2, y_max - y_min + padding * 2)
	def paint(self, *args, **kwargs):
		for line in self.lines:
			line.paint(*args, **kwargs)
		for node in self.nodes:
			node.paint(*args, **kwargs)
class sensorToBeFused_widget(ModuleWidget):
	pass

	
	

class sensor_fuser_widget(ModuleWidget):
	def init_gui(self):
		self.init_main_layout(orientation="vertical")
		self.init_attribute_layout()
		aws = self.attribute_widgets
		self.sensors_layout = QtWidgets.QVBoxLayout()
		self.main_layout.addLayout(self.sensors_layout)

		self.sensor_a = self.module.sensor_a._create_widget()
		self.sensor_b = self.module.sensor_b._create_widget()
		self.sensors_layout.addWidget(self.sensor_a)
		self.sensors_layout.addWidget(self.sensor_b)
		
		self.win = pg.GraphicsLayoutWidget(title="sensor calibration")
		self.plot_item = self.win.addPlot(title="sensor calibration")
		self.plot_item.showGrid(y=True, alpha=1.)
		self.viewBox = self.plot_item.getViewBox()
		self.viewBox.setMouseEnabled(y=False)
		self.main_layout.addWidget(self.win, stretch=10)
		
		self.ch_color = ['green', 'red', 'olive', 'magenta', 'blue']
		self.curves = [self.plot_item.plot(pen=(QtGui.QColor(color).red(),
												QtGui.QColor(color).green(),
												QtGui.QColor(color).blue()
												)) for color in self.ch_color]
		self.calibrate_button = QtWidgets.QPushButton("acquire sensors")
		self.calibrate_button.clicked.connect(self.autoCalibrate)
		self.sensors_layout.addWidget(self.calibrate_button)

		self.line_o = segmentedFunctionLine(self.plot_item, self.module.o, self, QtGui.QColor(self.ch_color[4]))
		self.line_a = segmentedFunctionLine(self.plot_item, self.sensor_a.module, self, QtGui.QColor(self.ch_color[2]))
		self.line_b = segmentedFunctionLine(self.plot_item, self.sensor_b.module, self, QtGui.QColor(self.ch_color[3]))

		
# 		def on_view_changed():
# 			self.line_a.updateSizes()
# 			self.line_b.updateSizes()
# 		self.plot_item.sigRangeChanged.connect(lambda _, __: on_view_changed())
# 		self.plot_item.getViewBox().sigResized.connect(on_view_changed)

	def autoCalibrate(self):
		self.module.calibrateFromScopeSignals()
		a, b = self.module.a, self.module.b
		t, a = a
		self.curves[0].setData(t, a)
		t, b = b
		self.curves[1].setData(t, b)

	def updateExpectedCurves(self):
		self.line_a.updateLines()
		self.line_b.updateLines()
		self.line_o.updateLines()
		