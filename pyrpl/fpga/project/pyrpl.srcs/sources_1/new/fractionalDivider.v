
// `define inModelsimSimulation

module fractionalDivider#(
	parameter A_WIDTH = 12,
	parameter B_WIDTH = 4,
	parameter OUTPUT_WIDTH = 8,
	parameter FRAC_BITS_A = 8,
	parameter FRAC_BITS_B = 2,
	parameter FRAC_BITS_OUT = 4,
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
	//if FRAC_BITS_OUT > FRAC_BITS_A: a <<= (FRAC_BITS_OUT-FRAC_BITS_A) so we have some more fractional bits in the result;
	//result = a / b;


	localparam 	
				WHOLE_BITS_A = A_WIDTH - FRAC_BITS_A,
				WHOLE_BITS_B = B_WIDTH - FRAC_BITS_B,

				fracPad_a = FRAC_BITS_B > FRAC_BITS_A ? FRAC_BITS_B - FRAC_BITS_A : 0,
				fracPad_b = 0,
				fracDifference = FRAC_BITS_A > FRAC_BITS_B ? FRAC_BITS_A - FRAC_BITS_B : 0,
				
				wholePad_a = B_WIDTH > (A_WIDTH + fracPad_a) ? B_WIDTH - (A_WIDTH + fracPad_a) : 0,
				
				fracOutputPad_a = FRAC_BITS_OUT > fracDifference ? FRAC_BITS_OUT - fracDifference : 0,
				
				numer_FRAC_BITS = fracDifference + fracOutputPad_a,
				num_WIDTH = 1 + A_WIDTH + fracPad_a + wholePad_a + fracOutputPad_a,
				den_WIDTH = B_WIDTH,
				den_FRAC_BITS = 0,
				
				rawQuotient_WIDTH = num_WIDTH,
				FRAC_BITS_rawQuotient = numer_FRAC_BITS,
				rawRem_WIDTH = den_WIDTH;
			
wire [num_WIDTH -1:0] a_shifted;
	fixedPointShifter#(
		.inputBitSize	(A_WIDTH),
		.inputFracSize	(FRAC_BITS_A),
		.outputBitSize	(num_WIDTH),
		.outputFracSize	(fracPad_a + FRAC_BITS_A + fracOutputPad_a),
		.isSigned		(areSignalsSigned),
		.saturateOutput (0)
	)a_shifter(
		.in				(a),
		.out			(a_shifted)
	);
wire [den_WIDTH -1:0] b_shifted = b;//we'll consider b as a completely whole number

generate

