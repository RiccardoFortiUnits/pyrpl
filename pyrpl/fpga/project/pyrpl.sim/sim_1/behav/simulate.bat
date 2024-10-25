@echo off
set xv_path=D:\\Xilinx2015_4\\Vivado\\2015.4\\bin
call %xv_path%/xsim red_pitaya_top_behav -key {Behavioral:sim_1:Functional:red_pitaya_top} -tclbatch red_pitaya_top.tcl -log simulate.log
if "%errorlevel%"=="0" goto SUCCESS
if "%errorlevel%"=="1" goto END
:END
exit 1
:SUCCESS
exit 0
