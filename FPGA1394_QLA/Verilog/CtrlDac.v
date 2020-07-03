/*******************************************************************************
 *
 * Copyright(C) 2011-2020 ERC CISST, Johns Hopkins University.
 *
 * This module controls SPI writes to a set of daisy chained dacs. It collects
 * 32-bit dac command words one-by-one from the firewire interface to create a
 * combined serial bitstream.
 * 
 * A memory interface is presented that allows the firewire interface to write
 * dac command words to the corresponding address/dac. The command words are
 * reset to NOP after each SPI transaction so that dacs are not updated unless
 * explicitly written to. Firewire write requests are ignored while an SPI
 * transaction is in progress.
 *
 * Revision history
 *     10/31/11    Paul Thienphrapa    Initial revision - Happy Halloween!
 */

// device register file offset
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
    // regfile ctrl/addr/data
    input wire reg_wen,            // register write enable
    input wire blk_wen,            // register write enable (end-of-block)
    input wire[15:0] reg_raddr,    // register read address
    input wire[15:0] reg_waddr,    // register write address
    output wire[31:0] reg_rdata,   // outgoing register data
    input wire[31:0] reg_wdata,    // incoming register data
    
    // output dac value
    output wire[15:0] dac1,        // register dac1 command current
    output wire[15:0] dac2,        // register dac2 command current 
    output wire[15:0] dac3,        // register dac3 command current
    output wire[15:0] dac4         // register dac4 command current
);

    // -------------------------------------------------------------------------
    // local wires and registers
    //

    reg trig;                      // used trigger an spi transaction
    wire busy;                     // busy signal from the dac module
    wire flush;                    // dac signal to flush command word to nop
    wire[3:0] addr;                // final memory address to write to
    wire[3:0] addr_dac;            // memory address originating from dac
    wire[31:0] data;               // final memory data value to write
    wire[31:0] data_nop;           // shortcut for nop command word
    wire[31:0] data_wru;           // shortcut for write/update command word
    wire[31:0] dac_word;           // command word going into dac module

    reg[31:0] mem_data[0:`NUM_CHANNELS-1]; // register file for dac bitstreams
    reg[31:0] mem_copy[0:`NUM_CHANNELS-1]; // for readback of most recent dac command

    integer i;
    initial begin                  // for simulation, but synthesizes too
        for (i=0; i<`NUM_CHANNELS; i=i+1) mem_data[i] = 32'h00f08000;
    end

//------------------------------------------------------------------------------
// hardware description
//

// dac module instantiation; note: dac is write-only
LTC2601x4 dac(
    .clkin(sysclk),
    .trig(trig),
    .word(dac_word),
    .addr(addr_dac),
    .sclk(sclk),
    .csel(csel),
    .mosi(mosi),
    .busy(busy),
    .flush(flush)
);

// select firewire or NOP data depending on if spi transfer in progress
assign addr = (busy ? addr_dac : reg_waddr[7:4]-1'b1);
assign data = (busy ? data_nop : data_wru);

// shortcuts for command words nop and write/update
assign data_nop = { 8'h00, `DAC_CMD_NOP, 4'h0, `DAC_VAL_INIT };
assign data_wru = { 8'h00, `DAC_CMD_WRU, 4'h0, reg_wdata[15:0] };
assign dac_word = mem_data[addr_dac];

// register file (memory) interface
always @(posedge(sysclk))
begin
    // write selected register with firewire or NOP data source
    if ((reg_wen && reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[3:0]==`OFF_DAC_CTRL && ~busy) || flush)
        mem_data[addr] <= data;
end

// copy of register file that doesn't get overwritten with NOPs
assign reg_rdata = mem_copy[reg_raddr[7:4]-1'b1];
always @(posedge(sysclk))
begin
    if (reg_wen && reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[3:0]==`OFF_DAC_CTRL && ~busy)
        mem_copy[addr] <= data;
end

// delay trigger (blk_wen) by a clock to allow quadlet data to be stored into
//   mem_data, as blk_wen and reg_wen become active at the same time for quadlet writes
always @(posedge(sysclk))
begin
    trig <= (blk_wen & (reg_waddr[15:12]==`ADDR_MAIN) & (reg_waddr[3:0]==`OFF_DAC_CTRL));
end


// connect mem_cop to dac(1-4)
assign dac1 = mem_copy[0][15:0];
assign dac2 = mem_copy[1][15:0];
assign dac3 = mem_copy[2][15:0];
assign dac4 = mem_copy[3][15:0];

endmodule
