/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2025 ERC CISST, Johns Hopkins University.
 *
 * This module decodes a pair of quadrature encoder inputs, a and b, analyzing
 * them via a state machine and outputting transition ticks and direction flag.
 * Assumes a and be are already synced to clk.
 *
 * Revision history
 *     07/20/08    Paul Thienphrapa    Initial revision
 *     11/16/11    Paul Thienphrapa    Infer (instead of instantiate) counter
 *     02/21/12    Paul Thienphrapa    Change problematic direction flag issue
 *     02/29/12    Zihan Chen          Fix direction flag in updated logic
 */

`include "Constants.v"

module EncQuad(
    input wire clk,              // global clock
    input wire a,                // quad encoder line a
    input wire b,                // quad encoder line b
    input wire set_enc,          // signal to preload the counter
    input wire[23:0] preload,    // encoder counter preload value
    output wire[24:0] count,     // counts number of encoder transitions
    output reg dir               // encodes the direction of encoder transition
);
    // local registers
    reg overflow;           // overflow flag, output as the count msb
    reg[24:0] counter;      // register for encoder event counter
    initial counter = {1'b0, `ENC_MIDRANGE};

    // signals for encoder state
    wire[1:0] code;         // value formed from concatenated encoder lines
    reg[1:0] prev;          // used to remember the previously received code
    wire code_changed;      // indicates if encoder has moved since prev clk

    reg init_done;          // indicates that prev has a valid value

// -----------------------------------------------------------------------------
// hardware description
//

// set the output count msb as the overflow flag
assign count = { overflow, counter[23:0] };
assign code = { a, b };
assign code_changed = init_done & (code[1] ^ prev[1] ^ code[0] ^ prev[0]);
always @(posedge clk) begin
    init_done <= 1;
    prev <= code;
end

// dir 0 is B leading A
// dir 1 is A leading B
always @(posedge clk)
begin
    if (code_changed)
        dir <= code[1] ^ prev[0];  // a ^ b_prev
end

// -----------------------------------------------------------------------------
// count encoder transitions, using an up/down counter with asynchronous preset
// overflow flag set by counter carryout, cleared by encoder preload
//
always @(posedge(clk))
begin
    if (set_enc) begin
        counter <= {1'b0, preload};
        overflow <= 0;
    end
    else begin
        if (code_changed)
            counter <= counter + (dir ? 25'd1 : -25'd1);
        if (counter[24])
            overflow <= 1;
    end
end

endmodule
