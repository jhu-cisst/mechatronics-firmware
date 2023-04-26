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
    // 1 -> FPGA V3.0
    input wire isV30,

    // I/O between FPGA and QLA (connectors J1 and J2)
    // Includes extra I/O from FPGA V3.1
    inout[0:33]      IO1,
    inout[0:39]      IO2,

    // EMIO feedback (to PS)
    output wire[63:0] reg_emio,

    // Read/Write bus
    input wire[15:0]  reg_raddr,
    input wire[15:0]  reg_waddr,
    output wire[31:0] reg_rdata,
    input wire[31:0]  reg_wdata,
    input wire reg_wen,
    input wire blk_wen,
    input wire blk_wstart,

    // Sampling support
    input wire sample_start,        // Start sampling read data
    output reg sample_busy,         // 1 -> data sampler has control of bus
    output wire[3:0] sample_chan,   // Channel for sampling
    input wire[5:0] sample_raddr,   // Address in sample_data buffer
    output wire[31:0] sample_rdata, // Output from sample_data buffer
    output reg[31:0] timestamp      // Timestamp used when sampling
);

    //******************* I/O pin mappings **************************

    // Board EEPROM
    // Assume that all boards define IO1[1]-IO1[4] the same (EEPROM interface)
    wire prom_sclk;
    wire prom_miso;
    wire prom_mosi;
    wire prom_CSn;
    assign IO1[3] = prom_CSn ? 1'bz : prom_sclk;
    assign IO1[2] = prom_CSn ? 1'bz : prom_mosi;
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

//---------------------------------------------------------------------------------
//
// Board detection logic
//
// The following logic distinguishes between the known boards (and NONE, which
// means no board attached) by looking at the power-up values of the IO lines.
// It assumes that all IO lines are configured with pull-up resistors
// (see BootConfig.ucf).
//
// Note that, except for NONE, we do not check all IOs, but rather only check
// when there is at least one expected difference.
//
// If desired, it would also be possible to read the PROM attached to IO1[1]-IO1[4],
// or to look for square waves on the temperature feedback lines on QLA/DQLA.
//
//---------------------------------------------------------------------------------

// NONE: all IO have pull-ups
assign isNONE = ((IO1[0:33] == {34{1'b1}}) && (IO2[0:39] == {40{1'b1}})) ? 1'b1 : 1'b0;

// QLA: it is sufficient to check the 0 values because IO1[31]=1 for DQLA
//      and there are many that are 1 for DRAC and NONE
assign QLAzeros = ~(IO1[0]|IO1[31]|IO1[32]|IO2[1]|IO2[3]|IO2[5]|IO2[7]|IO2[11]|
                    IO2[31]|IO2[32]|IO2[33]|IO2[34]|IO2[35]|IO2[36]|IO2[37]|IO2[38]);
assign isQLA = QLAzeros;

// DQLA
// IO1[0]=1 for NONE
assign DQLAzeros = ~IO1[0];
// IO1[12]=0 for DRAC and IO1[31]=0 for QLA
assign DQLAones = IO1[12]&IO1[31];
assign isDQLA = DQLAzeros & DQLAones;

// DRAC
// IO1[12]=1 for DQLA; all IOs are 1 for NONE
assign DRACzeros = ~(IO1[9]|IO1[12]|IO1[19]|IO1[21]|IO1[23]|IO1[32]|
                     IO2[10]|IO2[15]|IO2[22]|IO2[28]|IO2[29]|IO2[34]);
// Many IOs are 0 for QLA
assign DRACones = IO2[1]&IO2[3]&IO2[31]&IO2[32]&IO2[36];
assign isDRAC = DRACzeros & DRACones;

// --------------------------------------------------------------------------
// miscellaneous board I/Os
//
// Following could be moved to BoardRegs-BCFG.v, but since there is not
// much code, we keep it here.
//
// --------------------------------------------------------------------------

wire[31:0] reg_status;
assign reg_status = {4'd0, board_id, isNONE, isQLA, isDQLA, isDRAC, isV30,   // 31:19
                     QLAzeros, DQLAzeros, DQLAones, DRACzeros, DRACones,     // 18:14
                     14'd0 };                                                // 13:0
wire[31:0] reg_version;   // Hardware version
assign reg_version = 32'h42434647;   // "BCFG"

assign reg_rdata_chan0 = (reg_raddr[3:0] == `REG_STATUS) ? reg_status :
                         (reg_raddr[3:0] == `REG_VERSION) ? reg_version :
                         32'd0;

// EMIO feedback (to PS)
assign reg_emio = { reg_version, reg_status };

// --------------------------------------------------------------------------
// Sample data for block read
// This is a simplified version of SampleData.v
// --------------------------------------------------------------------------

reg[31:0] RT_Feedback[0:3];

integer ii;
initial begin
    for (ii = 0; ii <= 3; ii = ii + 1)
        RT_Feedback[ii] = 32'd0;
end

assign sample_rdata = RT_Feedback[sample_raddr[1:0]];
assign sample_chan = 4'd0;

always @(posedge sysclk)
begin
    timestamp <= sample_start&(~sample_busy) ? 32'd0 : timestamp + 1'b1;
    if (sample_start) begin
        sample_busy <= 1;
        if (~sample_busy) begin
            RT_Feedback[0] <= timestamp;
            RT_Feedback[1] <= { reg_status[31:10], IO1[0:9] };
            RT_Feedback[2] <= { IO1[10:33], IO2[0:7] };
            RT_Feedback[3] <= IO2[8:39];
        end
    end
    else if (sample_busy) begin
        sample_busy <= 0;
    end
end

endmodule
