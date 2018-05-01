/*******************************************************************************
 *
 * Copyright(C) 2011-2017 Johns Hopkins University.
 *
 * Module:  CtrlFlash
 *
 * Purpose: This module controls access to the encoder modules by selecting 
 *          the data to output based on the read address, and by handling
 *          preload write commands to the quadrature encoders.
 *
 * Revision history
 *     11/16/11    Paul Thienphrapa    Initial revision
 *     10/27/13    Zihan Chen          Minor, set preload to 24'h800000
 *     04/07/17    Jie Ying Wu         Minor change to clock frequency for velocity estimation
 *     05/01/18    Jie Ying Wu         Form update for flexible number of channels
 */

// device register file offset
`include "ConstantsEspm.v" 

module CtrlEnc(
    input  wire sysclk,           // global clock and reset signals
    input  wire reset,            // global reset
    input  wire[1:`NUM_CHANNELS] enc_a,       // set of quadrature encoder inputs
    input  wire[1:`NUM_CHANNELS] enc_b,
    input  wire[5:0] addr,   // register file read addr from outside 
    output wire[31:0] data  // outgoing register file data
);    
    
// -------------------------------------------------------------------------
// local wires and registers
// -------------------------------------------------------------------------

// encoder signals, etc.
reg [1:`NUM_CHANNELS] set_enc;             // used to raise enc preload flag
wire[1:`NUM_CHANNELS] enc_a_filt;          // filtered encoder a line
wire[1:`NUM_CHANNELS] enc_b_filt;          // filtered encoder b line
wire[1:`NUM_CHANNELS] dir;                 // encoder transition direction

// data buses to/from encoder modules
wire [24:0] quad_data[1:`NUM_CHANNELS];    // transition count FROM encoder (ovf msb)
wire [31:0] perd_data[1:`NUM_CHANNELS];    // 1st encoder period measurement    
wire [31:0]  acc_data[1:`NUM_CHANNELS];    // 2nd encoder period measurement
    
//--------------------------------------------------------------------------
// hardware description
// -------------------------------------------------------------------------
genvar i;

// filters for raw encoder lines a and b (all channels, 1-4)
generate 
for (i = 1; i < `NUM_CHANNELS+1; i = i + 1) begin : filt_loop 
   Debounce filter_a(sysclk, reset, enc_a[i], enc_a_filt[i]);
   Debounce filter_b(sysclk, reset, enc_b[i], enc_b_filt[i]);
end 
endgenerate

// modules for encoder counts, period, and frequency measurements
// position quad encoder 
generate
for (i = 1; i < `NUM_CHANNELS+1; i = i+1) begin : pos_loop
   EncQuad EncQuad(sysclk, ~reset, enc_a_filt[i], enc_b_filt[i], quad_data[i], dir[i]);
end
endgenerate

// velocity period (4/dT method)
// quad update version
wire [31:0] empty; // Assign to output running counter later when we update packet size

generate
for (i = 1; i < `NUM_CHANNELS+1; i = i+1) begin : vel_loop
   EncPeriodQuad EncPerd(sysclk, ~reset, enc_a_filt[i], enc_b_filt[i], dir[i], perd_data[i], acc_data[i], empty);
end
endgenerate
//--------------------------------------------------------------------------
// register file interface to outside world
// -------------------------------------------------------------------------

// output selected read register
assign data = (addr[2:0]==2'b00) ? 32'd2845 : // Should never be sent back
              (addr[4:3]==`OFF_POS_DATA) ? ({7'b0, quad_data[addr[2:0]]}) :
              (addr[4:3]==`OFF_VEL1_DATA) ? (perd_data[addr[2:0]]) : 
              (addr[4:3]==`OFF_VEL2_DATA) ? (acc_data[addr[2:0]]) : 32'd0;

endmodule
