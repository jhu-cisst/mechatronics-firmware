/*******************************************************************************
 *
 * Copyright(C) 2008-2012 ERC CISST, Johns Hopkins University.
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

module EncQuad(
    input wire clk,              // glocal clock
    input wire reset,            // reset signals
    input wire a,                // quad encoder line a
    input wire b,                // quad encoder line b
    input wire set_enc,          // signal to preload the counter
    input wire[23:0] preload,    // encoder counter preload value
    output wire[24:0] count,      // counts number of encoder transitions
    output reg dir               // encodes the direction of encoder transition
);
    // local registers
    reg overflow;           // overflow flag, output as the count msb
    reg[24:0] counter;      // register for encoder event counter

    // signals for encoder state
    wire[1:0] code;         // value formed from concatenated encoder lines
    reg[1:0] prev;          // used to remember the previously received code
    wire code_changed;      // indicates if encoder has moved since prev clk

// -----------------------------------------------------------------------------
// hardware description
//

// set the output count msb as the overflow flag
assign count = { overflow, counter[23:0] };
assign code = { a, b };
assign code_changed = code[1] ^ prev[1] ^ code[0] ^ prev[0];
always @(posedge(clk)) prev <= code;

// dir 0 is A leading B
// dir 1 is B leading A
always @(posedge clk)
begin
    if (code_changed)
        dir <= code[1] ^ prev[0];
end

// -----------------------------------------------------------------------------
// count encoder transitions, using an up/down counter with asynchronous preset
//
always @(posedge(clk) or posedge(set_enc))
begin
    if (set_enc)
        counter <= preload;
    else if (code_changed)
        counter <= counter + (dir ? 25'd1 : -25'd1);
end

// -----------------------------------------------------------------------------
// overflow flag set by counter carryout, cleared by reset or encoder preload
//
always @(posedge(counter[24]) or posedge(set_enc) or negedge(reset))
begin
    if (reset==0 || set_enc)
        overflow <= 0;
    else
        overflow <= 1;
end

endmodule
