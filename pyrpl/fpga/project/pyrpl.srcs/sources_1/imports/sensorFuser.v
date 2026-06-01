
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

	Assuming that the sensors read the same value x, we get the values a(x) and b(x). We assume that
	a(x) = a(x_low) + g_a * (x - x_low) if x <= x_high, else a(x_high) 		(saturates for values higher than x_high)
	b(x) = b(x_low) + g_b * (x - x_low) 		(it doesn't saturate, but it's not reliable for x < x_med)

	then, we can define the combination signal c, which is composed of 3 sections (depending on the input signal x)
	c(a(x), b(x)) = - 1 + 2 * (
		section_low * (a(x) - a(x_low)) / g_a													if a(x) <= a(x_med)
			else
		section_low + section_med * .5 * ((a(x) - a(x_med)) / g_a	(b(x) - b(x_med)) / g_b)	if a(x) > a(x_med) and b(x) <= b(x_high)
			else
		section_low + section_med + section_high * (b(x) - b(x_high)) / g_b)	if b(x) > b(x_high)
	)
	where section_low + section_med + section_high = 1

	this function maps x into the range [-1,1]
*/
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
	
    // System bus
    input      [ 16-1:0] addr   ,  // bus address
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
reg [signalSize+1 -1:0] uOut;
wire [signalSize -1:0] uOut_cropped;
fixedPointShifter#(
	.inputBitSize	(signalSize+1),
	.inputFracSize	(signalSize),
	.outputBitSize	(signalSize),
	.outputFracSize	(signalSize),
	.isSigned		(0)
)crop_uOut(
	.in				(uOut),
	.out			(uOut_cropped)
);
assign out = {!uOut_cropped[signalSize-1], uOut_cropped[signalSize-1 -1:0]};

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

localparam  s_low = 0,  
			s_med = 1,  
			s_high = 2,
			s_invalid = 3;

`define longRegisterFromDouble(array)\
		{array[1], array[0]}

`define delayedRegister(registerSize, inputName, outputName, delayCycles) 			\
	reg [registerSize -1:0] inputName;													\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk, 1, reset, inputName, outputName);

`define delayedWire(registerSize, inputName, outputName, delayCycles, assignedValue)\
	wire [registerSize -1:0] inputName = assignedValue;									\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk, 1, reset, inputName, outputName);

`define delayedWire_noAssignment(registerSize, inputName, outputName, delayCycles)	\
	wire [registerSize -1:0] inputName;													\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk, 1, reset, inputName, outputName);

localparam	delay_1 = 1,
			delay_2 = 1;//for multiplication. Not sure if I should increase it
localparam	delay_12 = delay_1 + delay_2;

//green wires
wire [signalSize -1:0] 	val		[1:0]; assign `longRegisterFromDouble(val) = {b, a};
reg [signalSize -1:0] 	offset	[1:0];//these registers are controlled by an always(*) block, so they will behave like wires
localparam summedSignalSize = signalSize + 1;
reg [summedSignalSize -1:0]	valMinusOffset [1:0]; 

//cyan wires
`delayedRegister(2, state_cyan, state_blue, delay_2)
reg [gainSize -1:0] 	gain	[1:0];

//blue wires
wire [signalSize -1:0] 	valMinusOffsetByGain	[1:0];

//set offset
always @(*) begin	
	if($signed(a) < $signed(offset_a_med))begin
		offset[0] <= offset_a_low;
		offset[1] <= 1'bx;
	end else if ($signed(b) > $signed(offset_b_high)) begin
		offset[0] <= 1'bx;
		offset[1] <= offset_b_high;
	end else begin
		offset[0] <= offset_a_med;
		offset[1] <= offset_b_med;
	end
