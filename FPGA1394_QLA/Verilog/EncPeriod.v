/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2020 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock between encoder pulses.  Each new encoder pulse
 * latches the current count and starts a new one.  From this measurement the
 * encoder period can be obtained by multiplying the number of counts by the
 * period of the fixed fast clock.
 *
 * Initially, the fixed fast clock was ~3 MHz, but it is now sysclk (FireWire clock),
 * which is 49.152 MHz.
 *
 * Assumes counter will overflow if encoder moves too slowly.
 *
 * Revision history
 *     07/20/08    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Fix to use ticks+ as clock
 *     02/27/12    Paul Thienphrapa    Only count up due to unknown problem
 *     02/29/12    Zihan Chen          Fix implementation and debug module
 *     03/17/14    Peter Kazanzides    Update data every tick (dP = 4)
 *     04/07/17    Jie Ying Wu         Return only larger of cnter or cnter_latch
 *     10/19/17    Jie Ying Wu         Added acceleration estimation
 *     12/07/20    Peter Kazanzides    Return both cnter (free running counter) and cnter_latch
 *     12/16/20    Peter Kazanzides    Revised implementation
 */

// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuad(
    input wire clk,               // sysclk
    input wire a,                 // quad encoder line a
    input wire b,                 // quad encoder line b
    input wire dir,               // dir from EncQuad
    output wire[31:0] period,     // num of clock ticks since last edge of same type (full cycle)
    output wire[31:0] quarter1,   // [25:0] clock ticks in last quarter cycle
    output wire[31:0] quarter5,   // [25:0] clock ticks in quarter cycle 5 edges ago
    output wire[31:0] t_cur       // time since last edge
);

    reg[1:0] mux;  // Indicates most recent edge (a_up, a_dn, b_up, or b_dn)
    reg a_r;       // Previous value of A channel
    reg b_r;       // Previous value of B channel

    // Starting with Rev 7, all bits are sent to the higher-level module (and to the PC via FireWire).
    parameter width = 26;
    parameter overflow_value = 26'h3FFFFFF; // Maximum 26-bit value (overflow)

    // Queue of last 5 quarter cycles for acceleration and counter since last tick
    //    counter[0] -- free running counter
    //    counter[1] -- most recent latched counter (QTR1)
    //    counter[2] -- QTR2
    //    counter[3] -- QTR3
    //    counter[4] -- QTR4
    //    counter[5] -- oldest latched counter (QTR5)
    // If edges were not skipped and direction changes did not occur, then counter[5] and counter[1]
    // correspond to the latched counters for the same encoder events and can be used to estimate
    // acceleration.
    reg[width-1:0] counter[0:5];
    reg            counter0_overflow;   // whether counter[0] has overflowed
    reg[3:0]       flags[1:5];          // overflow, dir, mux

    localparam ovf_bit = 3,     // overflow bit in flags
               dir_bit = 2;     // direction bit in flags

initial begin
    counter[0] = overflow_value;
    counter[1] = overflow_value;
    counter[2] = overflow_value;
    counter[3] = overflow_value;
    counter[4] = overflow_value;
    counter[5] = overflow_value;
    counter0_overflow = 1'b1;
    flags[1] = 4'b1000;
    flags[2] = 4'b1000;
    flags[3] = 4'b1000;
    flags[4] = 4'b1000;
    flags[5] = 4'b1000;
end   
    
//------------------------------------------------------------------------------
// hardware description
//

localparam[1:0] a_up = 2'b00;
localparam[1:0] a_dn = 2'b10;
localparam[1:0] b_up = 2'b01;
localparam[1:0] b_dn = 2'b11;

reg [1:0] latched_mux;   // Previous value of mux
reg [1:0] next_edge;     // Next expected edge (not currently used)

reg mux_dir;             // Direction bit when mux updated
reg latched_dir;         // Latched direction bit

reg enc_init;            // Indicates that at least one encoder edge has occurred
reg latched_init;

initial begin
    enc_init = 0;
    latched_init = 0;
end

