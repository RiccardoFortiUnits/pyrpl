
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
	QWidget:disabled {
		/* Slightly darker background and dimmed text for disabled containers */
		background-color: #262626;
		color: #8f8f8f;
	}

	QPushButton {
		background-color: #353535;
		border: 1px solid #5c5c5c;
		padding: 5px;
		border-radius: 5px;
		color: #ffffff;
	}
	QPushButton:hover {
		background-color: #454545;
	}
	QPushButton:disabled {
		background-color: #2f2f2f;
		border: 1px solid #444444;
		color: #9a9a9a;
	}

	QLineEdit, QSpinBox, QDoubleSpinBox {
		background-color: #353535;
		border: 1px solid #5c5c5c;
		border-radius: 5px;
		color: #ffffff;
	}
	QLineEdit:disabled, QSpinBox:disabled, QDoubleSpinBox:disabled {
		background-color: #2b2b2b;
		border: 1px dashed #444444;
		color: #8f8f8f;
	}

	QComboBox {
		background-color: #353535;
		border: 1px solid #5c5c5c;
		padding: 3px;
		border-radius: 5px;
		color: #ffffff;
	}
	QComboBox:disabled {
		background-color: #2b2b2b;
		border: 1px solid #444444;
		color: #8f8f8f;
	}

	QLabel:disabled {
		color: #8f8f8f;
	}
"""

# Optional: Apply the stylesheet
QtWidgets.QApplication.instance().setStyleSheet(DARK_STYLESHEET)