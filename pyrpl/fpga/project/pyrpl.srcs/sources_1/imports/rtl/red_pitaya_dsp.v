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
/***********************************************************
DSP Module

This module hosts the different submodules used for digital signal processing.

1)
The first half of this file manages the connection between different submodules by
implementing a bus between them: 

connecting the signal_arrivingFrom of submodule i to the signal_goingTo of submodule j is 
done by setting the register 
switchSignal[j] <= i;
 
Similarly, a second, possibly different output is allowed for each module: signal_arrivingFrom.
This output is added to the analog output 1 and/or 2 depending on the value
of the register output_direct_selectDAC: setting the first bit enables output1, the 2nd bit enables output 2.
Example:
output_direct_selectDAC[i] = s_OUT2;

By default, all routing is done as in the original redpitaya. 

2) 
The second half of this file defines the different submodules. For custom submodules, 
a good point to start is red_pitaya_pid_block.v. 

Submodule i is assigned the address space
0x40400000 + i*0x10000 + (0x0000 to 0xFFFF), that is 2**16 bytes.

Addresses 0x40[1zzz]z00zz where z is an arbitrary hex character are reserved to manage 
the input/output routing of the submodule and are not forwarded, and therefore 
should not be used.  
*************************************************************/


(* use_dsp = "yes" *) module red_pitaya_dsp(
   // signals
   input                 clk_i           ,  //!< processing clock
   input                 rstn_i          ,  //!< processing reset - active low
   input      [ 14-1: 0] dat_a_i         ,  //!< input data CHA
   input      [ 14-1: 0] dat_b_i         ,  //!< input data CHB
   output     [ 14-1: 0] dat_a_o         ,  //!< output data CHA
   output     [ 14-1: 0] dat_b_o         ,  //!< output data CHB

   output     [ 14-1: 0] scope1_o,
   output     [ 14-1: 0] scope2_o,
   input      [ 14-1: 0] asg1_i,
   input      [ 14-1: 0] asg2_i,
   output     [ 14-1: 0] asg_a_amp_o,
   output     [ 14-1: 0] asg_b_amp_o,
   input      [ 14-1: 0] asg1phase_i,

   // pwm and digital pins outputs
   output     [ 14-1: 0] pwm0,
   output     [ 14-1: 0] pwm1,
   output     [ 14-1: 0] extDigital0,
   output     [ 14-1: 0] extDigital1,

   // input triggers
   input                ramp_trigger,
   input                generic_module_trigger,
   // trigger outputs for the scope
   output                trig_o,   // output from trigger dsp module

   // system bus
   input      [ 32-1: 0] sys_addr        ,  //!< bus address
   input      [ 32-1: 0] sys_wdata       ,  //!< bus write data
   input      [  4-1: 0] sys_sel         ,  //!< bus write byte select
   input                 sys_wen         ,  //!< bus write enable
   input                 sys_ren         ,  //!< bus read enable
   output reg [ 32-1: 0] sys_rdata   ,  //!< bus read data
   output reg            sys_err         ,  //!< bus error indicator
   output reg            sys_ack         ,   //!< bus acknowledge signal

   input      [ 14 -1:0] peak_a,
   input      [ 14 -1:0] peak_a_index,
   input                 peak_a_valid,
   input      [ 14 -1:0] peak_b,
   input      [ 14 -1:0] peak_b_index,
   input                 peak_b_valid,
   input      [ 14 -1:0] peak_c,
   input      [ 14 -1:0] peak_c_index,
   input                 peak_c_valid
);



