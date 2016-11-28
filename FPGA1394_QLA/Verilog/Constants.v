/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013-2016 ERC CISST, Johns Hopkins University.
 *
 * Purpose: Global constants e.g. device address
 * 
 * Revision history
 *     10/26/13    Zihan Chen    Initial revision
 */
 
 /**************************************************************
  * NOTE:
  *   - InterfaceSpec: 
  *      - https://github.com/jhu-cisst/mechatronics-software/wiki/InterfaceSpec
  *   - Global Constants should be defined here
  **/


`ifndef _fpgaqla_constanst_v_
`define _fpgaqla_constanst_v_

// uncomment for simulation mode
//`define USE_SIMULATION 
//`define USE_CHIPSCOPE

// firmware constants
`define VERSION 32'h514C4131       // hard-wired version number "QLA1" = 0x514C4131 
`define FW_VERSION 32'h06          // firmware version = 6

// address space  
`define ADDR_MAIN     4'h0         // board reg & device reg
`define ADDR_HUB      4'h1         // hub address space
`define ADDR_PROM     4'h2         // prom address space
`define ADDR_PROM_QLA 4'h3         // prom qla address space

// channel 0 (board) registers
`define REG_STATUS   4'd0          // board id (8), fault (8), enable/masks (16)
`define REG_PHYCTRL  4'd1          // phy request bitstream (to request reg r/w)
`define REG_PHYDATA  4'd2          // holder for phy register read contents
`define REG_TIMEOUT  4'd3          // watchdog timer period register
`define REG_VERSION  4'd4          // read-only version number address
`define REG_TEMPSNS  4'd5          // temperature sensors (2x 8 bits concatenated)
`define REG_DIGIOUT  4'd6          // programmable digital outputs
`define REG_FVERSION 4'd7          // firmware version
`define REG_PROMSTAT 4'd8          // PROM interface status
`define REG_PROMRES  4'd9          // PROM result (from M25P16)
`define REG_DIGIN    4'd10         // Digital inputs (home, neg lim, pos lim)
`define REG_ETHRES   4'd12         // Ethernet register I/O result (from KSZ8851)
`define REG_DEBUG    4'd15         // Debug register for testing 
// `define REG_SAFETY  4'd11          // Safety amp disable 

// device register file offsets from channel base
`define OFF_ADC_DATA 4'd0          // adc data register offset (pot + cur)
`define OFF_DAC_CTRL 4'd1          // dac control register offset
`define OFF_POT_CTRL 4'd2          // pot control register offset
`define OFF_POT_DATA 4'd3          // pot data register offset
`define OFF_ENC_LOAD 4'd4          // enc data preload offset
`define OFF_ENC_DATA 4'd5          // enc quadrature register offset
`define OFF_PER_DATA 4'd6          // enc period register offset
`define OFF_FREQ_DATA 4'd7         // enc frequency register offset
`define OFF_DOUT_CTRL 4'd8         // dout hi/lo period (16-bits hi, 16-bits lo)

// FireWire transaction and response codes
`define TC_QWRITE 4'd0            // quadlet write
`define TC_BWRITE 4'd1            // block write
`define TC_QREAD 4'd4             // quadlet read
`define TC_BREAD 4'd5             // block read
`define TC_QRESP 4'd6             // quadlet read response
`define TC_BRESP 4'd7             // block read response
`define TC_CSTART 4'd8            // cycle start packet
`define RC_DONE 4'd0              // complete response code

// FireWire phy request types (Ref: Book P230)
`define LREQ_TX_IMM 3'd0          // immediate transmit header
`define LREQ_TX_ISO 3'd1          // isochronous transmit header
`define LREQ_TX_PRI 3'd2          // priority transmit header
`define LREQ_TX_FAIR 3'd3         // fair transmit header
`define LREQ_REG_RD 3'd4          // register read header
`define LREQ_REG_WR 3'd5          // register write header
`define LREQ_ACCEL 3'd6           // async arbitration acceleration
`define LREQ_RES 3'd7             // reserved, presumably do nothing

`endif  // _fpgaqla_constanst_v_
