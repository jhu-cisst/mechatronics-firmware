/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2023 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394V3-BCFG boot configuration firmware.
 *
 * Revision history
 *      2/20/23    Peter Kazanzides    Initial version
 */

`timescale 1ns / 1ps

`define HAS_ETHERNET

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"

module FPGA1394V3BCFG
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
    parameter NUM_MOTORS = 0;
    parameter NUM_ENCODERS = 0;

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
    wire blk_rt_rd;             // real-time block read

    // Timestamp
    wire[31:0] timestamp;

// LED on FPGA
// Lights when PS clock is correctly initialized (clk200_ok)
// and when firmware (this code) is running.
// LED is connected to different pins on V3.0 and V3.1, but we cannot use
// V3.0 with DQLA so the following only supports V3.1.
assign LED = isV30 ? 1'bz : LED_Out;        // FPGA V3.1 (pin U13)

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
    .blk_rt_rd(blk_rt_rd),

    // Timestamp
    .timestamp(timestamp),

    // Watchdog support (not used)
    .wdog_clear(1'd0)
);

//***************************** BootConfig Module ************************************

BootConfig bcfg(
    .sysclk(sysclk),
    .board_id(board_id),
    .isV30(isV30),

    // I/O from FPGA (connectors J1 and J2)
    // Note that extra I/O from FPGA V3.1 are included.
    .IO1(IO1),
    .IO2(IO2),

    // Read/write bus
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata),
    .reg_wdata(reg_wdata),
    .reg_rwait(reg_rwait),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),
    .blk_rt_rd(blk_rt_rd),

    // Timestamp
    .timestamp(timestamp)
);

endmodule
