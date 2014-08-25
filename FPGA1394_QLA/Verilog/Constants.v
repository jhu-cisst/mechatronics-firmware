/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013 ERC CISST, Johns Hopkins University.
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

// firmware constants
`define VERSION 32'h514C4131       // hard-wired version number "QLA1" = 0x514C4131 
`define FW_VERSION 32'h04          // firmware version = 4 

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

// `define REG_SAFETY  4'd11          // Safety amp disable 
// `define REG_WDOG    4'd14          // TEMP wdog_samp_disable
// `define REG_REGDISABLE 4'd15       // TEMP reg_disable 

// device register file offsets from channel base
`define OFF_ADC_DATA 4'd0          // adc data register offset (pot + cur)
`define OFF_DAC_CTRL 4'd1          // dac control register offset
`define OFF_POT_CTRL 4'd2          // pot control register offset
`define OFF_POT_DATA 4'd3          // pot data register offset
`define OFF_ENC_LOAD 4'd4          // enc data preload offset
`define OFF_ENC_DATA 4'd5          // enc quadrature register offset
`define OFF_PER_DATA 4'd6          // enc period register offset
`define OFF_FREQ_DATA 4'd7         // enc frequency register offset

`endif  // _fpgaqla_constanst_v_