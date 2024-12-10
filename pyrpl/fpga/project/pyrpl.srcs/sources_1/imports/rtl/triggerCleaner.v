`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.06.2024 16:09:04
// Design Name: 
// Module Name: triggerCleaner
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


module triggerCleaner#(
    parameter nOfInhibitionCycles = 125//1e-6s
)(
    input clk,
    input reset,
    input in,
    output out
);
reg [$clog2(nOfInhibitionCycles+1)-1:0] inhibitionCounter;

localparam  s_idle = 0,
            s_active = 1,
            s_inhibit = 2;
reg [1:0] state;
reg in_r;
reg out_r;     // Register for trigger output
reg prev_out_r;     // Register for trigger output

always @(negedge clk) begin
    if(reset)begin
        inhibitionCounter <= 0;
        state <= s_idle;
        out_r <= 0;
        prev_out_r <= 0;
        in_r <= 0;
    end else begin
        prev_out_r <= out_r;
        in_r <= in;
        case (state)
            s_idle: begin
                if (in_r) begin
                    state <= s_active;  // Transition to active state
                    out_r <= 1'b1;
                end
            end
            s_active: begin
                out_r <= 1'b0;
                state <= s_inhibit;      // Transition to inhibit state
                inhibitionCounter <= nOfInhibitionCycles;
            end
            s_inhibit: begin
                out_r <= 1'b0;
                if(inhibitionCounter)begin
                    inhibitionCounter <= inhibitionCounter - 1;
                end else if (!in_r)begin
                    state <= s_idle;  // Transition back to idle state
                end
            end
        endcase
    end
end

assign out = out_r & !prev_out_r;//somehow, there are still times where 2 
        //consecutive cycles are outputed. Let's just reject them with a second trigger cleaner
        
endmodule

module triggerCleaner_hold_n_release#(
    parameter nOfInhibitionCycles = 125//1e-6s
)(
    input clk,
    input reset,
    input in,
    output reg out
);
reg [$clog2(nOfInhibitionCycles+1)-1:0] inhibitionCounter;

localparam  s_idle_0 = 0,
            s_inhibit_1 = 1,
            s_inhibit_0 = 2,
            s_idle_1 = 3;
reg [1:0] state;
reg in_r;

always @(negedge clk) begin
    if(reset)begin
        inhibitionCounter <= 0;
        state <= s_idle_0;
        out <= 0;
        in_r <= 0;
    end else begin
        in_r <= in;
        if(state == s_idle_0)begin
            if (in_r) begin
                state <= s_inhibit_1;  // Transition to active state
                inhibitionCounter <= nOfInhibitionCycles;
                out <= 1;
            end
        end else if(state == s_idle_1)begin
            if (!in_r) begin
                state <= s_inhibit_0;  // Transition to inactive state
                inhibitionCounter <= nOfInhibitionCycles;
                out <= 0;
            end
        end else begin
            if(inhibitionCounter)begin
                inhibitionCounter <= inhibitionCounter - 1;
            end else begin
                state <= state == s_inhibit_1 ? s_idle_1 : s_idle_0;  // Transition back to idle state
                state <= state == s_inhibit_1 ? s_idle_1 : s_idle_0;  // Transition back to idle state
            end
        end
    end
end

endmodule
