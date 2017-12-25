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

module EncPeriod(
   input wire clk,      // count this clock between encoder ticks
   input wire reset,         // global reset signal
   input wire ticks,         // encoder transition signal
   output wire ticks_en      // edge signal
);

//------------------------------------------------------------------------------
// hardware description
//

// convert ticks to pulse
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);

always @(posedge clk)
begin
   ticks_r <= ticks;
end

endmodule


// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuad(
    input wire clk,           // sysclk
    input wire reset,         // global reset signal
    input wire a,             // quad encoder line a
    input wire b,             // quad encoder line b
    input wire dir,           // dir from EncQuad
    output reg[31:0] period,  // num of fast clock ticks
    output reg[31:0] acc,    // [31:16] time since last edge, [15:0] estimated acc
    output wire[31:0] t_cur   // time since last edge
);

    reg[1:0] mux;
    wire a_up_tick;
    wire a_dn_tick;
    wire b_up_tick;
    wire b_dn_tick;

    // overflow value for unsigned 22-bit number
    parameter width = 26;
    parameter comm_overflow = 20'hFFFFF;
    parameter small_overflow = 24'hFFFFFF;  // Has probably not stopped completely but is larger than bandwidth
    parameter overflow_value = 26'h3FFFFFF; // Has probably stopped completely

//Keep track of last 2 periods for acceleration and counter since last tick
reg[width-1:0] counter [1:5];
    
initial begin
    counter[1] = overflow_value;
    counter[2] = overflow_value;
    counter[3] = overflow_value;
    counter[4] = overflow_value;
    counter[5] = overflow_value;
end   
    
//------------------------------------------------------------------------------
// hardware description
//

EncPeriod EncPerUpA(clk, reset,  a, a_up_tick);
EncPeriod EncPerDnA(clk, reset, ~a, a_dn_tick);
EncPeriod EncPerUpB(clk, reset,  b, b_up_tick);
EncPeriod EncPerDnB(clk, reset, ~b, b_dn_tick);

localparam[1:0] a_up = 2'b00;
localparam[1:0] a_dn = 2'b10;
localparam[1:0] b_up = 2'b01;
localparam[1:0] b_dn = 2'b11;

reg [1:0] latched_mux;
reg [1:0] next_edge;
reg seen;

// Determine which edge is the most recent
always @(posedge clk)
begin
    if (a_up_tick) begin
        mux <= a_up;
        next_edge <= dir ? b_dn : b_up;
    end
    else if (b_up_tick) begin
        mux <= b_up;    
        next_edge <= dir ? a_up : a_dn;
    end    
    else if (a_dn_tick) begin
        mux <= a_dn;
        next_edge <= dir ? b_up : b_dn;
    end
    else if (b_dn_tick) begin
        mux <= b_dn;
        next_edge <= dir ? a_dn : a_up;
    end

end

wire latch_overflow;
wire [width+1:0] sum;
assign sum = counter[1]+counter[2]+counter[3]+counter[4];
assign latch_overflow = (counter[2] == overflow_value) || (counter[3] == overflow_value) 
                        || (counter[4] == overflow_value) || (counter[5] == overflow_value);

always @(posedge clk or negedge reset) begin
    if (reset == 0) begin
        counter[1] <= overflow_value;
        counter[2] <= overflow_value;
        counter[3] <= overflow_value;
        counter[4] <= overflow_value;
        counter[5] <= overflow_value;
        seen       <= 0;
        latched_mux <= mux;
    end else begin 
        if ((latched_mux != mux) && ~seen) begin
            counter[1] <= 0;
            counter[2] <= counter[1];
            counter[3] <= counter[2];
            counter[4] <= counter[3];
            counter[5] <= counter[4];
            seen <= 1;
            latched_mux <= mux;
            
            // Full cycle period
            if (sum > overflow_value) begin
                period[31] <= 1;
                period[21:0] <= overflow_value[width-1:4];
            end else begin
                period[31] <= 0;
                period[21:0] <= sum[width-1:4];
            end

            // Part of Recent counter for acceleration 
            if (counter[1] > small_overflow) begin
                period[30:22] <= {dir, comm_overflow[7:0]};
                acc[31:20] <= comm_overflow[19:8];
            end else begin
                period[30:22] <= {dir, counter[1][11:4]};
                acc[31:20] <= counter[1][23:12];
            end

            // Prev counter for acceleration
            if (counter[5] > small_overflow) begin
                acc[19:0] <= comm_overflow;
             end else begin
                acc[19:0] <= counter[5][23:4];
             end
             
        end else if (counter[1] != overflow_value) begin
            counter[1] <= counter[1] + 26'b1;
            if (counter[1] >= counter[5]) begin
                period[30] <= dir;
                if (sum > overflow_value) begin
                    period[31] <= 1;
                    period[21:0] <= overflow_value[width-1:4];
                end else begin
                    period[31] <= 0;
                    period[21:0] <= sum[width-1:4];
                end
            end
            seen <= 0;
        end else begin
            period[31] <= 1;
        end
    end
end

//Should overflow more values
assign t_cur = {6'b0, seen, latch_overflow, latched_mux, mux, counter[1][23:4]};
endmodule
