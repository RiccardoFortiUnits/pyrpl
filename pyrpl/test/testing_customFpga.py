# -*- coding: utf-8 -*-
"""
Created on Mon Jun 17 18:01:10 2024

@author: lastline
"""

# def install_and_import(package):
# 	import subprocess
# 	import sys
# 	try:
# 		__import__(package)
# 	except ImportError:
# 		try:
# 			subprocess.check_call([sys.executable, "-m", "pip", "install", package])
# 		except:
# 			subprocess.check_call([sys.executable, "-m", "pip", "install", f"py{package}"])
# 		__import__(package)
		
# install_and_import("qtpy")
# install_and_import("scp")
# install_and_import("PyQt5")
# install_and_import("PyQt6")
# install_and_import("yaml")




# from pyrpl import Pyrpl

# p = Pyrpl("dtfyfweg")
# # input("press enter to close pyrpl")


# Import necessary modules
from PyQt5.QtWidgets import QApplication
from pyrpl import Pyrpl
import sys

# Create the Qt Application
app = QApplication(sys.argv)

# Initialize Pyrpl
p = Pyrpl("dtfyueeg")

# (Optional) Interact with your Pyrpl object here
# e.g., p.set_attribute(...)

# Start the Qt event loop
sys.exit(app.exec_())









