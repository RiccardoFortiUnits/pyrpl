// (c) Copyright 1995-2024 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.

// IP VLNV: xilinx.com:ip:xadc_wiz:3.2
// IP Revision: 0

// The following must be inserted into your Verilog file for this
// core to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
system_xadc_0 your_instance_name (
  .s_axi_aclk(s_axi_aclk),                    // input wire s_axi_aclk
  .s_axi_aresetn(s_axi_aresetn),              // input wire s_axi_aresetn
  .s_axi_awaddr(s_axi_awaddr),                // input wire [10 : 0] s_axi_awaddr
  .s_axi_awvalid(s_axi_awvalid),              // input wire s_axi_awvalid
  .s_axi_awready(s_axi_awready),              // output wire s_axi_awready
  .s_axi_wdata(s_axi_wdata),                  // input wire [31 : 0] s_axi_wdata
  .s_axi_wstrb(s_axi_wstrb),                  // input wire [3 : 0] s_axi_wstrb
  .s_axi_wvalid(s_axi_wvalid),                // input wire s_axi_wvalid
  .s_axi_wready(s_axi_wready),                // output wire s_axi_wready
  .s_axi_bresp(s_axi_bresp),                  // output wire [1 : 0] s_axi_bresp
  .s_axi_bvalid(s_axi_bvalid),                // output wire s_axi_bvalid
  .s_axi_bready(s_axi_bready),                // input wire s_axi_bready
  .s_axi_araddr(s_axi_araddr),                // input wire [10 : 0] s_axi_araddr
  .s_axi_arvalid(s_axi_arvalid),              // input wire s_axi_arvalid
  .s_axi_arready(s_axi_arready),              // output wire s_axi_arready
  .s_axi_rdata(s_axi_rdata),                  // output wire [31 : 0] s_axi_rdata
  .s_axi_rresp(s_axi_rresp),                  // output wire [1 : 0] s_axi_rresp
  .s_axi_rvalid(s_axi_rvalid),                // output wire s_axi_rvalid
  .s_axi_rready(s_axi_rready),                // input wire s_axi_rready
  .ip2intc_irpt(ip2intc_irpt),                // output wire ip2intc_irpt
  .vp_in(vp_in),                              // input wire vp_in
  .vn_in(vn_in),                              // input wire vn_in
  .vauxp0(vauxp0),                            // input wire vauxp0
  .vauxn0(vauxn0),                            // input wire vauxn0
  .vauxp1(vauxp1),                            // input wire vauxp1
  .vauxn1(vauxn1),                            // input wire vauxn1
  .vauxp8(vauxp8),                            // input wire vauxp8
  .vauxn8(vauxn8),                            // input wire vauxn8
  .vauxp9(vauxp9),                            // input wire vauxp9
  .vauxn9(vauxn9),                            // input wire vauxn9
  .user_temp_alarm_out(user_temp_alarm_out),  // output wire user_temp_alarm_out
  .vccint_alarm_out(vccint_alarm_out),        // output wire vccint_alarm_out
  .vccaux_alarm_out(vccaux_alarm_out),        // output wire vccaux_alarm_out
  .vccpint_alarm_out(vccpint_alarm_out),      // output wire vccpint_alarm_out
  .vccpaux_alarm_out(vccpaux_alarm_out),      // output wire vccpaux_alarm_out
  .vccddro_alarm_out(vccddro_alarm_out),      // output wire vccddro_alarm_out
  .ot_out(ot_out),                            // output wire ot_out
  .channel_out(channel_out),                  // output wire [4 : 0] channel_out
  .eoc_out(eoc_out),                          // output wire eoc_out
  .alarm_out(alarm_out),                      // output wire alarm_out
  .eos_out(eos_out),                          // output wire eos_out
  .busy_out(busy_out)                        // output wire busy_out
);
// INST_TAG_END ------ End INSTANTIATION Template ---------

// You must compile the wrapper file system_xadc_0.v when simulating
// the core, system_xadc_0. When compiling the wrapper file, be sure to
// reference the Verilog simulation library.

