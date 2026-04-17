// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
// Date        : Fri Apr 17 10:07:12 2026
// Host        : PC-CAUTERO-NEW running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/Git/pyrpl/pyrpl/fpga/project/pyrpl.srcs/sources_1/ip/div_gen_s_44_28/div_gen_s_44_28_stub.v
// Design      : div_gen_s_44_28
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z010clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "div_gen_v5_1_16,Vivado 2020.1" *)
module div_gen_s_44_28(aclk, aresetn, s_axis_divisor_tvalid, 
  s_axis_divisor_tdata, s_axis_dividend_tvalid, s_axis_dividend_tdata, 
  m_axis_dout_tvalid, m_axis_dout_tdata)
/* synthesis syn_black_box black_box_pad_pin="aclk,aresetn,s_axis_divisor_tvalid,s_axis_divisor_tdata[31:0],s_axis_dividend_tvalid,s_axis_dividend_tdata[47:0],m_axis_dout_tvalid,m_axis_dout_tdata[79:0]" */;
  input aclk;
  input aresetn;
  input s_axis_divisor_tvalid;
  input [31:0]s_axis_divisor_tdata;
  input s_axis_dividend_tvalid;
  input [47:0]s_axis_dividend_tdata;
  output m_axis_dout_tvalid;
  output [79:0]m_axis_dout_tdata;
endmodule
