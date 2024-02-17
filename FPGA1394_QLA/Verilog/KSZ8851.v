/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2024 ERC CISST, Johns Hopkins University.
 *
 * This module implements the link layer interface to the KSZ8851 MAC/PHY chip.
 *
 * Revision history
 *     12/21/15    Peter Kazanzides    Initial Revision
 *     11/28/16    Zihan Chen          Added Disable/Enable in RECEIVE
 *     11/5/19     Peter Kazanzides    Added UDP support
 *     1/13/20     Peter Kazanzides    Incorporated low-level interface from KSZ8851.v
 *     8/27/22     Peter Kazanzides    Extracted KSZ8851 code from EthernetIO.v
 */

// global constant e.g. register & device address
`include "Constants.v"

// --------------------------------------------------------------------------
// Register Address Translator: from 8-bit offset to 16-bit address required by KSZ8851.
// The addressing is a bit unusual when the KSZ8851 is configured with a 16-bit bus;
// specifically, it appears to split the I/O space into 32-bit chunks. The 4 ByteEnable
// lines can select any one or two 8-bit registers from this 32-bit chunk. For an
// 8-bit transfer, only one ByteEnable should be set. For a 16-bit transfer, the most
// typical scenario would be to select the first two bytes (ByteEnable=4'b0011) or
// the last two bytes (ByteEnable=4'b1100).
// --------------------------------------------------------------------------
module getAddr(
    input wire[7:0] offset,     // register address (0x00-0xFF)
    input wire length,          // length: 0-byte(8-bit), 1-word(16-bit)
    output wire[15:0] Addr      // address recognized by ksz8851 (on SD lines)
    );

    // the rule of translation is available in the step-by-step guide of ksz8851-16mll
    wire[1:0] offsetTail;
    assign offsetTail = offset[1:0];

    // SD[15:12]  are for BE[3:0] (BE = Byte Enable)
    // The following code does not handle 16-bit transfers for odd addresses (i.e.,
    // if offsetTail is 1 or 3).
    //   BE[0]=1 if address is multiple of 4 (0x00, 0x04, 0x08, ...)
    //   BE[1]=1 if 16-bit access and multiple of 4 OR 8-bit access and odd (0x01, 0x03, ...)
    //   BE[2]=1 if address has 2 (0x02, 0x06, 0x0A, ...)
    //   BE[3]=1 if 16-bit access and has 2 OR 8-bit access and has 3
    assign Addr[12] = (offsetTail==0) ? 1'b1 : 1'b0;
    assign Addr[13] = ((~length && offsetTail==1) || (length && offsetTail==0)) ? 1'b1 : 1'b0;
    assign Addr[14] = (offsetTail==2) ? 1'b1 : 1'b0;
    assign Addr[15] = ((~length && offsetTail==3) || (length && offsetTail==2)) ? 1'b1 : 1'b0;
    assign Addr[7:2] = offset[7:2];

    assign Addr[1:0] = offsetTail;  // not necessary, for better integrity
    assign Addr[11:8] = 4'h0;       // not necessary, for better integrity

endmodule

// constants KSZ8851 chip
`define ETH_ADDR_MARL    8'h10     // Host MAC Address Reg Low
`define ETH_ADDR_MARM    8'h12     // Host MAC Address Reg Middle
`define ETH_ADDR_MARH    8'h14     // Host MAC Address Reg High
`define ETH_ADDR_TXCR    8'h70     // Transmit Control Reg
`define ETH_ADDR_RXCR1   8'h74     // RX Control Register 1
`define ETH_ADDR_RXCR2   8'h76     // RX Control Register 2
`define ETH_ADDR_TXMIR   8'h78     // TXQ Memory Information Reg
`define ETH_ADDR_RXFHSR  8'h7C     // RX Frame Header Status Reg
`define ETH_ADDR_RXFHBCR 8'h7E     // RX Frame Header Byte Count Reg
`define ETH_ADDR_TXQCR   8'h80     // TXQ Command Reg
`define ETH_ADDR_RXQCR   8'h82     // RXQ Command Reg
`define ETH_ADDR_TXFDPR  8'h84     // TX Frame Data Pointer Reg
`define ETH_ADDR_RXFDPR  8'h86     // RX Frame Data Pointer Reg
`define ETH_ADDR_IER     8'h90     // Interrupt Enable Reg
`define ETH_ADDR_ISR     8'h92     // Interrupt Status Reg
`define ETH_ADDR_RXFCTR  8'h9C     // RX Frame Count and Threshold Reg
`define ETH_ADDR_MAHTR1  8'hA2     // MAC Address Hash Table Reg 1
`define ETH_ADDR_MAHTR2  8'hA4     // MAC Address Hash Table Reg 2
`define ETH_ADDR_CIDER   8'hC0     // Chip ID and Enable Reg
`define ETH_ADDR_PMECR   8'hD4     // Power management event control register
`define ETH_ADDR_P1SR    8'hF8     // Port 1 status register

module KSZ8851(
    // global clock
    input wire sysclk,

    // board id (rotary switch)
    input wire[3:0] board_id,

    // Interface to KSZ8851
    input wire ETH_IRQn,  // interrupt request
    output reg ETH_RSTn,  // chip reset (active low)
    output wire ETH_CMD,  // 0 for data, 1 for address
    output wire ETH_RDn,  // read strobe (active low)
    output wire ETH_WRn,  // write strobe (active low)
    inout[15:0] SD,       // address/data bus

    // Firewire interface to KSZ8851 (for testing)
    input  wire fw_reg_wen,          // write enable
    input  wire[15:0] fw_reg_waddr,  // write address
    input  wire[31:0] fw_reg_wdata,  // write data
    output reg[15:0]  eth_data,      // Data to/from KSZ8851
    output wire[7:0] eth_status,     // Status feeedback

    // Register interface to Ethernet memory space (for debugging)
    input  wire[15:0] reg_raddr,
    output reg[31:0] reg_rdata,

    // Interface from Firewire (for sending packets via Ethernet)
    input wire sendReq,              // Send request from FireWire

    // Interface to EthernetIO
    output reg resetActive,           // Indicates that reset is active
    output reg isForward,             // Indicates that FireWire receiver is forwarding to Ethernet
    input wire responseRequired,      // Indicates that the received packet requires a response
    input wire[15:0] responseByteCount,   // Number of bytes in required response
    // Ethernet receive
    output reg recvRequest,           // Request EthernetIO to start receiving
    input wire recvBusy,              // From EthernetIO
    output wire recvReady,            // Indicates that recv_word is valid
    output wire[15:0] recv_word,      // Word received via Ethernet (`SDSwapped for KSZ8851)
    // Ethernet send
    output reg sendRequest,           // Request EthernetIO to start providing data to be sent
    input wire sendBusy,              // From EthernetIO
    output wire sendReady,            // Request EthernetIO to provide next send_word
    input wire[15:0] send_word,       // Word to send via Ethernet (SDRegDWR for KSZ8851)
    // Timing measurements (do not include times for KSZ8851 to receive/transmit packet)
    output reg[15:0] timeReceive,     // Time when receive portion finished
    output reg[15:0] timeSinceIRQ,    // Running time counter since last IRQ
    // Feedback bits
    input wire bw_active,             // Indicates that block write module is active
    output wire isHub,                // Whether this board directly connected to host PC
    output wire ethInternalError      // Error summary bit to EthernetIO
);

reg initOK;            // 1 -> Initialization successful
reg isWrite;           // 0 -> Read, 1 -> Write
reg isWord;            // 0 -> Byte, 1 -> Word
reg[7:0] RegAddr;      // Register address (N/A for DMA mode)
reg[15:0] WriteData;   // Data to be written to chip (N/A for read)
wire[15:0] ReadData;   // Data read from chip (N/A for write)
reg linkStatus;        // 1 -> Ethernet link good (cable connected)

