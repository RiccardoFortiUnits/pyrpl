

module FractionalMultiplier #(parameter A_WIDTH = 16,
                              parameter B_WIDTH = 16,
                              parameter OUTPUT_WIDTH = 16,
                              parameter FRAC_BITS_A = 4,
                              parameter FRAC_BITS_B = 4,
                              parameter FRAC_BITS_OUT = 8) (
  input wire signed [A_WIDTH-1:0] a,
  input wire signed [B_WIDTH-1:0] b,
  output wire signed [OUTPUT_WIDTH-1:0] result
);
  wire signed [A_WIDTH + B_WIDTH - 1:0] full_aByb;
 
  assign full_aByb = $signed(a) * $signed(b);
  
  assign result = full_aByb[OUTPUT_WIDTH - 1 + FRAC_BITS_A + FRAC_BITS_B - FRAC_BITS_OUT: 
                                               FRAC_BITS_A + FRAC_BITS_B - FRAC_BITS_OUT];

endmodule

module clocked_FractionalMultiplier #(
          parameter A_WIDTH = 16,
          parameter B_WIDTH = 16,
          parameter OUTPUT_WIDTH = 16,
          parameter FRAC_BITS_A = 4,
          parameter FRAC_BITS_B = 4,
          parameter FRAC_BITS_OUT = 8,
          parameter areSignalsSigned = 1) (
  input wire clk,
  input wire signed [A_WIDTH-1:0] a,
  input wire signed [B_WIDTH-1:0] b,
  output wire signed [OUTPUT_WIDTH-1:0] result
);
reg signed [A_WIDTH + B_WIDTH - 1:0] full_aByb;

generate
    if(areSignalsSigned)begin
        always @(posedge clk)
            full_aByb <= $signed(a) * $signed(b);
    end else begin
        always @(posedge clk)
            full_aByb <= $unsigned(a) * $unsigned(b);
        
    end

endgenerate

assign result = full_aByb[OUTPUT_WIDTH - 1 + FRAC_BITS_A + FRAC_BITS_B - FRAC_BITS_OUT: 
                                               FRAC_BITS_A + FRAC_BITS_B - FRAC_BITS_OUT];


//sadly, MULT_MACRO only works with inputs up to 18 bita...
//  wire signed [A_WIDTH + B_WIDTH - 1:0] full_aByb;
 
// MULT_MACRO #(
//   .DEVICE("7SERIES"), // Target Device: "7SERIES"
//   .LATENCY(0),        // Desired clock cycle latency, 0-4
//   .WIDTH_A(A_WIDTH),       // Multiplier A-input bus width, 1-25
//   .WIDTH_B(B_WIDTH)        // Multiplier B-input bus width, 1-18
//) MULT_MACRO_inst (
//   .P(full_aByb),     // Multiplier output bus, width determined by WIDTH_P parameter
//   .A(a),     // Multiplier input A bus, width determined by WIDTH_A parameter
//   .B(b),     // Multiplier input B bus, width determined by WIDTH_B parameter
//   .CE(1),   // 1-bit active high input clock enable
//   .CLK(clk), // 1-bit positive edge clock input
//   .RST(0)  // 1-bit input active high reset
//);

endmodule
