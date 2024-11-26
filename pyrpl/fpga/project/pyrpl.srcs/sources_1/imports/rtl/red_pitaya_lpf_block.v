`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: LKB 
// Engineer: Leonhard Neuhaus
// 
// Create Date: 18.02.2016 11:42:49
// Design Name: 
// Module Name: red_pitaya_lpf_block
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
/*
###############################################################################
#    pyrpl - DSP servo controller for quantum optics with the RedPitaya
#    Copyright (C) 2014-2016  Leonhard Neuhaus  (neuhaus@spectro.jussieu.fr)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
############################################################################### 
*/

module red_pitaya_lpf_block
#(
    parameter     SHIFTBITS =     4,//shift can be from 0 to 15 bits
    parameter     SIGNALBITS   = 14, //bitwidth of signals
    parameter     MINBW        = 10  //minimum allowed filter bandwidth
    )
(
    input clk_i,
    input rstn_i  ,
    input [SHIFTBITS:0] shift, 
    input filter_on,
    input highpass,
    input signed  [SIGNALBITS-1:0] signal_i,
    output signed [SIGNALBITS-1:0] signal_o
);


   
localparam MAXSHIFT = $clog2(125000000/MINBW);  // gives an effective limit of 10 MHz (divided by 4 pi)

reg  signed [SIGNALBITS+MAXSHIFT-1:0]    y;
reg  signed [SIGNALBITS+MAXSHIFT-1:0]    delta;   //we need this cumbersome imperfect implementation with a delta buffer to introduce some delay so the code works at 125 MHZ
wire signed [SIGNALBITS+MAXSHIFT-1:0]    shifted_delta;
wire signed [SIGNALBITS-1:0]  y_out;
wire filter_off;

assign y_out = y[MAXSHIFT+SIGNALBITS-1:MAXSHIFT];
assign shifted_delta = delta<<((shift<MAXSHIFT) ? shift : MAXSHIFT);

always @(posedge clk_i) begin
    if (rstn_i == 1'b0) begin
        y <=            {MAXSHIFT+SIGNALBITS{1'b0}};
        delta <=        {MAXSHIFT+SIGNALBITS{1'b0}};
    end
    else begin
        delta <= signal_i - y_out;
        y <= y + shifted_delta;
    end
end
  
assign signal_o = (filter_on == 1'b0) ? signal_i : ( (highpass==1'b0) ? y_out : delta);

endmodule
