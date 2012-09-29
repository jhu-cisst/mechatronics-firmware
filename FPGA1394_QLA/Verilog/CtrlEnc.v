/*******************************************************************************
 *
 * Copyright(C) 2011 ERC CISST, Johns Hopkins University.
 *
 * This module controls access to the encoder modules by selecting the data to 
 * output based on the read address, and by handling preload write commands to
 * the quadrature encoders.
 *
 * Revision history
 *     11/16/11    Paul Thienphrapa    Initial revision
 *     03/02/12    Zihan Chen          Add acc
 */

// device register file offsets from channel base
`define OFF_ADC_DATA 4'd0          // adc data register offset
`define OFF_DAC_CTRL 4'd1          // dac control register offset
`define OFF_POT_CTRL 4'd2          // pot control register offset
`define OFF_POT_DATA 4'd3          // pot data register offset
`define OFF_ENC_LOAD 4'd4          // enc data preload offset
`define OFF_ENC_DATA 4'd5          // enc quadrature register offset
`define OFF_PER_DATA 4'd6          // enc period register offset
`define OFF_FREQ_DATA 4'd7         // enc frequency register offset
`define OFF_ACC1_DATA 4'd8         // enc acc1 register offset
`define OFF_ACC2_DATA 4'd9         // enc acc2 register offset 
//`define OFF_SCUR_DATA 4'd10        // enc sync motor cur offset 

module CtrlEnc(
    sysclk, reset,
    clk_1mhz, clk_12hz,
    enc_a, enc_b,
    reg_addr, reg_rdata,
    reg_wdata, reg_we
);

    // -------------------------------------------------------------------------
    // define I/Os
    //

    input sysclk, reset;           // global clock and reset signals
    input clk_1mhz;                // fast clock to measure encoder period
    input clk_12hz;                // slow clock to measure encoder frequency
    input[1:4] enc_a, enc_b;       // set of quadrature encoder inputs
    input[7:0] reg_addr;           // register file addr from outside world
    output[31:0] reg_rdata;        // outgoing register file data
    input[31:0] reg_wdata;         // incoming register file data
    input reg_we;                  // write enable signal from outside world
    
    
    // -------------------------------------------------------------------------
    // local wires and registers
    //

    // encoder signals, etc.
    reg[1:4] set_enc;              // used to raise enc preload flag
    wire[1:4] enc_a_filt;          // filtered encoder a line
    wire[1:4] enc_b_filt;          // filtered encoder b line
    wire[1:4] dir;                 // encoder transition direction

    // data buses to/from encoder modules
    reg[23:0] preload[0:15];       // to encoder counter preload register
    wire[24:0] quad_data[0:15];    // transition count FROM encoder (ovf msb)
    wire[15:0] per_data[0:15];     // encoder period measurement
    wire[15:0] freq_data[0:15];    // encoder frequency measurement
    wire[15:0] acc1_data[0:15];    // encoder acc1 value
    wire[15:0] acc2_data[0:15];    // encoder acc2 value
    wire[15:0] scur_data[0:15];    // encoder sync motor cur
    
    wire[31:0] reg_rdata;          // outgoing register file data

    // for array-style access to the encoder data
    wire[31:0] mem_data[0:15][0:15];

//------------------------------------------------------------------------------
// hardware description
//

// filters for raw encoder lines a and b (all channels, 1-4)
Debounce filter_a1(sysclk, reset, enc_a[1], enc_a_filt[1]);
Debounce filter_b1(sysclk, reset, enc_b[1], enc_b_filt[1]);
Debounce filter_a2(sysclk, reset, enc_a[2], enc_a_filt[2]);
Debounce filter_b2(sysclk, reset, enc_b[2], enc_b_filt[2]);
Debounce filter_a3(sysclk, reset, enc_a[3], enc_a_filt[3]);
Debounce filter_b3(sysclk, reset, enc_b[3], enc_b_filt[3]);
Debounce filter_a4(sysclk, reset, enc_a[4], enc_a_filt[4]);
Debounce filter_b4(sysclk, reset, enc_b[4], enc_b_filt[4]);

