`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.03.2024 09:12:36
// Design Name: 
// Module Name: segmentedFunction
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module segmentedFunction#(
    parameter     nOfEdges 			= 4,
    parameter     totalBits_IO 		= 8,
    parameter     fracBits_IO 		= 0,
    parameter     totalBits_m 		= 2*totalBits_IO,
    parameter     fracBits_m 		= totalBits_m-1,
    parameter     areSignalsSigned 	= 1
)(
    input                                       clk   ,
    input                                       reset ,
    input [totalBits_IO-1:0]                    in    ,
    output [totalBits_IO-1:0]               out   ,
    // System bus
    input      [ 16-1:0] addr   ,  // bus address
    input      [ 32-1:0] wdata  ,  // bus write data
    input                wen    ,  // bus write enable
    input                ren    ,  // bus read enable
    output reg [ 32-1:0] rdata  ,  // bus read data
    output reg           err    ,  // bus error indicator
    output reg           ack       // bus acknowledge signal
);
reg [nOfEdges*totalBits_IO -1:0] edgePoints;
reg [nOfEdges*totalBits_IO -1:0] qs;
reg [nOfEdges*totalBits_m -1:0]  ms;

`define valueOfArray(array, index, registerSize) array[((index) + 1) * (registerSize) -1-:(registerSize)]
`define edgePoint(index) 	`valueOfArray(edgePoints, index, totalBits_IO)
`define q(index) 			`valueOfArray(qs, index, totalBits_IO)
`define m(index) 			`valueOfArray(ms, index, totalBits_m)

//applies to the input a segmented function. The values for edgePoints, qs and 
    //ms can be found for any segmented function as follows
    /*    
    #x and y are the sample points and values of the function ( y[i] = f(x[i]) )
    #es: x = np.linspace(0,1,8)
    #    y = np.tanh(x*4)
    a = x[0:len(x)-1]
    b = x[1:]
    c = y[0:len(y)-1]
    d = y[1:]
    edgePoints = a
    qs = c
    ms = (d-c) / (b-a)
    */
    
//if you don't use some samples, set their edgePoint to a value <= edgePoint[0] (just set them to 0 
    //or -(2^(totalBits_IO-1)), depending on if the signals are signed or not)


localparam 	delay_0 = 1,
			delay_1 = 1,
			delay_2 = 1,
			delay_01 = delay_0 + delay_1;


`define delayedRegister(registerSize, inputName, outputName, delayCycles) 			\
	reg [registerSize -1:0] inputName;													\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk, 1, reset, inputName, outputName);

`define delayedWire(registerSize, inputName, outputName, delayCycles, assignedValue)\
	wire [registerSize -1:0] inputName = assignedValue;									\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk, 1, reset, inputName, outputName);

`define delayedWire_inputAlreadyAssigned(registerSize, inputName, outputName, delayCycles)	\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk, 1, reset, inputName, outputName);




//green wires
wire [nOfEdges-1:0] isInHigherThanEdge;//bitString of the form 00...0011...11
wire [nOfEdges-1:0] isCurrentEdge;//bitString of the form      00...0010...00
`delayedWire_inputAlreadyAssigned(totalBits_IO, in, in_r, delay_0)

//blue wires
reg [$clog2(nOfEdges):0] edgeIndex;
wire [totalBits_IO-1:0] current_Edge = `edgePoint(edgeIndex);
wire [totalBits_m-1:0] current_m = `m(edgeIndex);
`delayedWire(totalBits_IO, current_q_blue, current_q, delay_1, `q(edgeIndex))
wire in_r_signBit, current_Edge_signBit;//let's make a wire to keep track of the sign of the registers, to make the code more 
											//readable. We'll asign it in the generate block, depending on if the signals are 
											//signed or not

//purple wires
wire [totalBits_IO+2 -1:0] mx;//mx requires one more bit. It's allowed to surpass the output range, because it will be later 
									//shifted back by current_q
wire current_q_signBit;
wire [totalBits_IO+2 -1:0] out_unsaturated = reset ? 0 : {{2{current_q_signBit}}, current_q} + mx;