///////////////////////////////////// /*			input					output						*/
///////////////////////////////////// localparam	PID0		= 0			/*modules use both input and output*/;
///////////////////////////////////// localparam	PID1		= 1			/*modules use both input and output*/;
///////////////////////////////////// localparam	PID2		= 2			/*modules use both input and output*/;
///////////////////////////////////// localparam	TRIG		= 3			/*modules use both input and output*/;
///////////////////////////////////// localparam	LIN			= 5			/*modules use both input and output*/;
///////////////////////////////////// localparam	RAMP		= 6			/*modules use both input and output*/;
///////////////////////////////////// localparam	ASG0		= 7,		SCOPE1 					= 7;
///////////////////////////////////// localparam	ASG1		= 8,		SCOPE2 					= 8;
///////////////////////////////////// localparam	IN1		= 9,		PWM0					= 9;
///////////////////////////////////// localparam	IN2		= 10,		PWM1					= 10;
///////////////////////////////////// localparam	OUT1		= 11,		DIG0				= 11;
///////////////////////////////////// localparam	OUT2		= 12,		DIG1				= 12;
///////////////////////////////////// localparam	PEAK1		= 13,		ASG_AMPL0				= 13;
///////////////////////////////////// localparam	PEAK2		= 14,		ASG_AMPL1				= 14;
///////////////////////////////////// localparam	PEAK3		= 15,		PID0_SETPOINT_SIGNAL	= 15;
///////////////////////////////////// localparam	PEAK_IDX1	= 16,		PID1_SETPOINT_SIGNAL	= 16;
///////////////////////////////////// localparam	PEAK_IDX2	= 17,		PID2_SETPOINT_SIGNAL	= 17;
///////////////////////////////////// localparam	PEAK_IDX3	= 18 									;
///////////////////////////////////// localparam nOfDSP_outputs = 19, 		nOfDSP_inputs = 18;
///////////////////////////////////// localparam MODULES = 7;
///////////////////////////////////// localparam nOfDSP_directOutputs = 7;//directOutputs are the outputs tha can be outputed to the DACs

/*			arrivingFrom						goingTo						*/
/*§§#§§*/
localparam	PID0					= 0;			/*modules use both input and outpt ;*/
localparam	PID1					= 1;			/*modules use both input and outpt ;*/
localparam	PID2					= 2;			/*modules use both input and outpt ;*/
localparam	LIN						= 3;			/*modules use both input and outpt ;*/
localparam	RAMP					= 4;			/*modules use both input and outpt ;*/
localparam	ASG0					= 5;		localparam	SCOPE1 					= 5;
localparam	ASG1					= 6;		localparam	SCOPE2 					= 6;
localparam	IN1						= 7;		localparam	DIG0					= 7;
localparam	IN2						= 8;		localparam	DIG1					= 8;
localparam	OUT1					= 9;		localparam	ASG_AMPL0				= 9;
localparam	OUT2					= 10;		localparam	ASG_AMPL1				= 10;
										/*;*/	localparam	PID0_SETPOINT_SIGNAL	= 11;
										/*;*/	localparam	PID1_SETPOINT_SIGNAL	= 12;
										/*;*/	localparam	PID2_SETPOINT_SIGNAL	= 13;
/*§§#§§*/
localparam nOfDSP_outputs = 14, 		nOfDSP_inputs = 11;
localparam MODULES = 7;
localparam nOfDSP_directOutputs = 7;//directOutputs are the outputs tha can be outputed to the DACs

localparam LOG_INPUT_MODULES = $clog2(nOfDSP_inputs);
localparam LOG_OUTPUT_MODULES = $clog2(nOfDSP_outputs);
localparam LOG_DIRECT_OUTPUT_MODULES = $clog2(nOfDSP_directOutputs);

localparam NONE = 2**LOG_INPUT_MODULES-1; //code for no module; only used to switch off PWM outputs

initial begin
   if (LOG_OUTPUT_MODULES > 4)begin
        $error("LOG_OUTPUT_MODULES is too high, the current memory architecture does not allow for a number higher than 4. you would need to change the memory structure");
   end
   if(NONE <= nOfDSP_outputs)begin
        $error("nOfDSP_outputs is too high, there's no space for index NONE");
   end
end


//output states
localparam s_BOTH = 2'b11;
localparam s_OUT1 = 2'b01;
localparam s_OUT2 = 2'b10;
localparam s_OFF  = 2'b00;


// the selected input signal of each module: modules and extramodules have inputs
// extraoutputs are treated like extramodules that do not provide their own signal_arrivingFrom
wire [14-1:0] signal_goingTo [nOfDSP_outputs -1:0];
// the selected input signal NUMBER of each module
reg [LOG_OUTPUT_MODULES-1:0] switchSignal [nOfDSP_outputs -1:0];

// the output of each module for internal routing, including 'virtual outputs' for the EXTRAINPUTS
wire [14-1:0] signal_arrivingFrom [nOfDSP_inputs-1+1:0];
wire [nOfDSP_inputs-1+1:0] isValid_arrivingFrom;

// the output of each module that is added to the chosen DAC
reg [2-1:0] output_direct_selectDAC [nOfDSP_directOutputs-1:0]; 

