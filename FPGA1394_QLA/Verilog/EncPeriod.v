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
 * Assumes counter will overflow if encoder moves too slowly.
 *
 * Revision history
 *     07/20/08    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Fix to use ticks+ as clock
 *     02/27/12    Paul Thienphrapa    Only count up due to unknown problem
 *     02/29/12    Zihan Chen          Fix implementation and debug module
 */

module EncPeriod(clk_fast, reset, ticks, dir, count);

    // define I/Os
    input clk_fast;           // count this clock between encoder ticks
    input reset;              // global reset signal
    input ticks;              // encoder transition signal
    input dir;                // direction of the ticks
    output[15:0] count;       // number clk_fast periods per tick

    // local registers
    reg[15:0] count;          // latched counter measurement
    reg[15:0] count_temp;     // register for counter
    reg[15:0] count_2;        // intermediate count register
//    reg[15:0] count_prev;     // previous count register

    // overflow value for signed 16-bit number
    parameter overflow = 16'h7FFF;

// When motor stops use use 7FFF as output
always @(posedge clk_fast)
begin
    if (count_temp != overflow)
        count <= count_2;
    else if (dir)
        count <= overflow;
    else
        count <= 16'h8000;
end


// Convert ticks to pulse
reg ticks_r;    // previous ticks
wire ticks_en = ticks & (~ticks_r);
always @(posedge clk_fast)
begin
    ticks_r <= ticks;
end

// Latch count value to count_2
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0)
        count_2 <= 16'd0;
    else
        count_2 <= count_temp;
end

// up/down counter to measure period between encoder ticks
always @(posedge ticks_en or posedge clk_fast)
begin
    if (ticks_en)
        count_temp <= 16'd0;
    else if (count_temp != overflow)
        count_temp <= count_temp + (dir ? 1'b1 : -1'b1);
end

endmodule
