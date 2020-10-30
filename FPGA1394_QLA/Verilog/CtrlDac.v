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
 *     07/31/20    Stefan Kohlgrueber  Revised to support digital current control
 */

// device register file offset
`include "Constants.v"

// dac SPI commands 
`define DAC_CMD_WRU 4'h3           // dac write and update command
`define DAC_CMD_NOP 4'hF           // dac nop command
`define DAC_VAL_INIT 16'h8000      // dac init (zero) value --> 2^15 --> no current

module CtrlDac(
    // globals
    input wire sysclk,             // global input clock
    // data inputs
    input wire[15:0] cont_val1,    // controller output CH1
    input wire[15:0] cont_val2,    // controller output CH2
    input wire[15:0] cont_val3,    // controller output CH3
    input wire[15:0] cont_val4,    // controller output CH4
    // spi
    output wire sclk,              // serial clock
    output wire mosi,              // serial data out
    output wire csel,              // serial chip select
    // regfile ctrl/addr/data
    input wire val_ready,          // register write enable (end-of-block) //SK: XXX - was blk_wen earlier
    input wire[15:0] reg_raddr,    // register read address
    output wire[31:0] reg_rdata    // outgoing register data
);

    // -------------------------------------------------------------------------
    // local wires and registers
    //
    reg[15:0] cont_val[1:4];        // controller values
    reg[15:0] cont_val_copy[1:4];   // controller values copy

    // Timing
    reg val_ready_now;              // new state for edge detection
    reg val_ready_last;             // old state for edge detection

    reg trig;                      // used trigger an spi transaction
    wire busy;                     // busy signal from the dac module
    wire flush;                    // dac signal to flush command word to nop
    wire[3:0] addr;                // final memory address to write to
    wire[3:0] addr_dac;            // memory address originating from dac
    wire[31:0] data;               // final memory data value to write
    wire[31:0] data1;              // final memory data value to write
    wire[31:0] data2;              // final memory data value to write
    wire[31:0] data3;              // final memory data value to write
    wire[31:0] data4;              // final memory data value to write

    wire[31:0] data_nop;           // shortcut for nop command word
    wire[31:0] data_wru;           // shortcut for write/update command word
    wire[31:0] data_wru1;          // shortcut for write/update command word
    wire[31:0] data_wru2;          // shortcut for write/update command word
    wire[31:0] data_wru3;          // shortcut for write/update command word
    wire[31:0] data_wru4;          // shortcut for write/update command word

    wire[31:0] dac_word;           // command word going into dac module

    reg[31:0] mem_data[0:`NUM_CHANNELS-1]; // register file for dac bitstreams
    reg[31:0] mem_copy[0:`NUM_CHANNELS-1]; // for readback of most recent dac command

    integer i;
    initial begin                  // for simulation, but synthesizes too
        for (i=0; i<`NUM_CHANNELS; i=i+1) mem_data[i] = 32'h00f08000;

        val_ready_now = 0;
        val_ready_last = 0;
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

// shortcuts for command words nop and write/update
assign data_nop  = { 8'h00, `DAC_CMD_NOP, 4'h0, `DAC_VAL_INIT};
assign data_wru1 = { 8'h00, `DAC_CMD_WRU, 4'h0, cont_val1};
assign data_wru2 = { 8'h00, `DAC_CMD_WRU, 4'h0, cont_val2};
assign data_wru3 = { 8'h00, `DAC_CMD_WRU, 4'h0, cont_val3};
assign data_wru4 = { 8'h00, `DAC_CMD_WRU, 4'h0, cont_val4};

// select firewire or NOP data depending on if spi transfer in progress
assign data1 = (busy ? data_nop : data_wru1);
assign data2 = (busy ? data_nop : data_wru2);
assign data3 = (busy ? data_nop : data_wru3);
assign data4 = (busy ? data_nop : data_wru4);

//DAC handling
assign dac_word = mem_data[addr_dac]; //word is sent based on address given by  LTC2601x4.

//actualize whenever the new values are ready, IF NOT BUSY
always @(posedge(sysclk))
begin
   val_ready_now = val_ready; //fetching of ready status --> val_ready is the blk_wen input --> rename

   if ((val_ready_last==0 && val_ready_now==1 && ~busy)) begin //edge detection for availability of controller output values XXX "|| flush" removed!
      //if (~busy || flush) begin //update values
         mem_data[0] <= data1; //update value
         mem_data[1] <= data2; //update value
         mem_data[2] <= data3; //update value
         mem_data[3] <= data4; //update value
      //end
   end
   val_ready_last = val_ready_now; // update value for next clock cycle
end

always @(posedge(sysclk))
begin
   if (val_ready_last==0 && val_ready_now==1 && ~busy) begin //edge detection for availability of controller output values
      //if(~busy) begin
         mem_copy[0] <= data1; //update value
         mem_copy[1] <= data2; //update value
         mem_copy[2] <= data3; //update value
         mem_copy[3] <= data4; //update value
      //end
   end
end

always @(posedge(sysclk))
begin
    trig <= val_ready; //no need to check if value is available as the val_ready is set high by the controller when cont_out was just calculated
end

// word sent to ADC
assign dac_word = mem_data[addr_dac]; //used from code --> probably the addr_dac is counted up by LTC2601x4 automatically.

//to read back dac values
assign reg_rdata = mem_copy[reg_raddr[7:4]-1'b1];

endmodule
