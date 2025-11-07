
from qtpy import QtCore, QtWidgets

# Available Qt styles
AVAILABLE_STYLES = QtWidgets.QStyleFactory.keys()
# print(AVAILABLE_STYLES)
# Optional: Set a default style for all widgets
# Common styles include: 'Fusion', 'Windows', 'WindowsVista', 'Macintosh'
DEFAULT_STYLE = 'Windows'  # Or choose another style
if DEFAULT_STYLE in AVAILABLE_STYLES:
	QtWidgets.QApplication.setStyle(DEFAULT_STYLE)

# You can also set a stylesheet for custom colors/styling
# Example dark theme stylesheet
DARK_STYLESHEET = """
	QWidget {
		background-color: #2b2b2b;
		color: #ffffff;
	}
	QPushButton {
		background-color: #353535;
		border: 1px solid #5c5c5c;
		padding: 5px;
		border-radius: 5px;
	}
	QPushButton:hover {
		background-color: #454545;
	}
	QLineEdit, QSpinBox, QDoubleSpinBox {
		background-color: #353535;
		border: 1px solid #5c5c5c;
		max-width: 100px;
		border-radius: 5px;
	}
	QComboBox {
		background-color: #353535;
		border: 1px solid #5c5c5c;
		padding: 3px;
		border-radius: 5px;
	}
"""

# Optional: Apply the stylesheet
QtWidgets.QApplication.instance().setStyleSheet(DARK_STYLESHEET)