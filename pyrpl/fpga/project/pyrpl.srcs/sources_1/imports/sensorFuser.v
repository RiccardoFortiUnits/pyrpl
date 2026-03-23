
/*
		sensorFuser:
	module that combines two input signals that work in different ranges. For example, if you have two sensors monitoring the same signal, 
	and the sensors have different sensitivities and working ranges. In that case, you would use a highly sensitive sensor (a) to measure signals 
	close to 0, and have a broader-range sensor (b) to measure signals far from 0, where the other sensor would saturate. With this module, you 
	can combine the signals coming from the two sensors to have a signal in the range [-1,1] where, for example, an output in the range [-1,0] 
	is used for small input values (section low, following only the signal of sensor a), while the range [0,1] indicates large input values 
	(section high, following sensor b). And you can even have an intermediate range, where you assume that both sensors are valid/not saturated, 
	and so a combination of the two sensor signals is used (section med).
	The ranges of the 3 sections (low, med, high) can be configured to give more range to a specific section (example, large low section, to have 
	more resolution on the small values, or small med section, if the signal is never expected to have "intermediate" values)

*/
module sensorFuser#(
	parameter signalSize = 14,
	parameter gainSize = 8,
	parameter gainFractionalSize = 6,
	parameter sectionSize = 4
) (
	input 						clk,
	input 						reset,
	input [signalSize -1:0]		a,
	input [signalSize -1:0]		b,
	output [signalSize -1:0]	out,
	
    // System bus
    input      [ 32-1:0] addr   ,  // bus address
    input      [ 32-1:0] wdata  ,  // bus write data
    input                wen    ,  // bus write enable
    input                ren    ,  // bus read enable
    output reg [ 32-1:0] rdata  ,  // bus read data
    output reg           err    ,  // bus error indicator
    output reg           ack       // bus acknowledge signal
);

/*			parameters			*/
reg [signalSize -1:0]		offset_a_low;
reg [signalSize -1:0]		offset_a_med;
reg [signalSize -1:0]		offset_b_med;
reg [signalSize -1:0]		offset_b_high;
reg [gainSize -1:0]			gain_a_low;
reg [gainSize -1:0]			gain_a_med;
reg [gainSize -1:0]			gain_b_med;
reg [gainSize -1:0]			gain_b_high;
reg [sectionSize -1:0] 		section_low;
reg [sectionSize -1:0] 		section_med;

//let's assume that the output is unsigned (value between 0 and 1), we'll make it signed at the end
reg [signalSize -1:0] uOut;
assign out = {!uOut[signalSize-1], uOut[signalSize-1 -1:0]};

wire [sectionSize -1:0] section_lowPlusMed = section_low + section_med;
wire [signalSize -1:0] section_low_resized, section_lowPlusMed_resized;
fixedPointShifter#(
	.inputBitSize	(sectionSize),
	.inputFracSize	(sectionSize),
	.outputBitSize	(signalSize),
	.outputFracSize	(signalSize),
	.isSigned		(0)
)shiftSections[1:0](
	.in				({section_low, section_lowPlusMed}),
	.out			({section_low_resized, section_lowPlusMed_resized})
);


/*	pipeline
	0 read input and choose state and parameters
	1 inputs - offset
	2 ans * gain
	3 output chosen depending on state
	the various parameters have to be buffered for a few clock cycles
*/

localparam  s_low = 0,  
			s_med = 1,  
			s_high = 2,
			s_invalid = 3;

localparam	delay_sum = 1,
			delay_mult = 1;//not sure if I should increase it
localparam	delay_1 = 1,
			delay_2 = delay_1 + delay_sum,
			delay_3 = delay_2 + delay_mult;

reg [1:0] 								state					[delay_3 -1:0]				;
reg [signalSize -1:0] 					val					  /*[delay_1 -1:0]*/	[1:0]	;
reg [signalSize -1:0] 					offset				  /*[delay_1 -1:0]*/	[1:0]	;
reg [gainSize -1:0] 					gain					[delay_2 -1:0]		[1:0]	;

localparam summedSignalSize = signalSize + 1;
reg [summedSignalSize -1:0]	valMinusOffset											[1:0]	;

wire [signalSize -1:0] 					valMinusOffsetByGain						[1:0]	;

`define longRegisterFromDouble(array)\
		{array[1], array[0]}

clocked_FractionalMultiplier #(
  .A_WIDTH			(summedSignalSize),
  .B_WIDTH			(gainSize),
  .OUTPUT_WIDTH		(signalSize),
  .FRAC_BITS_A		(signalSize - 1),
  .FRAC_BITS_B		(gainFractionalSize),
  .FRAC_BITS_OUT	(signalSize),//the output should never be above 1, right?
  .areSignalsSigned (0)
) valMinusOffset_by_gain[1:0] (
  .clk(clk),
  .a(`longRegisterFromDouble(valMinusOffset)),
  .b(`longRegisterFromDouble(gain[delay_2-1])),
  .result(`longRegisterFromDouble(valMinusOffsetByGain))
);


integer i;
`define setArray(array, length, val)	\
		for(i=0;i<length;i=i+1)begin		\
			array[i] <= val;				\
		end		
`define resetArray(array, length)		\
		`setArray(array, length, 0)
`define resetDoubleArray(array, length)	\
		for(i=0;i<length;i=i+1)begin		\
			array[i][0] <= 0;				\
			array[i][1] <= 0;				\
		end
`define resetDouble(array)				\
		array[0] <= 0;					\
		array[1] <= 0;
`define shiftArray(array, length)		\
		for(i=1;i<length;i=i+1)begin		\
			array[i] <= array[i-1];			\
		end
