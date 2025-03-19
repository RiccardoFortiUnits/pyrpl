module fixedPointShifter#(
	parameter inputBitSize = 8,
	parameter inputFracSize = 4,
	parameter outputBitSize = 8,
	parameter outputFracSize = 6,
	parameter isSigned = 1,
	parameter saturateOutput = 1//useful only if the output whole part is smaller than the input whole part
)(
	input [inputBitSize-1:0] in,
	output [outputBitSize-1:0] out
);
//move a fixed-point number to another with different sizes and decimal point position
//for now, there is no saturation (es: 0x52.3 shifted into a Q4.4 will become 0x2.3)
	localparam 	inputWholeSize = inputBitSize - inputFracSize,
				outputWholeSize = outputBitSize - outputFracSize;
				
wire [outputBitSize-1:0] out_unsaturated;
generate
//fractional part
	if(outputFracSize <= inputFracSize)begin
		if(outputFracSize > 0)begin
			assign out_unsaturated[outputFracSize-1:0] = in[inputFracSize -1-:outputFracSize];
		end
	end else begin
		if(inputFracSize > 0)begin
			assign out_unsaturated[outputFracSize -1-:inputFracSize] = in[inputFracSize -1:0];
		end
		assign out_unsaturated[outputFracSize-inputFracSize -1:0] = 0;
	end
//whole part
	if(outputWholeSize <= inputWholeSize)begin
		if(outputWholeSize > 0)begin
			assign out_unsaturated[outputBitSize -1:outputFracSize] = in[inputFracSize+outputWholeSize -1:inputFracSize];
		end
	end else begin
		if(inputWholeSize > 0)begin
			assign out_unsaturated[inputWholeSize+outputFracSize -1-:inputWholeSize] = in[inputBitSize -1:inputFracSize];
		end
		if(isSigned)begin
			assign out_unsaturated[outputBitSize -1-:outputWholeSize-inputWholeSize] = {(outputWholeSize-inputWholeSize){in[inputBitSize -1]}};
		end else begin
			assign out_unsaturated[outputBitSize -1-:outputWholeSize-inputWholeSize] = {(outputWholeSize-inputWholeSize){1'b0}};
		end
	end

	if(saturateOutput & outputWholeSize < inputWholeSize)begin
		wire isSaturated = 	((in[inputBitSize-1]) & ~(&in[inputBitSize-1 -1-:inputWholeSize-outputWholeSize])) |
									((~in[inputBitSize-1]) & (|in[inputBitSize-1 -1-:inputWholeSize-outputWholeSize]));
		assign out = isSaturated ? {in[inputBitSize-1], {(outputBitSize - 1){~in[inputBitSize-1]}}} : out_unsaturated;
	end else begin
		assign out = out_unsaturated;
	end

endgenerate	
endmodule