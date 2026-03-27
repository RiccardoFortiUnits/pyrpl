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

# class dot(QtWidgets.QGraphicsEllipseItem):
# 	def __init__(self, center_x, center_y, size_x, segmentedFunctionLine, parent = ...):
		
# 		self.parent = parent
# 		size_y = self.size_y(size_x)
# 		super().__init__(center_x - size_x / 2, center_y - size_y / 2, size_x, size_y, parent)
# 		self.setPen(QtGui.QPen(QtCore.Qt.red, 0))
# 		self.segmentedFunctionLine = segmentedFunctionLine
# 		self.setFlags(
# 			QtWidgets.QGraphicsItem.ItemIsSelectable |
# 			QtWidgets.QGraphicsItem.ItemIsMovable
# 		)

# 	def size_y(self, size_x):		
# 		left, bottom, right, top = self.parent.viewRect().getCoords()
# 		return size_x * (top - bottom) / (right - left)
# 	def xCenter(self):
# 		return self.rect().center().x()
# 	def yCenter(self):
# 		self.setRect
# 		return self.rect().center().y()
# 	def set(self, x, y, size_x = None):
# 		if size_x is None:
# 			size_x = self.rect().width()
# 		size_y = self.size_y(size_x)		
# 		self.setRect(x - size_x / 2, y - size_y / 2, size_x, size_y)
# 	def setWidth(self, size_x):
# 		size_y = self.size_y(size_x)		
# 		self.setRect(self.xCenter() - size_x / 2, self.yCenter() - size_y / 2, size_x, size_y)
	
# 	def mousePressEvent(self, event):
# 		self._distanceBetweenClickAndCenter = self.xCenter() - event.pos().x(), self.yCenter() - event.pos().y()
# 		super().mousePressEvent(event)

# 	def mouseMoveEvent(self, event):
# 		self.set(event.pos().x() + self._distanceBetweenClickAndTop[0], 
# 		   		event.pos().y() + self._distanceBetweenClickAndTop[1])
# 		self.segmentedFunctionLine.updateLines()
# 		self.segmentedFunctionLine.updateSegmentedFunctionFromLine()

import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtGui
import numpy as np


class segmentedFunctionLine(pg.ScatterPlotItem):
	# def __init__(self, x, y, point_size=10, line_width=2, **kwargs):
	def __init__(self, parent, segmentedFunction, parentWidget, color = QtCore.Qt.red, point_size=10, line_width=2, **kwargs):
		
		self.parent = parent
		self.segmentedFunction = segmentedFunction
		self.parentWidget = parentWidget
		self.color = color
		self.line_width = line_width

		x, y = self.segmentedFunction.points()

		super().__init__(
			x=x, y=y,
			size=point_size,
			brush=color,
			# pen='black',
			# symbol='o',
			pxMode=True,    # fixed-size symbols
			**kwargs
		)
		parent.addItem(self)

		self.setAcceptedMouseButtons(QtCore.Qt.LeftButton)
		self.moving_point = None
		self.x_y = np.column_stack([x, y])

		# Create constant‑width line
		self.line = pg.PlotCurveItem(self.x_y[:, 0], self.x_y[:, 1])
		self.line.setPen(pg.mkPen(color, width=line_width))
		self.line.setZValue(self.zValue() - 1)

		# Make the line ignore view transforms → constant pixel width
		self.line.setFlag(self.line.GraphicsItemFlag.ItemIgnoresTransformations)

		# Connect to sigPlotChanged so the curve stays on the same plot
		self.sigPlotChanged.connect(self._on_plot_changed)


	def _on_plot_changed(self):
		"""Ensure the line appears in the same plot as the ScatterPlotItem."""
		plot = self.getViewBox()
		if plot is not None:
			if self.line not in plot.addedItems:
				plot.addItem(self.line)

	def updateLines(self):
		x, y = self.segmentedFunction.points()

		self.x_y = np.column_stack([x, y])
		self.setData(self.x_y[:, 0], self.x_y[:, 1])
		self.line.setData(self.x_y[:, 0], self.x_y[:, 1])

		# plot = self.getViewBox()		
		# newLine = pg.PlotCurveItem(self.x_y[:, 0], self.x_y[:, 1])
		# newLine.setPen(pg.mkPen(self.color, width=self.line_width))
		# newLine.setZValue(self.zValue() - 1)
		# if plot is not None:
		# 	if self.line not in plot.addedItems:
		# 		plot.removeItem(self.line)
		# 	plot.addItem(newLine)
		# self.line = newLine


	# ------------------------
	#   DRAGGING LOGIC
	# ------------------------
	def mousePressEvent(self, event):
		pts = self.pointsAt(event.pos())
		if pts:
			self.moving_pointIndex = list(self.points()).index(pts[0])
			event.accept()
		else:
			super().mousePressEvent(event)

	def mouseMoveEvent(self, event):
		if self.moving_pointIndex is not None:
			# Convert screen pos → data coordinates
			vb = self.getViewBox()
			mouse_point = vb.mapSceneToView(event.scenePos())

			# Update data
			self.x_y[self.moving_pointIndex] = [mouse_point.x(), mouse_point.y()]
	
			self.segmentedFunction.updateFromInterface(*self.x_y.T)

			'''no need to actually update the point position, self.updateLines will be called by self.segmentedFunction already'''
			# # Update display
			# self.setData(self.x_y[:, 0], self.x_y[:, 1])
			# self.line.setData(self.x_y[:, 0], self.x_y[:, 1])

			event.accept()
		else:
			super().mouseMoveEvent(event)

	def mouseReleaseEvent(self, event):
		self.moving_point = None
		super().mouseReleaseEvent(event)


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
		t = np.linspace(0,1,len(a))
		self.curves[0].setData(t, a)
		self.curves[1].setData(t, b)

	def updateExpectedCurves(self):
		self.line_a.updateLines()
		self.line_b.updateLines()
		self.line_o.updateLines()
		