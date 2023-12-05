/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394V2-QLA motor controller interface.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/27/11    Paul Thienphrapa    Initial revision (pault at cs.jhu.edu)
 *     02/29/12    Zihan Chen
 *     11/01/15    Peter Kazanzides    Modified for FPGA Rev 2 (Ethernet)
 *     08/29/18    Peter Kazanzides    Added DS2505 module
 *     01/13/20    Peter Kazanzides    Removed KSZ8851 module (now in EthernetIO)
 *     01/22/20    Peter Kazanzides    Removed global reset
 *     12/10/22    Peter Kazanzides    Separated code to FPGA1394V2.v and QLA.v
 */

`timescale 1ns / 1ps

`define HAS_ETHERNET

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"


module FPGA1394V2QLA
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
    // output wire [3:0] DEBUG,

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

    // Number of motors and encoders
    parameter NUM_MOTORS = 4;
    parameter NUM_ENCODERS = 4;

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
    wire[3:0] board_id;         // 4-bit board id
    assign board_id = ~wenid;

    wire[15:0] reg_raddr;       // 16-bit reg read address
    wire[15:0] reg_waddr;       // 16-bit reg write address
    wire[31:0] reg_rdata;       // reg read data
    wire[31:0] reg_wdata;       // reg write data
    wire reg_wen;               // register write signal
    wire blk_wen;               // block write enable
    wire blk_wstart;            // block write start
    wire blk_rt_rd;             // real-time block read

    // Timestamp
    wire[31:0] timestamp;

    // Wires for watchdog
    wire wdog_period_led;     // 1 -> external LED displays wdog_period_status
    wire[2:0] wdog_period_status;
    wire wdog_timeout;        // watchdog timeout status flag
    wire wdog_clear;          // clear watchdog timeout (e.g., on powerup)

assign LED = IO1[32];     // NOTE: IO1[32] pwr_enable

//******************************* FPGA Module *************************************

// FPGA module, including Firewire and Ethernet
FPGA1394V2
    #(.NUM_MOTORS(NUM_MOTORS), .NUM_ENCODERS(NUM_ENCODERS))
fpga(
    .sysclk(sysclk),
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
    .blk_rt_rd(blk_rt_rd),

    // Timestamp
    .timestamp(timestamp),

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear)
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
    .blk_rt_rd(blk_rt_rd),

    // Timestamp
    .timestamp(timestamp),

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear)
);

endmodule