generate
    genvar gi;
    
    //set isInHigherThanEdge    
    if(areSignalsSigned) begin
        assign isInHigherThanEdge[0] = $signed(in_r[0]) >= $signed(`edgePoint(0));
        for(gi = 1; gi < nOfEdges; gi = gi + 1)begin
            assign isInHigherThanEdge[gi] = ($signed(in) >= $signed(`edgePoint(gi))) && 
                ($signed(`edgePoint(gi)) > $signed(`edgePoint(gi-1)));// if set lower or higher than the first 
                                                                                    //edge, it means it is disabled
        end
		assign current_q_signBit = current_q[totalBits_IO-1];
		assign in_r_signBit = in_r[totalBits_IO-1];
		assign current_Edge_signBit = current_Edge[totalBits_IO-1];
    end else begin
        assign isInHigherThanEdge[0] = $unsigned(in_r[0]) >= $unsigned(`edgePoint(0));
        for(gi = 1; gi < nOfEdges; gi = gi + 1)begin
            assign isInHigherThanEdge[gi] = ($unsigned(in) >= $unsigned(`edgePoint(gi))) && 
                ($unsigned(`edgePoint(gi)) > $unsigned(`edgePoint(gi-1)));// if set lower or higher than the first 
                                                                            //edge, it means it is disabled
        end    
		assign current_q_signBit = 0;
		assign in_r_signBit = 0;
		assign current_Edge_signBit = 0;
    end
    
    //set isCurrentEdge
    assign isCurrentEdge[nOfEdges - 1] = isInHigherThanEdge[nOfEdges - 1];
    for(gi = 0; gi < nOfEdges - 1; gi = gi + 1)begin
        assign isCurrentEdge[gi] = !isInHigherThanEdge[gi + 1] & isInHigherThanEdge[gi];
    end
    
endgenerate

//let's calculate edgeIndex (everything else is already calculated)
integer i;
always @(posedge clk)begin
    if(reset)begin     
        edgeIndex <= 0;        
    end else begin    
        for(i=0; i < nOfEdges; i = i + 1)begin
            if(isCurrentEdge[i])begin
                edgeIndex <= i;     
            end
        end
    end
end

clocked_FractionalMultiplier #(
  .A_WIDTH			(totalBits_IO + 1),//stupid sum/difference between integers, which requires one more bit to not overflow... 
  .B_WIDTH			(totalBits_m),
  .OUTPUT_WIDTH		(totalBits_IO+2),
  .FRAC_BITS_A		(fracBits_IO),
  .FRAC_BITS_B		(fracBits_m),
  .FRAC_BITS_OUT	(fracBits_IO),
  .areSignalsSigned (1)//the coefficient can always be negative
) mult (
  .clk(clk),
  .clkEnable(1'b1),
  .a({in_r_signBit,in_r} - {current_Edge_signBit,current_Edge}),
  .b(current_m),
  .result(mx)
);

fixedPointShifter#(
	.inputBitSize	(totalBits_IO+2),
	.inputFracSize	(fracBits_IO),
	.outputBitSize	(totalBits_IO),
	.outputFracSize	(fracBits_IO),
	.isSigned		(areSignalsSigned)
)clipOutput(
	.in				(out_unsaturated),
	.out			(out)
);


//---------------------------------------------------------------------------------
//
//  System bus connection

always @(posedge clk)
if (reset) begin
	edgePoints	<= 0;
	qs			<= 0;
	ms			<= 0;
end else if (wen) begin

    for(i=0; i < nOfEdges; i = i + 1)begin
        if (addr==20'h100 + i*8)  {`q(i), `edgePoint(i)} <= wdata;
        if (addr==20'h104 + i*8)          `m(i)          <= wdata;
    end
end

wire en;
assign en = wen | ren;

always @(posedge clk)
if (reset) begin
    err <= 1'b0;
    ack <= 1'b0;
end else begin
    err <= 1'b0;
    ack <= en;  
    rdata <=  32'h0;
    for(i=0; i < nOfEdges; i = i + 1)begin
        if (addr==20'h100 + i*8)  rdata <= {`q(i), `edgePoint(i)};
        if (addr==20'h104 + i*8)  rdata <=         `m(i)         ;
    end
end


endmodule

module segmentedFunction_with_ramp#(
    parameter nOfEdges = 4,
    parameter totalBits_IO = 8,
    parameter fracBits_IO = 0,
    parameter totalBits_m = 2*totalBits_IO,
    parameter fracBits_m = totalBits_m-3,
    parameter areSignalsSigned = 1
)(
    input clk,
    input reset,
    output [totalBits_IO-1:0] out
);

reg [totalBits_IO-1:0] ramp_counter;

always @(posedge clk)
if (reset)
    ramp_counter <= 0;
else
    ramp_counter <= ramp_counter + 1;

segmentedFunction #(
    .nOfEdges(nOfEdges),
    .totalBits_IO(totalBits_IO),
    .fracBits_IO(fracBits_IO),
    .totalBits_m(totalBits_m),
    .fracBits_m(fracBits_m),
    .areSignalsSigned(areSignalsSigned)
) segFunc_inst (
    .clk(clk),
    .reset(reset),
    .in(ramp_counter),
    .out(out)
);

endmodule



/*
vsim work.segmentedFunction_with_ramp
add wave -position insertpoint sim:/segmentedFunction_with_ramp/*
add wave -position insertpoint sim:/segmentedFunction_with_ramp/segFunc_inst/*
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/reset z1 0
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/edgePoints 603080 0
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/qs f81080 0
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/ms 7ffff0001a00 0
run
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/reset 10 0
run 40ns
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/in C0 0
run
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/in 31 0
run
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/in 72 0
run
force -freeze sim:/segmentedFunction_with_ramp/segFunc_inst/in f7 0
run
run
run
run

*/