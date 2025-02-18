/**
 * $Id: red_pitaya_hk.v 961 2014-01-21 11:40:39Z matej.oblak $
 *
 * @brief Red Pitaya house keeping.
 *
 * @Author Matej Oblak
 *
 * (c) Red Pitaya  http://www.redpitaya.com
 *
 * This part of code is written in Verilog hardware description language (HDL).
 * Please visit http://en.wikipedia.org/wiki/Verilog
 * for more details on the language used herein.
 */

/**
 * GENERAL DESCRIPTION:
 *
 * House keeping module takes care of system identification.
 *
 *
 * This module takes care of system identification via DNA readout at startup and
 * ID register which user can define at compile time.
 *
 * Beside that it is currently also used to test expansion connector and for
 * driving LEDs.
 * 
 */

(* use_dsp = "yes" *) module red_pitaya_hk #(
		parameter DWL = 8, // data width for LED
		parameter DWE = 8, // data width for extension
		parameter [57-1:0] DNA = 57'h0823456789ABCDE,
		parameter DWD = 14 // data width for dsp inputs
)(
	// system signals
	input                clk_i      ,  // clock
	input                rstn_i     ,  // reset - active low
	// LED
	output reg [DWL-1:0] led_o      ,  // LED output
	// global configuration
	output reg           digital_loop,
	// Expansion connector
	input      [DWE-1:0] exp_p_dat_i,  // exp. con. input data
	output     [DWE-1:0] exp_p_dat_o,  // exp. con. output data
	output reg [DWE-1:0] exp_p_dir_o,  // exp. con. 1-output enable
	output 				 asg_trigger,
	output 				 scope_trigger,
	output 	    		 ramp_trigger,
	output 	    		 generic_module_trigger,
	input      [DWE-1:0] exp_n_dat_i,  //
	output     [DWE-1:0] exp_n_dat_o,  //
	output reg [DWE-1:0] exp_n_dir_o,  //
	// inputs from dsp
	input	   [DWD -1:0] dsp_input0,
	input	   [DWD -1:0] dsp_input1,
	// System bus
	input      [ 32-1:0] sys_addr   ,  // bus address
	input      [ 32-1:0] sys_wdata  ,  // bus write data
	input      [  4-1:0] sys_sel    ,  // bus write byte select
	input                sys_wen    ,  // bus write enable
	input                sys_ren    ,  // bus read enable
	output reg [ 32-1:0] sys_rdata  ,  // bus read data
	output reg           sys_err    ,  // bus error indicator
	output reg           sys_ack       // bus acknowledge signal
);

localparam DLE = $clog2(DWE*2); // logarithm of DWE*2, equals to the size of a register pointing to one of the external pins
localparam DLD = $clog2(DWD*2); // logarithm of DWD*2, equals to the max size of a register pointing to a bit of the 2 dsp input registers


reg [DWE-1:0] exp_p_dat_o_reg, exp_n_dat_o_reg;


wire [DWE*2-1:0] allInputPins = {exp_p_dat_i, exp_n_dat_i};
wire [DWE*2-1:0] allMemoryPins = {exp_p_dat_o_reg, exp_n_dat_o_reg};
wire [DWD*2-1:0] allDspInputs = {dsp_input1, dsp_input0};

localparam  s_fromMemory 		= 0,
			s_fromOtherPin 		= 1,
			s_fromDsp 			= 2,
			s_fromFastSwitch 	= 3;
reg [DWE*2 -1:0] pinState_p, pinState_n;
wire [1:0] pinStates [DWE*2 -1:0];

reg  [DLE -1:0] otherPinSelectorBit_p [DWE -1:0], otherPinSelectorBit_n [DWE -1:0];
wire [DLE -1:0] otherPinSelectorBit [DWE*2 -1:0];

reg [DLD -1:0] dspSelectorBit_p [DWE -1:0], dspSelectorBit_n [DWE -1:0];
wire [DLD -1:0] dspSelectorBit [DWE*2 -1:0];

