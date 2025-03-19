//returns the value (middle-min)/(max-min), i.e. the normalized position of middle to respect to min and max
module normalizedRatio#(
	parameter inputSize = 16,
	parameter ratioSize = 16,//ratio is unsigned, with 0 whole bits (only fractional bits)
	parameter isInputSigned = 1
) (
	input clk,
	input reset,
	input [inputSize -1:0] min,
	input [inputSize -1:0] max,
	input [inputSize -1:0] middle,
	output [ratioSize -1:0] ratio
);

wire [inputSize -1:0] middle_minus_min, max_minus_min;
generate
	if(isInputSigned)begin
		assign middle_minus_min = $signed(middle) - $signed(min);
		assign max_minus_min = $signed(max) - $signed(min);
	end else begin
		assign middle_minus_min = $unsigned(middle) - $unsigned(min);
		assign max_minus_min = $unsigned(max) - $unsigned(min);
	end
endgenerate

fractionalDivider #(
	.A_WIDTH			(inputSize),
	.B_WIDTH			(inputSize),
	.OUTPUT_WIDTH		(ratioSize),
	.FRAC_BITS_A		(0),
	.FRAC_BITS_B		(0),
	.FRAC_BITS_OUT		(ratioSize),
	.areSignalsSigned	(0)// numerator and denominators will always be positive
) fd(
	.clk		(clk),
	.reset		(reset),
	.a			(middle_minus_min),
	.b			(max_minus_min),
	.result		(ratio)
);

endmodule
/*

add wave -position insertpoint sim:/normalizedRatio/*
force -freeze sim:/normalizedRatio/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/normalizedRatio/reset 1 0
force -freeze sim:/normalizedRatio/min 0000 0
force -freeze sim:/normalizedRatio/max 0100 0
force -freeze sim:/normalizedRatio/middle 0051 0
run
run
force -freeze sim:/normalizedRatio/reset 0 0
run
run
force -freeze sim:/normalizedRatio/min 0050 0
run
run
force -freeze sim:/normalizedRatio/max 052 0
run
run
force -freeze sim:/normalizedRatio/min 00100 0
force -freeze sim:/normalizedRatio/middle 0080 0
force -freeze sim:/normalizedRatio/min 0 0
run
run

*/