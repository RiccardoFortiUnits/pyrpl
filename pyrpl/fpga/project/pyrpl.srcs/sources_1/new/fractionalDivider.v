module fractionalDivider#(
	parameter A_WIDTH = 16,
	parameter B_WIDTH = 16,
	parameter OUTPUT_WIDTH = 32,
	parameter FRAC_BITS_A = 8,
	parameter FRAC_BITS_B = 8,
	parameter FRAC_BITS_OUT = 12,
	parameter areSignalsSigned = 1,
	parameter saturateOutput = 0
)(
	input wire clk,
	input wire reset,
	input wire signed [A_WIDTH-1:0] a,
	input wire signed [B_WIDTH-1:0] b,
	output wire signed [OUTPUT_WIDTH-1:0] result,
	output wire signed [OUTPUT_WIDTH-1:0] remain
);

//operations: 
	// a,b <<= FRAC_BITS_B;// => b becomes an integer; 
	//if FRAC_BITS_OUT > FRAC_BITS_A: a <<= (FRAC_BITS_OUT-FRAC_BITS_A) input a;
	//result = a / b;


	localparam 	
				WHOLE_BITS_A = A_WIDTH - FRAC_BITS_A,
				WHOLE_BITS_B = B_WIDTH - FRAC_BITS_B,

				fracPad_a = FRAC_BITS_B > FRAC_BITS_A ? FRAC_BITS_B - FRAC_BITS_A : 0,
				fracPad_b = 0,
				fracDifference = FRAC_BITS_A > FRAC_BITS_B ? FRAC_BITS_A - FRAC_BITS_B : 0,
				
				wholePad_a = B_WIDTH > (A_WIDTH + fracPad_a) ? B_WIDTH - (A_WIDTH + fracPad_a) : 0,
				wholePad_b = A_WIDTH + fracPad_a + wholePad_a - B_WIDTH,
				
				fracOutputPad_a = FRAC_BITS_OUT > fracDifference ? FRAC_BITS_OUT - fracDifference : 0,
				
				numer_FRAC_BITS = fracDifference + fracOutputPad_a,
				numDen_WIDTH = 1 + A_WIDTH + fracPad_a + wholePad_a + fracOutputPad_a,
				den_FRAC_BITS = 0,
				
				rawQuotient_WIDTH = numDen_WIDTH,
				FRAC_BITS_rawQuotient = numer_FRAC_BITS;
			
wire [numDen_WIDTH -1:0] a_shifted;
	fixedPointShifter#(
		.inputBitSize	(A_WIDTH),
		.inputFracSize	(FRAC_BITS_A),
		.outputBitSize	(numDen_WIDTH),
		.outputFracSize	(fracPad_a + FRAC_BITS_A + fracOutputPad_a),
		.isSigned		(areSignalsSigned),
		.saturateOutput (saturateOutput)
	)a_shifter(
		.in				(a),
		.out			(a_shifted)
	);
wire [numDen_WIDTH -1:0] b_shifted;
	fixedPointShifter#(
		.inputBitSize	(B_WIDTH),
		.inputFracSize	(FRAC_BITS_B),
		.outputBitSize	(numDen_WIDTH),
		.outputFracSize	(fracPad_b + FRAC_BITS_B),
		.isSigned		(areSignalsSigned),
		.saturateOutput (saturateOutput)
	)b_shifter(
		.in				(b),
		.out			(b_shifted)
	);
				
//todo: numeratof and denominator don't have to have the same sizes. Also, length(num)==length(quot), and length(den)==length(rem)
				
				
reg [rawQuotient_WIDTH -1:0] rawQuotient;
reg [rawQuotient_WIDTH -1:0] rawRemain;
generate
	if(areSignalsSigned)begin
		always @(posedge clk) begin
			if(reset) begin
				rawQuotient <= 0;
				rawRemain <= 0;
			end else begin
				rawQuotient <= $signed(a_shifted) / $signed(b_shifted);
				rawRemain <= $signed(a_shifted) % $signed(b_shifted);
			end
		end		
	end else begin
		always @(posedge clk) begin
			if(reset) begin
				rawQuotient <= 0;
				rawRemain <= 0;
			end else begin
				rawQuotient <= $unsigned(a_shifted) / $unsigned(b_shifted);
				rawRemain <= $unsigned(a_shifted) % $unsigned(b_shifted);
			end
		end		
	end
endgenerate


// wire [rawQuotient_WIDTH -1:0] rawQuotient;
// wire [rawQuotient_WIDTH -1:0] rawRemain;
// lpm_divide#(
// 	.lpm_drepresentation				("SIGNED"),
// 	.lpm_hint				("MAXIMIZE_SPEED=6,LPM_REMAINDERPOSITIVE=FALSE"),
// 	.lpm_nrepresentation				("SIGNED"),
// 	.lpm_pipeline				(3),
// 	.lpm_type				("LPM_DIVIDE"),
// 	.lpm_widthd				(numDen_WIDTH),
// 	.lpm_widthn				(numDen_WIDTH)
// )LPM_DIVIDE_component (
// 	.aclr (reset),
// 	.clock (clk),
// 	.denom (b_shifted),
// 	.numer (a_shifted),
// 	.quotient (rawQuotient),
// 	.remain (rawRemain),
//  .clken (1'b1));
		
fixedPointShifter#(
	.inputBitSize	(rawQuotient_WIDTH),
	.inputFracSize	(FRAC_BITS_rawQuotient),
	.outputBitSize	(OUTPUT_WIDTH),
	.outputFracSize	(FRAC_BITS_OUT),
	.isSigned		(areSignalsSigned),
	.saturateOutput (saturateOutput)
)quotient_shifter(
	.in				(rawQuotient),
	.out			(result)
);

fixedPointShifter#(
	.inputBitSize	(rawQuotient_WIDTH),
	.inputFracSize	(FRAC_BITS_rawQuotient),
	.outputBitSize	(OUTPUT_WIDTH),
	.outputFracSize	(FRAC_BITS_OUT),
	.isSigned		(areSignalsSigned),
	.saturateOutput (saturateOutput)
)remainder_shifter(
	.in				(rawRemain),
	.out			(remain)
);
endmodule