generate
	genvar gi;
	for(gi=0;gi<DWE;gi=gi+1)begin
		assign pinStates			[gi]     =			pinState_n				[gi*2	+ 2	  -1-:2  ];
		assign pinStates			[gi+DWE] =			pinState_p				[gi*2	+ 2	  -1-:2  ];
		assign otherPinSelectorBit	[gi]     =			otherPinSelectorBit_n	[gi];
		assign otherPinSelectorBit	[gi+DWE] =			otherPinSelectorBit_p	[gi];
		assign dspSelectorBit		[gi]     =			dspSelectorBit_n		[gi];
		assign dspSelectorBit		[gi+DWE] =			dspSelectorBit_p		[gi];
	end
endgenerate

wire [1:0] fastSwitchOutputs;
reg[7:0] nOfActivePeriods, nOfInactivePeriods, switchPhase;
reg[DLE -1:0] fastSwitch_triggerPin;

reg [DWE*2-1:0] allOutputPins;
assign {exp_p_dat_o, exp_n_dat_o} = allOutputPins;
integer i;
always @(posedge clk_i)
if (rstn_i == 1'b0) begin
	allOutputPins <= 0;
end else begin
	for(i=0;i<DWE*2;i=i+1)begin
		case (pinStates[i])
			s_fromMemory:		begin allOutputPins[i] <= allMemoryPins[i]; end
			s_fromOtherPin:		begin allOutputPins[i] <= allInputPins[otherPinSelectorBit[i]]; end
			s_fromDsp:			begin allOutputPins[i] <= allDspInputs[dspSelectorBit[i]]; end
			s_fromFastSwitch:	begin allOutputPins[i] <= i < DWE ? fastSwitchOutputs[1] : fastSwitchOutputs[0]; end
			default : /* default */;
		endcase
	end
end

doubleFastSwitcher_HalfStart#(
		.maxPeriods(255)
)fs(
		.clk(clk_i),
		.reset(!rstn_i),
		.trigger(allInputPins[fastSwitch_triggerPin]),
		.nOfPeriodsActive(nOfActivePeriods),
		.nOfPeriodsInactive(nOfInactivePeriods),
		.phase(switchPhase),
		.out1(fastSwitchOutputs[0]),
		.out2(fastSwitchOutputs[1])
);

//triggers for external modules
reg [DLE -1:0] ramp_triggerPin, asg_triggerPin, scope_triggerPin, generic_module_triggerPin;

assign asg_trigger = allInputPins[asg_triggerPin];
assign scope_trigger = allInputPins[scope_triggerPin];
assign ramp_trigger = allInputPins[ramp_triggerPin];
assign generic_module_trigger = allInputPins[generic_module_triggerPin];

//---------------------------------------------------------------------------------
//
//  Read device DNA

wire           dna_dout ;
reg            dna_clk  ;
reg            dna_read ;
reg            dna_shift;
reg  [ 9-1: 0] dna_cnt  ;
reg  [57-1: 0] dna_value;
reg            dna_done ;

