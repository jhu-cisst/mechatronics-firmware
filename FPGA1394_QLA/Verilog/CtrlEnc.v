/*******************************************************************************
 *
 * Copyright(C) 2011-2020 ERC CISST, Johns Hopkins University.
 *
 * Module:  CtrlEnc
 *
 * Purpose: This module controls access to the encoder modules by selecting 
 *          the data to output based on the read address, and by handling
 *          preload write commands to the quadrature encoders.
 *
 * Revision history
 *     11/16/11    Paul Thienphrapa    Initial revision
 *     10/27/13    Zihan Chen          Minor, set preload to 24'h800000 (`ENC_MIDRANGE)
 *     04/07/17    Jie Ying Wu         Minor change to clock frequency for velocity estimation
 *     05/01/18    Jie Ying Wu         Form update for flexible number of channels
 */

`include "Constants.v"

module CtrlEnc(
    input  wire sysclk,           // global clock
    input  wire[1:`NUM_CHANNELS] enc_a,  // set of quadrature encoder inputs
    input  wire[1:`NUM_CHANNELS] enc_b,
`ifdef ENC_INDEX
    input  wire[1:`NUM_CHANNELS] enc_i,
`endif
    input  wire[3:0] reg_raddr_chan,  // register file read addr from outside
    input  wire[15:0] reg_waddr,  // register file write addr from outside
    input  wire[31:0] reg_wdata,  // incoming register file data
    input  wire reg_wen,          // write enable signal from outside world
    output wire[31:0] reg_preload,
    output wire[31:0] reg_quad_data,
`ifdef ENC_INDEX
    output wire[31:0] reg_index_data,
`endif
    output wire[31:0] reg_perd_data,
    output wire[31:0] reg_qtr1_data,
    output wire[31:0] reg_qtr5_data,
    output wire[31:0] reg_run_data
);    
    
// -------------------------------------------------------------------------
// local wires and registers
// -------------------------------------------------------------------------

// encoder signals, etc.
reg[1:`NUM_CHANNELS]  set_enc;             // used to raise enc preload flag
wire[1:`NUM_CHANNELS] enc_a_filt;          // filtered encoder a line
wire[1:`NUM_CHANNELS] enc_b_filt;          // filtered encoder b line
`ifdef ENC_INDEX
wire[1:`NUM_CHANNELS] enc_i_filt;          // filtered encoder index line
`endif
wire[1:`NUM_CHANNELS] dir;                 // encoder transition direction

//------------------------------------------------------------------------------
// data buses to/from encoder modules
reg[23:0]  preload[1:`NUM_CHANNELS];      // to encoder counter preload register
wire[24:0] quad_data[1:`NUM_CHANNELS];    // transition count FROM encoder (ovf msb)
wire[31:0] perd_data[1:`NUM_CHANNELS];    // 1st encoder period measurement    
wire[31:0] qtr1_data[1:`NUM_CHANNELS];    // recent quarter encoder period measurement    
wire[31:0] qtr5_data[1:`NUM_CHANNELS];    // old quarter encoder period measurement    
wire[31:0] run_data[1:`NUM_CHANNELS];     // running encoder period measurement
    
integer ii;
initial begin
   // set preload to half value
   for (ii = 1; ii < `NUM_CHANNELS+1; ii = ii + 1) preload[ii] = `ENC_MIDRANGE;
end

// output selected read register
assign reg_preload = {8'd0, preload[reg_raddr_chan]};
assign reg_quad_data = {7'd0, quad_data[reg_raddr_chan]};
assign reg_perd_data = perd_data[reg_raddr_chan];
assign reg_qtr1_data = qtr1_data[reg_raddr_chan];
assign reg_qtr5_data = qtr5_data[reg_raddr_chan];
assign reg_run_data = run_data[reg_raddr_chan];

//--------------------------------------------------------------------------
// hardware description
// -------------------------------------------------------------------------
genvar i;

// filters for raw encoder lines a, b and i (all channels, 1-`NUM_CHANNELS)
generate 
for (i = 1; i < `NUM_CHANNELS+1; i = i + 1) begin : filt_loop 
   Debounce filter_a(sysclk, enc_a[i], enc_a_filt[i]);
   Debounce filter_b(sysclk, enc_b[i], enc_b_filt[i]);
`ifdef ENC_INDEX
   Debounce #(.bits(3)) filter_i(sysclk, enc_i[i], enc_i_filt[i]);
`endif
end 
endgenerate

// modules for encoder counts, period, and frequency measurements
// position quad encoder 
generate
for (i = 1; i < `NUM_CHANNELS+1; i = i+1) begin : pos_loop
   EncQuad EncQuad(sysclk, enc_a_filt[i], enc_b_filt[i], set_enc[i], preload[i], quad_data[i], dir[i]);
end
endgenerate

// velocity period (4/dT method with acceleration)
// quad update version
generate
for (i = 1; i < `NUM_CHANNELS+1; i = i+1) begin : vel_loop
   EncPeriodQuad EncPerd(sysclk, enc_a_filt[i], enc_b_filt[i], dir[i], perd_data[i],
                         qtr1_data[i], qtr5_data[i], run_data[i]);
end
endgenerate

`ifdef ENC_INDEX
reg[25:0] index_data[1:`NUM_CHANNELS];   // dir, encoder counter when index occurred
reg[3:0]  index_cnt[1:`NUM_CHANNELS];    // counts number of index pulses
assign reg_index_data = {index_cnt[reg_raddr_chan], 2'b00, index_data[reg_raddr_chan]};

generate
for (i = 1; i < `NUM_CHANNELS+1; i = i+1) begin : index_loop
   always @(posedge(enc_i_filt[i]))
   begin
      index_cnt[i] <= index_cnt[i] + 4'd1;
      index_data[i] <= {dir[i], quad_data[i]};
   end
end
endgenerate
`endif

// write selected preload register
// set_enc: create a pulse when encoder preload is written

always @(posedge(sysclk))
begin
    if (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_ENC_LOAD))
    begin
        preload[reg_waddr[7:4]] <= reg_wdata[23:0]; 
        set_enc[reg_waddr[7:4]] <= 1'b1;
    end
    else 
        set_enc <= {`NUM_CHANNELS{1'b0}};
end

endmodule
