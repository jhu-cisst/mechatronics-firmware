/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 ERC CISST, Johns Hopkins University.
 *
 * This module contains code for the boot configuration check
 *
 * Revision history
 *      2/20/23    Peter Kazanzides    Initial version
 */

`include "Constants.v"

module BootConfig(
    // global clock
    input wire       sysclk,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,

    // I/O between FPGA and QLA (connectors J1 and J2)
    // Includes extra I/O from FPGA V3.1
    inout[0:33]      IO1,
    inout[0:39]      IO2,

    // Read/Write bus
    input wire[15:0]  reg_raddr,
    input wire[15:0]  reg_waddr,
    output wire[31:0] reg_rdata,
    input wire[31:0]  reg_wdata,
    input wire reg_wen,
    input wire blk_wen,
    input wire blk_wstart
);

    //******************* I/O pin mappings **************************

    // Board EEPROM
    // Assume that all boards define IO1[1]-IO1[4] the same (EEPROM interface)
    wire prom_sclk;
    wire prom_miso;
    wire prom_mosi;
    wire prom_CSn;
    assign IO1[3] = prom_sclk;
    assign IO1[2] = prom_mosi;
    assign prom_miso = IO1[1];
    assign IO1[4] = prom_CSn;

    //***********************************************************************************

//------------------------------------------------------------------------------
// hardware description
//

wire[31:0] reg_rdata_prom;       // reads from prom
wire[31:0] reg_rdata_chan0;      // 'channel 0' is a special axis that contains various board I/Os

// Mux routing read data based on read address
//   See Constants.v for details
assign reg_rdata = (reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom) :
                   (reg_raddr[15:12]==`ADDR_MAIN) ? (reg_rdata_chan0) : 32'd0;

// --------------------------------------------------------------------------
// Prom 25AA128
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

wire reg_wen_prom;
assign reg_wen_prom = ((reg_waddr[15:12] == `ADDR_PROM_QLA) && (reg_waddr[7:4] == 4'd0)) ?
                       reg_wen : 1'b0;

QLA25AA128 prom(
    .clk(sysclk),

    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom),
    .reg_wdata(reg_wdata),

    .reg_wen(reg_wen_prom),
    .blk_wen(blk_wen),       // not used
    .blk_wstart(blk_wstart), // not used

    // spi interface
    .prom_mosi(prom_mosi),
    .prom_miso(prom_miso),
    .prom_sclk(prom_sclk),
    .prom_cs(prom_CSn),
    .other_busy(1'b0)
);

// --------------------------------------------------------------------------
// miscellaneous board I/Os
//
// Following could be moved to BoardRegs-BCFG.v, but since there is not
// much code, we keep it here.
//
// --------------------------------------------------------------------------

wire[31:0] reg_status;    // Status register
assign reg_status = {4'd0, board_id, 24'd0 };
wire[31:0] reg_version;   // Hardware version
assign reg_version = 32'h42434647;   // "BCFG"

assign reg_rdata_chan0 = (reg_raddr[3:0] == `REG_STATUS) ? reg_status :
                         (reg_raddr[3:0] == `REG_VERSION) ? reg_version :
                         32'd0;

endmodule
