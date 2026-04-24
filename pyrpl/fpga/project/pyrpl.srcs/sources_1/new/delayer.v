`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.04.2026 10:46:42
// Design Name: 
// Module Name: delayer
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


module delayer#(
	parameter 	data_size = 8,
				nOfDelays = 3
)(
    input clk,
	input reset,
	input [data_size -1:0] newValue,	
	output [data_size -1:0] delayedValue	
);
reg [data_size -1:0] delays[nOfDelays -1:0];
integer i;
always @(posedge clk) begin
	if (reset) begin
		for(i=0;i<nOfDelays;i=i+1)begin
			delays[i] <= 0;
		end
	end else begin
		for(i=1;i<nOfDelays;i=i+1)begin
			delays[i] <= delays[i-1];
		end
		delays[0] <= newValue;		
	end
end
assign delayedValue = delays[nOfDelays-1];
endmodule

module delayer_withIntermediateSet#(
	parameter 	data_size = 8,
				nOfDelays = 3,
				intermediateIndex = nOfDelays/2
)(
    input clk,
	input reset,
	input [data_size -1:0] newValue,
	input setFromIntermediateIndex,	
	output [data_size -1:0] delayedValue	
);

reg [data_size -1:0] delays[nOfDelays -1:0];

integer i;
always @(posedge clk) begin
	if (reset) begin
		for(i=0;i<nOfDelays;i=i+1)begin
			delays[i] <= 0;
		end
	end else begin
		if (setFromIntermediateIndex) begin
			for(i=0;i<=intermediateIndex;i=i+1)begin
				delays[i] <= newValue;
			end
			for(i=intermediateIndex+1;i<nOfDelays;i=i+1)begin
				delays[i] <= delays[i-1];
			end		
		end else begin			
			for(i=1;i<nOfDelays;i=i+1)begin
				delays[i] <= delays[i-1];
			end
			delays[0] <= newValue;
		end		
	end
end

assign delayedValue = delays[nOfDelays-1];
endmodule
