module fixedSumCoefficientShifter #(
	parameter coefficientSize = 8,//the coefficients are assumed to be unsigned, in ascending order, and their sum is coefficientSize-bit long (or less)
	parameter nOfCoefficients = 4
) (
	input clk,
	input reset,
	input trigger,//when high, the input coefficients will be saved.
	input triggerShift, //when high, the coefficients will be shifted one bit right. To change/reset the values of the coefficients, pull high the trigger pin again.
							//while trigger is high, triggerShift is not checked
	input [coefficientSize*nOfCoefficients -1:0] initialCoefficients,
	output reg [coefficientSize*nOfCoefficients -1:0] shiftedCoefficients
);

wire [nOfCoefficients -1:0] nexShift_carryBits;
wire [nOfCoefficients -1:0] cumsumOfLastBits;

generate
	genvar gi;
	assign cumsumOfLastBits[0] = shiftedCoefficients[0];
	for (gi = 1; gi<nOfCoefficients; gi=gi+1) begin
		assign cumsumOfLastBits[gi] = cumsumOfLastBits[gi-1] ^ shiftedCoefficients[gi*coefficientSize];
	end
	assign nexShift_carryBits[0] = 0;
	for (gi = 1; gi<nOfCoefficients; gi=gi+1) begin
		assign nexShift_carryBits[gi] = (!cumsumOfLastBits[gi]) & cumsumOfLastBits[gi-1];
	end
endgenerate

integer i;
always @(posedge clk) begin
	if (reset) begin
		shiftedCoefficients <= 0;
	end else begin
		if (trigger) begin
			shiftedCoefficients <= initialCoefficients;
		end else begin
			if(triggerShift)begin
				for (i = 0; i<nOfCoefficients; i=i+1) begin
					shiftedCoefficients[(i+1)*coefficientSize -1-:coefficientSize] <= //coeff>>1 + carryBit
					shiftedCoefficients[(i+1)*coefficientSize -1-:coefficientSize-1] + nexShift_carryBits[i];
				end
			end
		end
	end
end

	
endmodule

/*

vsim work.fixedSumCoefficientShifter
add wave -position insertpoint sim:/fixedSumCoefficientShifter/*
force -freeze sim:/fixedSumCoefficientShifter/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/fixedSumCoefficientShifter/reset z1 0
force -freeze sim:/fixedSumCoefficientShifter/trigger z0 0
force -freeze sim:/fixedSumCoefficientShifter/triggerShift z0 0
force -freeze sim:/fixedSumCoefficientShifter/initialCoefficients 29221d18 0
run
force -freeze sim:/fixedSumCoefficientShifter/reset 10 0
run
force -freeze sim:/fixedSumCoefficientShifter/trigger 01 0
run
force -freeze sim:/fixedSumCoefficientShifter/trigger 10 0
run
force -freeze sim:/fixedSumCoefficientShifter/triggerShift 01 0
run

*/

module fixedSumCoefficientShifter_oneAtATime #(
	parameter coefficientSize = 8,//coefficients are assumed to be signed
	parameter nOfCoefficients = 4,
	parameter maxShift = coefficientSize
) (
	input clk,
	input reset,
	input triggerNextCoeff,//when high, the input coefficients will be saved.
	input [coefficientSize -1:0] currentCoefficient,
	input [$clog2(maxShift+1) -1:0] shift,
	output [coefficientSize -1:0] shiftedCoefficient
);

reg [$clog2(nOfCoefficients) -1:0] coefficientIndex;
reg [coefficientSize -1:0] sum;

wire signed [coefficientSize -1:0] nextSum = sum + currentCoefficient;

wire signed [coefficientSize -1:0] shiftedSum_noRounding, shiftedNextSum_noRounding;
wire signed [coefficientSize -1:0] shiftedSum, shiftedNextSum;

wire sum_signBit = sum[coefficientSize -1];
wire nextSum_signBit = nextSum[coefficientSize -1];

assign shiftedSum_noRounding = $signed($signed(sum) >>> shift);//I have no idea why this stupidly easy shift has to be written in such a complicated way...
assign shiftedNextSum_noRounding = $signed($signed(nextSum) >>> shift);

assign shiftedSum = sum_signBit ? shiftedSum_noRounding : shiftedSum_noRounding + sum[shift-1];
assign shiftedNextSum = nextSum_signBit ? shiftedNextSum_noRounding : (shiftedNextSum_noRounding + ((coefficientIndex != nOfCoefficients-1) & nextSum[shift - 1]));


always @(posedge clk) begin
	if (reset) begin
		sum <= 0;
		coefficientIndex <= 0;
	end else begin
		if (triggerNextCoeff) begin
			if(coefficientIndex == nOfCoefficients-1)begin
				sum <= 0;
				coefficientIndex <= 0;
			end else begin
				sum <= nextSum;
				coefficientIndex <= coefficientIndex + 1;
			end
		end
	end
end
assign shiftedCoefficient = reset ? 0 : shiftedNextSum - shiftedSum;
	
endmodule

/*

vsim work.fixedSumCoefficientShifter_oneAtATime
add wave -position insertpoint sim:/fixedSumCoefficientShifter_oneAtATime/*
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/reset z 0
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/triggerNextCoeff z0 0
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 15 0
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/shift 2 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/reset z1 0
run
run
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/reset 10 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/triggerNextCoeff 01 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 11 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 0e 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient c 0
run
run
run
run
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient f3 0
run
run
run
run
run
run
run
run
run
run


*/