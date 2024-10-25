    `timescale 1ns / 1ps
    //////////////////////////////////////////////////////////////////////////////////
    // Company: 
    // Engineer: 
    // 
    // Create Date: 16.07.2024 09:52:59
    // Design Name: 
    // Module Name: fastSwitcher
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
    
    
    module fastSwitcher#(
        parameter maxPeriods = 255
    )(
        input clk,
        input reset,
        input trigger,
        input [$clog2(maxPeriods+1) -1:0] nOfPeriods,
        output reg out
    );
    reg [$clog2(maxPeriods+1) -1:0] counter;
        always @(posedge(clk))begin
            if(reset | !trigger)begin
                out <= 0;
                counter <= 0;
            end else begin
                if(counter)begin
                    counter <= counter - 1;
                end else begin
                    counter <= nOfPeriods - 1;
                    out <= !out;            
                end            
            end
        end
    endmodule
    
                
    module doubleFastSwitcher#(
        parameter maxPeriods = 255
    )(
        input clk,
        input reset,
        input trigger,
        input [$clog2(maxPeriods+1) -1:0] nOfPeriodsActive,
        input [$clog2(maxPeriods+1) -1:0] nOfPeriodsInactive,
        output reg out1,
        output reg out2
    );
    localparam  s_idle = 0,
                s_o1 = 1,
                s_deadTime = 3,
                s_o2 = 2;
    reg [1:0] state;
    reg [$clog2(maxPeriods+1) -1:0] counter;
        always @(posedge(clk))begin
            if(reset)begin
                state <= s_idle;
                counter <= 0;
                out1 <= 0;
                out2 <= 0;
            end else if(trigger) begin
                if(counter)begin
                    counter <= counter - 1;
                end else begin
                    if(state == s_o1 || state == s_o2)begin
                        counter <= nOfPeriodsInactive - 1;
                        out1 <= 0;
                        out2 <= 0;
                        state <= {state[0], state[0]};
                    end else begin
                        counter <= nOfPeriodsActive - 1;
                        out1 <= ! state[0];
                        out2 <= state[0];
                        state <= {state[0], !state[0]};                
                    end            
                end            
            end
        end
    endmodule
    
              
module doubleFastSwitcher_phased#(
    parameter maxPeriods = 255 * 2

)(
    input clk,
    input reset,
    input trigger,
    input [$clog2(maxPeriods+1) -1:0] nOfPeriodsActive,
    input [$clog2(maxPeriods+1) -1:0] nOfPeriodsInactive,
    input [$clog2(maxPeriods+1) -1:0] phase,//this value should be lower (in absolute 
                //value) than nOfPeriodsActive, but it can be both positive and negative
    output out1,
    output out2
);
    localparam  s_idle = 0,
                s_running = 1;
    localparam  s_deadTime21 = 0,
                s_o1 = 1,
                s_deadTime12 = 3,
                s_o2 = 2;
    reg [$clog2(maxPeriods+1) -1:0] prevActive, prevInactive, prevPhase;
    reg state;
    reg [1:0] outState[1:0];
    reg outs [1:0];
    assign out1 = outs[0];
    assign out2 = outs[1];
    
    integer i;
    reg [$clog2(maxPeriods+1) -1:0] counter[1:0];
    always @(posedge(clk))begin:main_state_machine
        prevActive <= nOfPeriodsActive;
        prevInactive <= nOfPeriodsInactive;
        prevPhase <= phase;
        if(reset)begin
            state <= s_idle;
            outState[0] <= s_deadTime21; outState[1] <= s_deadTime21;
            counter[0] <= 0;    counter[1] <= 0;
            outs[0] <= 1'b0;
            outs[1] <= 1'b0;
        end else if(trigger | state == s_idle) begin
            case (state)
                s_idle: begin
                    outState[0] <= s_o1;
                    outState[1] <= s_o2;
                    counter[0] <= nOfPeriodsActive - 1;
                    counter[1] <= nOfPeriodsActive + phase - 1;
                    if(trigger)begin
                        state <= s_running;
                        outs[0] <= 1'b1;
                        outs[1] <= 1'b0;
                    end else begin
                        state <= s_idle;
                        outs[0] <= 1'b0;
                        outs[1] <= 1'b0;
                    end
                end
                s_running: begin
                    if( prevActive != nOfPeriodsActive || 
                        prevInactive != nOfPeriodsInactive || 
                        phase != prevPhase)begin
                        //reset the machine to use the new values
                        state <= s_idle;
                    end else begin
                        for(i=0;i<2;i=i+1)begin
                            if(counter[i])begin
                                counter[i] <= counter[i] - 1;
                            end else begin
                                if(outState[i] == s_o1 || outState[i] == s_o2)begin
                                    counter[i] <= nOfPeriodsInactive - 1;
                                    outs[i] <= 0;
                                    outState[i] <= {outState[i][0], outState[i][0]};
                                end else begin
                                    counter[i] <= nOfPeriodsActive - 1;
                                    outs[i] <= ! outState[i][0];
                                    outState[i] <= {outState[i][0], !outState[i][0]};                
                                end            
                            end 
                        end 
                    end
                end
                default : state <= s_idle;
            endcase          
        end else begin
            state <= s_idle;
        end
    end
    
endmodule

//the first and last active time of this switch is half the time of the normal active states. 
    //These half states are performed by the same output (out1), and since the procedure has 
    //to finish the last part correctly, the disabling of the trigger will be seen only when 
    //the procedure can actually finish 
module doubleFastSwitcher_HalfStart#(
    parameter maxPeriods = 255 * 2
)(
    input clk,
    input reset,
    input trigger,
    input [$clog2(maxPeriods+1) -1:0] nOfPeriodsActive,
    input [$clog2(maxPeriods+1) -1:0] nOfPeriodsInactive,
    input [$clog2(maxPeriods+1) -1:0] phase,//this value should be lower (in absolute 
                //value) than nOfPeriodsActive, but it can be both positive and negative
    output out1,
    output out2
);
    localparam  s_idle = 0,
                s_running = 1;
    localparam  s_deadTime21 = 0,
                s_o1 = 1,
                s_deadTime12 = 3,
                s_o2 = 2;
    reg [$clog2(maxPeriods+1) -1:0] prevActive, prevInactive, prevPhase;
    reg state;
    reg [1:0] outState[1:0];
    reg outs [1:0];
    assign out1 = outs[0];
    assign out2 = outs[1];
        
    integer i;
    reg [$clog2(maxPeriods+1) -1:0] counter[1:0];
    wire [$clog2(maxPeriods+1) -1:0] halfPeriodsActive = (nOfPeriodsActive-1) >> 1;
    //the transmission can end when out1 is at half of its active state
    wire atHalfOf_o1 = (outState[0] == s_o1) && (counter[0] == halfPeriodsActive + 1);
    
    always @(posedge(clk))begin:main_state_machine
        prevActive <= nOfPeriodsActive;
        prevInactive <= nOfPeriodsInactive;
        prevPhase <= phase;
        if(reset)begin
            state <= s_idle;
            outState[0] <= s_deadTime21; outState[1] <= s_deadTime21;
            counter[0] <= 0;    counter[1] <= 0;
            outs[0] <= 1'b0;
            outs[1] <= 1'b0;
        end else begin
            case (state)
                s_idle: begin
                    outState[0] <= s_o1;
                    outState[1] <= s_o2;
                    counter[0] <= halfPeriodsActive;//let's do only half a period
                    counter[1] <= halfPeriodsActive + phase;
                    if(trigger)begin
                        state <= s_running;
                        outs[0] <= 1'b1;
                        outs[1] <= 1'b0;
                    end else begin
                        state <= s_idle;
                        outs[0] <= 1'b0;
                        outs[1] <= 1'b0;
                    end
                end
                s_running: begin
                    //reset the machine if:
                    if( prevActive != nOfPeriodsActive || //use new values
                        prevInactive != nOfPeriodsInactive || 
                        phase != prevPhase ||
                        atHalfOf_o1 && !trigger //the trigger is low and the toggling can end right now
                       )begin
                        //reset the machine to use the new values
                        state <= s_idle;
                        outs[0] <= 1'b0;
                        outs[1] <= 1'b0;
                    end else begin
                        for(i=0;i<2;i=i+1)begin
                            if(counter[i])begin
                                counter[i] <= counter[i] - 1;
                            end else begin
                                if(outState[i] == s_o1 || outState[i] == s_o2)begin
                                    counter[i] <= nOfPeriodsInactive - 1;
                                    outs[i] <= 0;
                                    outState[i] <= {outState[i][0], outState[i][0]};
                                end else begin
                                    counter[i] <= nOfPeriodsActive - 1;
                                    outs[i] <= ! outState[i][0];
                                    outState[i] <= {outState[i][0], !outState[i][0]};                
                                end            
                            end 
                        end 
                    end
                end
                default : state <= s_idle;
            endcase          
        end
    end
    
endmodule
