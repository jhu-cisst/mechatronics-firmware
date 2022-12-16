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
 *     08/29/18    Peter Kazanzides    Added DS2505 module
 *     01/22/20    Peter Kazanzides    Removed global reset
 *     04/28/22    Peter Kazanzides    Adapted for FPGA V3
 *     12/10/22    Peter Kazanzides    Separated code to FPGA1394V3.v and QLA.v
 */

`timescale 1ns / 1ps

`define HAS_ETHERNET

`define ETH1    // Also need to update XC7Z020.ucf

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"

module FPGA1394V3QLA
(
    // ieee 1394 phy-link interface
    input            clk1394,   // 49.152 MHz
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // misc board I/Os
    input [3:0]      wenid,     // rotary switch
    inout [0:33]     IO1,
    inout [0:39]     IO2,
    output wire      LED,

    // Ethernet PHYs (RTL8211F)
    output wire      E1_MDIO_C,   // eth1 MDIO clock
    output wire      E2_MDIO_C,   // eth2 MDIO clock
    //Following are directly connected via constraint file
`ifdef ETH1
    //inout wire     E1_MDIO_D,   // eth1 MDIO data
    inout wire       E2_MDIO_D,   // eth2 MDIO data
`else
    inout wire       E1_MDIO_D,   // eth1 MDIO data
    //inout wire     E2_MDIO_D,   // eth2 MDIO data
`endif
    output wire      E1_RSTn,     // eth1 PHY reset
    output wire      E2_RSTn,     // eth2 PHY reset
    input wire       E1_IRQn,     // eth1 IRQ (FPGA V3.1+)
    input wire       E2_IRQn,     // eth2 IRQ (FPGA V3.1+)

    input wire       E1_RxCLK,    // eth1 receive clock (from PHY)
    input wire       E1_RxVAL,    // eth1 receive valid
    inout wire[3:0]  E1_RxD,      // eth1 data bits
    output wire      E1_TxCLK,    // eth1 transmit clock
    output wire      E1_TxEN,     // eth1 transmit enable
    output wire[3:0] E1_TxD,      // eth1 transmit data

    input wire       E2_RxCLK,    // eth2 receive clock (from PHY)
    input wire       E2_RxVAL,    // eth2 receive valid
    inout wire[3:0]  E2_RxD,      // eth2 data bits
    output wire      E2_TxCLK,    // eth2 transmit clock
    output wire      E2_TxEN,     // eth2 transmit enable
    output wire[3:0] E2_TxD,      // eth2 transmit data

    // PS7 interface
    inout[53:0]      MIO,
    input            PS_SRSTB,
    input            PS_CLK,
    input            PS_PORB
);

    // Number of motors and encoders
    parameter NUM_MOTORS = 4;
    parameter NUM_ENCODERS = 4;

    // Number of quadlets in real-time block read (not including Firewire header and CRC)
    localparam NUM_RT_READ_QUADS = (4 + 2*NUM_MOTORS + 5*NUM_ENCODERS);
    // Number of quadlets in broadcast real-time block; includes sequence number
    localparam NUM_BC_READ_QUADS = (1+NUM_RT_READ_QUADS);

    // System clock
    wire sysclk;
    BUFG clksysclk(.I(clk1394), .O(sysclk));

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //
    wire[3:0] board_id;         // 4-bit board id
    assign board_id = ~wenid;
    wire LED_Out;
    wire isV30;

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

    // Wires for watchdog
    wire wdog_period_led;     // 1 -> external LED displays wdog_period_status
    wire[2:0] wdog_period_status;
    wire wdog_timeout;        // watchdog timeout status flag
    wire wdog_clear;          // clear watchdog timeout (e.g., on powerup)

// LED on FPGA
// Lights when PS clock is correctly initialized (clk200_ok)
// and when firmware (this code) is running.
// LED is connected to different pins on V3.0 and V3.1
assign IO1[0] = isV30 ? LED_Out : 1'bz;     // FPGA V3.0 (pin N18)
assign LED = isV30 ? 1'bz : LED_Out;        // FPGA V3.1 (pin U13)

// FPGA V3.1 has 4 extra I/O lines; for now, we treat them as inputs.
wire[3:0] io_extra;
assign io_extra = isV30 ? 4'd0 : { IO2[39], IO2[0], IO1[33], IO1[0] };

//******************************* FPGA Module *************************************

// FPGA module, including Firewire and Ethernet
FPGA1394V3
    #(.NUM_BC_READ_QUADS(NUM_BC_READ_QUADS))
fpga(
    .sysclk(sysclk),
    .board_id(board_id),
    .LED(LED_Out),
    .isV30(isV30),

    // Firewire
    .data(data),
    .ctl(ctl),
    .lreq(lreq),
    .reset_phy(reset_phy),

    // Ethernet port 1
    .E1_RSTn(E1_RSTn),
    .E1_IRQn(E1_IRQn),
    .E1_MDIO_C(E1_MDIO_C),
    .E1_MDIO_D(E1_MDIO_D),
    .E1_RxCLK(E1_RxCLK),
    .E1_RxVAL(E1_RxVAL),
    .E1_RxD(E1_RxD),
    .E1_TxCLK(E1_TxCLK),
    .E1_TxEN(E1_TxEN),
    .E1_TxD(E1_TxD),

    // Ethernet port 2
    .E2_RSTn(E2_RSTn),
    .E2_IRQn(E2_IRQn),
    .E2_MDIO_C(E2_MDIO_C),
    .E2_MDIO_D(E2_MDIO_D),
    .E2_RxCLK(E2_RxCLK),
    .E2_RxVAL(E2_RxVAL),
    .E2_RxD(E2_RxD),
    .E2_TxCLK(E2_TxCLK),
    .E2_TxEN(E2_TxEN),
    .E2_TxD(E2_TxD),

    // PS7 interface
    .MIO(MIO),
    .PS_SRSTB(PS_SRSTB),
    .PS_CLK(PS_CLK),
    .PS_PORB(PS_PORB),

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
    .sample_chan(sample_chan),
    .sample_raddr(sample_raddr),
    .sample_rdata(sample_rdata),
    .timestamp(timestamp),

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear)
);

//******************************* QLA Module **************************************

// ~12 MHz clock
wire clkdiv2, clk_12M;
ClkDiv div2clk(sysclk, clkdiv2);
defparam div2clk.width = 2;
BUFG clk12(.I(clkdiv2), .O(clk_12M));

// divide 49.152 MHz clock down to 400 kHz for temperature sensor readings
wire clk400k_raw;
wire clk400k;
ClkDivI divtemp(sysclk, clk400k_raw);
defparam divtemp.div = 122;

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
     // Extra I/O (FPGA V3.1+)
    .io_extra(io_extra),

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

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear)
);

endmodule
