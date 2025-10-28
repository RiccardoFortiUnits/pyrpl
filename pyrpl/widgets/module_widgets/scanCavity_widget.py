from qtpy import QtCore, QtWidgets
import pyqtgraph as pg
import logging
import numpy as np
from ..attribute_widgets import BaseAttributeWidget
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
class PeakBorderLine(QtWidgets.QGraphicsLineItem):
    def __init__(self, parent, peakLine):
        super().__init__(0.0, 0, 0.001, 0, parent = parent)
        self.peakLine = peakLine
        self.setFlags(QtWidgets.QGraphicsItem.ItemIsSelectable)
    def mousePressEvent(self, event):
        return self.peakLine.mousePressEvent(event)
    
    def mouseMoveEvent(self, event):
        return self.peakLine.mouseMoveEvent(event)
    def mouseReleaseEvent(self, event):
        return self.peakLine.mouseReleaseEvent(event)
class PeakLine(QtWidgets.QGraphicsLineItem):
    

    def __init__(self, parent, peakWidget, scanCavityWidget, color = QtCore.Qt.red):
        super().__init__(0.0, 0, 0.001, 0, parent = parent)
        self.peak = peakWidget
        self.scanCavityWidget = scanCavityWidget
        self.setFlags(
            QtWidgets.QGraphicsItem.ItemIsSelectable |
            QtWidgets.QGraphicsItem.ItemIsMovable
        )
        parent.addItem(self)
        self.color = color
        self.centerLine = QtWidgets.QGraphicsLineItem(0.0, 0, 0.001, 0, parent=parent)
        parent.addItem(self.centerLine)
        self.leftEdgeLine = PeakBorderLine(parent, self)
        parent.addItem(self.leftEdgeLine)
        self.rightEdgeLine = PeakBorderLine(parent, self)
        parent.addItem(self.rightEdgeLine)
        self.targetLine = QtWidgets.QGraphicsLineItem(0.0, 0, 0.0005, 0, parent=parent)
        parent.addItem(self.targetLine)
        self.parent = parent
        self.isSetpointActive = False
        self.updateSizes()
        self.updateFromPeakRanges()

    def updateSizes(self):
        pen = QtGui.QPen(QtGui.QColor(0, 0, 0, 0), self.barHeight)
        pen.setCapStyle(QtCore.Qt.FlatCap)
        self.setPen(pen)

        pen = QtGui.QPen(self.color, self.strokeWidth)
        pen.setCapStyle(QtCore.Qt.FlatCap)
        self.centerLine.setPen(pen)

        barPen = QtGui.QPen(self.color, self.barWidths)
        barPen.setCapStyle(QtCore.Qt.FlatCap)
        self.leftEdgeLine.setPen(barPen)
        self.rightEdgeLine.setPen(barPen)

        centerPen = QtGui.QPen(self.color, self.targetLineWidths)
        centerPen.setCapStyle(QtCore.Qt.FlatCap)
        self.targetLine.setPen(centerPen)

        self.updateBarPositions()
        if hasattr(self, "tab"):
            self.tab.tabBar().setTabTextColor(self.tabIdx, self.color)

    def updateBarPositions(self):
        self.centerLine.setLine(self.line().x1(), self.line().y1(), self.line().x2(), self.line().y2())
        self.leftEdgeLine.setLine(self.line().x1() - self.barWidths/2, self.line().y1() + self.barHeight/2, self.line().x1() - self.barWidths/2, self.line().y1() - self.barHeight/2)
        self.rightEdgeLine.setLine(self.line().x2() + self.barWidths/2, self.line().y2() + self.barHeight/2, self.line().x2() + self.barWidths/2, self.line().y2() - self.barHeight/2)
        self.targetLine.setLine((self.line().x1() + self.line().x2()) / 2, self.line().y1() + self.barHeight/2, (self.line().x1() + self.line().x2()) / 2, self.line().y2() - self.barHeight/2)

    def updatePeakRanges(self):
        self.peak.minTime.attribute_value = self.line().x1()
        self.peak.maxTime.attribute_value = self.line().x2()
        self.peak.minValue.attribute_value = self.line().y1()
        self.updateSetpoint()
    def updateFromPeakRanges(self):
        y = self.peak.minValue.attribute_value
        x1 = self.peak.minTime.attribute_value
        x2 = self.peak.maxTime.attribute_value
        if x1 == x2:
            x2 += 1e-9
        self.setLine(x1, y, x2, y)
    def updateLeftValue(self, newLeft):
        right = self.line().x2()
        if newLeft < right:
            self.updateSetpoint()
            self.setLine(newLeft, self.line().y1(), right, self.line().y1())
            self.updateBarPositions()
            self.scanCavityWidget.setPeakGroups()
        
    def updateRightValue(self, newRight):
        left = self.line().x1()
        if left < newRight:
            self.updateSetpoint()
            self.setLine(left, self.line().y1(), newRight, self.line().y1())
            self.updateBarPositions()
            self.scanCavityWidget.setPeakGroups()
    def updateHeight(self, newHeigth):
        self.setLine(self.line().x1(), newHeigth, self.line().x2(), newHeigth)
        self.updateBarPositions()
    def updateSetpoint(self):
        self.peak.setpoint.attribute_value = (self.line().x1() + self.line().x2()) / 2


    @property
    def strokeWidth(self):
        left, bottom, right, top = self.parent.viewRect().getCoords()
        return (top - bottom) * 0.05
    @property
    def barWidths(self):
        left, bottom, right, top = self.parent.viewRect().getCoords()
        return (right - left) * 0.01
    @property
    def targetLineWidths(self):
        return self.barWidths * 0.5
    @property
    def barHeight(self):
        return self.strokeWidth * 5		
    # @property
    # def centerWidth(self):
    # 	return self.barWidths * 0.2

    def mousePressEvent(self, event):
        # Determine if the click is near one of the line's endpoints
        line = self.line()
        self._drag_edge = None

        # Map scene position to line coordinates
        p1 = QtCore.QPointF(line.x1(), line.y1())
        p2 = QtCore.QPointF(line.x2(), line.y2())

        # Use mapFromScene to get local coordinates
        click = event.pos()
        if (QtCore.QLineF(p1, click).dx() < 0):
            self._drag_edge = 'left'
        elif (QtCore.QLineF(click, p2).dx() < 0):
            self._drag_edge = 'right'
        else:
            self._drag_edge = None
        self._distanceBetweenClickAndTop = self.line().x1() - event.pos().x(), self.line().y1() - event.pos().y()
        self._width = self.line().x2() - self.line().x1()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        line = self.line()
        # super().mouseMoveEvent(event)
        if hasattr(self, '_drag_edge') and self._drag_edge:
            if self._drag_edge == 'left' and event.pos().x() < line.x2():
                self.setLine(event.pos().x(),line.y1(), line.x2(), line.y2())
            elif self._drag_edge == 'right' and event.pos().x() > line.x1():
                self.setLine(line.x1(), line.y1(), event.pos().x(),line.y2())
        else:
            topCorner = event.pos().x() + self._distanceBetweenClickAndTop[0], event.pos().y() + self._distanceBetweenClickAndTop[1]
            self.setLine(topCorner[0], topCorner[1], topCorner[0] + self._width, topCorner[1])
        self.updateBarPositions()
        self.updatePeakRanges()
        self.scanCavityWidget.setPeakGroups()

    def mouseReleaseEvent(self, event):
        self._drag_edge = None
        super().mouseReleaseEvent(event)