// syncronization register to trigger simultaneous action of different dsp modules
//it is usually used as a enable flag (each module just looks at its own sync bit), so I also added the possibility of disabling it with an external trigger
reg [MODULES-1:0] sync_fromMemory;
reg [MODULES-1:0] sync_alsoUseGenericTrigger;
wire [MODULES-1:0] sync = sync_fromMemory & (~sync_alsoUseGenericTrigger | {MODULES{generic_module_trigger}});//disables module[i] when sync_fromMemory[i] == 0 or (if sync_alsoUseGenericTrigger == 1) generic_module_trigger == 0
//todo add isValid_arrivingFrom[switchSignal[j]] to the formula for sync

// bus read data of individual modules (only needed for 'real' modules)
wire [ 32-1: 0] module_rdata [MODULES-1:0];  
wire            module_ack   [MODULES-1:0];

//connect scope
assign scope1_o = signal_goingTo[SCOPE1];
assign scope2_o = signal_goingTo[SCOPE2];
assign asg_a_amp_o = signal_goingTo[ASG_AMPL0];
assign asg_b_amp_o = signal_goingTo[ASG_AMPL1];
assign extDigital0 = signal_goingTo[DIG0];
assign extDigital1 = signal_goingTo[DIG1];

//connect asg output
assign signal_arrivingFrom[ASG0] = asg1_i;
assign signal_arrivingFrom[ASG1] = asg2_i;

//connect dac/adc to internal signals
assign signal_arrivingFrom[IN1] = dat_a_i;
assign signal_arrivingFrom[IN2] = dat_b_i;
assign signal_arrivingFrom[OUT1] = dat_a_o;
assign signal_arrivingFrom[OUT2] = dat_b_o;
// assign signal_arrivingFrom[PEAK1] = peak_a;
// assign signal_arrivingFrom[PEAK2] = peak_b;
// assign signal_arrivingFrom[PEAK3] = peak_c;
// assign signal_arrivingFrom[PEAK_IDX1] = {~peak_a_index[13], peak_a_index[12:0]};//the index is a positive 14bit value, let's shift it to a signed value (0 becomes the lowest negative value: 0x2000 = -8192, 0x3FFF becomes 0x1FF = +8191)
// assign signal_arrivingFrom[PEAK_IDX2] = {~peak_b_index[13], peak_b_index[12:0]};
// assign signal_arrivingFrom[PEAK_IDX3] = {~peak_c_index[13], peak_c_index[12:0]};
assign isValid_arrivingFrom = -1;

wire  signed [   14+LOG_DIRECT_OUTPUT_MODULES -1: 0] sum1; 
wire  signed [   14+LOG_DIRECT_OUTPUT_MODULES -1: 0] sum2; 

wire dac_a_saturated; //high when dac_a is saturated
wire dac_b_saturated; //high when dac_b is saturated

integer i, y;
genvar j;

//select inputs
generate 
   for (j = 0; j < nOfDSP_outputs; j = j+1) begin
        assign signal_goingTo[j] = (switchSignal[j]==NONE) ? 14'b0 : signal_arrivingFrom[switchSignal[j]];
   end
endgenerate

//sum together the direct outputs
wire  signed [(nOfDSP_directOutputs)*14 -1: 0] signalToSum1; 
wire  signed [(nOfDSP_directOutputs)*14 -1: 0] signalToSum2; 

generate
  //first, put all the signals to be added at the start of signalToSum
  for (j=0;j<nOfDSP_directOutputs;j=j+1) begin
     assign signalToSum1[(j+1)*14 -1-:14] = output_direct_selectDAC[j]&s_OUT1 ? signal_arrivingFrom[j] : 0;//{{LOG_OUTPUT_MODULES{signal_arrivingFrom[j][14-1]}},signal_arrivingFrom[j]} : {14+LOG_OUTPUT_MODULES{1'b0}};
     assign signalToSum2[(j+1)*14 -1-:14] = output_direct_selectDAC[j]&s_OUT2 ? signal_arrivingFrom[j] : 0;//{{LOG_OUTPUT_MODULES{signal_arrivingFrom[j][14-1]}},signal_arrivingFrom[j]} : {14+LOG_OUTPUT_MODULES{1'b0}};
  end
endgenerate

clockedTreeSum#(
   .dataSize   (14),
   .nOfInputs  (nOfDSP_directOutputs)
) cts[0:1](
   .clk        (clk_i),
   .reset      (!rstn_i),
   .ins        ({signalToSum1, signalToSum2}),
   .out        ({sum1, sum2})
);