`ifdef InModelsimSimulation
	parameter delay = 20;
	reg [rawQuotient_WIDTH -1:0] rawQuotient_nonDelayed;
	reg [rawQuotient_WIDTH -1:0] rawRemain_nonDelayed;
	wire [rawQuotient_WIDTH -1:0] rawQuotient;
	wire [rawQuotient_WIDTH -1:0] rawRemain;
	delayer#(rawQuotient_WIDTH, delay-1) delayquot(clk,reset, rawQuotient_nonDelayed, rawQuotient);
	delayer#(rawQuotient_WIDTH, delay-1) delayrem(clk,reset, rawRemain_nonDelayed, rawRemain);
	if(areSignalsSigned)begin
		always @(posedge clk) begin
			if(reset) begin
				rawQuotient_nonDelayed <= 0;
				rawRemain_nonDelayed <= 0;
			end else begin
				rawQuotient_nonDelayed <= $signed(a_shifted) / $signed(b_shifted);
				rawRemain_nonDelayed <= $signed(a_shifted) % $signed(b_shifted);
			end
		end		
	end else begin
		always @(posedge clk) begin
			if(reset) begin
				rawQuotient_nonDelayed <= 0;
				rawRemain_nonDelayed <= 0;
			end else begin
				rawQuotient_nonDelayed <= $unsigned(a_shifted) / $unsigned(b_shifted);
				rawRemain_nonDelayed <= $unsigned(a_shifted) % $unsigned(b_shifted);
			end
		end		
	end


`else
	wire [rawQuotient_WIDTH -1:0] rawQuotient;
	wire [rawRem_WIDTH -1:0] rawRemain;
	if(num_WIDTH == 29 && den_WIDTH == 14 && !areSignalsSigned)begin:div29_29
		wire [47:0]m_axis_dout_tdata;
		div_gen_u_29_14 d29_14(
			.aclk					(clk),
			.aresetn				(!reset),	
			.s_axis_divisor_tvalid	(1),				
			.s_axis_divisor_tdata	(b_shifted),					
			.s_axis_dividend_tvalid	(1),				
			.s_axis_dividend_tdata	(a_shifted),
			.m_axis_dout_tdata		({rawQuotient, {16 - rawRem_WIDTH{1'b0}}, rawRemain})
		);
		assign rawRemain = m_axis_dout_tdata[14 -1:0];
		assign rawQuotient = m_axis_dout_tdata[47:16];
	end else if(num_WIDTH == 44 && den_WIDTH == 29 && areSignalsSigned)begin:div_gen_s_44_29
		wire [79:0]m_axis_dout_tdata;
		div_gen_s_44_29 d44_29(
			.aclk					(clk),
			.aresetn				(!reset),	
			.s_axis_divisor_tvalid	(1),				
			.s_axis_divisor_tdata	(b_shifted),					
			.s_axis_dividend_tvalid	(1),				
			.s_axis_dividend_tdata	(a_shifted),
			.m_axis_dout_tdata		(m_axis_dout_tdata)
		);
		assign rawRemain = m_axis_dout_tdata[29 -1:0];
		assign rawQuotient = m_axis_dout_tdata[79:32];
		//delay: 20
	end 
		else begin
		$error("combination of register lengths does not have an IP core divider associated. Create a new divider with the correct register sizes and add it to the fractionalDivider module (yes, I know it sucks...).%sSigned, numerator size: %n, denominator size %n",
		(areSignalsSigned ? " " : " Un"), num_WIDTH, den_WIDTH);
		/*
		how to create a new divider IP core:
			In Vivado, open the IP Catalog (Window->IP Catalog), search and select DIVIDE GENERATOR.
			set the Component Name to div_gen_<u|s>_<num_WIDTH>_<den_WIDTH>
			select the operand sign (signed or unsigned)
			select the dividend (numerator) and divisor (denominator) widths
			in the tab Options, set the latency configuration to manual. For the latency, you'll have to try out different values, but you can definitely go lower than the proposed delay
				(I know, we're asking a lot to the FPGA, but I'm not waiting tens of clock cycles for a single division operation)
				in the control signals, add the input ARESETN
			Click OK and start the generation of the IP. It's gonna take a few minutes, and it's gonna be executed in the background

			Now add the module to this script. For the wire m_axis_dout_tdata: it's a register combining remainder and quotient, and the 
				divider module aligns them so that the quotient starts at a power of 2 (16, 32...). So, put the correct amout of 
				stuffing bits between the remainder and quotient

			If you compile the project and you get an error saying that the newly added module does not exist, try again after a few 
				minutes, maybe the generation of the IP core wasn't finished yet (and compliment yourself, you finished faster than  
				the IP module generator!)
		*/
	end
`endif
endgenerate
		
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
	.inputBitSize	(rawRem_WIDTH),
	.inputFracSize	(FRAC_BITS_B),
	.outputBitSize	(OUTPUT_WIDTH),
	.outputFracSize	(FRAC_BITS_OUT),
	.isSigned		(areSignalsSigned),
	.saturateOutput (saturateOutput)
)remainder_shifter(
	.in				(rawRemain),
	.out			(remain)
);
endmodule


/*

vsim work.fractionalDivider
add wave -position insertpoint sim:/fractionalDivider/*
force -freeze sim:/fractionalDivider/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/fractionalDivider/reset z1 0
force -freeze sim:/fractionalDivider/a 2e4 0
force -freeze sim:/fractionalDivider/b 4 0
run
force -freeze sim:/fractionalDivider/reset 10 0
run
run
force -freeze sim:/fractionalDivider/a 200 0
run
run
*/