class peak_widget(ModuleWidget):
    """
    Widget for a single peak.
    """
    # def _togglePID(self):
    #     activated = self.module.togglePID()
    #     self.line.isSetpointActive = activated
    #     self.line.updateFromPeakRanges()
    #     if hasattr(self, "line"):
    #         self.line.isSetpointActive = activated
    #         self.line.updateFromPeakRanges()
    #     self.button_activatePID.setText("unlock peak" if activated else "lock peak")
    # def _enableLocking(self):
    #     self.button_activatePID.setEnabled(self.enabled.attribute_value)
        

    def init_gui(self):
        self.init_main_layout(orientation="vertical")
        #self.main_layout = QtWidgets.QVBoxLayout()
        #self.setLayout(self.main_layout)
        self.init_attribute_layout()
        aws = self.attribute_widgets
        self.minTime = aws["left"]
        self.maxTime = aws["right"]
        self.minValue = aws["height"]
        self.setpoint = aws["timeSetpoint"]
        # if(self.module.peakType != "secondary"):
        #     self.attribute_layout.removeWidget(aws["normalizeIndex"])

        # self.attribute_layout.removeWidget(self.setpoint)
        self.minTime.value_changed.connect(lambda : self.line.updateLeftValue(self.minTime.attribute_value))
        self.maxTime.value_changed.connect(lambda : self.line.updateRightValue(self.maxTime.attribute_value))
        self.minValue.value_changed.connect(lambda : self.line.updateHeight(self.minValue.attribute_value))
        
        # self.button_activatePID = QtWidgets.QPushButton("lock peak")
        # self.button_activatePID.clicked.connect(self._togglePID)
        # self.main_layout.addWidget(self.button_activatePID)
        self.enabled = aws["enabled"]
        self.locking = aws["locking"]
        self.normalizeIndex = aws["normalizeIndex"]
        
        self.color = aws["peakColor"]
        self.color.value_changed.connect(self.updateCurve)
        self.enabled.value_changed.connect(self.updateCurve)
        self.normalizeIndex.value_changed.connect(self.updateCurve)
        self.enabled.value_changed.connect(lambda : self.line.scanCavityWidget.setPeakGroups())
        # self.enabled.value_changed.connect(self._enableLocking)
        # self._enableLocking()

    def __init__(self, name, module, parent=None):
        super().__init__(name, module, parent)
        self.graph = None
    def setGraphForPeakLine(self, graph, scanCavityWidget, color):
        self.graph = graph
        self.line = PeakLine(graph, self, scanCavityWidget, color)
        self.line.updateFromPeakRanges()
        if self.color.attribute_value == 0:
            self.color.attribute_value = color
        self.curve = graph.plot(pen=(QtGui.QColor(color).red(),
                                    QtGui.QColor(color).green(),
                                    QtGui.QColor(color).blue()
                                    ))
        self.updateCurve()
    def updateCurve(self, t = None, x = None):
        color = QtGui.QColor(self.color.attribute_value)
        self.line.color = color
        self.curve.setPen(( color.red(),
                            color.green(),
                            color.blue()
                            ))        
        if t is not None and self.module.inCurrentPeakGroup:
            indexes = np.logical_and(t > self.minTime.attribute_value, t < self.maxTime.attribute_value)
            x = x[indexes]
            t = t[indexes]      
            self.curve.setData(t, x)
            
        if self.module.active:
            self.curve.setVisible(True)
        else:
            self.curve.setVisible(self.module not in self.line.scanCavityWidget.unusablePeaks)
        self.line.updateSizes()
    def setpointToCurrentValue(self):
        #get the last acquisition from the scope and put its average as the new setpoint
        acquisition = self.module.parent.scope.getLastAcquisition(self.inputSignal_widget.attribute_value)
        self.setpoint_widget.attribute_value = np.mean(acquisition)



