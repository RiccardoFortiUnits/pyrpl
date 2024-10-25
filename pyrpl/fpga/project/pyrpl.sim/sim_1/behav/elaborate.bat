@echo off
set xv_path=D:\\Xilinx2015_4\\Vivado\\2015.4\\bin
call %xv_path%/xelab  -wto 0d6a1d89d1b94e79ab9a51f6f33cfc9b -m64 --debug typical --relax --mt 2 -L xil_defaultlib -L generic_baseblocks_v2_1_0 -L fifo_generator_v13_0_1 -L axi_data_fifo_v2_1_6 -L axi_infrastructure_v1_1_0 -L axi_register_slice_v2_1_7 -L axi_protocol_converter_v2_1_7 -L lib_cdc_v1_0_2 -L proc_sys_reset_v5_0_8 -L unisims_ver -L unimacro_ver -L secureip --snapshot red_pitaya_top_behav xil_defaultlib.red_pitaya_top xil_defaultlib.glbl -log elaborate.log
if "%errorlevel%"=="0" goto SUCCESS
if "%errorlevel%"=="1" goto END
:END
exit 1
:SUCCESS
exit 0
