/*******************************************************************************
 *
 * Copyright(C) 2011-2012 ERC CISST, Johns Hopkins University.
 *
 * Module: MAX6576
 *
 * Purpose: Converts the output of a MAX6576 into temperature
 *
 * Theory of operation:
 *     The MAX6576 produces a square wave of ~50% duty cycle and a period
 *     proportional to the device temperature. The period is defined as
 *     10uS per degree K
 *
 *     The timekeeping is done in an 11 bit counter clocked at 400KHz.
 *     4 counts of this counter corresponds to 10uS or 1C.
 *
 *     When an edge is detected, the counter is initialized to 0x3BC,
 *     which corresponds to -273*4. In other words, it will require
 *     273*4 counts for the counter to overflow to 0.
 *
 *     When an edge is detected, the counter value is saved and reported
 *     as the result. If the counter value is less than 127*4 (0x1FC),
 *     then the value/2 is reported as the output. This results in each
 *     output bit corresponding to 0.5C. Since we know that the value is
 *     less than 127*4, the upper bits can be ignored and the result is
 *     guaranteed to fit in 8 bits.
 *
 *     If the register value is out of range, the output is reported
 *     as 0xFF
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     11/15/11    Paul Thienphrapa    Initial revision
 */

module Max6576(
    input wire clk400k,     // 400 kHz Clock
    input wire reset,       // global reset signal
    input wire In,          // PWM output of the MAX6576
    output reg[7:0] Out,    // Temperature in 0.5C per bit
    output reg change       // Indicates the temperature is changing
);

    reg[3:0] sync;          // Synchronization & edge detection register
    reg[10:0] count;        // Main counter

always @(posedge(clk400k) or negedge(reset))
begin
    if (reset == 0) begin
        Out <= 8'hFF;
        change <= 1'b0;
        sync <= 0;
        count <= 11'h3BC;
    end

    else begin
        sync <= { In, sync[3:1] };

        // signal change on edge detect or counter overflow
        if ((sync[1:0]==2'b10) || (count==10'h3B8))
            change <= 1'b1;
        else
            change <= 1'b0;

        // on change, output the counter value and reset it to -273*4
        if (change) begin
            count <= 11'h3BC;
            // output count/2 if count<127*4
            if (count[10:9] == 0)
                Out <= count[8:1];
            else
                Out <= 8'hFF;
        end
        else
            count <= count + 1'b1;
    end
end

endmodule