`define shiftDoubleArray(array, length)	\
		for(i=0;i<length;i=i+1)begin		\
			array[i][0] <= array[i-1][0];	\
			array[i][1] <= array[i-1][1];	\
		end
always @(posedge clk) begin
	if (reset) begin
		uOut <= 1<<signalSize;
		`setArray(state, delay_3, s_invalid)
		`resetDouble(val)
		`resetDouble(offset)
		`resetDouble(valMinusOffset)
		`resetDoubleArray(gain, delay_2)
	end else begin
		`shiftArray(state, delay_3)
		val[0] <= a;
		val[1] <= b;
		for (i=0;i<2;i=i+1) begin
			valMinusOffset[i] <= {val[i][signalSize-1],val[i]} - {offset[i][signalSize-1],offset[i]};
		end
		`shiftDoubleArray(gain, delay_2)
		if($signed(a) < $signed(offset_a_med))begin
			state[0] <= s_low;
			offset[0] <= offset_a_low;
			gain[0][0] <= gain_a_low;
		end else if ($signed(b) > $signed(offset_b_high)) begin
			state[0] <= s_high;
			offset[1] <= offset_b_high;
			gain[0][1] <= gain_b_high;
		end else begin
			state[0] <= s_med;
			offset[0] <= offset_a_med;
			offset[1] <= offset_b_med;
			gain[0][0] <= gain_a_med;
			gain[0][1] <= gain_b_med;
		end

		case (state[delay_3-1])
			s_low : begin
				uOut <= valMinusOffsetByGain[0];
			end
			s_med : begin
				uOut <= section_low_resized + ((valMinusOffsetByGain[0] +  valMinusOffsetByGain[1])>>1);
			end
			s_high : begin
				uOut <= section_lowPlusMed_resized + valMinusOffsetByGain[1];
			end
			default: begin
				uOut <= 1<<signalSize;
			end
		endcase
	end
end


//---------------------------------------------------------------------------------
//
//  System bus connection

always @(posedge clk)
if (reset) begin
	offset_a_low	<= 0;
	offset_a_med	<= 0;
	offset_b_med	<= 0;
	offset_b_high	<= 0;
	gain_a_low		<= 0;
	gain_a_med		<= 0;
	gain_b_med		<= 0;
	gain_b_high		<= 0;
	section_low		<= 0;
	section_med		<= 0;
end else if (wen) begin
	if (addr[19:0]==20'h100) {offset_a_med, offset_a_low} <= wdata;
	if (addr[19:0]==20'h104) {offset_b_high, offset_b_med} <= wdata;
	if (addr[19:0]==20'h108) {gain_a_low} <= wdata;
	if (addr[19:0]==20'h10c) {gain_a_med} <= wdata;
	if (addr[19:0]==20'h110) {gain_b_med} <= wdata;
	if (addr[19:0]==20'h114) {gain_b_high} <= wdata;
	if (addr[19:0]==20'h118) {section_med, section_low} <= wdata;
	
end

wire en;
assign en = wen | ren;

always @(posedge clk) begin
	if (reset) begin
	    err <= 1'b0;
	    ack <= 1'b0;
	end else begin
	    err <= 1'b0;
	    ack <= en;  
	    rdata <=  32'h0;

		if (addr[19:0]==20'h100) rdata <= {offset_a_med, offset_a_low};
		if (addr[19:0]==20'h104) rdata <= {offset_b_high, offset_b_med};
		if (addr[19:0]==20'h108) rdata <= {gain_a_low};
		if (addr[19:0]==20'h10c) rdata <= {gain_a_med};
		if (addr[19:0]==20'h110) rdata <= {gain_b_med};
		if (addr[19:0]==20'h114) rdata <= {gain_b_high};
		if (addr[19:0]==20'h118) rdata <= {section_med, section_low};
	end
end


endmodule


/*

vsim work.sensorFuser
add wave -position insertpoint sim:/sensorFuser/*
add wave -position insertpoint sim:/sensorFuser/state
add wave -position insertpoint sim:/sensorFuser/val
add wave -position insertpoint sim:/sensorFuser/offset
add wave -position insertpoint sim:/sensorFuser/valMinusOffset
add wave -position insertpoint sim:/sensorFuser/gain
force -freeze sim:/sensorFuser/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/sensorFuser/reset z1 0
force -freeze sim:/sensorFuser/a 63d 0
force -freeze sim:/sensorFuser/b 428 0
force -freeze sim:/sensorFuser/section_low 4 0
force -freeze sim:/sensorFuser/section_med 8 0
force -freeze sim:/sensorFuser/offset_a_low 0 0
force -freeze sim:/sensorFuser/offset_a_med 400 0
force -freeze sim:/sensorFuser/offset_b_med fffffc00 0
force -freeze sim:/sensorFuser/offset_b_high fffffe67 0
force -freeze sim:/sensorFuser/gain_a_low 400 0
force -freeze sim:/sensorFuser/gain_a_med a00 0
force -freeze sim:/sensorFuser/gain_b_med d55 0
force -freeze sim:/sensorFuser/gain_b_high 471 0
run
force -freeze sim:/sensorFuser/reset 10 0
run
force -freeze sim:/sensorFuser/a 300 0
force -freeze sim:/sensorFuser/b fffffc00 0
run
force -freeze sim:/sensorFuser/a 533 0
force -freeze sim:/sensorFuser/b fffffce7 0
run
force -freeze sim:/sensorFuser/a 733 0
force -freeze sim:/sensorFuser/b ffffff4d 0
run
force -freeze sim:/sensorFuser/a 200 0
force -freeze sim:/sensorFuser/b fffffc00 0
run
force -freeze sim:/sensorFuser/a 733 0
force -freeze sim:/sensorFuser/b 1b3 0
run
run
run
run
run



*/