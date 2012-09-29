/*******************************************************************************
 *
 * Copyright(C) 2008-2012 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock (~1 MHz) between encoder pulses.  Each new encoder pulse
 * latches the current count and starts a new one.  From this measurement the
 * encoder period can be obtained by multiplying the number of counts by the
 * period of the fixed fast clock.
 * 
 * This module blablabal measures enc acceleration
 *
 * Revision history
 *     03/01/12    Zihan Chen          Initial revision
 */


module EncAcc(clk, reset, period, acc1, acc2, scur);

    // define I/Os 
    input clk;                // sysclk
    input reset;              // global reset signal
    input[15:0] period;       // period form EncPeriod
    output[15:0] acc1;        // speed count 1
    output[15:0] acc2;        // speed count 2
    output[15:0] scur;        // sync cur value

    // local reg or wire
    // reg[15:0] count;
    reg[15:0] acc1;
    reg[15:0] acc2;
    reg[15:0] scur;
    
/*
// assign constant value for test
always @(posedge clk or negedge reset)
begin
    if (reset == 0)
        count <= 16'd0;
    else
        count <= 16'h0123;
end
*/

// latch period value
always @(posedge clk or negedge reset)
begin
    if (reset == 0)
        acc1 <= 16'd0;
    else
        acc1 <= period;
end

// latch prev period value
always @(posedge clk or negedge reset)
begin
    if (reset == 0)
        acc2 <= 16'd0;
    else
        acc2 <= acc1;
end


// latch sync motor cur value
always @(posedge clk or negedge reset)
begin
    if (reset == 0)
        scur <= 16'd0;
    else
        scur <= 16'h5432;
end



endmodule
