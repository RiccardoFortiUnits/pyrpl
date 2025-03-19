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

connecting the output_signal of submodule i to the input_signal of submodule j is 
done by setting the register 
input_select[j] <= i;
 
Similarly, a second, possibly different output is allowed for each module: output_direct.
This output is added to the analog output 1 and/or 2 depending on the value
of the register output_select: setting the first bit enables output1, the 2nd bit enables output 2.
Example:
output_select[i] = OUT2;

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


(* use_dsp = "yes" *) module red_pitaya_dsp #(
   parameter MODULES = 11
)
(
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

localparam EXTRAMODULES = 2; //need two extra control registers for scope/asg
localparam EXTRAINPUTS = 10; //four extra input signals for dac(2)/adc(2), plus ADC peaks and peak positions
localparam EXTRAOUTPUTS = 6; //two extra output signals for pwm channels, plus 2 signals for the external digital pins and asg_amplitude controllers
localparam LOG_INPUT_MODULES = $clog2(EXTRAINPUTS+EXTRAMODULES+MODULES);
localparam LOG_OUTPUT_MODULES = $clog2(EXTRAMODULES+MODULES);//the EXTRAOUTPUTS cannot be put on the DAC output, so we don't consider it. 
                                                               //This value is used in combination with output_direct and output_select
localparam LOG_OUTPUT_DIRECT_MODULES = $clog2(EXTRAMODULES+MODULES+EXTRAOUTPUTS);//the EXTRAOUTPUTS cannot be put on the DAC output, so we don't consider it. 

// initial begin
//    if (LOG_OUTPUT_DIRECT_MODULES > 4)begin
//         $fatal("LOG_OUTPUT_DIRECT_MODULES is too high, the current memory architecture does not allow for a number higher than 4. you would need to change the memory structure");
//    end
// end

//Module numbers
localparam PID0  = 'd0;  //formerly PID11
localparam PID1  = 'd1;  //formerly PID12: input2->output1
localparam PID2  = 'd2;  //formerly PID21: input1->output2
localparam TRIG  = 'd3;  //formerly PID3
localparam IIR   = 'd4;  //IIR filter to connect in series to PID module
localparam IQ0   = 'd5;  //for PDH signal generation
localparam IQ1   = 'd6;  //for NA functionality
localparam IQ2   = 'd7;  //for PFD error signal
localparam IQ2_1 = 'd8;  //for second output of IQ2
localparam LIN   = 'd9;  //linearizer
localparam RAMP  = 'd10; //triggered ramp (does not use an input)
//localparam CUSTOM1 = 'd8; //available slots
localparam NONE = 2**LOG_INPUT_MODULES-1; //code for no module; only used to switch off PWM outputs

//EXTRAMODULE numbers
localparam ASG1   = MODULES; //scope and asg can have the same number
localparam ASG2   = MODULES+1; //because one only has outputs, the other only inputs
localparam SCOPE1 = MODULES;
localparam SCOPE2 = MODULES+1;
//EXTRAINPUT numbers
localparam ADC1  = MODULES+2;
localparam ADC2  = MODULES+3;
localparam DAC1  = MODULES+4;
localparam DAC2  = MODULES+5;
localparam PEAK1  = MODULES+6;
localparam PEAK2  = MODULES+7;
localparam PEAK3  = MODULES+8;
localparam PEAK_IDX1  = MODULES+9;
localparam PEAK_IDX2  = MODULES+10;
localparam PEAK_IDX3  = MODULES+11;
//EXTRAOUTPUT numbers
localparam PWM0  = MODULES+2; //they can have the same indexes as the extra inputs
localparam PWM1  = MODULES+3;
localparam EXT_DIG0  = MODULES+4;
localparam EXT_DIG1  = MODULES+5;
localparam ASG_AMP1 = MODULES+6;
localparam ASG_AMP2 = MODULES+7;

//output states
localparam BOTH = 2'b11;
localparam OUT1 = 2'b01;
localparam OUT2 = 2'b10;
localparam OFF  = 2'b00;


// the selected input signal of each module: modules and extramodules have inputs
// extraoutputs are treated like extramodules that do not provide their own output_signal
wire [14-1:0] input_signal [MODULES+EXTRAMODULES+EXTRAOUTPUTS-1:0];
// the selected input signal NUMBER of each module
reg [LOG_INPUT_MODULES-1:0] input_select [MODULES+EXTRAMODULES+EXTRAOUTPUTS-1:0];

// the output of each module for internal routing, including 'virtual outputs' for the EXTRAINPUTS
wire [14-1:0] output_signal [MODULES+EXTRAMODULES+EXTRAINPUTS-1+1:0];
wire [MODULES+EXTRAMODULES+EXTRAINPUTS-1+1:0] output_valid;

// the output of each module that is added to the chosen DAC
wire [14-1:0] output_direct [MODULES+EXTRAMODULES-1:0];
// the channel that the module's output_direct is added to (bit0: DAC1, bit 1: DAC2) 
reg [2-1:0] output_select [MODULES+EXTRAMODULES-1:0]; 

// syncronization register to trigger simultaneous action of different dsp modules
//it is usually used as a enable flag (each module just looks at its own sync bit), so I also added the possibility of disabling it with an external trigger
reg [MODULES-1:0] sync_fromMemory;
reg [MODULES-1:0] sync_alsoUseGenericTrigger;
wire [MODULES-1:0] sync = sync_fromMemory & (~sync_alsoUseGenericTrigger | {MODULES{generic_module_trigger}});//disables module[i] when sync_fromMemory[i] == 0 or (if sync_alsoUseGenericTrigger == 1) generic_module_trigger == 0
//todo add output_valid[input_select[j]] to the formula for sync

// bus read data of individual modules (only needed for 'real' modules)
wire [ 32-1: 0] module_rdata [MODULES-1:0];  
wire            module_ack   [MODULES-1:0];

//connect scope
assign scope1_o = input_signal[SCOPE1];
assign scope2_o = input_signal[SCOPE2];

//connect asg output
assign output_signal[ASG1] = asg1_i;
assign output_signal[ASG2] = asg2_i;
assign output_direct[ASG1] = asg1_i;
assign output_direct[ASG2] = asg2_i;

//connect dac/adc to internal signals
assign output_signal[ADC1] = dat_a_i;
assign output_signal[ADC2] = dat_b_i;
assign output_signal[DAC1] = dat_a_o;
assign output_signal[DAC2] = dat_b_o;
assign output_signal[PEAK1] = peak_a;
assign output_signal[PEAK2] = peak_b;
assign output_signal[PEAK3] = peak_c;
assign output_signal[PEAK_IDX1] = {~peak_a_index[13], peak_a_index[12:0]};//the index is a positive 14bit value, let's shift it to a signed value (0 becomes the lowest negative value: 0x2000 = -8192, 0x3FFF becomes 0x1FF = +8191)
assign output_signal[PEAK_IDX2] = {~peak_b_index[13], peak_b_index[12:0]};
assign output_signal[PEAK_IDX3] = {~peak_c_index[13], peak_c_index[12:0]};
assign output_valid = {peak_c_valid, peak_b_valid, peak_a_valid, peak_c_valid, peak_b_valid, peak_a_valid, {PEAK1{1'b1}}};// all inputs are always valid, except for the peak signals

//connect pwm and external digital pins to internal signals
assign pwm0 = (input_select[PWM0] == NONE) ? 14'h0 : output_signal[input_select[PWM0]];
assign pwm1 = (input_select[PWM1] == NONE) ? 14'h0 : output_signal[input_select[PWM1]];
assign extDigital0 = (input_select[EXT_DIG0] == NONE) ? 14'h0 : output_signal[input_select[EXT_DIG0]];
assign extDigital1 = (input_select[EXT_DIG1] == NONE) ? 14'h0 : output_signal[input_select[EXT_DIG1]];
assign asg_a_amp_o = (input_select[ASG_AMP1] == NONE) ? 14'h0 : output_signal[input_select[ASG_AMP1]];
assign asg_b_amp_o = (input_select[ASG_AMP2] == NONE) ? 14'h0 : output_signal[input_select[ASG_AMP2]];

wire  signed [   14+LOG_OUTPUT_MODULES-1: 0] sum1; 
wire  signed [   14+LOG_OUTPUT_MODULES-1: 0] sum2; 

wire dac_a_saturated; //high when dac_a is saturated
wire dac_b_saturated; //high when dac_b is saturated

integer i, y;
genvar j;

//select inputs
generate 
   for (j = 0; j < MODULES+EXTRAMODULES; j = j+1) begin
        assign input_signal[j] = (input_select[j]==NONE) ? 14'b0 : output_signal[input_select[j]];
   end
endgenerate

//sum together the direct outputs
wire  signed [(MODULES+EXTRAMODULES)*14 -1: 0] signalToSum1; 
wire  signed [(MODULES+EXTRAMODULES)*14 -1: 0] signalToSum2; 

generate
  //first, put all the signals to be added at the start of signalToSum
  for (j=0;j<MODULES+EXTRAMODULES;j=j+1) begin
     assign signalToSum1[(j+1)*14 -1-:14] = output_select[j]&OUT1 ? {{LOG_OUTPUT_MODULES{output_direct[j][14-1]}},output_direct[j]} : {14+LOG_OUTPUT_MODULES{1'b0}};
     assign signalToSum2[(j+1)*14 -1-:14] = output_select[j]&OUT2 ? {{LOG_OUTPUT_MODULES{output_direct[j][14-1]}},output_direct[j]} : {14+LOG_OUTPUT_MODULES{1'b0}};
  end
endgenerate

clockedTreeSum#(
   .dataSize   (14),
   .nOfInputs  (MODULES+EXTRAMODULES)
) cts[0:1](
   .clk        (clk_i),
   .reset      (!rstn_i),
   .ins        ({signalToSum1, signalToSum2}),
   .out        ({sum1, sum2})
);

//saturation of outputs
red_pitaya_saturate #(
    .BITS_IN (14+LOG_OUTPUT_MODULES), 
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
      input_select [PID0] <= ADC1;
      output_select[PID0] <= OFF;
      
      input_select [PID1] <= ADC1;
      output_select[PID1] <= OFF;

      input_select [PID2] <= ADC1;
      output_select[PID2] <= OFF;

      input_select [TRIG] <= ADC1;
      output_select[TRIG] <= OFF;

      input_select [IIR] <= ADC1;
      output_select[IIR] <= OFF;

      input_select [IQ0] <= ADC1;
      output_select[IQ0] <= OFF;
      
      input_select [IQ1] <= ADC1;
      output_select[IQ1] <= OFF;

      input_select [IQ2] <= ADC1;
      output_select[IQ2] <= OFF;

      input_select [SCOPE1] <= ADC1;
      input_select [SCOPE2] <= ADC2;
      output_select[ASG1] <= OFF;
      output_select[ASG2] <= OFF;
      
      input_select [PWM0] <= NONE;
      input_select [PWM1] <= NONE;
      
      sync_fromMemory <= {MODULES{1'b1}} ;  // all modules on by default
      sync_alsoUseGenericTrigger <= 0;
   end
   else begin
      if (sys_wen) begin
         if (sys_addr[16-1:0]==16'h00)     input_select[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]] <= sys_wdata[LOG_INPUT_MODULES -1:0];
         if (sys_addr[16-1:0]==16'h04)    { sync_alsoUseGenericTrigger[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]], output_select[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]]} <= sys_wdata;
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
      20'h00 : begin sys_ack <= sys_en;          sys_rdata <= {{32- LOG_INPUT_MODULES{1'b0}},input_select[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]]}; end 
      20'h04 : begin sys_ack <= sys_en;          sys_rdata <= {sync_alsoUseGenericTrigger[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]], output_select[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]]}; end
      20'h08 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 2{1'b0}},dat_b_saturated,dac_a_saturated}; end
      20'h0C : begin sys_ack <= sys_en;          sys_rdata <= {{32-MODULES{1'b0}},sync_fromMemory} ; end
      20'h10 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 14{1'b0}},output_signal[sys_addr[16+LOG_OUTPUT_DIRECT_MODULES-1:16]]} ; end
      default : begin sys_ack <= module_ack[sys_addr[16+LOG_OUTPUT_MODULES-1:16]];    sys_rdata <=  module_rdata[sys_addr[16+LOG_OUTPUT_MODULES-1:16]]  ; end
   endcase