//saturation of outputs
red_pitaya_saturate #(
    .BITS_IN (14+LOG_DIRECT_OUTPUT_MODULES), 
    .SHIFT(0), 
    .BITS_OUT(14)
    ) dac_saturate [1:0] (
   .input_i({sum2,sum1}),
   .output_o({dat_b_o,dat_a_o}),
   .overflow ({dat_b_saturated,dac_a_saturated})
   );   

//  System bus connection
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      //default settings for backwards compatibility with original code
      for(i=0;i<nOfDSP_outputs;i=i+1)begin
      	switchSignal [i] <= IN1;
      end
      
      for(i=0;i<nOfDSP_inputs;i=i+1)begin
      	output_direct_selectDAC [i] <= s_OFF;
      end
      
      
      sync_fromMemory <= {MODULES{1'b1}} ;  // all modules on by default
      sync_alsoUseGenericTrigger <= 0;
   end
   else begin
      if (sys_wen) begin
         if (sys_addr[16-1:0]==16'h00)     switchSignal[sys_addr[16+LOG_OUTPUT_MODULES-1:16]] <= sys_wdata[LOG_INPUT_MODULES -1:0];
         if (sys_addr[16-1:0]==16'h04)    { sync_alsoUseGenericTrigger[sys_addr[16+LOG_OUTPUT_MODULES-1:16]], output_direct_selectDAC[sys_addr[16+LOG_OUTPUT_MODULES-1:16]]} <= sys_wdata;
         if (sys_addr[16-1:0]==16'h0C)                                               sync_fromMemory <= sys_wdata[MODULES -1:0];
      end
   end
end

wire sys_en;
assign sys_en = sys_wen | sys_ren;
always @(posedge clk_i)
if (rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;
   casez (sys_addr[16-1:0])
      20'h00 : begin sys_ack <= sys_en;          sys_rdata <= {{32- LOG_INPUT_MODULES{1'b0}},switchSignal[sys_addr[16+LOG_OUTPUT_MODULES-1:16]]}; end 
      20'h04 : begin sys_ack <= sys_en;          sys_rdata <= {sync_alsoUseGenericTrigger[sys_addr[16+LOG_OUTPUT_MODULES-1:16]], output_direct_selectDAC[sys_addr[16+LOG_OUTPUT_MODULES-1:16]]}; end
      20'h08 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 2{1'b0}},dat_b_saturated,dac_a_saturated}; end
      20'h0C : begin sys_ack <= sys_en;          sys_rdata <= {{32-MODULES{1'b0}},sync_fromMemory} ; end
      20'h10 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 14{1'b0}},signal_arrivingFrom[sys_addr[16+LOG_OUTPUT_MODULES-1:16]]} ; end
      default : begin sys_ack <= module_ack[sys_addr[16+LOG_OUTPUT_MODULES-1:16]];    sys_rdata <=  module_rdata[sys_addr[16+LOG_OUTPUT_MODULES-1:16]]  ; end
   endcase
end


/**********************************************
 MODULE DEFINITIONS
 *********************************************/

//PID

// wire [14-1:0] diff_input_signal [3-1:0];
// wire [14-1:0] diff_output_signal [3-1:0];
// //assign diff_input_signal[0] = signal_goingTo[1]; // difference input of PID0 is PID1
// //assign diff_input_signal[1] = signal_goingTo[0]; // difference input of PID1 is PID0
// assign diff_input_signal[0] = diff_output_signal[1]; // difference input of PID0 is PID1
// assign diff_input_signal[1] = diff_output_signal[0]; // difference input of PID1 is PID0
// assign diff_input_signal[2] = {14{1'b0}};      // difference input of PID2 is zero

generate for (j = PID0; j < LIN; j = j+1) begin
   red_pitaya_pid_block i_pid (
     // data
     .clk_i        (  clk_i          ),  // clock
     .rstn_i       (  rstn_i         ),  // reset - active low
     .sync_i       (  sync[j] & isValid_arrivingFrom[switchSignal[j]] ),  // syncronization of different dsp modules
     .dat_i        (  signal_goingTo [j] ),  // input data
     .dat_o        (  signal_arrivingFrom[j]),  // output data
     .setpoint_i   (  signal_goingTo[PID0_SETPOINT_SIGNAL + j]),  // output data
    // .diff_dat_i   (  diff_input_signal[j] ),  // input data for differential mode
    // .diff_dat_o   (  diff_output_signal[j] ),  // output data for differential mode

    //communincation with PS
    .addr ( sys_addr[16-1:0] ),
    .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
    .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
    .ack  ( module_ack[j] ),
    .rdata (module_rdata[j]),
     .wdata (sys_wdata)
   );
