/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394V2-DRAC motor controller interface.
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


module FPGA1394V2DRAC
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
    parameter NUM_MOTORS = 10;
    parameter NUM_ENCODERS = 7;

    // Number of quadlets in real-time block read (not including Firewire header and CRC)
    localparam NUM_RT_READ_QUADS = (4 + 2*NUM_MOTORS + 5*NUM_ENCODERS);
    // Number of quadlets in broadcast real-time block; includes sequence number
    localparam NUM_BC_READ_QUADS = (1+NUM_RT_READ_QUADS);

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
    wire sample_busy;         // Sampling in process
    wire[5:0] sample_raddr;   // Address in sample_data buffer
    wire[31:0] sample_rdata;  // Output from sample_data buffer
    wire sample_read;
    wire[31:0] timestamp;     // Timestamp used when sampling

    // Wires for watchdog
    wire wdog_period_led;     // 1 -> external LED displays wdog_period_status
    wire[2:0] wdog_period_status;
    wire wdog_timeout;        // watchdog timeout status flag
    wire wdog_clear;          // clear watchdog timeout (e.g., on powerup)

assign LED = IO1[21];     // NOTE: IO1[21] pwr_enable

//******************************* FPGA Module *************************************

// FPGA module, including Firewire and Ethernet
FPGA1394V2
    #(.NUM_BC_READ_QUADS(NUM_BC_READ_QUADS))
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
    .sample_raddr(sample_raddr),
    .sample_rdata(sample_rdata),
    .sample_read(sample_read),
    .timestamp(timestamp),

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear)
);

//******************************* dRAC Module **************************************
wire pwmclk;
wire lvds_tx_clk;
wire adc_sck;

wire LVDS_TCLK;
assign IO2[1] = LVDS_TCLK;

wire SCLK_ADC;
assign IO2[14] = SCLK_ADC;



pwm_clk_gen pwm_clk_gen_instance
    (// Clock in ports
    .CLK_IN1            (sysclk),
    // Clock out ports
    .CLK_OUT1           (pwmclk));

DRAC drac(
    .sysclk(sysclk),
    .pwmclk(pwmclk),
    .board_id(board_id),
    
    // I/O between FPGA and QLA (connectors J1 and J2)
    .IO1(IO1[1:32]),
    .IO2(IO2[1:38]),
    // .io_extra(4'd0),

    // Read/write bus
    .reg_raddr_non_sample(reg_raddr),
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
    .sample_raddr(sample_raddr),
    .sample_rdata(sample_rdata),
    .sample_read(sample_read),
    .timestamp(timestamp),

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear),

    .lvds_tx_clk(lvds_tx_clk),
    .adc_sck(adc_sck)
);

ODDR2 #(
    .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1"
    .INIT(1'b0),    // Sets initial state of the Q output to 1'b0 or 1'b1
    .SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
) adc_sck_oddr (
    .Q(SCLK_ADC),     // 1-bit DDR output data
    .C0(adc_sck),  // 1-bit clock input
    .C1(~adc_sck), // 1-bit clock input
    .CE(1'b1),      // 1-bit clock enable input
    .D0(1'b1), // 1-bit data input (associated with C0)
    .D1(1'b0), // 1-bit data input (associated with C1)
    .R(1'b0),   // 1-bit reset input
    .S(1'b0)   // 1-bit set input
);

ODDR2 #(
    .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1"
    .INIT(1'b1), // Sets initial state of the Q output to 1'b0 or 1'b1
    .SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
) lvds_tx_clk_oddr (
    .Q(LVDS_TCLK), // 1-bit DDR output data
    .C0(lvds_tx_clk), // 1-bit clock input
    .C1(~lvds_tx_clk), // 1-bit clock input
    .CE(1'b1), // 1-bit clock enable input
    .D0(1'b1), // 1-bit data input (associated with C0)
    .D1(1'b0), // 1-bit data input (associated with C1)
    .R(1'b0), // 1-bit reset input
    .S(1'b0) // 1-bit set input
);


endmodule