// modules for encoder counts, period, and frequency measurements
// channel 1
EncQuad EncQuad1(sysclk, reset, enc_a_filt[1], enc_b_filt[1], set_enc[1], preload[1], quad_data[1], dir[1]);
EncPeriod EncPer1(clk_1mhz, reset, enc_b_filt[1], dir[1], per_data[1]);
EncFreq EncFreq1(sysclk, clk_12hz, reset, enc_b_filt[1], dir[1], freq_data[1]);
EncAcc EncAcc1(clk_12hz, reset, per_data[1], acc1_data[1], acc2_data[1], scur_data[1]);
// channel 2
EncQuad EncQuad2(sysclk, reset, enc_a_filt[2], enc_b_filt[2], set_enc[2], preload[2], quad_data[2], dir[2]);
EncPeriod EncPer2(clk_1mhz, reset, enc_b_filt[2], dir[2], per_data[2]);
EncFreq EncFreq2(sysclk, clk_12hz, reset, enc_b_filt[2], dir[2], freq_data[2]);
EncAcc EncAcc2(clk_12hz, reset, per_data[2], acc1_data[2], acc2_data[2], scur_data[2]);
// channel 3
EncQuad EncQuad3(sysclk, reset, enc_a_filt[3], enc_b_filt[3], set_enc[3], preload[3], quad_data[3], dir[3]);
EncPeriod EncPer3(clk_1mhz, reset, enc_b_filt[3], dir[3], per_data[3]);
EncFreq EncFreq3(sysclk, clk_12hz, reset, enc_b_filt[3], dir[3], freq_data[3]);
EncAcc EncAcc3(clk_12hz, reset, per_data[3], acc1_data[3], acc2_data[3], scur_data[3]);
// channel 4
EncQuad EncQuad4(sysclk, reset, enc_a_filt[4], enc_b_filt[4], set_enc[4], preload[4], quad_data[4], dir[4]);
EncPeriod EncPer4(clk_1mhz, reset, enc_b_filt[4], dir[4], per_data[4]);
EncFreq EncFreq4(sysclk, clk_12hz, reset, enc_b_filt[4], dir[4], freq_data[4]);
EncAcc EncAcc4(clk_12hz, reset, per_data[4], acc1_data[4], acc2_data[4], scur_data[4]);

// create a pulse when encoder preload is written
always @(posedge(sysclk) or negedge(reset))
begin
    if (reset == 0)
        set_enc <= 0;
    else
        set_enc[reg_addr[7:4]] <= (reg_we && reg_addr[3:0]==`OFF_ENC_LOAD);
end

//------------------------------------------------------------------------------
// register file interface to outside world
//

// output selected read register
assign reg_rdata = mem_data[reg_addr[7:4]][reg_addr[3:0]];

// write selected preload register
always @(posedge(sysclk))
begin
    if (reg_we && reg_addr[3:0]==`OFF_ENC_LOAD)
        preload[reg_addr[7:4]] <= reg_wdata[23:0];
end

// map the data lines to access them as memory: [channel #][device #]
// channel 1
assign mem_data[1][`OFF_ENC_LOAD] = preload[1];
assign mem_data[1][`OFF_ENC_DATA] = quad_data[1];
assign mem_data[1][`OFF_PER_DATA] = per_data[1];
assign mem_data[1][`OFF_FREQ_DATA] = freq_data[1];
assign mem_data[1][`OFF_ACC1_DATA] = acc1_data[1];
assign mem_data[1][`OFF_ACC2_DATA] = acc2_data[1];
//assign mem_data[1][`OFF_SCUR_DATA] = scur_data[1];
// channel 2
assign mem_data[2][`OFF_ENC_LOAD] = preload[2];
assign mem_data[2][`OFF_ENC_DATA] = quad_data[2];
assign mem_data[2][`OFF_PER_DATA] = per_data[2];
assign mem_data[2][`OFF_FREQ_DATA] = freq_data[2];
assign mem_data[2][`OFF_ACC1_DATA] = acc1_data[2];
assign mem_data[2][`OFF_ACC2_DATA] = acc2_data[2];
//assign mem_data[2][`OFF_SCUR_DATA] = scur_data[2];
// channel 3
assign mem_data[3][`OFF_ENC_LOAD] = preload[3];
assign mem_data[3][`OFF_ENC_DATA] = quad_data[3];
assign mem_data[3][`OFF_PER_DATA] = per_data[3];
assign mem_data[3][`OFF_FREQ_DATA] = freq_data[3];
assign mem_data[3][`OFF_ACC1_DATA] = acc1_data[3];
assign mem_data[3][`OFF_ACC2_DATA] = acc2_data[3];
//assign mem_data[3][`OFF_SCUR_DATA] = scur_data[3];
// channel 4
assign mem_data[4][`OFF_ENC_LOAD] = preload[4];
assign mem_data[4][`OFF_ENC_DATA] = quad_data[4];
assign mem_data[4][`OFF_PER_DATA] = per_data[4];
assign mem_data[4][`OFF_FREQ_DATA] = freq_data[4];
assign mem_data[4][`OFF_ACC1_DATA] = acc1_data[4];
assign mem_data[4][`OFF_ACC2_DATA] = acc2_data[4];
//assign mem_data[4][`OFF_SCUR_DATA] = scur_data[4];

endmodule