end

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
  .clkEnable(1'b1),
  .a(`longRegisterFromDouble(valMinusOffset)),
  .b(`longRegisterFromDouble(gain)),
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
		state_cyan <= s_invalid;
		`resetDouble(valMinusOffset)
		`resetDouble(gain)
	end else begin
		for (i=0;i<2;i=i+1) begin
			valMinusOffset[i] <= $signed(val[i]) > $signed(offset[i]) ? 
									{val[i][signalSize-1],val[i]} - {offset[i][signalSize-1],offset[i]} :
									0;//let's clip the difference if it would be negative
		end
		if($signed(a) < $signed(offset_a_med))begin
			state_cyan <= s_low;
			// offset[0] <= offset_a_low;//already set in an always(*) block
			gain[0] <= gain_a_low;
		end else if ($signed(b) > $signed(offset_b_high)) begin
			state_cyan <= s_high;
			// offset[1] <= offset_b_high;
			gain[1] <= gain_b_high;
		end else begin
			state_cyan <= s_med;
			// offset[0] <= offset_a_med;
			// offset[1] <= offset_b_med;
			gain[0] <= gain_a_med;
			gain[1] <= gain_b_med;
		end

		case (state_blue)
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
	if (addr==20'h100) {offset_a_med, offset_a_low} <= wdata;
	if (addr==20'h104) {offset_b_high, offset_b_med} <= wdata;
	if (addr==20'h108) {gain_a_low} <= wdata;
	if (addr==20'h10c) {gain_a_med} <= wdata;
	if (addr==20'h110) {gain_b_med} <= wdata;
	if (addr==20'h114) {gain_b_high} <= wdata;
	if (addr==20'h118) {section_med, section_low} <= wdata;
	
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

		if (addr==20'h100) rdata <= {offset_a_med, offset_a_low};
		if (addr==20'h104) rdata <= {offset_b_high, offset_b_med};
		if (addr==20'h108) rdata <= {gain_a_low};
		if (addr==20'h10c) rdata <= {gain_a_med};
		if (addr==20'h110) rdata <= {gain_b_med};
		if (addr==20'h114) rdata <= {gain_b_high};
		if (addr==20'h118) rdata <= {section_med, section_low};
	end
end
endmodule

module sensorFuser_with_SimulatedInputs#(
	parameter signalSize = 14,
	parameter gainSize = 8,
	parameter gainFractionalSize = 6,
	parameter sectionSize = 4
)(
    input clk,
    input reset,
    output [signalSize-1:0] out
);

reg [signalSize-1:0] a;
reg [signalSize+1-1:0] b;

always @(posedge clk)
if (reset)begin
    a <= 14'h0;
	b <= 15'h000;
end else begin
	if (a != 14'h1fff) begin
		a <= a + 1;
	end
	if (b != 15'h3fff) begin
		b <= b + 1;
	end else begin
		a <= 14'h0;
		b <= 15'h000;
	end
end
sensorFuser#(
	.signalSize			(signalSize),
	.gainSize			(gainSize),
	.gainFractionalSize	(gainFractionalSize),
	.sectionSize		(sectionSize) 
)segFus(
	.clk				(clk),
	.reset				(reset),
	.a					(a),
	.b					(b[signalSize+1 -1:1]),
	.out				(out)
);	
endmodule

/*
vsim work.sensorFuser_with_SimulatedInputs
add wave -position insertpoint sim:/sensorFuser_with_SimulatedInputs/segFus/*
add wave -position insertpoint sim:/sensorFuser_with_SimulatedInputs/segFus/valMinusOffsetByGain
add wave -position insertpoint sim:/sensorFuser_with_SimulatedInputs/segFus/gain
add wave -position insertpoint sim:/sensorFuser_with_SimulatedInputs/segFus/valMinusOffset
add wave -position insertpoint sim:/sensorFuser_with_SimulatedInputs/segFus/offset
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/reset z1 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/offset_a_low 0 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/offset_b_med 61d 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/offset_a_med c38 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/offset_b_high ffe 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/section_low 8 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/section_med 1 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/gain_a_low 54 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/gain_a_med 6 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/gain_b_med d 0
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/gain_b_high 39 0
run
force -freeze sim:/sensorFuser_with_SimulatedInputs/segFus/reset 10 0
run
run 2000ns


*/