always @(posedge clk_i)
if (rstn_i == 1'b0) begin
	dna_clk   <=  1'b0;
	dna_read  <=  1'b0;
	dna_shift <=  1'b0;
	dna_cnt   <=  9'd0;
	dna_value <= 57'd0;
	dna_done  <=  1'b0;
end else begin
	if (!dna_done)
		dna_cnt <= dna_cnt + 1'd1;

	dna_clk <= dna_cnt[2] ;
	dna_read  <= (dna_cnt < 9'd10);
	dna_shift <= (dna_cnt > 9'd18);

	if ((dna_cnt[2:0]==3'h0) && !dna_done)
		dna_value <= {dna_value[57-2:0], dna_dout};

	if (dna_cnt > 9'd465)
		dna_done <= 1'b1;
end

//// parameter specifies a sample 57-bit DNA value for simulation
//DNA_PORT #(.SIM_DNA_VALUE (DNA)) i_DNA (
//  .DOUT  ( dna_dout   ), // 1-bit output: DNA output data.
//  .CLK   ( dna_clk    ), // 1-bit input: Clock input.
//  .DIN   ( 1'b0       ), // 1-bit input: User data input pin.
//  .READ  ( dna_read   ), // 1-bit input: Active high load DNA, active low read input.
//  .SHIFT ( dna_shift  )  // 1-bit input: Active high shift enable input.
//);

//---------------------------------------------------------------------------------
//
//  Design identification

wire [32-1: 0] id_value;

assign id_value[31: 4] = 28'h0; // reserved
assign id_value[ 3: 0] =  4'h1; // board type   1 - release 1

//---------------------------------------------------------------------------------
//
//  System bus connection

always @(posedge clk_i)
if (rstn_i == 1'b0) begin
	led_o        <= {DWL{1'b0}};
	exp_p_dat_o_reg  <= {DWE{1'b0}};
	exp_p_dir_o  <= {DWE{1'b0}};
	exp_n_dat_o_reg  <= {DWE{1'b0}};
	exp_n_dir_o  <= {DWE{1'b0}};
	pinState_p <= 0;
	pinState_n <= 0;
	ramp_triggerPin <= 0;
	asg_triggerPin <= 0;
	scope_triggerPin <= 0;
	generic_module_triggerPin <= 0;
	
	for(i=0;i<DWE;i=i+1)begin
		otherPinSelectorBit_p[i] <= 0;
		otherPinSelectorBit_n[i] <= 0;
		dspSelectorBit_p[i] <= 0;
		dspSelectorBit_n[i] <= 0;
	end

	nOfActivePeriods <= 0;
	nOfInactivePeriods <= 0;
	fastSwitch_triggerPin <= 0;
	switchPhase <= 0;
end else if (sys_wen) begin
	if (sys_addr[19:0]==20'h0c)   digital_loop <= sys_wdata[0];

	if (sys_addr[19:0]==20'h10)   exp_p_dir_o  <= sys_wdata[DWE-1:0];
	if (sys_addr[19:0]==20'h14)   exp_n_dir_o  <= sys_wdata[DWE-1:0];
	if (sys_addr[19:0]==20'h18)   exp_p_dat_o_reg  <= sys_wdata[DWE-1:0];
	if (sys_addr[19:0]==20'h1C)   exp_n_dat_o_reg  <= sys_wdata[DWE-1:0];

	if (sys_addr[19:0]==20'h28)   {generic_module_triggerPin, ramp_triggerPin, asg_triggerPin, scope_triggerPin} <= sys_wdata;

	if (sys_addr[19:0]==20'h30)   led_o        <= sys_wdata[DWL-1:0];
	if (sys_addr[19:0]==20'h34)   {pinState_p} <= sys_wdata;
	if (sys_addr[19:0]==20'h38)   {pinState_n} <= sys_wdata;
	if (sys_addr[19:0]==20'h3c)   {fastSwitch_triggerPin, nOfInactivePeriods, nOfActivePeriods} <= sys_wdata;
	if (sys_addr[19:0]==20'h40)   {switchPhase} <= sys_wdata;
			
	if (sys_addr[19:0]==20'h50)  {dspSelectorBit_p[0], otherPinSelectorBit_p[0], dspSelectorBit_n[0], otherPinSelectorBit_n[0]} <= sys_wdata;
	if (sys_addr[19:0]==20'h54)  {dspSelectorBit_p[1], otherPinSelectorBit_p[1], dspSelectorBit_n[1], otherPinSelectorBit_n[1]} <= sys_wdata;
	if (sys_addr[19:0]==20'h58)  {dspSelectorBit_p[2], otherPinSelectorBit_p[2], dspSelectorBit_n[2], otherPinSelectorBit_n[2]} <= sys_wdata;
	if (sys_addr[19:0]==20'h5c)  {dspSelectorBit_p[3], otherPinSelectorBit_p[3], dspSelectorBit_n[3], otherPinSelectorBit_n[3]} <= sys_wdata;
	if (sys_addr[19:0]==20'h60)  {dspSelectorBit_p[4], otherPinSelectorBit_p[4], dspSelectorBit_n[4], otherPinSelectorBit_n[4]} <= sys_wdata;
	if (sys_addr[19:0]==20'h64)  {dspSelectorBit_p[5], otherPinSelectorBit_p[5], dspSelectorBit_n[5], otherPinSelectorBit_n[5]} <= sys_wdata;
	if (sys_addr[19:0]==20'h68)  {dspSelectorBit_p[6], otherPinSelectorBit_p[6], dspSelectorBit_n[6], otherPinSelectorBit_n[6]} <= sys_wdata;
	if (sys_addr[19:0]==20'h6c)  {dspSelectorBit_p[7], otherPinSelectorBit_p[7], dspSelectorBit_n[7], otherPinSelectorBit_n[7]} <= sys_wdata;
end

wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge clk_i)
if (rstn_i == 1'b0) begin
	sys_err <= 1'b0;
	sys_ack <= 1'b0;
end else begin
	sys_err <= 1'b0;

	casez (sys_addr[19:0])
		20'h00000: begin sys_ack <= sys_en;  sys_rdata <= {                id_value          }; end
		20'h00004: begin sys_ack <= sys_en;  sys_rdata <= {                dna_value[32-1: 0]}; end
		20'h00008: begin sys_ack <= sys_en;  sys_rdata <= {{64- 57{1'b0}}, dna_value[57-1:32]}; end
		20'h0000c: begin sys_ack <= sys_en;  sys_rdata <= {{32-  1{1'b0}}, digital_loop      }; end

		20'h00010: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWE{1'b0}}, exp_p_dir_o}       ; end
		20'h00014: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWE{1'b0}}, exp_n_dir_o}       ; end
		20'h00018: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWE{1'b0}}, exp_p_dat_o_reg}       ; end
		20'h0001C: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWE{1'b0}}, exp_n_dat_o_reg}       ; end
		20'h00020: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWE{1'b0}}, exp_p_dat_i}       ; end
		20'h00024: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWE{1'b0}}, exp_n_dat_i}       ; end

		20'h00028: begin sys_ack <= sys_en;  sys_rdata <= {generic_module_triggerPin, ramp_triggerPin, asg_triggerPin, scope_triggerPin}       ; end

		20'h00030: begin sys_ack <= sys_en;  sys_rdata <= {{32-DWL{1'b0}}, led_o}             ; end
		20'h00034: begin sys_ack <= sys_en;  sys_rdata <= {pinState_p}             ; end
		20'h00038: begin sys_ack <= sys_en;  sys_rdata <= {pinState_n}             ; end
		20'h0003c: begin sys_ack <= sys_en;  sys_rdata <= { fastSwitch_triggerPin, nOfInactivePeriods, nOfActivePeriods}             ; end
		20'h00040: begin sys_ack <= sys_en;  sys_rdata <= { switchPhase}             ; end

		20'h00050: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[0], otherPinSelectorBit_p[0], dspSelectorBit_n[0], otherPinSelectorBit_n[0]}             ; end
		20'h00054: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[1], otherPinSelectorBit_p[1], dspSelectorBit_n[1], otherPinSelectorBit_n[1]}             ; end
		20'h00058: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[2], otherPinSelectorBit_p[2], dspSelectorBit_n[2], otherPinSelectorBit_n[2]}             ; end
		20'h0005c: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[3], otherPinSelectorBit_p[3], dspSelectorBit_n[3], otherPinSelectorBit_n[3]}             ; end
		20'h00060: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[4], otherPinSelectorBit_p[4], dspSelectorBit_n[4], otherPinSelectorBit_n[4]}             ; end
		20'h00064: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[5], otherPinSelectorBit_p[5], dspSelectorBit_n[5], otherPinSelectorBit_n[5]}             ; end
		20'h00068: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[6], otherPinSelectorBit_p[6], dspSelectorBit_n[6], otherPinSelectorBit_n[6]}             ; end
		20'h0006c: begin sys_ack <= sys_en;  sys_rdata <= { dspSelectorBit_p[7], otherPinSelectorBit_p[7], dspSelectorBit_n[7], otherPinSelectorBit_n[7]}             ; end

			default: begin sys_ack <= sys_en;  sys_rdata <=  32'h0                              ; end
	endcase
end

endmodule
