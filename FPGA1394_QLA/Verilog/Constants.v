/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013-2023 ERC CISST, Johns Hopkins University.
 *
 * Purpose: Global constants e.g. device address
 * 
 * Revision history
 *     10/26/13    Zihan Chen    Initial revision
 *     11/14/19    Jintan Zhang  Added watchdog phase constant
 */
 
 /**************************************************************
  * NOTE:
  *   - InterfaceSpec: 
  *      - https://github.com/jhu-cisst/mechatronics-software/wiki/InterfaceSpec
  *   - Global Constants should be defined here
  **/


`ifndef _fpgaqla_constants_v_
`define _fpgaqla_constants_v_

// uncomment for simulation mode
//`define USE_SIMULATION 
//`define USE_CHIPSCOPE

// firmware constants
`define FW_VERSION 32'h08          // firmware version = 8

// address space  
`define ADDR_MAIN     4'h0         // board reg & device reg
`define ADDR_HUB      4'h1         // hub address space
`define ADDR_PROM     4'h2         // prom address space
`define ADDR_PROM_QLA 4'h3         // prom qla address space
`define ADDR_ETH      4'h4         // ethernet (firewire packet) address space
`define ADDR_FW       4'h5         // firewire packet address space
`define ADDR_DS       4'h6         // Dallas 1-wire memory (dV instrument)
`define ADDR_DATA_BUF 4'h7         // Data buffer address space
`define ADDR_WAVEFORM 4'h8         // Waveform table address space (DOUT waveforms)
`define ADDR_CTRL     4'h9         // Closed-loop control

`define ADDR_MOTOR_CONTROL  4'h9 
`define ADDR_ESPM      4'hA         // buffer for commands intended for the ESPM
`define ADDR_BOARD_SPECIFIC 4'hB

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
`define REG_IPADDR   4'd11         // IP address
`define REG_ETHSTAT  4'd12         // Ethernet status/control register
`define REG_DSSTAT   4'd13         // Dallas chip status
`define REG_IO_EXP   4'd14         // I/O Expander (MAX7317)

// device register file offsets from channel base
// For additional fields, please update SampleData.v to send back data in the correct slot
`define OFF_ADC_DATA  4'h0         // adc data register offset (pot + cur)
`define OFF_DAC_CTRL  4'h1         // dac control register offset
`define OFF_UNUSED_02 4'h2         // (was pot control register offset)
`define OFF_UNUSED_03 4'h3         // (was pot data register offset)
`define OFF_ENC_LOAD  4'h4         // enc data preload offset
`define OFF_ENC_DATA  4'h5         // enc quadrature register offset
`define OFF_PER_DATA  4'h6         // enc period register offset
`define OFF_QTR1_DATA 4'h7         // enc most recent quarter offset
`define OFF_DOUT_CTRL 4'h8         // dout hi/lo period (16-bits hi, 16-bits lo)
`define OFF_QTR5_DATA 4'h9         // enc previous quarter offset
`define OFF_RUN_DATA  4'hA         // enc running counter offset
`define OFF_MOTOR_CONFIG 4'hB      // motor configuration
`define OFF_MOTOR_STATUS 4'hC      // motor status
`define OFF_UNUSED_13 4'hD
`define OFF_UNUSED_14 4'hE
`define OFF_UNUSED_15 4'hF

`define ENC_MIDRANGE 24'h800000    // encoder mid-range value

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

// Byte offsets into Ethernet frame (Begin is offset to first byte, End is offset to byte
// after last byte)
`define ETH_Frame_Begin      6'd0                     // ********* FrameHeader [length=14] *********
`define ETH_Dest_MAC         `ETH_Frame_Begin         // Destination MAC address
`define ETH_Src_MAC          `ETH_Frame_Begin+6       // Source MAC address
`define ETH_Frame_Length     `ETH_Frame_Begin+12      // EtherType/Length
`define ETH_Frame_End        `ETH_Frame_Begin+14      // ******** End of Frame Header *************
`define ETH_IPv4_Begin       `ETH_Frame_End           // ******* IPv4 Header (14) [length=20]  *****
`define ETH_IPv4_Protocol    `ETH_IPv4_Begin+9        // Protocol (UDP=17, ICMP=1)
`define ETH_IPv4_Checksum    `ETH_IPv4_Begin+10       // Header checksum
`define ETH_IPv4_End         `ETH_IPv4_Begin+20       // ******** End of IPv4 Header **************
`define ETH_UDP_Begin        `ETH_IPv4_End            // ******* UDP Header (34) [Length=8] *******
`define ETH_UDP_hostPort     `ETH_UDP_Begin           // Source (host) port
`define ETH_UDP_destPort     `ETH_UDP_Begin+2         // Destination (fpga) port
`define ETH_UDP_Length       `ETH_UDP_Begin+4         // UDP Length
`define ETH_UDP_Checksum     `ETH_UDP_Begin+6         // UDP Checksum
`define ETH_UDP_End          `ETH_UDP_Begin+8         // ******** End of UDP Header **************

// Bit indices in Ethernet recv_info_din and recv_info_dout (FPGA V3)
`define ETH_RECV_CRC_ERROR_BIT 26
`define ETH_RECV_FLUSH_BIT 31

// Watchdog period status 
`define WDOG_DISABLE     3'b0     // watchdog period = 0ms (disabled)
`define WDOG_TIMEOUT     3'b110   // watchdog timeout has occurred
`define WDOG_PHASE_ONE   3'b001   // watchdog period between 0ms and 50 ms
`define WDOG_PHASE_TWO   3'b010   // watchdog period between 50ms and 100 ms
`define WDOG_PHASE_THREE 3'b011   // watchdog period between 100ms and 150 ms
`define WDOG_PHASE_FOUR  3'b100   // watchdog period between 150ms and 200 ms
`define WDOG_PHASE_FIVE  3'b101   // watchdog period larger than 200ms

// espm packet
`define ADDR_SWITCH  6'h00
`define ADDR_ESII    6'h08
`define ADDR_ESPM_PRELOAD_VALID    6'h10
`define ADDR_INST_MODEL    6'h18
`define ADDR_INST_ID       6'h20

`define ESPM_POT_DATA 'd0
`define ESPM_POS_DATA 'd1
`define ESPM_PER_DATA 'd2
`define ESPM_QTR1_DATA 'd3
`define ESPM_QTR5_DATA 'd4
`define ESPM_RUN_DATA 'd5

// Address space ADDR_MOTOR_CONTROL
`define OFF_MOTOR_CONTROL_MODE 4'h0
`define OFF_MOTOR_CONTROL_CURRENT_KP 4'h1
`define OFF_MOTOR_CONTROL_CURRENT_KI 4'h2
`define OFF_MOTOR_CONTROL_CURRENT_I_TERM_LIMIT 4'h3
`define OFF_MOTOR_CONTROL_CURRENT_OUTPUT_LIMIT 4'h4
`define OFF_MOTOR_CONTROL_DUTY_CYCLE 4'hA
`define OFF_MOTOR_CONTROL_FAULT 4'hB
`define OFF_MOTOR_CONTROL_TUNE 4'hC
`define OFF_MOTOR_CONTROL_DEBUG 4'hF

`define MOTOR_CONTROL_MODE_RESET_CONTROLLER 4'h2
`define MOTOR_CONTROL_MODE_VOLTAGE 4'h1
`define MOTOR_CONTROL_MODE_CURRENT 4'h0

`endif  // _fpgaqla_constants_v_
