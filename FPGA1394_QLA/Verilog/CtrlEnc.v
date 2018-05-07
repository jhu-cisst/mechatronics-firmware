/*******************************************************************************
 *
 * Copyright(C) 2011-2017 ERC CISST, Johns Hopkins University.
 *
 * Module:  CtrlEnc
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
`include "Constants.v" 

module CtrlEnc(
    input  wire sysclk,           // global clock and reset signals
    input  wire reset,            // global reset
    input  wire[1:`NUM_CHANNELS] enc_a,       // set of quadrature encoder inputs
    input  wire[1:`NUM_CHANNELS] enc_b,
    input  wire[15:0] reg_raddr,  // register file read addr from outside 
    input  wire[15:0] reg_waddr,  // register file write addr from outside 
    output wire[31:0] reg_rdata,  // outgoing register file data
    input  wire[31:0] reg_wdata,  // incoming register file data
    input  wire reg_wen           // write enable signal from outside world
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
reg  [23:0]   preload[1:`NUM_CHANNELS];    // to encoder counter preload register
wire [24:0] quad_data[1:`NUM_CHANNELS];    // transition count FROM encoder (ovf msb)
wire [31:0] perd_data[1:`NUM_CHANNELS];    // 1st encoder period measurement    
wire [31:0] qtr1_data[1:`NUM_CHANNELS];    // recent quarter encoder period measurement    
wire [31:0] qtr5_data[1:`NUM_CHANNELS];    // old quarter encoder period measurement    
wire [31:0]  run_data[1:`NUM_CHANNELS];    // running encoder period measurement
    
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
   EncQuad EncQuad(sysclk, reset, enc_a_filt[i], enc_b_filt[i], set_enc[i], preload[i], quad_data[i], dir[i]);
end
endgenerate

// velocity period (4/dT method with acceleration)
// quad update version
generate
for (i = 1; i < `NUM_CHANNELS+1; i = i+1) begin : vel_loop
   EncPeriodQuad EncPerd(sysclk, reset, enc_a_filt[i], enc_b_filt[i], dir[i], perd_data[i], qtr1_data[i], qtr5_data[i], run_data[i]);
end
endgenerate
//--------------------------------------------------------------------------
// register file interface to outside world
// -------------------------------------------------------------------------

// output selected read register
assign reg_rdata = (reg_raddr == `OFF_ENC_LOAD) ? (preload[reg_raddr[7:4]]) :
              (reg_raddr[3:0]==`OFF_ENC_DATA) ? ({7'b0, quad_data[reg_raddr[7:4]]}) :
              (reg_raddr[3:0]==`OFF_PER_DATA) ? (perd_data[reg_raddr[7:4]]) : 
              (reg_raddr[3:0]==`OFF_QTR1_DATA) ? (qtr1_data[reg_raddr[7:4]]) : 
              (reg_raddr[3:0]==`OFF_QTR5_DATA) ? (qtr5_data[reg_raddr[7:4]]) : 
              (reg_raddr[3:0]==`OFF_RUN_DATA) ? (run_data[reg_raddr[7:4]]) : 32'd0;

// write selected preload register
// set_enc: create a pulse when encoder preload is written

reg [0:3] j; 
always @(posedge(sysclk) or negedge(reset))
begin
    if (reset == 0) begin
        set_enc <= 4'h0;
        for (j = 1; j < `NUM_CHANNELS + 1; j = j+1) begin
            preload[j] <= 24'h800000;    // set to half value
        end
    end
    else if (reg_wen && reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[3:0]==`OFF_ENC_LOAD)
    begin
        preload[reg_waddr[7:4]] <= reg_wdata[23:0]; 
        set_enc[reg_waddr[7:4]] <= 1'b1;
    end
    else 
        set_enc <= 4'h0;
end

endmodule
