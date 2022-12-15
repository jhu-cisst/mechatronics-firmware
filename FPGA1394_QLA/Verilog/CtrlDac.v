/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * This module controls SPI writes to a set of daisy chained dacs. It collects
 * 32-bit dac command words from the host interface (Firewire or Ethernet)
 * to create a combined serial bitstream.
 * 
 * A memory interface is presented that allows the host interface to write
 * dac command words to the corresponding address/dac. The command words are
 * reset to NOP after each SPI transaction so that dacs are not updated unless
 * explicitly written to. Host write requests are ignored while an SPI
 * transaction is in progress.
 *
 * Revision history
 *     10/31/11    Paul Thienphrapa    Initial revision - Happy Halloween!
 *     04/20/21    Peter Kazanzides    Revised to accept dac1-dac4 and data_ready
 */

`include "Constants.v"

// dac SPI commands 
`define DAC_CMD_WRU 4'h3           // dac write and update command
`define DAC_CMD_NOP 4'hF           // dac nop command
`define DAC_VAL_INIT 16'h8000      // dac init (zero) value

module CtrlDac(
    // globals
    input wire sysclk,             // global input clock
    // spi
    output wire sclk,              // serial clock
    output wire mosi,              // serial data out
    output wire csel,              // serial chip select
    // DAC input
    input wire[15:0] dac1,
    input wire[15:0] dac2,
    input wire[15:0] dac3,
    input wire[15:0] dac4,
    // status
    output wire busy,              // busy signal from the dac module
    input wire  data_ready,        // indicates new DAC input data available
    input wire  mosi_read,         // serial data out feedback (used during initialization)
    output reg  isQuadDac,         // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
    input wire  dac_test_reset     // repeat DAC test
);

    // -------------------------------------------------------------------------
    // local wires and registers
    //

    reg trig;                      // used trigger an spi transaction
    wire flush;                    // dac signal to flush command word to nop
    wire[3:0] addr_dac;            // memory address originating from dac
    wire[31:0] data_nop;           // shortcut for nop command word
    wire[11:0] data_wru_msw;       // MSW (12-bits) for write/update command word
    wire[31:0] dac_word;           // command word going into dac module
    reg dac_test_done;             // true if we checked for DAC type (4xLTC2601 or 1xLTC2604)

    // mem_data is for writing to DAC; entries set to NOP after being written
    reg[31:0] mem_data[0:3];       // register file for dac bitstreams

    integer i;
    initial begin
        for (i=0; i<4; i=i+1) mem_data[i] = 32'h00f08000;
    end

//------------------------------------------------------------------------------
// hardware description
//

wire mosi_out;
assign mosi = dac_test_done ? mosi_out : 1'bz;

// dac module instantiation; note: dac is write-only
LTC2601x4 dac(
    .clkin(sysclk),
    .trig(trig),
    .word(dac_word),
    .addr(addr_dac),
    .sclk(sclk),
    .csel(csel),
    .mosi(mosi_out),
    .busy(busy),
    .flush(flush),
    .isQuadDac(isQuadDac)
);

// shortcuts for command words nop and write/update
assign data_nop = { 8'h00, `DAC_CMD_NOP, 4'h0, `DAC_VAL_INIT };
assign data_wru_msw = { 8'h00, `DAC_CMD_WRU };
assign dac_word = mem_data[addr_dac];

// register file (memory) interface
always @(posedge(sysclk))
begin
    // test for DAC type
    if (~dac_test_done) begin
        dac_test_done <= 1'b1;
        isQuadDac <= ~mosi_read;  // LTC2604 (quad DAC) has pulldown
    end
    if (dac_test_reset) begin
        dac_test_done <= 1'b0;
    end
    // write selected register
    if (data_ready&(~busy)) begin
        // TODO: For LTC2604, can write to first 3, then write & update 4th
        mem_data[0] <= { data_wru_msw, 4'd0, dac1 };
        mem_data[1] <= { data_wru_msw, 4'd1, dac2 };
        mem_data[2] <= { data_wru_msw, 4'd2, dac3 };
        mem_data[3] <= { data_wru_msw, 4'd3, dac4 };
        trig <= 1;
    end
    else if (trig&busy) begin
        trig <= 0;
    end
    else if (flush) begin
        mem_data[addr_dac] <= data_nop;
    end
end

endmodule
