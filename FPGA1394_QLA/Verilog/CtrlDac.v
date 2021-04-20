/*******************************************************************************
 *
 * Copyright(C) 2011-2021 ERC CISST, Johns Hopkins University.
 *
 * This module controls SPI writes to a set of daisy chained dacs. It collects
 * 32-bit dac command words one-by-one from the host interface (Firewire or
 * Ethernet) to create a combined serial bitstream.
 * 
 * A memory interface is presented that allows the host interface to write
 * dac command words to the corresponding address/dac. The command words are
 * reset to NOP after each SPI transaction so that dacs are not updated unless
 * explicitly written to. Host write requests are ignored while an SPI
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
    // Host write of desired current
    input wire reg_wen,            // register write enable
    input wire blk_wen,            // register write enable (end-of-block)
    input wire[15:0] reg_waddr,    // register write address
    input wire[15:0] reg_wdata,    // incoming register data
    // Read back of DAC value
    input wire[3:0] reg_rchan,     // register read channel (reg_raddr[7:4])
    output wire[31:0] reg_rdata,   // outgoing register data
    
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
    wire[3:0] addr_wrt;            // final memory address to write to
    wire[3:0] addr_dac;            // memory address originating from dac
    wire[31:0] data_nop;           // shortcut for nop command word
    wire[31:0] data_wru;           // shortcut for write/update command word
    wire[31:0] dac_word;           // command word going into dac module

    // mem_data is for writing to DAC; entries set to NOP after being written
    reg[31:0] mem_data[0:`NUM_CHANNELS-1]; // register file for dac bitstreams
    // copy of mem_data that doesn't get overwritten with NOPs
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

assign addr_wrt = reg_waddr[7:4]-1'b1;

// shortcuts for command words nop and write/update
assign data_nop = { 8'h00, `DAC_CMD_NOP, 4'h0, `DAC_VAL_INIT };
assign data_wru = { 8'h00, `DAC_CMD_WRU, 4'h0, reg_wdata };
assign dac_word = mem_data[addr_dac];

// Indicates that DAC channel is being addressed.
// Check for non-zero channel number (reg_waddr[7:4]) to ignore write to global register.
// It would be even better to check that channel number is 1-4.
wire reg_waddr_dac;
assign reg_waddr_dac = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] != 4'd0) &&
			(reg_waddr[3:0]==`OFF_DAC_CTRL)) ? 1'd1 : 1'd0;

// register file (memory) interface
always @(posedge(sysclk))
begin
`ifdef DIAGNOSTIC
    if (trig || flush) begin
        mem_data[0] <= data_wru;
        mem_data[1] <= data_wru;
        mem_data[2] <= data_wru;
        mem_data[3] <= data_wru;
        // Don't need to update mem_copy since we don't plan to read from board
        // in diagnostic mode.
    end
`else
    // write selected register
    if (flush) begin  // Should also be busy
        mem_data[addr_dac] <= data_nop;
    end
    else if (reg_wen && reg_waddr_dac && ~busy) begin
        mem_data[addr_wrt] <= data_wru;
        mem_copy[addr_wrt] <= data_wru;
    end
`endif
end

assign reg_rdata = mem_copy[reg_rchan-1'b1];

`ifdef DIAGNOSTIC
reg[9:0] trig_counter;
always @(posedge(sysclk))
begin
    trig <= (trig_counter < 10'd10) ? 1'b1 : 1'b0;
    trig_counter <= trig_counter + 1'b1;
end
`else
// delay trigger (blk_wen) by a clock to allow quadlet data to be stored into
//   mem_data, as blk_wen and reg_wen become active at the same time for quadlet writes
always @(posedge(sysclk))
begin
    trig <= (blk_wen & reg_waddr_dac & (reg_waddr[3:0]==`OFF_DAC_CTRL));
end
`endif

// connect mem_copy to dac(1-4)
assign dac1 = mem_copy[0][15:0];
assign dac2 = mem_copy[1][15:0];
assign dac3 = mem_copy[2][15:0];
assign dac4 = mem_copy[3][15:0];

endmodule