// Determine which edge is the most recent and sets mux (no longer a mux, but used
// to indicate the most recent edge). Could do some error checking here; for example,
// when the current edge is not equal to next_edge.
always @(posedge clk)
begin
    a_r <= a;
    b_r <= b;
    if (a & (~a_r)) begin        // a_up
        mux <= a_up;
        mux_dir <= dir;
        enc_init <= 1'b1;
        next_edge <= dir ? b_dn : b_up;
    end
    else if (b & (~b_r)) begin   // b_up
        mux <= b_up;    
        mux_dir <= dir;
        enc_init <= 1'b1;
        next_edge <= dir ? a_up : a_dn;
    end    
    else if ((~a) & a_r) begin   // a_dn
        mux <= a_dn;
        mux_dir <= dir;
        enc_init <= 1'b1;
        next_edge <= dir ? b_up : b_dn;
    end
    else if ((~b) & b_r) begin   // b_dn
        mux <= b_dn;
        mux_dir <= dir;
        enc_init <= 1'b1;
        next_edge <= dir ? a_dn : a_up;
    end
end

wire [width+1:0] sum;   // 28-bits for sum of 4 26-bit values
assign sum = counter[1]+counter[2]+counter[3]+counter[4];

// Indicates whether last 4 quarter-cycles were all in the same direction (all 0 or all 1).
// A 4-input NOR indicates whether all bits are 0 and a 4-input AND indicates whether all bits are 1.
wire dir_same;
assign dir_same =
  ~(flags[1][dir_bit] | flags[2][dir_bit] | flags[3][dir_bit] | flags[4][dir_bit]) |
   (flags[1][dir_bit] & flags[2][dir_bit] & flags[3][dir_bit] | flags[4][dir_bit]);

// Counts initial encoder edges (up to 4). This is useful for testing, so the test software can
// determine whether dir_same is valid (i.e., ignore if less than 4 edges have occurred).
reg[1:0] enc_cnt;

always @(posedge clk) begin

    latched_init <= enc_init;
    if ((latched_mux != mux) || (latched_init != enc_init)) begin
        // If a new edge has been detected, shift the queue and initialize the running counter
        // (check for latched_init != init handles first encoder edge).
        counter[0] <= 26'b1;
        counter0_overflow <= 1'b0;
        counter[1] <= counter0_overflow ? overflow_value : (counter[0]-26'b1);
        flags[1] <= {counter0_overflow, mux_dir, mux};
        counter[2] <= counter[1];
        flags[2] <= flags[1];
        counter[3] <= counter[2];
        flags[3] <= flags[2];
        counter[4] <= counter[3];
        flags[4] <= flags[3];
        counter[5] <= counter[4];
        flags[5] <= flags[4];
        latched_mux <= mux;
        // Update encoder counter (counts up to 4 edges)
        enc_cnt <= (enc_cnt == 2'd3) ? 2'd3 : (enc_cnt + 2'd1);
    end
    else if (counter[0] != overflow_value) begin
        // If not overflowed, increment free-running counter
        counter[0] <= counter[0] + 26'b1;
    end
    else begin
        // Indicate that overflow has occurred
        counter0_overflow <= 1'b1;
    end
end

assign t_cur =    {counter0_overflow, dir, enc_cnt, {28-width{1'b0}}, counter[0]};
assign quarter1 = {flags[1], {28-width{1'b0}}, counter[1]};
assign quarter5 = {flags[5], {28-width{1'b0}}, counter[5]};

// Last full-cycle period
// Set overflow bit if sum is greater than overflow_value; note that if any quarter-cycle period
// has overflowed, then sum will also overflow.
// Set direction bit based on most recent quarter-cycle direction (flags[1][dir_bit]),
// but also indicate if there was a direction change (~dir_same).
assign period = (sum > overflow_value) ?
                { 1'b1, flags[1][dir_bit], ~dir_same, {29-width{1'b0}}, overflow_value } :
                { 1'b0, flags[1][dir_bit], ~dir_same, {29-width{1'b0}}, sum[width-1:0] };

endmodule
