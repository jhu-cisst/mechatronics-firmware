/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394V3-DRAC motor controller interface.
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

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"

module FPGA1394V3DRAC
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
    // Following are directly connected via constraint file
    // inout wire    E1_MDIO_D,   // eth1 MDIO data
    // inout wire    E2_MDIO_D,   // eth2 MDIO data
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
    parameter NUM_MOTORS = 10;
    parameter NUM_ENCODERS = 7;

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
    wire reg_rwait;             // reg read wait state
    wire reg_wen;               // register write signal
    wire blk_wen;               // block write enable
    wire blk_wstart;            // block write start
    wire req_blk_rt_rd;         // real-time block read request
    wire blk_rt_rd;             // real-time block read

    // Timestamp
    wire[31:0] timestamp;

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
// wire[3:0] io_extra;
// assign io_extra = isV30 ? 4'd0 : { };
// assign IO2[39] = 'bz;
// assign IO2[0] = 'bz;
// assign IO1[33] = io_extra[1]; // dSIB-Si RX

//******************************* FPGA Module *************************************

// FPGA module, including Firewire and Ethernet
FPGA1394V3
    #(.NUM_MOTORS(NUM_MOTORS), .NUM_ENCODERS(NUM_ENCODERS))
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
    // .E1_MDIO_D(E1_MDIO_D),
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
    // .E2_MDIO_D(E2_MDIO_D),
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
    .reg_rwait_ext(reg_rwait),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),
    .req_blk_rt_rd(req_blk_rt_rd),
    .blk_rt_rd(blk_rt_rd),

    // Timestamp
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



pwm_clk_gen_zynq pwm_clk_gen_instance
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
    .io_extra({IO2[39], IO2[0], IO1[33], IO1[0]}),

    // Read/write bus
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata),
    .reg_wdata(reg_wdata),
    .reg_rwait(reg_rwait),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),
    .sample_start(req_blk_rt_rd),
    .sample_read(blk_rt_rd),

    // Timestamp
    .timestamp(timestamp),

    // Watchdog support
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear),

    .lvds_tx_clk(lvds_tx_clk),
    .adc_sck(adc_sck)
);


ODDR #(
   .DDR_CLK_EDGE("OPPOSITE_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE"
   .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
   .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC"
) adc_sck_oddr (
   .Q(SCLK_ADC),   // 1-bit DDR output
   .C(adc_sck),   // 1-bit clock input
   .CE(1'b1), // 1-bit clock enable input
   .D1(1'b1), // 1-bit data input (positive edge)
   .D2(1'b0), // 1-bit data input (negative edge)
   .R(1'b0),   // 1-bit reset
   .S(1'b0)    // 1-bit set
);

ODDR #(
   .DDR_CLK_EDGE("OPPOSITE_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE"
   .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
   .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC"
) lvds_tx_oddr (
   .Q(LVDS_TCLK),   // 1-bit DDR output
   .C(lvds_tx_clk),   // 1-bit clock input
   .CE(1'b1), // 1-bit clock enable input
   .D1(1'b1), // 1-bit data input (positive edge)
   .D2(1'b0), // 1-bit data input (negative edge)
   .R(1'b0),   // 1-bit reset
   .S(1'b0)    // 1-bit set
);

endmodule
