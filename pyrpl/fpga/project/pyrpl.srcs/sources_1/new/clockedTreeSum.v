`timescale 1ns / 1ps

module clockedTreeSum #(
	parameter dataSize = 8,
	parameter nOfInputs = 8
)
(
   // signals
   input                 clk,
   input                 reset,
   input [dataSize * nOfInputs -1:0] ins,
   output [dataSize + $clog2(nOfInputs) -1:0] out
);

localparam logNI = $clog2(nOfInputs);
localparam totInputs = 1 << logNI;

wire [dataSize + logNI -1:0] extendedIns [totInputs -1:0];

generate
	genvar gi;
	for(gi=0;gi<nOfInputs;gi=gi+1)begin
		assign extendedIns[gi] = {{logNI{ins[(gi+1)*dataSize-1]}}, ins[(gi+1)*dataSize -1-:dataSize]};
	end
	for(gi=nOfInputs;gi<totInputs;gi=gi+1)begin
		assign extendedIns[gi] = 0;
	end
endgenerate

reg [dataSize + logNI -1:0] sums [totInputs-1 -1:0];

integer i;

always @(posedge clk) begin
	if(reset) begin
		for(i=0;i<totInputs - 1;i=i+1)begin
			sums[i] <= 0;
		end
	end else begin
		for(i=0;i<totInputs>>1;i=i+1)begin
			sums[i] <= extendedIns[(i<<1)] + extendedIns[(i<<1) + 1];
		end
		for(i=0;i<(totInputs>>1) - 1;i=i+1)begin
			sums[(totInputs>>1)+i] <= sums[(i<<1)] + sums[(i<<1) + 1];
		end
	end
end
assign out = sums[totInputs - 1 - 1];
endmodule



