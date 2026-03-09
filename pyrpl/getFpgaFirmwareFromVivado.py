# -*- coding: utf-8 -*-
"""
Created on Thu May  9 10:03:38 2024

@author: lastline
"""

"""
This code speeds up the process to generate the .bin file that will be loaded on the fpga. Of course, you need to setup the correct file paths of your PC.
"""

import subprocess
from datetime import datetime
import shutil

newFpgaName = "scanCavity" + datetime.now().strftime(" %d_%m_%Y %H_%M")+".bit.bin"

#I also save every binary file into a backup folder, in case I create intermediate 
# binaries that I end up not committing. You can omit this extra backup by setting 
# this folder to None
backupSaveFolder = "d:/lastline/new_backupFpgaBinaries/" #None

fpgaFilePath = "C:/Git/pyrpl/pyrpl/fpga/"
projectBinFilePath = fpgaFilePath + "project/pyrpl.runs/impl_1/"

#execute the batch that converts the bitstream to one usable by the redPitaya
batFilePath="D:/Xilinx/Vivado/2020.1/bin/create_RP_binFile.bat " + projectBinFilePath
p = subprocess.Popen(batFilePath, shell=True, stdout = subprocess.PIPE)
stdout, stderr = p.communicate()

if backupSaveFolder is not None:
	backupSaveFolder += newFpgaName
	#save a backup of the newly created binary
	shutil.copyfile(projectBinFilePath + "red_pitaya_top.bit.bin", 
				backupSaveFolder)

shutil.copyfile(projectBinFilePath + "red_pitaya_top.bit.bin", 
            fpgaFilePath + "red_pitaya.bin")
shutil.copyfile(projectBinFilePath + "red_pitaya_top.bit.bin", 
            "D:/Anaconda3/Lib/site-packages/pyrpl/fpga/red_pitaya.bin")
print("done. Yay!")