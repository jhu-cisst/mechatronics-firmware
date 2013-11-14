/*******************************************************************************
 *
 * Copyright(C) 2009-2011 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse frequency by counting encoder edges
 * within a fixed slow clock (~12 Hz) period.  Each new slow clock latches the
 * current count and starts a new one.  From this measurement the encoder
 * frequency can be obtained by dividing the number of counts by the period of
 * the fixed slow clock.
 *
 * Assumes counter is large enough to never overflow.
 *
 * Revision history
 *     04/10/09    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Fix to use clk_slow+ as clock (~12 Hz)
 *     02/29/12    Zihan Chen          Fix constant 0 problem // Add sysclk
 */

module EncFreq(sysclk, clk_slow, reset, ticks, dir, count);

    // define I/Os
    input sysclk;             // sysclk 49.152 MHz
    input clk_slow;           // intervals to count encoder ticks
    input reset;              // global reset signal
    input ticks;              // encoder transition signal, to be counted
    input dir;                // direction of the ticks
    output[15:0] count;       // number ticks per clk_slow period

    // local registers
    reg[15:0] count;          // latched counter measurement
    reg[15:0] count_temp;     // register for counter

    // overflow value for signed 16-bit number
    parameter overflow = 16'h7FFF;
    

// convert clk_slow to pulse
reg clk_slow_prev;
wire clk_slow_en = clk_slow & (~clk_slow_prev);
always @(posedge sysclk) begin
    clk_slow_prev <= clk_slow;
end

// convert ticks to pulse
reg ticks_prev;
wire ticks_en = ticks & (~ticks_prev);
always @(posedge sysclk) begin
    ticks_prev <= ticks;
end

// latch counter at each clk_slow counting period
always @(posedge clk_slow_en or negedge reset)
begin
    if (reset == 0)
        count <= 0;
    else
        count <= count_temp;
end

// up/down counter for No. of enc ticks, reset at each slow clk period
always @(posedge sysclk)
begin
    if (clk_slow_en)
        count_temp <= 0;
    else if (ticks_en && count_temp != overflow)
        count_temp <= count_temp + (dir ? 16'd1 : -16'd1);
end

endmodule
