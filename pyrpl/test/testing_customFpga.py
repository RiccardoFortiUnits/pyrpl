# -*- coding: utf-8 -*-
"""
Created on Mon Jun 17 18:01:10 2024

@author: lastline
"""
# from pyrpl.redpitaya import RedPitaya
# import numpy as np
# import time
# try:
#     rp.end_all()
# except:
#     pass
# rp = RedPitaya(
#     hostname='rp-f0bd67.local', # the ip or hostname of the board
#     port=2222,  # port for PyRPL datacommunication
#     sshport=22,  # port of ssh server - default 22
#     user='root',
#     password='root',
#     delay=0.05,  # delay between ssh commands - console is too slow otherwise
#     autostart=True,  # autostart the client?
#     reloadserver=False,  # reinstall the server at startup if not necessary?
#     reloadfpga=True,  # reload the fpga bitfile at startup?
#     filename='C:/Git/pyrpl/pyrpl/fpga/red_pitaya.bin',  # name of the bitfile for the fpga, None is default file
#     serverbinfilename='red_pitaya.bin',  # name of the binfile on the server
#     serverdirname = "//opt//pyrpl//",  # server directory for server app and bitfile
#     leds_off=True,  # turn off all GPIO lets at startup (improves analog performance)
#     frequency_correction=1.0,  # actual FPGA frequency is 125 MHz * frequency_correction
#     timeout=3,  # timeout in seconds for ssh communication
#     monitor_server_name='monitor_server',  # name of the server program on redpitaya
#     silence_env=False)  # suppress all environment variables that may override the configuration?)

# # rp.pidnouveau0.p = -1
# # rp.pidnouveau0.active = True
# # rp.pidnouveau0.setLLinearizer(x=[-1,0,1],y=[-1,1,-1])

# # rp.amsnouveau.staticValue = 1.5
# # # rp.amsnouveau.outputSource='ramp'
# # rp.amsnouveau.setRamp(True, TriggerType='digitalPin', useMultiTriggers = False, IdleConfig = 'endValue')

# # rp.hk.expansion_N0 = True
# # rp.hk.expansion_P0 = True
# rp.hk.setFastSwitch(pin = 0, triggerPin = 1, activeTime = 1e-7, inactiveTime = 5e-7, channelsDelay = 25e-9)

# # rp.end_all()


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

# p = Pyrpl("erdt")
# input("press enter to close pyrpl")
# Python
# Import necessary modules
from PyQt5.QtWidgets import QApplication
from pyrpl import Pyrpl
import sys

# Create the Qt Application
app = QApplication(sys.argv)

# Initialize Pyrpl
p = Pyrpl("singlePitaya")

# (Optional) Interact with your Pyrpl object here
# e.g., p.set_attribute(...)

# Start the Qt event loop
sys.exit(app.exec_())