assign ReadData = eth_data;

`define ReadDataSwapped {ReadData[7:0], ReadData[15:8]}
`define WriteDataSwapped {WriteData[7:0], WriteData[15:8]}

// Address translator
wire[15:0] Addr16;
getAddr newAddr(
    .offset(RegAddr),
    .length(isWord),
    .Addr(Addr16)
);

// tri-state bus configuration
// Drive bus except when ETH_RDn is active (low)
reg[15:0] SDReg;
reg[15:0] SDRegDWR;  // For DMA write
assign SD = (ETH_RDn&~isDMARead) ? (isDMAWrite ? ((state == ST_SEND_DMA_WAIT) ? send_word : SDRegDWR) : SDReg) : 16'hz;

`define SDSwapped {SD[7:0], SD[15:8]}
`define SDRegSwapped {SDReg[7:0], SDReg[15:8]}

assign recv_word = `SDSwapped;

// address decode for KSZ8851 I/O access
wire   ksz_reg_wen;
assign ksz_reg_wen = (fw_reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHSTAT}) ? fw_reg_wen : 1'b0;

reg       ksz_req;    // External request pending for KSZ I/O
reg[31:0] ksz_wdata;  // Cached register for KSZ I/O request

reg isDMARead;      // 1 -> DMA Read process should have control
reg isDMAWrite;     // 1 -> DMA Write process should have control

reg[2:0] RWcnt;     // Counter used for reading/write KSZ8851
reg[2:0] lastRWcnt;

// Register Read/Write from/to KSZ8851
wire Reg_RDn;
wire Reg_WRn;
wire Reg_CMD;
// DMA Read/Write from/to KSZ8851
wire DMA_RDn;          // Output from DMA Read process
wire DMA_WRn;          // Output from DMA Write process

// KSZ8851 datasheet specifies that WRn and RDn must have minimum active (low) time
// of 40 ns (2 sysclk) and minimum inactive (high) time of 10 ns.
assign ETH_WRn = isDMARead ? 1'b1    : (isDMAWrite ? DMA_WRn : Reg_WRn);
assign ETH_RDn = isDMARead ? DMA_RDn : (isDMAWrite ? 1'b1 : Reg_RDn);
assign ETH_CMD = (isDMAWrite|isDMARead) ? 1'b0 : Reg_CMD;

// Register for latching ~ETH_IRQn, which is an asynchronous signal
reg ethIrq;            // 1 -> Ethernet interrupt request

reg[20:0] initCount;

//*****************************************************************
//  ETHERNET Receive DMA
//*****************************************************************

reg[1:0] skipCnt;       // For skipping first 3 words in RXQ

// Shift register for I/O control. The register is shifted left with each clock, with the left-most
// bit placed on the right (shift and rotate). Each state (except IDLE) is entered with
// recvCtrl==5'b00001 and goes through the following sequence:
//   00001   (DMA_RDn=0), wait
//   00010   (DMA_RDn=0), wait
//   00100   (DMA_RDn=0), read data (recvReady=1)
//   01000   (DMA_RDn=0), use data
//   10000   (DMA_RDn=1), transition to next state
reg[4:0] recvCtrl = 5'b00001;

assign DMA_RDn = recvCtrl[4];

// We sample the data after two cycles
assign recvReady = (skipCnt == 2'd0) ? recvCtrl[2] : 1'b0;
// Transition to next state when recvCtrl=10000, so that we enter each new state with
// recvCtrl=00001. Note that nextRecvState must be set before recvTransition -- usually
// it is set when dataValid, though it can be set earlier if the next state transition
// does not depend on the data read from the KSZ8851.
wire recvTransition;
assign recvTransition = recvCtrl[4];

//*****************************************************************
//  ETHERNET Send DMA
//*****************************************************************

// sendCtrl==100 in the IDLE state.
// When entering a state, sendCtrl==100 (DMA_WRn inactive)
//    Writing data (via SDRegDWR) will coincide with falling edge of DMA_WRn
// Transition to next state (or increment sfw_count or replyCnt) when sendCtrl==010
//    (with rising edge of DMA_WRn)
reg [2:0] sendCtrl = 3'b100;
assign DMA_WRn = sendCtrl[2];

wire   sendTransition;
assign sendTransition = sendCtrl[1];
// sendReady is 1 cycle before the transition; note that we have to set sendReady one time
// before entering ST_SEND_DMA_WAIT so that send_word contains valid data when we enter
// ST_SEND_DMA_WAIT. Thus, we also set it in ST_SEND_DMA_BYTECOUNT.
// This is due to a design change in EthernetIO.v.
assign sendReady = ((state == ST_SEND_DMA_BYTECOUNT) ||
                    (state == ST_SEND_DMA_WAIT)) ? sendCtrl[0] : 1'b0;

// Error flags
reg ethFwReqError;     // 1 -> I/O request received (from Firewire) when not in idle state
reg ethStateError;     // 1 -> Invalid Ethernet state in top-level state machine

// Summary of internal error bits
assign ethInternalError = ethStateError;

`ifdef DEBOUNCE_STATES
reg[7:0] numStateGlitch;    // Number of invalid states (for debugging)
`endif
reg[7:0] numReset;          // Number of times reset called

`ifdef HAS_DEBUG_DATA
`ifdef DEBOUNCE_STATES
// For debugging
reg[31:0] errorInfo;
`endif
`endif

reg resetRequest;      // 1 -> reset requested (e.g., when Ethernet cable unplugged)

// IER value
// B15: LCIE link change interrupt enable
// B14: TXIE transmit interrupt enable
// B13: RXIE receive interrupt enable
localparam[15:0] ETH_VALUE_IER = 16'hA000;

// RXQCR value
// B5: RXFCTE enable QMU frame count threshold (1)
// B4: ADRFE  auto-dequeue
// Not enabling auto-dequeue because we flush packet
// instead of reading to end.
localparam[15:0] ETH_VALUE_RXQCR = 16'h0020;

// RXCR1 value
// 7: enable UDP, TCP, and IP checksums
// C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
// E: enable broadcast, multicast, and unicast
// Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
localparam[15:0] ETH_VALUE_RXCR1 = 16'h7CE0;

// Enable QMU ICMP/UDP/TCP/IP checksum, transmit flow control, padding, and CRC
localparam[15:0] ETH_VALUE_TXCR = 16'h01EE;

localparam[4:0]
    ST_IDLE = 5'd0,
    // reset/init states
    ST_RESET_ASSERT = 5'd1,         // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 5'd2,           // wait after bringing reset high -- 50 msec
    ST_INIT_CHECK_CHIPID = 5'd3,
    ST_HANDLE_PORT_STATUS = 5'd4,
    // run program
    ST_RUN_PROGRAM_EXECUTE = 5'd5,
    // interrupt handler states
    ST_IRQ_HANDLER = 5'd6,
    ST_IRQ_DISPATCH = 5'd7,
    // receive states
    ST_RECEIVE_FRAME_COUNT = 5'd8,
    ST_RECEIVE_FRAME_STATUS = 5'd9,
    ST_RECEIVE_FRAME_LENGTH = 5'd10,
    ST_RECEIVE_DMA_REQUEST = 5'd11,
    ST_RECEIVE_DMA_WAIT = 5'd12,
    ST_RECEIVE_FLUSH_WAIT = 5'd13,
    // send states
    ST_SEND_ENABLE_DMA = 5'd14,
    ST_SEND_DMA_REQUEST = 5'd15,
    ST_SEND_DMA_CONTROLWORD = 5'd16,
    ST_SEND_DMA_BYTECOUNT = 5'd17,
    ST_SEND_DMA_WAIT = 5'd18,
    ST_SEND_DMA_DWORD_PAD = 5'd19,
    ST_SEND_TXQ_ENQUEUE = 5'd20,
    ST_SEND_TXQ_ENQUEUE_WAIT = 5'd21,
    ST_SEND_END = 5'd22,
    // KSZIO states
    ST_WAVEFORM_ADDR = 5'd23,    // write the address to the KSZ8851
    ST_WAVEFORM_DATA = 5'd24;    // read/write data from/to the KSZ8851

// Current state
reg[4:0] state = ST_RESET_ASSERT;
// Next state
reg[4:0] nextState;
`ifdef DEBOUNCE_STATES
reg[4:0] nextStateLatched = ST_RESET_ASSERT;
`endif
// State to return to after ST_WAVEFORM_DATA
reg[4:0] retState = ST_IDLE;

// Debugging support
assign eth_io_isIdle = (state == ST_IDLE) ? 1'd1 : 1'd0;

// Keep track of areas where state machine may wait
// for unknown amount of time (for debugging)
localparam [1:0]
    WAIT_NONE = 2'd0,
    WAIT_RECEIVE_DMA = 2'd1,
    WAIT_SEND_DMA = 2'd2,
    WAIT_FLUSH = 2'd3;

reg[1:0] waitInfo;

reg FrameValid;

// Non-zero initial values
initial begin
   //ETH_RSTn = 1'd1;
   isWord = 1'd1;
end

// Ethernet status. Note that these bits supply the upper bits of the Ethernet status register,
// so bit 7 actually corresponds to bit 31.
//   Bit 7: 1 to indicate that Ethernet is present -- must be kept for backward compatibility
//   Bit 6: 1 to indicate that an error occurred in KSZ8851 -- must be kept for backward compatibility
//   Other bits can be assigned as needed
assign eth_status[7] = 1'b1;             // 1 -> Ethernet is present
assign eth_status[6] = ethFwReqError;    // 1 -> Could not access KSZ registers via FireWire
assign eth_status[5] = initOK;           // 1 -> Initialization OK
assign eth_status[4] = ethStateError;    // 1 -> Invalid state detected
assign eth_status[3] = linkStatus;       // Link status
assign eth_status[2] = eth_io_isIdle;    // Ethernet I/O state machine is idle
assign eth_status[1:0] = waitInfo;       // Wait points in KSZ8851.v

reg isInIRQ;           // True if IRQ handle routing
reg[15:0] RegISR;      // 16-bit ISR register
`ifdef HAS_DEBUG_DATA
reg[15:0] RegISROther; // Unexpected ISR value (for debugging)
`endif
reg[7:0] FrameCount;   // Number of received frames
reg[11:0] rxPktWords;  // Num of words in receive queue
reg[11:0] txPktWords;  // Num of words sent in response

`ifdef HAS_DEBUG_DATA
reg[15:0] timeSend;          // Time when send portion finished
reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[7:0]  numPacketInvalid;  // Number of invalid Ethernet frames received
reg[7:0] numPacketSent;      // Number of packets sent to host PC
`endif

`ifdef HAS_DEBUG_DATA
reg[9:0] bw_wait;
`endif

// -----------------------------------------------
// Debug data
// -----------------------------------------------
`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:15];
assign DebugData[0]  = "2GBD";  // DBG2 byte-swapped
assign DebugData[1]  = { isDMAWrite, sendRequest, ~ETH_IRQn, isInIRQ,     // 31:28
                         linkStatus, 3'd0,                                // 27:24
                         24'd0 };
assign DebugData[2]  = { 3'd0, state, 3'd0, retState, 3'd0, nextState, 3'd0, runPC }; // 5, 5, 5, 5
assign DebugData[3]  = { responseByteCount, RegISROther};                 // 16, 16
assign DebugData[4]  = { 6'd0, bw_wait, FrameCount, numPacketSent};       // 10, 8, 8
assign DebugData[5]  = { 4'd0, txPktWords, 4'd0, rxPktWords };            // 12, 12
assign DebugData[6]  = { timeSend, timeReceive };                         // 16, 16
assign DebugData[7]  = { numReset, numPacketInvalid, numPacketValid };    // 8, 8, 16
`ifdef DEBOUNCE_STATES
assign DebugData[8] = { 16'd0, numStateGlitch, 3'd0, nextStateLatched };  // 8, 5
assign DebugData[9] = errorInfo;
`else
assign DebugData[8] = 32'd0;
assign DebugData[9] = 32'd0;
`endif
assign DebugData[10] = 32'd0;
assign DebugData[11] = 32'd0;
assign DebugData[12] = 32'd0;
assign DebugData[13] = 32'd0;
assign DebugData[14] = 32'd0;
assign DebugData[15] = 32'd0;
`endif

//***************************************************************************************
// Microcode for KSZ8851 register access
//
// A simple microcode is defined to streamline access to the KSZ8851 registers.
// This is used for both initializing the registers and for runtime access to
// the registers (i.e., in response to packets received).
//
// The instruction length is 26 bits, defined as follows:
//   Write  Mod   Addr    Data
//     25    24  23:16    15:0
//
// Bit 25:     Write (1) or Read (0)
// Bit 24:     Mod flag: Used to indicate special processing
// Bits 23:16  Address of register to read or write
// Bits 15:0   Data to write to register; for Read commands, the 5 LSB indicate
//             the next state
//
//   - The Mod flag is used to indicate that the system should branch to the
//     ST_IRQ_DISPATCH state. This is only needed for Write commands because the
//     Read commands already indicate the next state.
//
// The microcode does not include any branching statements (other than using the Mod
// flag to indicate a branch to ST_IRQ_DISPATCH), but branches can be initiated external
// to the program by changing the program counter (runPC).
//
// There is also some use of self-modifying code; specifically, ST_IRQ_DISPATCH changes
// the contents of the ID_CLEAR_INTERRUPT instruction (ClearInterrupt register).
//***************************************************************************************

localparam CMD_WRITE = 1'd1,  // Write to register
           CMD_READ  = 1'd0,  // Read from register
           CMD_NOP   = 1'd0,  // No operation
           CMD_BRA   = 1'd1;  // Special-case branch

`define WRITE_BIT 25
`define MOD_BIT 24
`define ADDR_BITS 23:16
`define DATA_BITS 15:0
`define NEXT_BITS 4:0

// Program for initialization (0-16) and run-time (16-31)
wire[25:0] RunProgram[0:31];
reg[25:0] ClearInterrupt;

// Some useful indices
localparam[4:0]
   ID_CHIP_ID = 5'd0,
   ID_MAC_LOW = 5'd1,
   ID_MAC_MID = 5'd2,
   ID_MAC_HIGH = 5'd3,
   ID_READ_PORT1SR = 5'd16,
   ID_READ_INTERRUPT = 5'd17,
   ID_DISABLE_INTERRUPT = 5'd18,
   ID_CLEAR_INTERRUPT = 5'd19,
   ID_READ_FRAME_COUNT = 5'd20,
   ID_READ_FRAME_STATUS = 5'd21,
   ID_READ_FRAME_LENGTH = 5'd22,
   ID_SET_FRAME_POINTER = 5'd23,
   ID_ENABLE_DMA_RECV = 5'd24,
   ID_FLUSH_FRAME = 5'd25,
   ID_READ_CMD_REG = 5'd26,
   ID_ENABLE_INTERRUPT = 5'd27,
   ID_ENABLE_DMA_SEND = 5'd28,
   ID_DISABLE_DMA = 5'd29,
   ID_TXQ_ENQUEUE = 5'd30,
   ID_TXQ_READ = 5'd31;

// Read Chip ID
assign RunProgram[ID_CHIP_ID] = {CMD_READ, CMD_NOP, `ETH_ADDR_CIDER, 11'd0, ST_INIT_CHECK_CHIPID};
// Set MAC address (4 LSB below should be set to board_id)
assign RunProgram[ID_MAC_LOW] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MARL, 12'h940, board_id};
assign RunProgram[ID_MAC_MID] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MARM, 16'h0E13};
assign RunProgram[ID_MAC_HIGH] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MARH, 16'hFA61};
// Enable QMU transmit frame data pointer auto increment
assign RunProgram[4] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXFDPR, 16'h4000};
assign RunProgram[5] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXCR, ETH_VALUE_TXCR};
// B14: Enable QMU receive frame data pointer auto increment
// B12: Decrease write data valid sample time to 4 nS (max) -- currently not set
// B11: Set Little Endian (0) or Big Endian (1)-- currently, Little Endian.
// According to KSZ8851 Step-by-Step Programmer's Guide, in Little Endian mode,
// registers are:
//     ____________________________________
//     | Data 15-8 (MSB) | Data 7-0 (LSB) |
//     ------------------------------------
// The Verilog code has been written assuming a Little Endian convention (e.g.,
// reg[31:0] myVar), rather than Big Endian (e.g., reg[0:31] myVar), though this
// refers to the bit order, not just the byte order. Nevertheless, it is more
// convenient to keep the KSZ8851 in Little Endian mode.
// Note, however, that Ethernet and FireWire are both Big Endian, so some byte-swapping
// is needed.
assign RunProgram[6] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXFDPR, 16'h4000};
// Configure receive frame threshold for 1 frame
assign RunProgram[7] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXFCTR, 16'h0001};
// 7: enable UDP, TCP, and IP checksums
// C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
// E: enable broadcast, multicast, and unicast
// Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
assign RunProgram[8] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXCR1, ETH_VALUE_RXCR1};
// Enable UDP checksums; pass packets with 0 checksum
assign RunProgram[9] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXCR2, 16'h001C};
// Following are hard-coded values for which hash register to use and which bit to set
// for multicast address FB:61:0E:13:94:FF. This is obtained by computing the CRC for
// this MAC address and then using the first two (most significant) bits to determine
// the register and the next four bits to determine which bit to set.
// See code in mainEth1394.cpp.
assign RunProgram[10] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MAHTR1, 16'h0008};
// Following are hard-coded values for UDP multicast address 224.0.0.100 (also see
// code in mainEth1394.cpp). But, not using it for the following two reasons:
//   1) Already have 32 entries in RunProgram, so would need to add another bit
//      of address space and renumber.
//   2) Hard-coding for 224.0.0.100 would not allow different UDP Multicast addresses
//      to be set.
// Thus, we do not use UDP Multicast when talking to FPGA V2, which is fine because we will
// only support an Ethernet-Only network for FPGA V3 (FPGA V2 will use Ethernet/Firewire bridge).
// assign RunProgram[] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MAHTR2, 16'h0020};
// RXQCR value
// B5: RXFCTE enable QMU frame count threshold (1)
// B4: ADRFE  auto-dequeue
// Not enabling auto-dequeue because we flush packet
// instead of reading to end.
assign RunProgram[11] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR};
// Clear all pending interrupts
assign RunProgram[12] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_ISR, 16'hFFFF};
// Enable receive and link change interrupts
assign RunProgram[13] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_IER, ETH_VALUE_IER};
// Enable transmit
assign RunProgram[14] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXCR, ETH_VALUE_TXCR[15:1], 1'd1};
// Enable receive
assign RunProgram[15] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXCR1, ETH_VALUE_RXCR1[15:1], 1'd1};
// Check link status. This is the last command for initialization, but will also be called
// in response to a link change interrupt. Note that ST_HANDLE_PORT_STATUS will transition
// to ST_IDLE if called during initialization and to ST_IRQ_DISPATCH if called as a result
// of the interrupt (isInIRQ).
assign RunProgram[ID_READ_PORT1SR]      = {CMD_READ,  CMD_NOP, `ETH_ADDR_P1SR,  11'd0, ST_HANDLE_PORT_STATUS};
// The following commands are used at runtime
assign RunProgram[ID_READ_INTERRUPT]    = {CMD_READ,  CMD_NOP, `ETH_ADDR_ISR, 11'd0, ST_IRQ_HANDLER};
assign RunProgram[ID_DISABLE_INTERRUPT] = {CMD_WRITE, CMD_BRA, `ETH_ADDR_IER, 16'd0};
// Clear interrupt (data field updated in ST_IRQ_DISPATCH)
assign RunProgram[ID_CLEAR_INTERRUPT]   = ClearInterrupt;
initial ClearInterrupt                  = {CMD_WRITE, CMD_BRA, `ETH_ADDR_ISR, 16'd0};
assign RunProgram[ID_READ_FRAME_COUNT]  = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXFCTR, 11'd0, ST_RECEIVE_FRAME_COUNT};
assign RunProgram[ID_READ_FRAME_STATUS] = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXFHSR, 11'd0, ST_RECEIVE_FRAME_STATUS};
assign RunProgram[ID_READ_FRAME_LENGTH] = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXFHBCR, 11'd0, ST_RECEIVE_FRAME_LENGTH};
// Set QMU RXQ frame pointer to 0 (not decreasing write sample time)
assign RunProgram[ID_SET_FRAME_POINTER] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXFDPR, 16'h4000};
assign RunProgram[ID_ENABLE_DMA_RECV]   = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
// Flush the rest of the packet: Clear DMA bit (bit 3) and set flush bit (bit 0)
assign RunProgram[ID_FLUSH_FRAME]       = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:1],1'b1};
assign RunProgram[ID_READ_CMD_REG]      = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXQCR, 11'd0, ST_RECEIVE_FLUSH_WAIT};
assign RunProgram[ID_ENABLE_INTERRUPT]  = {CMD_WRITE, CMD_NOP, `ETH_ADDR_IER, ETH_VALUE_IER};
assign RunProgram[ID_ENABLE_DMA_SEND]   = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
assign RunProgram[ID_DISABLE_DMA]       = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:0]};
assign RunProgram[ID_TXQ_ENQUEUE]       = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXQCR, 16'h0001};
assign RunProgram[ID_TXQ_READ]          = {CMD_READ,  CMD_NOP, `ETH_ADDR_TXQCR, 11'd0, ST_SEND_TXQ_ENQUEUE_WAIT};

reg[4:0] runPC;    // Program counter for RunProgram

// Reg_CMD is 0 except when writing address to the KSZ8851
assign Reg_CMD = (state == ST_WAVEFORM_ADDR) ? 1'd1 : 1'd0;
// Reg_WRn is sequenced 1001 for writing address or data; held at 1 when reading data
assign Reg_WRn = (Reg_CMD|isWrite) ? RWcnt[0]^~RWcnt[1] : 1'b1;
// Reg_RDn is sequenced 100001 for reading data; held at 1 when writing address or data
assign Reg_RDn = (Reg_CMD|isWrite) ? 1'b1 :~RWcnt[1]&(RWcnt[0]^~RWcnt[2]);

// -------------------------------------------------------------
// Ethernet top-level state machine
//
// This design uses two always blocks:
//   1) Combinatorial, to set nextState
//   2) Sequential, to update state based on nextState and set outputs.
//
// -------------------------------------------------------------

// Combinatorial always block to set nextState.
always @(*)
begin

   case (state)

   ST_IDLE:
   begin
      if (ksz_req) begin
         if (ksz_wdata[26])
            nextState = ST_RESET_ASSERT;
         else
            nextState = ksz_wdata[27] ? ST_WAVEFORM_DATA : ST_WAVEFORM_ADDR;
      end
      else if (ethIrq|sendReq) begin
         nextState = ST_RUN_PROGRAM_EXECUTE;
      end
      else if (resetRequest) begin
         nextState = ST_RESET_ASSERT;
      end
      else if (numReset == 1) begin
         // For some reason, it is necessary to reset twice.
         // After the first reset, the FPGA can receive packets via Ethernet,
         // but cannot send responses.
         // Or, maybe we just need to wait longer before doing the first reset.
         nextState = ST_RESET_ASSERT;
      end
      else
         nextState = ST_IDLE;
   end

   //******************* RESET STATES ***********************
   ST_RESET_ASSERT:
   begin
      // 10 ms (49.152 MHz sysclk)
      nextState = (initCount == 21'd491520) ? ST_RESET_WAIT : ST_RESET_ASSERT;
   end

   ST_RESET_WAIT:
   begin
      nextState = (initCount == 21'h1FFFFF) ? ST_RUN_PROGRAM_EXECUTE : ST_RESET_WAIT;
   end

   ST_INIT_CHECK_CHIPID:
   begin
      nextState = (ReadData[15:4] == 12'h887) ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
   end

   ST_HANDLE_PORT_STATUS:
   begin
      nextState = isInIRQ ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
   end

   //********************* RUN PROGRAM ************************

   ST_RUN_PROGRAM_EXECUTE:
   begin
      nextState = ST_WAVEFORM_ADDR;
   end

   //********************* IRQ STATES *************************

   ST_IRQ_HANDLER:
   begin
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end

   ST_IRQ_DISPATCH:
   begin
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end


   //******************* RECEIVE STATES ***********************

   ST_RECEIVE_FRAME_COUNT:
   begin
      nextState = (ReadData[15:8] == 0) ? ST_IRQ_DISPATCH : ST_RUN_PROGRAM_EXECUTE;
   end

   ST_RECEIVE_FRAME_STATUS:
   begin
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end

   ST_RECEIVE_FRAME_LENGTH:
   begin
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end

   ST_RECEIVE_DMA_REQUEST:
   begin
      nextState = (recvRequest&recvBusy) ? ST_RECEIVE_DMA_WAIT : ST_RECEIVE_DMA_REQUEST;
   end

   ST_RECEIVE_DMA_WAIT:
   begin
      nextState = recvBusy ? ST_RECEIVE_DMA_WAIT : ST_RUN_PROGRAM_EXECUTE;
   end

   ST_RECEIVE_FLUSH_WAIT:
   begin
      if (ReadData[0]) begin
         // Not yet finished flushing; check again
         nextState = ST_RUN_PROGRAM_EXECUTE;
      end
      else if (bw_active) begin
         // Flush finished, but waiting for a local or remote block write to finish
         nextState = ST_RECEIVE_FLUSH_WAIT;
      end
      else begin
         if (FrameValid & responseRequired) begin
            nextState = ST_RUN_PROGRAM_EXECUTE;
         end
         else begin
            nextState = (FrameCount == 8'd0) ? ST_IRQ_DISPATCH : ST_RUN_PROGRAM_EXECUTE;
         end
      end
   end

   ST_SEND_DMA_REQUEST:
   begin
      nextState = (sendRequest&sendBusy) ? ST_SEND_DMA_CONTROLWORD : ST_SEND_DMA_REQUEST;
   end

   ST_SEND_DMA_CONTROLWORD:
   begin
      nextState = sendTransition ? ST_SEND_DMA_BYTECOUNT : ST_SEND_DMA_CONTROLWORD;
   end

   ST_SEND_DMA_BYTECOUNT:
   begin
      nextState = sendTransition ? ST_SEND_DMA_WAIT : ST_SEND_DMA_BYTECOUNT;
   end

   ST_SEND_DMA_WAIT:
   begin
      // The KSZ8851MLL Step-by-Step guide specifies that the TXQ must
      // be DWORD (32-bit) aligned. In practice, this does not seem to
      // be necessary, but we do it anyway to be safe.
      nextState = sendBusy ? ST_SEND_DMA_WAIT :
                  (responseByteCount[1]|responseByteCount[0]) ? ST_SEND_DMA_DWORD_PAD
                           : ST_RUN_PROGRAM_EXECUTE;
   end

   ST_SEND_DMA_DWORD_PAD:
   begin
      nextState = sendTransition ? ST_RUN_PROGRAM_EXECUTE : ST_SEND_DMA_DWORD_PAD;
   end

   ST_SEND_TXQ_ENQUEUE_WAIT:
   begin
      nextState = (ReadData[0] == 1'b0) ? ST_SEND_END : ST_RUN_PROGRAM_EXECUTE;
   end

   ST_SEND_END:
   begin
      if (isInIRQ)
         nextState = (FrameCount == 8'd0) ? ST_IRQ_DISPATCH : ST_RUN_PROGRAM_EXECUTE;
      else
         nextState = ST_IDLE;
   end

   ST_WAVEFORM_ADDR:
   begin
      nextState = (RWcnt == 3'd3) ? ST_WAVEFORM_DATA : ST_WAVEFORM_ADDR;
   end

   ST_WAVEFORM_DATA:
   begin
      nextState = ((isWrite && (RWcnt == 3'd3)) || (RWcnt == 3'd5)) ? retState : ST_WAVEFORM_DATA;
   end

   default:
   begin
      nextState = ST_IDLE;
   end

   endcase

end

always @(posedge sysclk) begin

   // Store request to write to KSZ register (from Firewire), in case
   // we are not in the idle state.
   if (ksz_reg_wen) begin
      if (ksz_req) begin
         // if previous request still pending, set error flag
         ethFwReqError <= 1;
      end
      ksz_req <= 1;
      // Possibly overwrite previous request (note: if current state is ST_IDLE, then
      // previous request will still be executed and current request will be ignored
      // because ksz_wdata is not updated until next cycle).
      ksz_wdata <= fw_reg_wdata;
   end

   if (resetActive) begin
      resetRequest <= 0;
      FrameValid <= 0;
      isForward <= 0;
      ethStateError <= 0;
`ifdef HAS_DEBUG_DATA
      RegISROther <= 16'd0;
      numPacketValid <= 16'd0;
      numPacketInvalid <= 8'd0;
`endif
   end

   // Latch asynchronous Ethernet IRQ
   ethIrq <= ~ETH_IRQn;

   //******************** State Machine ********************

   timeSinceIRQ <= timeSinceIRQ + 16'd1;

`ifdef DEBOUNCE_STATES
   nextStateLatched <= nextState;

   if (nextState != nextStateLatched) begin
      // Record state glitch
      if (state != nextStateLatched) begin
         numStateGlitch <= numStateGlitch + 8'd1;
`ifdef HAS_DEBUG_DATA
         errorInfo <= { 3'd0, state, 3'd0, nextState, 3'd0, nextStateLatched, 3'd0, runPC };
`endif
      end

   end
   else begin

   state <= nextStateLatched;
`else
   state <= nextState;
`endif

   case (state)

   ST_IDLE:
   begin
      isWord <= 1;       // all transfers are word
      isInIRQ <= 0;
      resetActive <= 0;
      recvRequest <= 0;
      sendRequest <= 0;
      RWcnt <= 3'd0;
      initCount <= 21'd0;
      waitInfo <= WAIT_NONE;
      if (ksz_req) begin
         //****** Access to KSZ8851 registers via Firewire interface ******
         // Format of 32-bit register:
         // 0(2) clearErrors(2) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
         // bit 29: clear network layer error flags and counters (EthernetIO)
         // bit 28: clear link layer error flags and counters (this file)
         // bit 27: DMA
         // bit 26: reset PHY
         // bit 25: R/W Read (0) or Write (1)
         // bit 24: W/B Word or Byte
         // bit 23-16: 8-bit address
         // bit 15-0 : 16-bit data
         // Previously, this was implemented to accept the reset command at any time,
         // but now it will only work in the IDLE state.
         ksz_req <= 0;
         if (ksz_wdata[28]) begin
            ethFwReqError <= 0;
            ethStateError <= 0;
`ifdef HAS_DEBUG_DATA
            numPacketValid <= 16'd0;
            numPacketInvalid <= 8'd0;
`endif
         end
         if (!ksz_wdata[26] && (ksz_wdata[31:28] == 4'd0)) begin
            // if not reset or upper bits set
            isWrite <= ksz_wdata[25];
            isWord <= ksz_wdata[24];
            RegAddr <= ksz_wdata[23:16];
            WriteData <= ksz_wdata[15:0];
            retState <= ST_IDLE;
         end
      end
      else if (ethIrq) begin
         // If an interrupt transition to ST_RUN_PROGRAM_EXECUTE
         runPC <= ID_READ_INTERRUPT;
         timeSinceIRQ <= 16'd0;
      end
      else if (sendReq) begin
         // forward packet from FireWire
         isForward <= 1;
         runPC <= ID_ENABLE_DMA_SEND;
      end
   end

   //********** States for chip reset and initializing Ethernet *************
   // This is the first state called.
   // It can also be called via the Firewire interface.
   // When done, it returns to ST_IDLE.

   // Assert the reset and wait 10 ms before removing it.
   // (For the first time, we could skip asserting the reset because it is already asserted)
   ST_RESET_ASSERT:
   begin
      if (initCount == 21'd491520) begin  // 10 ms (49.152 MHz sysclk)
         ETH_RSTn <= 1;   // Remove the reset
         numReset <= numReset + 8'd1;
      end
      else begin
         ETH_RSTn <= 0;
         initOK <= 0;
         resetActive <= 1;
         initCount <= initCount + 21'd1;
      end
   end

   // The reset has ended, wait 50 ms before initializing chip registers
   ST_RESET_WAIT:
   begin
      if (initCount == 21'h1FFFFF) begin
         runPC <= ID_CHIP_ID;
      end
      else begin
         initCount <= initCount + 21'd1;
      end
   end

   ST_INIT_CHECK_CHIPID:
   begin
      // Can set initOK now, since the rest of initialization will
      // proceed without any further checks.
      initOK <= (ReadData[15:4] == 12'h887) ? 1'b1 : 1'b0;
   end

   //*************** State for the run-time program ******************

   ST_RUN_PROGRAM_EXECUTE:
   begin
      isWrite <= RunProgram[runPC][`WRITE_BIT];
      RegAddr <= RunProgram[runPC][`ADDR_BITS];
      WriteData <= RunProgram[runPC][`DATA_BITS];
      runPC <= runPC + 5'd1;

      if (RunProgram[runPC][`MOD_BIT])
         retState <= ST_IRQ_DISPATCH;
      else if (runPC == ID_ENABLE_DMA_RECV)
         retState <= ST_RECEIVE_DMA_REQUEST;
      else if (runPC == ID_ENABLE_DMA_SEND)
         retState <= ST_SEND_DMA_REQUEST;
      else if (runPC == ID_ENABLE_INTERRUPT)
         retState <= ST_IDLE;
      else if (~RunProgram[runPC][`WRITE_BIT])
         retState <= RunProgram[runPC][`NEXT_BITS];
      else
         retState <= ST_RUN_PROGRAM_EXECUTE;
   end

   //*************** States for handling IRQs ******************
   // There are two states:  ST_IRQ_HANDLER and ST_IRQ_DISPATCH
   //
   //   ST_IDLE transitions to ST_IRQ_HANDLER when ETH_IRQn is asserted (0).
   //   ST_IRQ_DISPATCH transitions to ST_IDLE (after enabling interrupts) when all interrupts are cleared.
   //
   //   ST_IRQ_DISPATCH transitions to ST_RECEIVE_FRAME_COUNT (via retState) when the receive interrupt bit is set.
   //   There are three transitions to ST_IRQ_DISPATCH:
   //       when ST_RECEIVE_FRAME_COUNT reads 0 frames
   //       when ST_RECEIVE_FLUSH_WAIT has 0 frames left and there is no reply (e.g., write command)
   //       when ST_SEND_END has 0 frames left

   ST_IRQ_HANDLER:
   begin
      // ISR Register bit definitions:
      //   B15: Link change (handled, though currently not enabled)
      //   B14: Transmit interrupt
      //   B13: Receive interrupt (handled)
      //   B11: Receive overrun
      //    B9: Transmit process stopped
      //    B8: Receive process stopped
      //    B6: Transmit space available
      //    B5: Receive wakeup frame
      //    B4: Receive magic packet
      //    B3: Linkup detect
      //    B2: Energy detect
      RegISR <= ReadData;
`ifdef HAS_DEBUG_DATA
      if (~(ReadData[15]|ReadData[13])) begin
         // Record unexpected interrupt
         RegISROther <= ReadData;
      end
`endif
   end

   ST_IRQ_DISPATCH:
   begin
      if (RegISR[13] == 1'b1) begin
         // Handle receive
         isInIRQ <= 1;
         runPC <= ID_CLEAR_INTERRUPT;
         ClearInterrupt[`MOD_BIT] <= 1'b0;
         ClearInterrupt[`ADDR_BITS] <= `ETH_ADDR_ISR;
         ClearInterrupt[`DATA_BITS] <= 16'h2000;
         RegISR[13] <= 1'b0;     // clear ISR receive IRQ bit
      end
      else if (RegISR[15] == 1'b1) begin
         // Handle link change
         isInIRQ <= 1;
         runPC <= ID_READ_PORT1SR;
         // ST_HANDLE_PORT_STATUS will set runPC to ID_CLEAR_INTERRUPT
         ClearInterrupt[`MOD_BIT] <= 1'b1;
         ClearInterrupt[`ADDR_BITS] <= `ETH_ADDR_ISR;
         ClearInterrupt[`DATA_BITS] <= 16'h8000;
         RegISR[15] <= 1'b0;       // Clear RegISR
      end
      else if (RegISR[14] || RegISR[11] || RegISR[9] || RegISR[8] || RegISR[6]) begin
         // These interrupts are not handled and are disabled, so clear them
         // if they somehow occurred.
         runPC <= ID_CLEAR_INTERRUPT;
         ClearInterrupt[`MOD_BIT] <= 1'b1;
         ClearInterrupt[`ADDR_BITS] <= `ETH_ADDR_ISR;
         ClearInterrupt[`DATA_BITS] <= RegISR&16'b0100101101000000;
         RegISR <= RegISR&16'b1011010010111111;    // Clear RegISR bits
      end
      else if (RegISR[5] || RegISR[4] || RegISR[3] || RegISR[2]) begin
         // These interrupts are also not handled and are disabled, but are
         // cleared differently (by writing to PMECR)
         runPC <= ID_CLEAR_INTERRUPT;
         ClearInterrupt[`MOD_BIT] <= 1'b1;
         ClearInterrupt[`ADDR_BITS] <= `ETH_ADDR_PMECR;
         ClearInterrupt[`DATA_BITS] <= RegISR&16'h003c;
         RegISR    <= RegISR&16'hffc3;    // Clear RegISR bits
      end
      else begin
         // Done IRQ handle, clear flag
         isInIRQ <= 0;
         // Enable interrupts
         runPC <= ID_ENABLE_INTERRUPT;
      end
   end

   ST_HANDLE_PORT_STATUS:
   begin
      // Bit 5 is "link good"
      linkStatus <= ReadData[5];
      // Request KSZ8851 reset if Ethernet cable unplugged
      resetRequest <= ~ReadData[5]&isInIRQ;
      runPC <= ID_CLEAR_INTERRUPT;
   end

   //*************** States for receiving Ethernet packets ******************
   // ST_IRQ_DISPATCH transitions to ST_RECEIVE_FRAME_COUNT when the receive interrupt bit is set.
   // ST_SEND_END transitions to ST_RECEIVE_FRAME_STATUS when FrameCount is greater than 0.
   //
   // ST_RECEIVE_FLUSH_WAIT transitions to ST_SEND_ENABLE_DMA if the processed packet requires a response.
   //
   // There are two transitions to ST_IRQ_DISPATCH:
   //    when ST_RECEIVE_FRAME_COUNT reads 0 frames
   //    when ST_RECEIVE_FLUSH_WAIT has 0 frames left and there is no reply (e.g., write command)

   ST_RECEIVE_FRAME_COUNT:
   begin
      FrameCount <= ReadData[15:8];
   end

   ST_RECEIVE_FRAME_STATUS:
   begin
      FrameCount <= FrameCount-8'd1;
      // Check if packet valid:
      // B15: RXFV receive frame valid
      // B13: ICMP checksum invalid
      // B12: IP checksum invalid
      // B11: TCP checksum invalid
      // B10: UDP checksum invalid
      // B07: Received broadcast frame
      // B06: Received multicast frame
      // B05: Received unicastframe
      // B04: Received MII error
      // B03: Indicates Ethernet-type frame (length > 1500 bytes)
      // B02: RXFTL receive frame too long (IGNORED -- see below)
      // B01: RXRF  receive runt frame, damaged by collision
      // B00: RXCE  receive CRC error
      //
      // According to the KSZ8851 datasheet, the "frame too long" bit is set
      // if the frame is greater than 2000 bytes. However, the datasheet also
      // states that it does not cause frame truncation.
      if (~ReadData[15] || (ReadData&16'b0011110000010011 != 16'h0)) begin
         // Error detected, so flush frame
         FrameValid <= 0;
`ifdef HAS_DEBUG_DATA
         numPacketInvalid <= numPacketInvalid + 8'd1;
`endif
         runPC <= ID_FLUSH_FRAME;
      end
      else begin
         // Valid frame, so start processing
         FrameValid <= 1;
`ifdef HAS_DEBUG_DATA
         numPacketValid <= numPacketValid + 16'd1;
`endif
      end
   end

   ST_RECEIVE_FRAME_LENGTH:
   begin
      if (ReadData[11:0] == 12'd0) begin
`ifdef HAS_DEBUG_DATA
         numPacketInvalid <= numPacketInvalid + 8'd1;
`endif
         runPC <= ID_FLUSH_FRAME;
      end
      else begin
         rxPktWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
      end
   end

   ST_RECEIVE_DMA_REQUEST:
   begin
      skipCnt <= 2'd3;  // Skip first 3 words in packet when receiving
                        // ignore(1) + status(1) + byte-count(1)
      waitInfo <= WAIT_RECEIVE_DMA;
      if (~recvRequest) begin
         // First time through: set request flag to EthernetIO
         // (recvBusy should not be set)
         recvRequest <= ~recvBusy;
         isDMARead <= 1'b1;
         recvCtrl <= 5'b00001;
      end
   end

   ST_RECEIVE_DMA_WAIT:
   begin
      // Left shift and rotate recvCtrl
      recvCtrl <= { recvCtrl[3:0], recvCtrl[4] };
      // Decrement skipCnt until it is 0
      if (recvTransition) begin
          skipCnt <= (skipCnt == 2'd0) ? 2'd0 : skipCnt - 2'd1;
      end
      if (~recvBusy) begin
         // Clear request flag
         recvRequest <= 1'b0;
         isDMARead <= 1'b0;
         waitInfo <= WAIT_NONE;
`ifdef HAS_DEBUG_DATA
         bw_wait <= 10'd0;
`endif
         runPC <= ID_FLUSH_FRAME;
      end
   end

   ST_RECEIVE_FLUSH_WAIT:
   begin
      // Wait for bit 0 in Register RXQCR to be cleared; also wait for
      // local or remote block write to finish.
      // Then enable interrupt
      //   - if a read command, start sending response
      //     (check FrameCount after send complete)
      //   - else if more frames available, receive status of next frame
      //   - else go to idle state
      if (ReadData[0]) begin
         runPC <= ID_READ_CMD_REG;  // Check again
         waitInfo <= WAIT_FLUSH;
      end
      else if (bw_active) begin
`ifdef HAS_DEBUG_DATA
         // Track time we are waiting for block write to finish.
         // Experimentally determined that it takes about 20-23 clocks to flush
         // the queue (i.e., after bw_left is latched). Thus, the ideal range
         // for bw_left is 2-6 (for local block write).
         bw_wait <= bw_wait + 10'd1;
`endif
      end
      else begin
         timeReceive <= timeSinceIRQ;
         if (FrameValid & responseRequired) begin
            runPC <= ID_ENABLE_DMA_SEND;
         end
         else begin
            if (FrameCount != 8'd0) begin
               runPC <= ID_READ_FRAME_STATUS;
            end
         end
         waitInfo <= WAIT_NONE;
      end
   end

   //*************** States for sending Ethernet packets ******************
   // First, should check if enough memory on QMU TXQ
   //
   // ST_IDLE transitions to ST_SEND when sendReq is asserted (used by Firewire module
   //    to forward packets to Ethernet). In this case, isInIRQ==0.
   // ST_RECEIVE_FLUSH_WAIT transitions to ST_SEND if the processed packet requires a response.
   //    In this case, isInIRQ==1, since the receive occurs in response to an interrupt.
   //
   // ST_SEND_END transitions to ST_RECEIVE_FRAME_STATUS (via retState) when FrameCount
   //    is greater than 0 (and isInIRQ==1).
   // Otherwise, ST_SEND_END transitions to ST_IDLE (via retState).

   ST_SEND_DMA_REQUEST:
   begin
      txPktWords <= 12'd0;
      // Set request flag
      waitInfo <= WAIT_SEND_DMA;
      if (~sendRequest) begin
         // First time through: set request flag to EthernetIO
         // (sendBusy should not be set)
         sendRequest <= ~sendBusy;
         isDMAWrite <= 1'b1;
         sendCtrl <= 3'b100;
      end
   end

   ST_SEND_DMA_CONTROLWORD:
   begin
      sendCtrl <= {sendCtrl[1:0], sendCtrl[2] };
      // TX Control word
      // B15  : TXIC transmit interrupt on completion
      // B0-B5: TXFID transmit frame ID
      SDRegDWR <= 16'h0;  // Control word = 0
   end

   ST_SEND_DMA_BYTECOUNT:
   begin
      sendCtrl <= {sendCtrl[1:0], sendCtrl[2] };
      SDRegDWR <= responseByteCount;
   end

   ST_SEND_DMA_WAIT:
   begin
      // Clear request flag
      sendRequest <= 1'b0;
      if (txPktWords != responseByteCount[12:1]) begin
          sendCtrl <= {sendCtrl[1:0], sendCtrl[2] };
          if (sendCtrl[2]) begin
             SDRegDWR <= send_word;
             txPktWords <= txPktWords + 12'd1;
          end
      end
      if (~sendBusy) begin
         waitInfo <= WAIT_NONE;
         if (~(responseByteCount[1]|responseByteCount[0])) begin
             isDMAWrite <= 1'b0;
             isForward <= 1'd0;
             runPC <= ID_DISABLE_DMA;
         end
      end
   end

   ST_SEND_DMA_DWORD_PAD:
   begin
      // The KSZ8851MLL Step-by-Step guide specifies that the TXQ must
      // be DWORD (32-bit) aligned. In practice, this does not seem to
      // be necessary, but we do it anyway to be safe.
      // Left shift and rotate sendCtrl
      sendCtrl <= {sendCtrl[1:0], sendCtrl[2] };
      SDRegDWR <= 16'h0;
      isDMAWrite <= 1'b0;
      isForward <= 1'd0;
      runPC <= ID_DISABLE_DMA;
   end

   ST_SEND_TXQ_ENQUEUE_WAIT:
   begin
      // Wait for bit 0 in Register TXQCR (0x80) to be cleared.
      // According to the datasheet, "the software should wait for the bit to be cleared before
      // setting up another new TX frame," so this check could be moved elsewhere for efficiency.
      if (ReadData[0] == 1'b0) begin
         waitInfo <= WAIT_NONE;
      end
      else begin
         waitInfo <= WAIT_FLUSH;
         runPC <= ID_TXQ_READ;  // Check again
      end
   end

   ST_SEND_END:
   begin
`ifdef HAS_DEBUG_DATA
      numPacketSent <= numPacketSent + 8'd1;
      timeSend <= timeSinceIRQ;
`endif
      if ((isInIRQ) && (FrameCount != 8'd0))
         runPC <= ID_READ_FRAME_STATUS;
   end

   //******************* States for I/O to/from KSZ8851 **********************
   // There are two states: ST_WAVEFORM_ADDR and ST_WAVEFORM_DATA.
   // ST_WAVEFORM_ADDR writes the address to the bus; it is the same regardless of
   //    whether reading or writing from a register. It is not used for DMA transfers.
   // ST_WAVEFORM_DATA writes the data to the bus (isWrite) or reads from the bus
   //    (!isWrite), then transitions to whatever state is in retState, which
   //    usually is the calling state.
   // DMA transfers do not use these states, but rather use separate state machines.
   // ST_WAVEFORM_DATA should work for DMA transfers requested by the host via ksz_req.

   ST_WAVEFORM_ADDR:
   begin
      SDReg <= Addr16;
      RWcnt <= (RWcnt == 3'd3) ? 3'd0 : RWcnt + 3'd1;
   end

   ST_WAVEFORM_DATA:
   begin
      RWcnt <= ((isWrite && (RWcnt == 3'd3)) || (RWcnt == 3'd5)) ? 3'd0 : RWcnt + 3'd1;
      if (isWrite) begin
         SDReg <= WriteData;
      end
      else if (RWcnt == 3'd4) begin
         eth_data <= SD;
      end
   end

   default:
   begin
      ethStateError <= 1;
   end

   endcase // case (state)

`ifdef DEBOUNCE_STATES
   end
`endif

end

//************** Emulate some features of FPGA V3 EthSwitch ****************

// Ethernet broadcast MAC address
localparam[47:0] BroadcastMAC = 48'hFFFFFFFFFFFF;

// FPGA MAC addresses contain the LCSR Company ID (CID) as the first 24-bits,
// followed by 16-bits for the RT or PS interface, followed by 8-bits for the board-id
// (PS interface only available in FPGA V3).
localparam[23:0] LCSR_CID    = 24'hfa610e;

// Host MAC address (typically, MAC address of PC)
reg[47:0] MacAddrHost;

// PortForwardFpga[board-id]:
//     1 --> FPGA board is accessible via Ethernet board (i.e., received a packet
//           with the corresponding SrcMac address)
//     0 --> Not known whether FPGA board is accessible via Ethernet port
reg[15:0] PortForwardFpga;

assign isHub = (PortForwardFpga == 16'd0) ? 1'b1 : 1'b0;

// Counts words received
reg[2:0] swcnt;
// Source MAC address
reg[47:0] SrcMac;

always @(posedge sysclk)
begin
   if (~linkStatus) begin
      MacAddrHost <= BroadcastMAC;
      PortForwardFpga <= 16'd0;
   end
   else if (initOK & recvRequest & recvBusy) begin
      if (recvReady) begin
         if (swcnt == 3'd3)      SrcMac[47:32] <= recv_word;
         else if (swcnt == 3'd4) SrcMac[31:16] <= recv_word;
         else if (swcnt == 3'd5) SrcMac[15:0]  <= recv_word;
         else if (swcnt == 3'd6) begin
            // If the upper 24-bits of SrcMac match LCSR_CID, then
            // there is an FPGA board accessible via that port.
            // For this purpose, it does not matter whether the middle
            // 16-bits are FPGA_RT_MAC or FPGA_PS_MAC.
            if (SrcMac[47:24] == LCSR_CID)
               PortForwardFpga[SrcMac[3:0]] <= 1'b1;
            else
               MacAddrHost <= SrcMac;
         end
         if (swcnt != 3'd7)
            swcnt <= swcnt + 3'd1;
      end
   end
   else begin
      swcnt <= 3'd0;
   end
end

wire[31:0] SwitchData[0:31];
assign SwitchData[0]  = "0WSE";  // ESW0 byte-swapped
// Port configuration and forwarding info
assign SwitchData[1]  = { 4'b1001, 20'd0,                 // Ports 3 (RT) and 0 (ETH) exist
                          4'd0,                           // All port are slow
                          1'd1, 2'd0, linkStatus };       // Port 3 active, Port 0 depends on linkStatus
assign SwitchData[2]  = MacAddrHost[47:16];
assign SwitchData[3]  = { MacAddrHost[15:0], 16'd0 };
assign SwitchData[4]  = 32'd0;
assign SwitchData[5]  = { 16'd0, PortForwardFpga };
assign SwitchData[6]  = 32'd0;
assign SwitchData[7]  = 32'd0;
assign SwitchData[8]  = { 16'd0,               numPacketValid };      // NumPacketRecv[0] (received from ETH)
assign SwitchData[9]  = { 8'd0, numPacketSent, 16'd0 };               // NumPacketRecv[3] (received from RT)
assign SwitchData[10] = { 16'd0,               8'd0, numPacketSent }; // NumPacketSent[0] (sent to ETH)
assign SwitchData[11] = { numPacketValid,      16'd0 };               // NumPacketSent[3] (sent to RT)
genvar i;
for (i = 12; i < 32; i = i + 1) begin : switch_data_loop
   assign SwitchData[i] = 32'd0;
end

// Following data is accessible via block read from address `ADDR_ETH (0x4000)
// Note that some data (some DebugData and RunProgram) is provided by this module
// (KSZ8851) whereas everything else is provided by the high-level interface (EthernetIO).
//    4000 - 407f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4080 - 408f (16 quadlets) EthernetIO Debug data
//    4090 - 409f (16 quadlets) Low-level (e.g., KSZ8851) Debug data
//    40a0 - 40bf (32 quadlets) Switch data (was RunProgram prior to Firmware Rev 9)
//    40c0 - 40df (32 quadlets) PacketBuffer/ReplyBuffer (64 words)
//    40e0 - 40ff (32 quadlets) ReplyIndex (64 words)
always @(*)
begin
   if (reg_raddr[11:4] == 8'h09) begin             // 4090-409f
`ifdef HAS_DEBUG_DATA
      reg_rdata = DebugData[reg_raddr[3:0]];
`else
      reg_rdata = "0GBD";
`endif
   end
   else if (reg_raddr[11:5] == 7'b0000101) begin   // 40a0-40bf
      reg_rdata = SwitchData[reg_raddr[4:0]];
   end
   else begin
      reg_rdata = 32'd0;
   end
end

endmodule
