/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394-QLA motor controller interface.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/27/11    Paul Thienphrapa    Initial revision (pault at cs.jhu.edu)
 *     02/29/12    Zihan Chen
 *     11/01/15    Peter Kazanzides    Modified for FPGA Rev 2 (Ethernet)
 *     08/29/18    Peter Kazanzides    Added DS2505 module
 *     01/13/20    Peter Kazanzides    Removed KSZ8851 module (now in EthernetIO)
 *     01/22/20    Peter Kazanzides    Removed global reset
 */

`timescale 1ns / 1ps

`define HAS_ETHERNET

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"


module FPGA1394EthQLA
(
    // ieee 1394 phy-link interface
    input            clk1394,   // 49.152 MHz
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // ksz8851-16mll ethernet interface
    output wire      ETH_CSn,       // chip select
    output wire      ETH_RSTn,      // reset
    input wire       ETH_PME,       // power management event, unused
    output wire      ETH_CMD,       // command input for ksz8851 register IO
    output wire      ETH_8n,        // 8 or 16 bit bus
    input wire       ETH_IRQn,      // interrupt request
    output wire      ETH_RDn,
    output wire      ETH_WRn,
    inout [15:0]     SD,

    input wire       clk25m,    // 25.0000 MHz 
    // debug I/Os
    //output wire [3:0] DEBUG,

    // misc board I/Os
    input [3:0]      wenid,     // rotary switch
    inout [1:32]     IO1,
    inout [1:38]     IO2,
    output wire      LED,

    // SPI interface to PROM
    output           XCCLK,    
    input            XMISO,
    output           XMOSI,
    output           XCSn
);

    // System clock
    wire sysclk;
    BUFG clksysclk(.I(clk1394), .O(sysclk));

    // ~12 MHz clock
    wire clkdiv2, clk_12M;
    ClkDiv div2clk(sysclk, clkdiv2);
    defparam div2clk.width = 2;
    BUFG clk12(.I(clkdiv2), .O(clk_12M));

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //
    wire reboot;                // Reboot FPGA
    wire[3:0] board_id;         // 4-bit board id
    assign board_id = ~wenid;

    wire[15:0] reg_raddr;       // 16-bit reg read address
    wire[15:0] reg_waddr;       // 16-bit reg write address
    wire[31:0] reg_rdata;       // reg read data
    wire[31:0] reg_wdata;       // reg write data
    wire reg_wen;               // register write signal
    wire blk_wen;               // block write enable
    wire blk_wstart;            // block write start

    // Wires for block write
    wire bw_reg_wen;            // register write signal from WriteRtData
    wire bw_blk_wen;            // block write enable from WriteRtData
    wire bw_blk_wstart;         // block write start from WriteRtData
    wire[7:0] bw_reg_waddr;     // 16-bit reg write address from WriteRtData
    wire[31:0] bw_reg_wdata;    // reg write data from WriteRtData
    wire bw_write_en;           // 1 -> WriteRtData (real-time block write) is driving write bus

    // Wires for real-time write
    wire  rt_wen;
    wire [3:0] rt_waddr;
    wire [31:0] rt_wdata;

    // Wires for sampling block read data
    wire sample_start;        // Start sampling read data
    wire sample_busy;         // 1 -> data sampler has control of bus
    wire[3:0] sample_chan;    // Channel for sampling
    wire[5:0] sample_raddr;   // Address in sample_data buffer
    wire[31:0] sample_rdata;  // Output from sample_data buffer
    wire[31:0] timestamp;     // Timestamp used when sampling

    wire[31:0] PROM_Status;
    wire[31:0] PROM_Result;

    wire[31:0] ip_address;
    wire[31:0] Eth_Result;

assign LED = IO1[32];     // NOTE: IO1[32] pwr_enable

//******************************* FPGA Module *************************************

// FPGA module, including Firewire and Ethernet
FPGA1394V2 fpga(
    .sysclk(sysclk),
    .reboot(reboot),
    .reboot_clk(clk_12M),
    .board_id(board_id),

    // Firewire
    .data(data),
    .ctl(ctl),
    .lreq(lreq),
    .reset_phy(reset_phy),

    // Ethernet (KSZ8851)
    .ETH_CSn(ETH_CSn),
    .ETH_RSTn(ETH_RSTn),
    .ETH_PME(ETH_PME),
    .ETH_CMD(ETH_CMD),
    .ETH_8n(ETH_8n),
    .ETH_IRQn(ETH_IRQn),
    .ETH_RDn(ETH_RDn),
    .ETH_WRn(ETH_WRn),
    .SD(SD),

    // PROM (M25P16)
    .XCCLK(XCCLK),
    .XMISO(XMISO),
    .XMOSI(XMOSI),
    .XCSn(XCSn),

    // Read/write bus
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata_ext(reg_rdata),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),

    // Block write support
    .bw_reg_waddr(bw_reg_waddr),
    .bw_reg_wdata(bw_reg_wdata),
    .bw_reg_wen(bw_reg_wen),
    .bw_blk_wen(bw_blk_wen),
    .bw_blk_wstart(bw_blk_wstart),
    .bw_write_en(bw_write_en),

    // Real-time write suppor
    .rt_wen(rt_wen),
    .rt_waddr(rt_waddr),
    .rt_wdata(rt_wdata),

    // Sampling support
    .sample_start(sample_start),
    .sample_busy(sample_busy),
    .sample_chan(sample_chan),
    .sample_raddr(sample_raddr),
    .sample_rdata(sample_rdata),
    .timestamp(timestamp),

    // Board register info
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .ip_address(ip_address),
    .Eth_Result(Eth_Result)
);

//******************************* QLA Module **************************************

// divide 25 MHz clock down to 400 kHz for temperature sensor readings
// TO FIX: dividing by 63 gives ~397 kHz (actual factor is 62.5)
wire clk400k_raw, clk400k;
ClkDivI divtemp(clk25m, clk400k_raw);
defparam divtemp.div = 63;
BUFG clktemp(.I(clk400k_raw), .O(clk400k));

QLA qla(
    .sysclk(sysclk),
    .reboot(reboot),
    .board_id(board_id),
    // Supplying 400k clock because different versions of hardware create
    // this clock differently.
    .clk400k(clk400k),
    // ~12MHz clock for ADC
    .clkadc(clk_12M),
    
    // I/O between FPGA and QLA (connectors J1 and J2)
    .IO1(IO1[1:32]),
    .IO2(IO2[1:38]),
    .io_extra(4'd0),

    // Read/write bus
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),

    // Block write support
    .bw_reg_waddr(bw_reg_waddr),
    .bw_reg_wdata(bw_reg_wdata),
    .bw_reg_wen(bw_reg_wen),
    .bw_blk_wen(bw_blk_wen),
    .bw_blk_wstart(bw_blk_wstart),
    .bw_write_en(bw_write_en),

    // Real-time write support
    .rt_wen(rt_wen),
    .rt_waddr(rt_waddr),
    .rt_wdata(rt_wdata),

    // Sampling support
    .sample_start(sample_start),
    .sample_busy(sample_busy),
    .sample_chan(sample_chan),
    .sample_raddr(sample_raddr),
    .sample_rdata(sample_rdata),
    .timestamp(timestamp),

    // Board register info
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .ip_address(ip_address),
    .Eth_Result(Eth_Result)
);

endmodule
