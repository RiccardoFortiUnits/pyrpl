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
    

/*
implemented process:
optical tweezer turned off (by default its always on)
delay
PI pulse, to move the atoms to the excited state
delay
blast pulse, to push away the atoms that decayed to the ground state. The blast laser is one the fastSwitch ones, which is used for both processes
delay
tweezers turned on again
*/
    
module tweezer_pi_blast#(
    parameter maxSmallTimes = 255,
    parameter maxLongTimes = 2_000_000
)(
    input clk,
    input reset,
    input trigger,
    input [$clog2(maxLongTimes+1) -1:0] nOfPeriods_inactive_TweezerPi,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_pi,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_inactive_PiBlast,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_blast,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_inactive_BlastTweezer,
    output reg tweezer,
    output reg pi,
    output reg blast,
    output reg running
);

wire cleanTrigger;
triggerCleaner_hold_n_release#(
    .nOfInhibitionCycles(125)//1e-6s
)tc(
    .clk	(clk),
    .reset	(reset),
    .in		(trigger),
    .out	(cleanTrigger)
);

    localparam  s_idle = 0,
                s_inactive_TweezerPi = 1,
                s_pi = 2,
                s_inactive_PiBlast = 3,
                s_blast = 4,
                s_inactive_BlastTweezer = 5;

    reg [$clog2(maxSmallTimes+1) -1:0] prev_pi, prev_inactive_PiBlast, prev_blast, prev_inactive_BlastTweezer;
    reg [$clog2(maxLongTimes+1) -1:0] prev_inactive_TweezerPi;
    reg [2:0] state;
        
    reg [$clog2(maxLongTimes+1) -1:0] counter;
    
    `define resetAllOutputs \
        tweezer <= 1;     \
        pi <= 0;          \
        blast <= 0;       \
        running <= 0;     \
        counter <= 0;
    `define timedState(tweezerValue, piValue, blastValue, finalTime, nextState)\
        tweezer <= tweezerValue;                \
        pi <= piValue;                          \
        blast <= blastValue;                    \
        if(counter >= finalTime)begin            \
            state <= nextState;                 \
            counter <= 0;                       \
        end

    always @(posedge(clk))begin:main_state_machine
        if(reset)begin
            `resetAllOutputs
            state <= s_idle;
        end else begin
            if(state != s_idle)begin
                counter <= counter + 1;
                running <= 1;
            end else begin				
				prev_inactive_TweezerPi <= nOfPeriods_inactive_TweezerPi - 1;
				prev_pi <= nOfPeriods_pi - 1;
				prev_inactive_PiBlast <= nOfPeriods_inactive_PiBlast - 1;
				prev_blast <= nOfPeriods_blast - 1;
				prev_inactive_BlastTweezer <= nOfPeriods_inactive_BlastTweezer - 1;
                counter <= 0;
                running <= 0;
            end
            case(state)
                s_idle: begin
                    `resetAllOutputs
                    if(cleanTrigger)begin
                        state <= s_inactive_TweezerPi;
                    end
                end
                s_inactive_TweezerPi: begin
                    `timedState(0,0,0,prev_inactive_TweezerPi, s_pi)
                end
                s_pi: begin
                    `timedState(0,1,0,prev_pi, s_inactive_PiBlast)
                end
                s_inactive_PiBlast: begin
                    `timedState(0,0,0,prev_inactive_PiBlast, s_blast)
                end
                s_blast: begin
                    `timedState(0,0,1,prev_blast, s_inactive_BlastTweezer)
                end
                s_inactive_BlastTweezer: begin
                    `timedState(0,0,0,prev_inactive_BlastTweezer, s_idle)
                end
                default : state <= s_idle;
            endcase          
        end
    end
    
endmodule



/*
force -freeze sim:/tweezer_pi_blast/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/tweezer_pi_blast/reset z1 0
force -freeze sim:/tweezer_pi_blast/trigger z0 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_inactive_TweezerPi 4 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_pi 2 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_inactive_PiBlast 3 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_blast 2 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_inactive_BlastTweezer 5 0
run
run
run
force -freeze sim:/tweezer_pi_blast/reset 00 0
run
run
force -freeze sim:/tweezer_pi_blast/trigger 01 0
run
force -freeze sim:/tweezer_pi_blast/trigger 0 0
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