end


/**********************************************
 MODULE DEFINITIONS
 *********************************************/

//PID

wire [14-1:0] diff_input_signal [3-1:0];
wire [14-1:0] diff_output_signal [3-1:0];
//assign diff_input_signal[0] = input_signal[1]; // difference input of PID0 is PID1
//assign diff_input_signal[1] = input_signal[0]; // difference input of PID1 is PID0
assign diff_input_signal[0] = diff_output_signal[1]; // difference input of PID0 is PID1
assign diff_input_signal[1] = diff_output_signal[0]; // difference input of PID1 is PID0
assign diff_input_signal[2] = {14{1'b0}};      // difference input of PID2 is zero

generate for (j = PID0; j < TRIG; j = j+1) begin
   red_pitaya_pid_block i_pid (
     // data
     .clk_i        (  clk_i          ),  // clock
     .rstn_i       (  rstn_i         ),  // reset - active low
     .sync_i       (  sync[j] & output_valid[input_select[j]] ),  // syncronization of different dsp modules
     .dat_i        (  input_signal [j] ),  // input data
     .dat_o        (  output_direct[j]),  // output data
    .diff_dat_i   (  diff_input_signal[j] ),  // input data for differential mode
    .diff_dat_o   (  diff_output_signal[j] ),  // output data for differential mode

    //communincation with PS
    .addr ( sys_addr[16-1:0] ),
    .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
    .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
    .ack  ( module_ack[j] ),
    .rdata (module_rdata[j]),
     .wdata (sys_wdata)
   );
   assign output_signal[j] = output_direct[j];
end
endgenerate

wire trig_signal;
//TRIG
generate for (j = TRIG; j < IIR; j = j+1) begin
   red_pitaya_trigger_block i_trigger (
     // data
     .clk_i        (  clk_i          ),  // clock
     .rstn_i       (  rstn_i         ),  // reset - active low
     .dat_i        (  input_signal [j] ),  // input data
     .dat_o        (  output_direct[j]),  // output data
     .signal_o     (  output_signal[j]),  // output signal
     .phase1_i     (  asg1phase_i ),  // phase input
     .trig_o       (  trig_signal ),

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
assign trig_o = trig_signal;

// // IIR module 
// generate for (j = IIR; j < IQ0; j = j+1) begin
//     red_pitaya_iir_block iir (
//         // data
//         .clk_i        (  clk_i          ),  // clock
//         .rstn_i       (  rstn_i         ),  // reset - active low
//         .dat_i        (  input_signal [j] ),  // input data
//         .dat_o        (  output_direct[j]),  // output data

//        //communincation with PS
//        .addr ( sys_addr[16-1:0] ),
//        .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
//        .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
//        .ack  ( module_ack[j] ),
//        .rdata (module_rdata[j]),
//         .wdata (sys_wdata)
//       );
//      assign output_signal[j] = output_direct[j];
// end endgenerate


//IQ modules
generate for (j = IQ0; j < IQ2; j = j+1) begin
    red_pitaya_iq_block 
      iq
      (
        // data
        .clk_i        (  clk_i          ),  // clock
        .rstn_i       (  rstn_i         ),  // reset - active low
         .sync_i       (  sync[j]        ),  // syncronization of different dsp modules
        .dat_i        (  input_signal [j] ),  // input data
        .dat_o        (  output_direct[j]),  // output data
       .signal_o     (  output_signal[j]),  // output signal

         // not using 2nd quadrature for most iq's: multipliers will be
         // synthesized away by Vivado
         //.signal2_o  (  output_signal[j*2]),  // output signal

       //communincation with PS
       .addr ( sys_addr[16-1:0] ),
       .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
       .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
       .ack  ( module_ack[j] ),
       .rdata (module_rdata[j]),
        .wdata (sys_wdata)
      );
end endgenerate

// IQ with two outputs
generate for (j = IQ2; j < LIN; j = j+2) begin
    red_pitaya_iq_block   #( .QUADRATUREFILTERSTAGES(4) )
      iq_2_outputs
      (
         // data
         .clk_i        (  clk_i          ),  // clock
         .rstn_i       (  rstn_i         ),  // reset - active low
         .sync_i       (  sync[j]        ),  // syncronization of different dsp modules
         .dat_i        (  input_signal [j] ),  // input data
         .dat_o        (  output_direct[j]),  // output data
         .signal_o     (  output_signal[j]),  // output signal
         .signal2_o    (  output_signal[j+1]),  // output signal 2

         //communincation with PS
         .addr ( sys_addr[16-1:0] ),
         .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
         .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
         .ack  ( module_ack[j] ),
         .rdata (module_rdata[j]),
         .wdata (sys_wdata)
      );
end endgenerate

// segmented function, for linearizations
// generate for (j = LIN; j < RAMP; j = j+1) begin

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
//         .in            (input_signal [j]),
//         .out           (output_signal[j]),
        
//         //communincation with PS
//         .addr ( sys_addr[16-1:0] ),
//         .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
//         .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
//         .ack  ( module_ack[j] ),
//         .rdata (module_rdata[j]),
//         .wdata (sys_wdata)
//     );
//    assign output_signal[j] = output_direct[j];
   
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
        
//         .out           (output_signal[j]),
//         //communincation with PS
//         .addr ( sys_addr[16-1:0] ),
//         .wen  ( sys_wen & (sys_addr[20-1:16]==j) ),
//         .ren  ( sys_ren & (sys_addr[20-1:16]==j) ),
//         .ack  ( module_ack[j] ),
//         .rdata (module_rdata[j]),
//         .wdata (sys_wdata)
//     );
//    assign output_signal[j] = output_direct[j];
   
// end endgenerate

endmodule
