

module sensorFuser#(
	parameter signalSize = 12,
	parameter gainSize = 8,
	parameter gainFractionalSize = 6,
	parameter sectionSize = 4
) (
	input 						clk,
	input 						reset,
	input [signalSize -1:0]		a,
	input [signalSize -1:0]		b,
	output [signalSize -1:0]	out,
	input [signalSize -1:0]		offset_a_low, //should always be 0, but let's define it just in case
	input [signalSize -1:0]		offset_a_med,
	input [signalSize -1:0]		offset_b_med,
	input [signalSize -1:0]		offset_b_high,
	input [gainSize -1:0]		gain_a_low,
	input [gainSize -1:0]		gain_a_med,
	input [gainSize -1:0]		gain_b_med,
	input [gainSize -1:0]		gain_b_high,
	input [sectionSize -1:0] 	section_low,
	input [sectionSize -1:0] 	section_med
);

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