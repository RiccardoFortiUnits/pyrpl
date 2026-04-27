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
	parameter coefficientSize = 8,
	parameter nOfCoefficients = 4,
	parameter maxShift = coefficientSize
) (
	input clk,
	input reset,
	input triggerNextCoeff,//when high, the input coefficients will be saved.
	input [coefficientSize -1:0] currentCoefficient,
	input [$clog2(maxShift+1) -1:0] shift,
	input areCoefficientsDecreasing,// in absolute number
	output [coefficientSize -1:0] shiftedCoefficient
);

reg [$clog2(nOfCoefficients) -1:0] coefficientIndex;
reg [coefficientSize -1:0] sum;

//let's work only with positive values
wire sign = currentCoefficient[coefficientSize-1];
wire [coefficientSize -1:0] abs = sign ? - currentCoefficient : currentCoefficient;

wire [coefficientSize -1:0] nextSum = sum + abs;
wire signed [coefficientSize -1:0] shiftedSum;
wire signed [coefficientSize -1:0] shiftedNextSum;
assign shiftedSum = (sum >> shift) + (areCoefficientsDecreasing & sum[shift-1]);
assign shiftedNextSum = (nextSum >> shift) + (areCoefficientsDecreasing && (coefficientIndex != nOfCoefficients-1) & nextSum[shift - 1]);


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
wire [coefficientSize -1:0] abs_shiftedCoefficient = reset ? 0 : shiftedNextSum - shiftedSum;
assign shiftedCoefficient = sign ? - abs_shiftedCoefficient : abs_shiftedCoefficient;
	
endmodule

/*

vsim work.fixedSumCoefficientShifter_oneAtATime
add wave -position insertpoint sim:/fixedSumCoefficientShifter_oneAtATime/*
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/reset z 0
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/triggerNextCoeff z0 0
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 29 0
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/shift 3 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/reset z1 0
run
run
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/reset 10 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/triggerNextCoeff 01 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 22 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 1d 0
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 18 0
run
run
run
run
run
force -freeze sim:/fixedSumCoefficientShifter_oneAtATime/currentCoefficient 1f 0
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