/*******************************************************************************
 *
 * Copyright(C) 2008-2017 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock (~3 MHz) between encoder pulses.  Each new encoder pulse
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
 *     03/17/14    Peter Kazanzides    Update data every tick (dP = 4)
 *     04/07/17    Jie Ying Wu         Return only larger of cnter or cnter_latch
 */

module EncPeriodSingle(
   input wire clk_fast,      // count this clock between encoder ticks
   input wire reset,         // global reset signal
   input wire ticks,         // encoder transition signal
   input wire dir,           // direction of the ticks
   output wire ticks_en,     // edge signal
   output reg[21:0] latched, // latched counter from last encoder event
   output reg[21:0] count,   // number clk_fast periods per tick
   output reg dir_changed
);

    // overflow value for unsigned 22-bit number
    parameter overflow = 22'h3FFFFF;


//------------------------------------------------------------------------------
// hardware description
//

// convert ticks to pulse
reg dir_r;      // dir start 
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);

always @(posedge clk_fast)
begin
   ticks_r <= ticks;
   dir_r <= dir;
end

// latch counter value
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0) begin
        latched <= 22'd0;
    end
    else begin
        latched <= count;
    end
end

// free-running counter 
always @(posedge clk_fast or posedge ticks_en or negedge reset) 
begin
   if (reset == 0 || ticks_en) begin
      count <= 22'd0;
      dir_changed <= 0;
   end
   else if (dir != dir_r) begin
      count <= overflow;
      dir_changed <= 1;
   end
   else if (count != overflow) begin
      count <= count + 1;
   end
end

endmodule


// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuadSingle(
    input wire clk,           // sysclk
    input wire clk_fast,      // count this clock between encoder ticks
    input wire reset,         // global reset signal
    input wire a,             // quad encoder line a
    input wire b,             // quad encoder line b
    input wire dir,           // dir from EncQuad
    output reg[31:0] period   // num of fast clock ticks
);
    wire a_up_tick;
    wire[21:0] a_up_latched;   // channel a up latched value
    wire[21:0] a_up_counter;   // channel a up free running counter
    wire a_up_dir_changed;

//------------------------------------------------------------------------------
// hardware description
//
EncPeriodSingle EncPerUpA(clk_fast, reset,  a, dir, a_up_tick, a_up_latched, a_up_counter, a_up_dir_changed);

// The following code returns the larger of (1) the most recent latched value (determined by mux)
// or (2) the free-running counter for the next expected encoder transition, based on direction, dir.
// Note that a direction change sets the free-running counter to overflow, so that will take priority
// over the latched value, which is reasonable behavior (i.e., a recent direction change should result
// in an estimated velocity of 0).
// From EncQuad.v:
//   dir 0 is A leading B  (cycle is Aup -> Bup -> Adown -> Bdown)
//   dir 1 is B leading A  (cycle is Bup -> Aup -> Bdown -> Adown)
always @(posedge clk_fast or negedge reset) begin
   if (reset == 0) begin
      period <= 32'd0;
   end else begin
   if (a_up_counter >= a_up_latched) begin
      period <= {1'b0, dir, a_up_dir_changed, 1'b0, 5'd0, a_up_counter};
   end else begin
      period <= {1'b1, dir, a_up_dir_changed, 1'b0, 5'd0, a_up_latched};
   end
   end
end

endmodule