class secondaryPitaya_widget(ModuleWidget):
    pass

class ScanCavity_widget(AcquisitionModuleWidget):
    """
    A widget to represent a scan cavity lock
    """
    colors = [
        QtGui.QColor(255, 0, 0),      # red
        QtGui.QColor(0, 255, 0),      # green
        QtGui.QColor(0, 0, 255),      # blue
        QtGui.QColor(255, 165, 0),    # orange
        QtGui.QColor(255, 0, 255),    # magenta
        QtGui.QColor(0, 255, 255),    # cyan
        QtGui.QColor(200, 200, 0),    # ocra (yellow is too bright)
        QtGui.QColor(139, 0, 0),      # dark red
        QtGui.QColor(0, 100, 0),      # dark green
        QtGui.QColor(0, 0, 139),       # dark blue
    ]
    def init_gui(self):                
        """
        sets up all the gui for the scope.
        """
        self.datas = [None, None]
        self.times = None
        self.ch_color = ['white']#('green', 'red', 'blue')
        self.ch_transparency = 0x80#(255, 255, 255)  # 0 is transparent, 255 is not  # deactivated transparency for speed reasons
        #self.module.__dict__['curve_name'] = 'scope'
        #self.main_layout = QtWidgets.QVBoxLayout()
        self.init_main_layout(orientation="vertical")
        self.init_attribute_layout()
        aws = self.attribute_widgets

        self.layout_channels = QtWidgets.QVBoxLayout()
        self.layout_ch1 = QtWidgets.QHBoxLayout()
        self.layout_math = QtWidgets.QHBoxLayout()
        self.layout_channels.addLayout(self.layout_ch1)
        self.layout_channels.addLayout(self.layout_math)

        self.attribute_layout.removeWidget(aws['input1'])

        self.layout_ch1.addWidget(aws['input1'])


        self.attribute_layout.addLayout(self.layout_channels)

        self.attribute_layout.removeWidget(aws['duration'])
        self.layout_duration = QtWidgets.QVBoxLayout()
        self.duration = aws['duration']
        self.layout_duration.addWidget(self.duration)
        self.attribute_layout.addLayout(self.layout_duration)
        self.duration.value_changed.connect(self.scalePeaksWithNewDuration)

        #self.attribute_layout.removeWidget(aws['curve_name'])

        self.button_layout = QtWidgets.QHBoxLayout()

        aws = self.attribute_widgets
        self.attribute_layout.removeWidget(aws["trace_average"])
        self.attribute_layout.removeWidget(aws["curve_name"])

        #self.setLayout(self.main_layout)

        self.unusablePeaks = []
        self.setWindowTitle("Cavity scan")
        self.win = pg.GraphicsLayoutWidget(title="Cavity scan")
        self.plot_item = self.win.addPlot(title="Cavity scan")
        self.plot_item.showGrid(y=True, alpha=1.)
        self.viewBox = self.plot_item.getViewBox()
        self.viewBox.setMouseEnabled(y=False)
        def add_new_tab(tab, content, tabTitle):
            new_tab = QtWidgets.QWidget()
            new_tab_layout = QtWidgets.QHBoxLayout()
            new_tab_layout.addWidget(content)
            new_tab.setLayout(new_tab_layout)
            tab.addTab(content, tabTitle)
            if isinstance(content, peak_widget):
                idx = tab.indexOf(content)
                tab.tabBar().setTabTextColor(idx, content.line.color)
                content.line.tab = tab
                content.line.tabIdx = idx
        
        def on_view_changed():
            for peak in self.peakList:
                peak.line.updateSizes()
        def updateAllPeakLines():
            for p in self.peakList:
                p.line.updateFromPeakRanges()
                p.line.updateBarPositions()

        self.curves = [self.plot_item.plot(pen=(QtGui.QColor(color).red(),
                                                QtGui.QColor(color).green(),
                                                QtGui.QColor(color).blue()
                                                )) for color in self.ch_color]
        # self.main_layout.addWidget(self.win, stretch=10) #let's do it later, so that the graph is on the bottom of the window

        self.peakTabs = QtWidgets.QTabWidget()
        self.main_layout.addWidget(self.peakTabs)

        ml : peak_widget = self.mainL._create_widget()
        ml.setGraphForPeakLine(self.plot_item, self, ScanCavity_widget.colors[0])
        add_new_tab(self.peakTabs, ml, "main Left")
        mr : peak_widget = self.mainR._create_widget()
        mr.setGraphForPeakLine(self.plot_item, self, ScanCavity_widget.colors[1])
        add_new_tab(self.peakTabs, mr, "main Right")
        self.peakList = [ml, mr]
        for i, peak in enumerate(self.module.secondaryPeaks):
            widget : peak_widget = peak._create_widget()
            widget.setGraphForPeakLine(self.plot_item, self, ScanCavity_widget.colors[i+2])
            add_new_tab(self.peakTabs, widget, peak.name)
            self.peakList.append(widget)
            self.secondaryPitayasTabs = QtWidgets.QTabWidget()

        # Create a collapsible container for the tabs
        self.secondaryPitayas_container = QtWidgets.QWidget()
        _container_layout = QtWidgets.QVBoxLayout()
        _container_layout.setContentsMargins(0, 0, 0, 0)

        # Header with a toggle button (collapses/expands the tabs)
        header = QtWidgets.QWidget()
        _h_layout = QtWidgets.QHBoxLayout()
        _h_layout.setContentsMargins(0, 0, 0, 0)
        self._secondary_toggle = QtWidgets.QToolButton()
        self._secondary_toggle.setCheckable(True)
        self._secondary_toggle.setChecked(True)
        self._secondary_toggle.setArrowType(QtCore.Qt.DownArrow)
        # toggle visibility and arrow direction
        self._secondary_toggle.toggled.connect(
            lambda checked: (
            self.secondaryPitayasTabs.setVisible(checked),
            self._secondary_toggle.setArrowType(QtCore.Qt.DownArrow if checked else QtCore.Qt.RightArrow)
            )
        )
        _h_layout.addWidget(self._secondary_toggle)
        _h_layout.addWidget(QtWidgets.QLabel("Secondary Pitayas"))
        _h_layout.addStretch(1)
        header.setLayout(_h_layout)

        _container_layout.addWidget(header)
        _container_layout.addWidget(self.secondaryPitayasTabs)
        self.secondaryPitayas_container.setLayout(_container_layout)

        # Add the whole container (header + tabs) to the main layout
        self.main_layout.addWidget(self.secondaryPitayas_container)

        for secondaryPitaya in self.module.secondaryPitayas:
            widget = secondaryPitaya._create_widget()
            add_new_tab(self.secondaryPitayasTabs, widget, secondaryPitaya.name)


        self.main_layout.addWidget(self.win, stretch=10)
        self.main_layout.addLayout(self.button_layout)

        
        self.rolling_group = QtWidgets.QGroupBox("Trigger mode")
        self.checkbox_normal = QtWidgets.QRadioButton("Normal")
        self.checkbox_untrigged = QtWidgets.QRadioButton("Untrigged (rolling)")
        self.checkbox_normal.setChecked(True)
        self.lay_radio = QtWidgets.QVBoxLayout()
        self.lay_radio.addWidget(self.checkbox_normal)
        self.lay_radio.addWidget(self.checkbox_untrigged)
        self.rolling_group.setLayout(self.lay_radio)
        self.attribute_layout.insertWidget(
            list(self.attribute_widgets.keys()).index("trigger_source"),
            self.rolling_group)
        self.rolling_group.setVisible(False)
        aws["threshold"].setVisible(False)
        aws["hysteresis"].setVisible(False)
        self.checkbox_normal.clicked.connect(self.rolling_mode_toggled)
        self.checkbox_untrigged.clicked.connect(self.rolling_mode_toggled)
        #self.update_rolling_mode_visibility()
        self.attribute_widgets['duration'].value_changed.connect(self.update_rolling_mode_visibility)
        self.attribute_widgets['duration'].value_changed.connect(updateAllPeakLines)

        self.plot_item.sigRangeChanged.connect(lambda _, __: on_view_changed())
        self.plot_item.getViewBox().sigResized.connect(on_view_changed)

        super(ScanCavity_widget, self).init_gui()
        # since trigger_mode radiobuttons is not a regular attribute_widget,
        # it is not synced with the module at creation time.
        self.update_running_buttons()
        self.update_rolling_mode_visibility()
        self.rolling_mode = self.module.rolling_mode
        self.attribute_layout.addStretch(1)
        self.setPeakGroups()
        
    def scalePeaksWithNewDuration(self):
        pass
    @property
    def mainL(self):
        return self.module.mainL
    @property
    def mainR(self):
        return self.module.mainR

    def update_attribute_by_name(self, name, new_value_list):
        """
        Updates all attributes on the gui when their values have changed.
        """
        super(ScanCavity_widget, self).update_attribute_by_name(name, new_value_list)
        if name in ['rolling_mode', 'duration']:
            self.rolling_mode = self.module.rolling_mode
            self.update_rolling_mode_visibility()
        if name in ['_running_state',]:
            self.update_running_buttons()

    def display_channel_obsolete(self, ch):
        """
        Displays channel ch (1 or 2) on the graph
        :param ch:
        """
        try:
                self.datas[ch-1] = self.module.trace(ch)
                self.times = self.module.times
                self.curves[ch-1].setData(self.times,
                                          self.datas[ch-1])
        except NotReadyError:
            pass

    def change_ownership(self):
        """
        For some reason the visibility of the rolling mode panel is not updated
        when the scope becomes free again unless we ask for it explicitly...
        """
        super(ScanCavity_widget, self).change_ownership()
        self.update_rolling_mode_visibility()

    def display_curve(self, list_of_arrays):
        """
        Displays all active channels on the graph.
        """
        times, (ch1, ch2) = list_of_arrays
        self.curves[0].setData(times, ch1)
        self.curves[0].setVisible(True)
        self.update_current_average() # to update the number of averages
        for peak in self.peakList:
            peak.updateCurve(times, ch1)

        self.changePeakGroup()

    def set_rolling_mode(self):
        """
        Set rolling mode on or off based on the module's attribute
        "rolling_mode"
        """
        self.rolling_mode = self.module.rolling_mode

    def rolling_mode_toggled(self):
        self.module.rolling_mode = self.rolling_mode

    @property
    def rolling_mode(self):
        return ((self.checkbox_untrigged.isChecked()) and self.rolling_group.isEnabled())

    @rolling_mode.setter
    def rolling_mode(self, val):
        if val:
            self.checkbox_untrigged.setChecked(True)
        else:
            self.checkbox_normal.setChecked(True)
        return val

    def update_rolling_mode_visibility(self):
        """
        Hide rolling mode checkbox for duration < 100 ms
        """
        self.rolling_group.setEnabled(self.module._rolling_mode_allowed())
        self.attribute_widgets['trigger_source'].widget.setEnabled(
            not self.rolling_mode)
        self.attribute_widgets['threshold'].widget.setEnabled(
            not self.rolling_mode)
        self.attribute_widgets['hysteresis'].widget.setEnabled(
            not self.rolling_mode)
        single_enabled = (not self.module._is_rolling_mode_active()) and \
                            self.module.running_state!="running_continuous"
        self.button_single.setEnabled(single_enabled)

    def update_running_buttons(self):
        super(ScanCavity_widget, self).update_running_buttons()
        self.update_rolling_mode_visibility()

    def save_clicked(self):
        self.module.save_curve()

    @staticmethod
    def getGroupsOfNonOverlapping_old(peakList):
        #I have to put it here instead than inside the peak class, because python doesn't let me import it 
        # (cannot import name 'ScanningCavity' from partially initialized module 
        #'pyrpl.software_modules.scanningCavity' (most likely due to a circular import))
        peakList = [p for p in peakList if p.enabled]
        if len(peakList) == 0:
            return [[]], []
        ranges = [(p.left, p.right) for p in peakList]
        mainPeaks = np.where([p.peakType != "secondary" for p in peakList])[0]
        normalizedPeaks = np.where([p.peakType == "secondary" and p.normalizeIndex for p in peakList])[0]

        def areIntersecting(range0, range1):
            return (range0[0] < range1[1]) ^ (range0[1] <= range1[0])
        
        intersections = np.eye(len(ranges), dtype=bool)
        for i in range(len(ranges)):
            for j in range(i+1, len(ranges)):
                intersections[i,j] = areIntersecting(ranges[i], ranges[j])
        intersections = np.logical_or(intersections, intersections[::-1,::-1])
        
        allGroups = []
        run = []
        inaccessiblePeaks = []
        if len(normalizedPeaks) > 0 and intersections[mainPeaks[0], mainPeaks[1]]:
            print("main peaks overlapping, the normalized peaks cannot be enabled")
            inaccessiblePeaks = normalizedPeaks
        elif len(normalizedPeaks) > 0:
            #main peaks non overlapping, let's add them to the first group
            run = mainPeaks
            intersectionWithMains = intersections[mainPeaks][:,normalizedPeaks]
            intersectionWithMains = np.logical_or(intersectionWithMains[0], intersectionWithMains[1])
            if any(intersectionWithMains):
                print("there's a normalized peak overlapping with the main ones")
                run = np.concatenate((run, normalizedPeaks[~intersectionWithMains]))
            else:                
                run = np.concatenate((run, normalizedPeaks))
            inaccessiblePeaks = normalizedPeaks[intersectionWithMains]
            run = list(run)

        stillFree = np.delete(np.arange(len(peakList)), np.concatenate((inaccessiblePeaks, run)).astype(int))
        while len(stillFree) > 0 or len(run) > 0:
            addedIndexes = []
            for i in range(len(stillFree)):
                testedLine = np.repeat(stillFree[i],len(run))
                if not np.any(intersections[run, testedLine]):
                    addedIndexes.append(i)
                    run.append(stillFree[i])
            stillFree = np.delete(stillFree, addedIndexes)
            allGroups.append(run)
            run = []
                
        return [[peakList[i] for i in group] for group in allGroups], inaccessiblePeaks
    def getGroupsOfNonOverlapping(peakList):
        '''finds a set of non-overlapping groups of peaks, so that they can be activated at the same time.
        The way it finds the groups is to transform the problem into a graph (each peak is a node, and edges 
        represent if 2 peaks are non-overlapping), and then it solves the problem of finding the smallest set 
        of subgraphs that are internally completely connected (each node is connected to all other nodes, which 
        means all the corresponding peaks are non-overlapping)
        The graph problem is solved with a greedy algorithm (the exact algorithm has exponential time, python 
        takes many seconds even to solve for a 10-node graph, we don't have time), so the solution might not be 
        the optimal one.
        Normalized peaks are taken into consideration, so they will always be set in a group that also contains 
        the main peaks (of course, if a normalized peak overlap with a main peak, it is immediately discarded 
        with a warning)'''
        #I have to put it here instead than inside the peak class, because python doesn't let me import it 
        # (cannot import name 'ScanningCavity' from partially initialized module 
        #'pyrpl.software_modules.scanningCavity' (most likely due to a circular import))

        #get all the peaks, and check which ones are normalized
        peakList = [p for p in peakList if p.enabled]
        indexToPeak = np.arange(len(peakList))
        if len(peakList) == 0:
            return [[]], []
        ranges = [(p.left, p.right) for p in peakList]
        mainPeaks = np.where([p.peakType != "secondary" for p in peakList])[0]
        normalizedPeaks = np.where([p.peakType == "secondary" and p.normalizeIndex for p in peakList])[0]

        # calcluate all intersections
        def areIntersecting(range0, range1):
            return (range0[0] < range1[1]) ^ (range0[1] <= range1[0])		
        intersections = np.zeros((len(ranges),len(ranges)), dtype=bool)
        for i in range(len(ranges)):
            for j in range(i+1, len(ranges)):
                intersections[i,j] = areIntersecting(ranges[i], ranges[j])
        intersections = np.logical_or(intersections, intersections.T)
        
        # check for unacceptable intersections (normalized with mains, main with main if there are normalized peaks)
        inaccessiblePeaks = np.zeros_like(peakList, dtype = bool)
        if len(normalizedPeaks) > 0 and intersections[mainPeaks[0], mainPeaks[1]]:
            print("main peaks overlapping, the normalized peaks cannot be enabled")
            inaccessiblePeaks[normalizedPeaks] = True
        elif len(normalizedPeaks) > 0:
            intersectionWithMains = intersections[mainPeaks]
            intersectionWithMains = np.logical_or(intersectionWithMains[0], intersectionWithMains[1])
            intersectionMain_Normalized = intersectionWithMains[normalizedPeaks]
            inaccessiblePeaks[normalizedPeaks[intersectionMain_Normalized]] = True
            normalizedPeaks = normalizedPeaks[~intersectionMain_Normalized]
            intersections[normalizedPeaks,:] = np.logical_or(intersections[normalizedPeaks,:], intersectionWithMains)
            intersections = np.logical_or(intersections, intersections.T)
        intersections = intersections[~inaccessiblePeaks][:,~inaccessiblePeaks]
        indexToPeak = indexToPeak[~inaccessiblePeaks]
        graphEdges = np.array(np.where(~intersections)).T
        graphEdges = [(row[0],row[1]) for row in graphEdges]
        G = nx.Graph(graphEdges)
        groups = greedy_clique_partition(G)
        return [[peakList[indexToPeak[i]] for i in group] for group in groups], [p for i,p in enumerate(peakList) if inaccessiblePeaks[i]]
    
    def setPeakGroups(self):
        # sc : ScanningCavity = self.module
        sc = self.module
        peaks = sc.usedPeaks
        self.peakGroups, self.unusablePeaks = ScanCavity_widget.getGroupsOfNonOverlapping(peaks)
        self.currentGroupIndex = np.random.randint(len(self.peakGroups))#let's randomize the first group, 
                # so that if we have very fast updates of the peaks (example, while dragging a peak around), 
                # we won't end up controlling only the first group
        for p in peaks:
            p.inCurrentPeakGroup = p in self.peakGroups[self.currentGroupIndex]
        for i in range(1, len(self.curves)):
            self.curves[i].setVisible(False)
        for p in self.unusablePeaks:
            p.inCurrentPeakGroup = False
    def changePeakGroup(self):
        if len(self.peakGroups) <= 1:
            #let's not do anything, since we don't need to swap peaks around
            return
        newIndex = (self.currentGroupIndex + 1) % len(self.peakGroups)
        for p in self.peakGroups[self.currentGroupIndex]:
            p.inCurrentPeakGroup = False
        for p in self.peakGroups[newIndex]:
            p.inCurrentPeakGroup = True

        self.currentGroupIndex = newIndex