end
endgenerate

// segmented function, for linearizations
// generate 
// 	for (j = LIN; j < RAMP; j = j+1) begin

//     segmentedFunction#(
//         .nOfEdges          (8),
//         .totalBits_IO      (14),
//         .fracBits_IO       (0),
//         .totalBits_m       (20),
//         .fracBits_m        (14),
//         .areSignalsSigned  (1)
//     )sf(
//         .clk           (clk_i),
//         .reset         (!rstn_i),
//         .in            (signal_goingTo [j]),
//         .out           (signal_arrivingFrom[j]),
        
//         //communincation with PS
//         .addr ( sys_addr[16-1:0] ),
//         .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
//         .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
//         .ack  ( module_ack[j] ),
//         .rdata (module_rdata[j]),
//         .wdata (sys_wdata)
//     );
   
// end endgenerate

// sequence of ramp functions, for arbitrary functions with strict timings (useful to make sequences of ramps with very different time frames, if you tried to do this with the normal asg, the very fast ramps would not be that precise)
// generate for (j = RAMP; j < MODULES; j = j+1) begin

//     ramp#(
//         .nOfRamps                   (8),
//         .data_size                  (14),
//         .time_size                  (24),
//         .inhibitionTimeForTrigger   (500)//4e-6s
//     )rmp(
//         .clk      (clk_i),
//         .reset    (!rstn_i),
//         .trigger  (ramp_trigger),
        
//         .out           (signal_arrivingFrom[j]),
//         //communincation with PS
//         .addr ( sys_addr[16-1:0] ),
//         .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
//         .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
//         .ack  ( module_ack[j] ),
//         .rdata (module_rdata[j]),
//         .wdata (sys_wdata)
//     );
   
// end endgenerate

endmodule


/*

add wave -position insertpoint sim:/red_pitaya_dsp/*
force -freeze sim:/red_pitaya_dsp/clk_i 1 0, 0 {50 ps} -r 100
force -freeze sim:/red_pitaya_dsp/rstn_i z0 0
force -freeze sim:/red_pitaya_dsp/dat_a_i 1234 0
noforce sim:/red_pitaya_dsp/dat_b_i
force -freeze sim:/red_pitaya_dsp/dat_b_i 5678 0
force -freeze sim:/red_pitaya_dsp/asg1_i aabb 0
force -freeze sim:/red_pitaya_dsp/asg2_i ccdd 0
force -freeze sim:/red_pitaya_dsp/asg_a_amp_o 7000 0
force -freeze sim:/red_pitaya_dsp/asg_b_amp_o 1000 0
noforce sim:/red_pitaya_dsp/asg_a_amp_o
noforce sim:/red_pitaya_dsp/asg_b_amp_o
force -freeze sim:/red_pitaya_dsp/asg1phase_i 0 0
force -freeze sim:/red_pitaya_dsp/ramp_trigger 0 0
force -freeze sim:/red_pitaya_dsp/generic_module_trigger 0 0
force -freeze sim:/red_pitaya_dsp/sys_addr 0 0
force -freeze sim:/red_pitaya_dsp/sys_wdata 0 0
force -freeze sim:/red_pitaya_dsp/sys_sel z0 0
force -freeze sim:/red_pitaya_dsp/sys_wen z0 0
force -freeze sim:/red_pitaya_dsp/sys_ren z0 0
force -freeze sim:/red_pitaya_dsp/peak_a 0 0
force -freeze sim:/red_pitaya_dsp/peak_a_index 0 0
force -freeze sim:/red_pitaya_dsp/peak_a_valid z0 0
force -freeze sim:/red_pitaya_dsp/peak_b 0000 0
force -freeze sim:/red_pitaya_dsp/peak_b_index 0 0
force -freeze sim:/red_pitaya_dsp/peak_b_valid z0 0
force -freeze sim:/red_pitaya_dsp/peak_c zzzz000000 0
force -freeze sim:/red_pitaya_dsp/peak_c_index zzzz00000000 0
force -freeze sim:/red_pitaya_dsp/peak_c_valid z0 0
run
run
run
force -freeze sim:/red_pitaya_dsp/rstn_i 01 0
run
run
run
run
run
run



*/