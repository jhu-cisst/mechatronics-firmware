/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2020 ERC CISST, Johns Hopkins University.
 *
 * This module implements the higher-level Ethernet I/O, which interfaces
 * to the KSZ8851 MAC/PHY chip.
 *
 * Revision history
 *     12/21/15    Peter Kazanzides    Initial Revision
 *     11/28/16    Zihan Chen          Added Disable/Enable in RECEIVE
 *     11/5/19     Peter Kazanzides    Added UDP support
 *     1/13/20     Peter Kazanzides    Incorporated low-level interface from KSZ8851.v
 * 
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
`define ETH_ADDR_CIDER   8'hC0     // Chip ID and Enable Reg
`define ETH_ADDR_PMECR   8'hD4     // Power management event control register

module EthernetIO(
    // global clock
    input wire sysclk,

    // board id (rotary switch)
    input wire[3:0] board_id,
    input wire[5:0] node_id,

    // Interface to KSZ8851
    output reg ETH_RSTn,  // chip reset (active low)
    output wire ETH_CMD,  // 0 for data, 1 for address
    output wire ETH_RDn,  // read strobe (active low)
    output wire ETH_WRn,  // write strobe (active low)
    inout[15:0] SD,       // address/data bus
    input wire ETH_IRQn,  // interrupt request

    // Firewire interface to KSZ8851 (for testing)
    input  wire fw_reg_wen,          // write enable
    input  wire[15:0] fw_reg_waddr,  // write address
    input  wire[31:0] fw_reg_wdata,  // write data
    output reg[15:0]  eth_data,      // Data to/from KSZ8851
    output wire[31:16] eth_status,

    // Register interface to Ethernet memory space and IP address register
    input  wire[15:0] reg_raddr,
    output wire[31:0] reg_rdata,
    input  wire[31:0] reg_wdata,
    input  wire ip_reg_wen,
    output wire[31:0] ip_address,

    // Interface to/from board registers. These enable the Ethernet module to drive
    // the internal bus on the FPGA. In particular, they are used to read registers
    // to respond to quadlet read and block read commands.
    input wire[31:0] eth_reg_rdata,
    output reg[15:0] eth_reg_raddr,
    output reg       eth_read_en,
    output reg[31:0] eth_reg_wdata,
    output reg[15:0] eth_reg_waddr,
    output reg       eth_reg_wen,
    output reg       eth_block_wen,
    output reg       eth_block_wstart,

    // Low-level Firewire PHY access
    output reg lreq_trig,         // trigger signal for a FireWire phy request
    output reg[2:0] lreq_type,    // type of request to give to the FireWire phy

    // Interface to FireWire module (for sending packets via FireWire)
    output reg eth_send_fw_req,   // request to send firewire packet
    input wire eth_send_fw_ack,   // ack from firewire module
    input  wire[6:0] eth_fwpkt_raddr,
    output wire[31:0] eth_fwpkt_rdata,
    output wire[15:0] eth_fwpkt_len,   // eth received fw pkt length
    output reg[15:0] host_fw_addr,     // Firewire address of host (e.g., ffd0)

    // Interface from Firewire (for sending packets via Ethernet)
    input wire sendReq,
    output reg sendAck,
    output reg[6:0] sendAddr,
    input wire[31:0] sendData,
    input wire[15:0] sendLen,

    // Interface for sampling data (for block read)
    output reg sample_start,         // 1 -> start sampling for block read
    input wire sample_busy,          // Sampling in process
    output wire[4:0] sample_raddr,   // Read address for sampled data
    input wire[31:0] sample_rdata,   // Sampled data (for block read)
    input wire[31:0] timestamp       // Timestamp (for debugging)
);

reg initOK;            // 1 -> Initialization successful
reg isWrite;           // 0 -> Read, 1 -> Write
reg isDMA;             // 1 -> DMA mode active
reg isWord;            // 0 -> Byte, 1 -> Word
reg[7:0] RegAddr;      // Register address (N/A for DMA mode)
reg[15:0] WriteData;   // Data to be written to chip (N/A for read)
wire[15:0] ReadData;   // Data read from chip (N/A for write)
reg eth_error;         // 1 -> I/O request received when not in idle state

assign ReadData = eth_data;

`define ReadDataSwapped {ReadData[7:0], ReadData[15:8]}
`define WriteDataSwapped {WriteData[7:0], WriteData[15:8]}

//**************************** From KSZ8851.v ****************************************

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
assign SD = ETH_RDn ? SDReg : 16'hz;

`define SDRegSwapped {SDReg[7:0], SDReg[15:8]}

// address decode for KSZ8851 I/O access
wire   ksz_reg_wen;
assign ksz_reg_wen = (fw_reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHRES}) ? fw_reg_wen : 1'b0;

reg       ksz_req;    // External request pending for KSZ I/O
reg[31:0] ksz_wdata;  // Cached register for KSZ I/O request

// Following registers hold address/data for requested register reads/writes
// (note: eth_data is declared above, as parameter)
//reg[7:0]  eth_addr;     // I/O register address (0-0xFF)

// Following are for generating waveforms for WRn, RDn and CMD
localparam[9:0]
   Init_WRn      = 10'b1111111111,
   Init_RDn      = 10'b1111111111,
   Init_CMD      = 10'b0000000000,
   Read_WRn      = 10'b1001111111,    // all 10 bits
   Read_RDn      = 10'b1111100001,
   Read_CMD      = 10'b1111000000,
   Write_WRn     = 10'b1001100111,    // first 8 bits
   Write_RDn     = 10'b1111111111,
   Write_CMD     = 10'b1111000000,
   DMA_Read_WRn  = 10'b1111111111,    // first 5 bits
   DMA_Read_RDn  = 10'b0000111111,
   DMA_Read_CMD  = 10'b0000000000,
   DMA_Write_WRn = 10'b1001111111,    // first 4 bits
   DMA_Write_RDn = 10'b1111111111,
   DMA_Write_CMD = 10'b0000000000;

reg[9:0] Cur_WRn;
reg[9:0] Cur_RDn;
reg[9:0] Cur_CMD;
reg[3:0] ShiftCnt;

assign ETH_WRn = Cur_WRn[9];
assign ETH_RDn = Cur_RDn[9];
assign ETH_CMD = Cur_CMD[9];

reg[20:0] initCount;

//******************************* End from KSZ8851.v *****************************************

// Error flags
reg ethFrameError;     // 1 -> Frame too long (currently, if more than 512 bytes)
reg ethIPv4Error;      // 1 -> IPv4 header error (protocol not UDP or ICMP; header version != 4)
reg ethUDPError;       // 1 -> Wrong UDP port (not 1394)
reg ethDestError;      // 1 -> Incorrect destination (FireWire destination does not begin with 0xFFC)
reg ethAccessError;    // 1 -> Unable to access internal bus

reg[9:0] numStateInvalid;   // Number of invalid states (for debugging)
reg[7:0] numReset;          // Number of times reset called

// IER value
// B15: LCIE link change interrupt enable
// B14: TXIE transmit interrupt enable
// B13: RXIE receive interrupt enable
localparam[15:0] ETH_VALUE_IER = 16'h2000;

// RXQCR value
// B5: RXFCTE enable QMU frame count threshold (1)
// B4: ADRFE  auto-dequeue
// Not enabling auto-dequeue because we flush packet
// instead of reading to end.
localparam[15:0] ETH_VALUE_RXQCR = 16'h0020;
   
// top-level state machine states
localparam[2:0]
    ST_IDLE = 3'd0,
    ST_RESET = 3'd1,
    ST_IRQ = 3'd2,
    ST_RECEIVE = 3'd3,
    ST_SEND = 3'd4,
    ST_KSZIO = 3'd5;

// Current state (one-hot encoding)
reg[5:0] state = 6'b000010;   // ST_RESET
// State to return to after ST_KSZIO
reg[2:0] retState = ST_IDLE;

// reset/init states
localparam[1:0]
    ST_RESET_ASSERT = 2'd0,         // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 2'd1,           // wait after bringing reset high -- 50 msec
    ST_INIT_CHECK_CHIPID = 2'd2,    // Read chip ID
    ST_INIT_RUN_PROGRAM = 2'd3;

reg[1:0] resetState = ST_RESET_ASSERT;

// interrupt handler states. Only 2 for now, but could extend
// when adding other interrupt handlers, such as for link change.
localparam
    ST_IRQ_HANDLER = 1'd0,
    ST_IRQ_DISPATCH = 1'd1;

reg irqState = ST_IRQ_HANDLER;

// receive states
localparam[3:0]
    ST_RECEIVE_FRAME_COUNT = 4'd0,
    ST_RECEIVE_FRAME_STATUS = 4'd1,
    ST_RECEIVE_FRAME_LENGTH = 4'd2,
    ST_RECEIVE_ENABLE_DMA = 4'd3,
    ST_RECEIVE_DMA_ETHERNET_HEADERS = 4'd4,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 4'd5,
    ST_RECEIVE_DMA_FRAME_CRC = 4'd6,
    ST_RECEIVE_FLUSH_START = 4'd7,
    ST_RECEIVE_FLUSH_WAIT = 4'd8,
    ST_RECEIVE_DMA_ICMP_DATA = 4'd9;

reg[3:0] recvState = ST_RECEIVE_FRAME_COUNT;

// send states
localparam[3:0]
    ST_SEND_ENABLE_DMA = 4'd0,
    ST_SEND_DMA_CONTROLWORD = 4'd1,
    ST_SEND_DMA_BYTECOUNT = 4'd2,
    ST_SEND_DMA_ETHERNET_HEADERS = 4'd3,
    ST_SEND_DMA_PACKETDATA_HEADER = 4'd4,
    ST_SEND_DMA_PACKETDATA_QUAD = 4'd5,
    ST_SEND_DMA_PACKETDATA_BLOCK_START = 4'd6,
    ST_SEND_DMA_PACKETDATA_BLOCK_MAIN = 4'd7,
    ST_SEND_DMA_PACKETDATA_BLOCK_PROM = 4'd8,
    ST_SEND_DMA_PACKETDATA_CHECKSUM = 4'd9,
    ST_SEND_DMA_FWD = 4'd10,
    ST_SEND_DMA_ICMP_DATA = 4'd11,
    ST_SEND_DMA_STOP = 4'd12,
    ST_SEND_TXQ_ENQUEUE = 4'd13,
    ST_SEND_TXQ_ENQUEUE_WAIT = 4'd14,
    ST_SEND_END = 4'd15;

reg[15:0] sendState = 16'd1;  // ST_SEND_ENABLE_DMA


// KSZIO states
localparam
    ST_WAVEFORM_OUTPUT_INIT = 1'd0,       // set up read/write waveforms
    ST_WAVEFORM_OUTPUT_EXECUTE = 1'd1;    // generate read/write waveforms

reg ioState = ST_WAVEFORM_OUTPUT_INIT;

// Debugging support
assign eth_io_isIdle = state[ST_IDLE];

// Keep track of areas where state machine may wait
// for unknown amount of time (for debugging)
localparam [1:0]
    WAIT_NONE = 2'd0,
    WAIT_FLUSH = 2'd3;

reg[1:0] waitInfo;

// Following flags are set based on the destination address. Note that
// a FireWire broadcast packet will set both isLocal and isRemote.
wire isLocal;       // 1 -> FireWire packet should be processed locally
wire isRemote;      // 1 -> FireWire packet should be forwarded

wire quadRead;
wire quadWrite;
wire blockRead;
wire blockWrite;

reg FrameValid;
reg isEthMulticast;
reg isEthBroadcast;

// Whether to use UDP (1) or raw Ethernet frames (0).
// This mode is set each time a valid packet is received
// (i.e., set if a valid UDP packet received, cleared if
// a valid raw Ethernet frame is received).
reg useUDP;

// Non-zero initial values
initial begin
   isWord = 1'd1;
   Cur_WRn = Init_WRn;
   Cur_RDn = Init_RDn;
   Cur_CMD = Init_CMD;
end

// Ethernet status:
//   Bit 31: 1 to indicate that Ethernet is present -- must be kept for backward compatibility
//   Bit 30: 1 to indicate that an error occurred in KSZ8851 -- must be kept for backward compatibility
//   Other fields can be assigned as needed
assign eth_status[31] = 1'b1;            // 31: 1 -> Ethernet is present
assign eth_status[30] = eth_error;       // 30: 1 -> Could not access KSZ registers via FireWire
assign eth_status[29] = initOK;          // 29: 1 -> Initialization OK
assign eth_status[28] = isLocal;         // 28: 1 -> command requested by higher level
assign eth_status[27] = isRemote;        // 27: 1 -> command acknowledged by lower level
assign eth_status[26] = ethFrameError;   // 26: 1 -> ethernet packet too long (higher layer)
assign eth_status[25] = ethDestError;    // 25: 1 -> ethernet destination error (higher layer)
assign eth_status[24] = quadRead;        // 24: quadRead (debugging)
assign eth_status[23] = quadWrite;       // 23: quadWrite (debugging)
assign eth_status[22] = blockRead;       // 22: blockRead (debugging)
assign eth_status[21] = blockWrite;      // 21: blockWrite (debugging)
assign eth_status[20] = useUDP;          // 20: UDP mode
assign eth_status[19] = isEthMulticast;  // 19: multicast received
assign eth_status[18] = eth_io_isIdle;   // 18: Ethernet I/O state machine is idle
assign eth_status[17:16] = waitInfo;     // 17-16: Wait points in EthernetIO.v


reg isInIRQ;           // True if IRQ handle routing
reg[15:0] RegISR;      // 16-bit ISR register
reg[15:0] RegISROther; // Unexpected ISR value (for debugging)
reg[7:0] FrameCount;   // Number of received frames
reg[7:0] fw_count;     // Counter when reading FireWire packet
reg blockw_active;     // Indicates that block write is active
reg[11:0] txPktWords;  // Num of words sent
reg[11:0] rxPktWords;  // Num of words in receive queue

wire[7:0] maxCountFW;  // Maximum count (of words) when reading FireWire packets
// Subtract 4 words for UDP header (nBytes/2-4-1); otherwise, just subtract 1 word
assign maxCountFW = isUDP ? (UDP_Length[8:1]-8'd5) : (Eth_EtherType[8:1]-8'd1);

wire[15:0] LengthFW;   // Firewire packet length in bytes
// Subtract 8 bytes for UDP header
assign LengthFW = isUDP ? UDP_Length-8'd8 : Eth_EtherType;

assign eth_fwpkt_len = LengthFW;

// Read address for sampled data (32-bit data)
assign sample_raddr = fw_count[5:1];

//************************ Large buffer to hold various packets **************************
// Note that it is fine for some buffers to overlap. Below, the UDP, ICMP and ARP buffers
// all start after the IPv4 Header. Technically, the ARP buffer could start after the
// Ethernet Frame Header (since it does not use IPv4), but it is more convenient to
// not overlap with the IPv4 Header so that part of the IPv4 Header can be used in
// reply packets.

// Following are word offsets into PacketBuffer
localparam[5:0]
   ID_Packet_Begin      = 0,
   ID_Frame_Begin       = ID_Packet_Begin,   // ********* FrameHeader [length=7] *********
   ID_Frame_destMac0    = ID_Frame_Begin,    // Destination (FPGA) MAC address
   ID_Frame_destMac1    = ID_Frame_Begin+1,  //
   ID_Frame_destMac2    = ID_Frame_Begin+2,  //
   ID_Frame_srcMac0     = ID_Frame_Begin+3,  // Source (PC) MAC address
   ID_Frame_srcMac1     = ID_Frame_Begin+4,  //
   ID_Frame_srcMac2     = ID_Frame_Begin+5,  //
   ID_Frame_Length      = ID_Frame_Begin+6,  // EtherType/Length
   ID_Frame_End         = ID_Frame_Begin+6,  // ******** End of Frame Header (6) *********
   ID_IPv4_Begin        = ID_Frame_End+1,    // ******* IPv4 Header (7) [length=10]  *****
   ID_IPv4_Word0        = ID_IPv4_Begin,     // Version (4), IHL (normally 5), DSCP, ECN
   ID_IPv4_Length       = ID_IPv4_Begin+1,   // Total Length
   ID_IPv4_Ident        = ID_IPv4_Begin+2,   // Identification (0)
   ID_IPv4_Flags        = ID_IPv4_Begin+3,   // Flags, Fragment offset
   ID_IPv4_Protocol     = ID_IPv4_Begin+4,   // Time to Live, Protocol (UDP=17, ICMP=1)
   ID_IPv4_Checksum     = ID_IPv4_Begin+5,   // Header checksum
   ID_IPv4_hostIP0      = ID_IPv4_Begin+6,   // Host IP address (MSW)
   ID_IPv4_hostIP1      = ID_IPv4_Begin+7,   // Host IP address (LSW)
   ID_IPv4_destIP0      = ID_IPv4_Begin+8,   // Destination (FPGA) IP address (MSW)
   ID_IPv4_destIP1      = ID_IPv4_Begin+9,   // Destination (FPGA) IP address (LSW)
   ID_IPv4_End          = ID_IPv4_Begin+9,   // ******** End of IPv4 Header (16) ********
   ID_UDP_Begin         = ID_IPv4_End+1,     // ******* UDP Header (17) [Length=4] *******
   ID_UDP_hostPort      = ID_UDP_Begin,      // Source (host) port
   ID_UDP_destPort      = ID_UDP_Begin+1,    // Destination (fpga) port
   ID_UDP_Length        = ID_UDP_Begin+2,    // UDP Length
   ID_UDP_Checksum      = ID_UDP_Begin+3,    // UDP Checksum
   ID_UDP_End           = ID_UDP_Begin+3,    // ******** End of UDP Header (20) *********
   ID_ICMP_Begin        = ID_IPv4_End+1,     // ****** ICMP Header (17) [length=6] ******
   ID_ICMP_TypeCode     = ID_ICMP_Begin,     // ICMP Type (8) and Code (0)
   ID_ICMP_End          = ID_ICMP_Begin+5,   // ******** End of ICMP Header (22) ********
   ID_ARP_Begin         = ID_IPv4_End+1,     // ******* ARP Packet (17) [length=14] *****
   ID_ARP_HTYPE         = ID_ARP_Begin,      // Hardware type (HTYPE):  1 for Ethernet
   ID_ARP_PTYPE         = ID_ARP_Begin+1,    // Protocol type (PTYPE):  0x0800 for IPv4
   ID_ARP_HLEN_PLEN     = ID_ARP_Begin+2,    // HLEN (6), PLEN (4)
   ID_ARP_Oper          = ID_ARP_Begin+3,    // 1 for ARP request, 2 for ARP reply
   ID_ARP_srcMac0       = ID_ARP_Begin+4,    // Sender MAC address
   ID_ARP_srcMac1       = ID_ARP_Begin+5,    // Sender MAC address
   ID_ARP_srcMac2       = ID_ARP_Begin+6,    // Sender MAC address
   ID_ARP_hostIP0       = ID_ARP_Begin+7,    // Sender IP address (MSW)
   ID_ARP_hostIP1       = ID_ARP_Begin+8,    // Sender IP address (LSW)
   ID_ARP_fpgaIP0       = ID_ARP_Begin+12,   // Target (FPGA) IP address (MSW)
   ID_ARP_fpgaIP1       = ID_ARP_Begin+13,   // Target (FPGA) IP address (LSW)
   ID_ARP_End           = ID_ARP_Begin+13,   // ******** End of ARP Header (30) *********
   ID_Csum_Begin        = ID_ARP_End+1,      // ***** Frame Checksum (31) [length=2] ****
   ID_Frame_Checksum0   = ID_Csum_Begin,     // Ethernet frame checksum (MSW)
   ID_Frame_Checksum1   = ID_Csum_Begin+1,   // Ethernet frame checksum (LSW)
   ID_Csum_End          = ID_Csum_Begin+1,   // ***** End of Frame Checksum (32) ********
   ID_Packet_End        = ID_Csum_End,       // ****** End of Packet Data (32) **********
   ID_Reply_Begin       = ID_Packet_End+1,   // ****** Start of Reply Data (33) *********
   ID_Rep_Zero          = ID_Reply_Begin,    // Value of 0 for generic use
   ID_Rep_fpgaMac0      = ID_Reply_Begin+1,  // FPGA MAC address (FA61)
   ID_Rep_fpgaMac1      = ID_Reply_Begin+2,  // FPGA MAC address (0E13)
   ID_Rep_fpgaMac2      = ID_Reply_Begin+3,  // FPGA MAC address (940N)
   ID_Rep_Frame_Length  = ID_Reply_Begin+4,  // Frame EtherType/Length
   ID_Rep_IPv4_Word0    = ID_Reply_Begin+5,  // IPv4 Word 0 (in case different)
   ID_Rep_IPv4_Length   = ID_Reply_Begin+6,  // IPv4 Flags (in case different)
   ID_Rep_IPv4_Flags    = ID_Reply_Begin+7,  // IPv4 Flags (in case different)
   ID_Rep_IPv4_Prot     = ID_Reply_Begin+8,  // IPv4 Protocol (UDP or ICMP)
   ID_Rep_IPv4_Address0 = ID_Reply_Begin+9,  // Source (FPGA) IP address (MSW)
   ID_Rep_IPv4_Address1 = ID_Reply_Begin+10, // Source (FPGA) IP address (LSW)
   ID_Rep_UDP_fpgaPort  = ID_Reply_Begin+11, // UDP port on FPGA (1394)
   ID_Rep_UDP_hostPort  = ID_Reply_Begin+12, // UDP port on host (ID_UDP_hostPort)
   ID_Rep_UDP_Length    = ID_Reply_Begin+13, // UDP Reply Length
   ID_Rep_ARP_Oper      = ID_Reply_Begin+14, // ARP reply operation = 2
   ID_Reply_End         = ID_Reply_Begin+14; // ******** End of all data (46) ***********

reg[15:0] PacketBuffer[0:63];

integer i;
initial begin
   for (i = ID_Packet_Begin; i <= ID_Packet_End; i=i+1) PacketBuffer[i] = 16'd0;
   PacketBuffer[ID_Rep_Zero]          = 16'd0;
   PacketBuffer[ID_Rep_fpgaMac0]      = 16'hFA61;
   PacketBuffer[ID_Rep_fpgaMac1]      = 16'h0E13;
   PacketBuffer[ID_Rep_fpgaMac2]      = 16'h9400;   // board_num updated in ST_RESET_WAIT
   PacketBuffer[ID_Rep_Frame_Length]  = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   PacketBuffer[ID_Rep_IPv4_Word0]    = {4'd4, 4'd5, 6'd0, 2'd0};  // 0x4500
   PacketBuffer[ID_Rep_IPv4_Length]   = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   PacketBuffer[ID_Rep_IPv4_Flags]    = {3'b010, 13'd0};  // 0x4000
   PacketBuffer[ID_Rep_IPv4_Prot]     = {8'd64, 8'd17};   // TTL=64; Prot updated in ST_SEND_DMA_BYTECOUNT
   PacketBuffer[ID_Rep_IPv4_Address0] = IP_UNASSIGNED[31:16];  // updated when IP address assigned
   PacketBuffer[ID_Rep_IPv4_Address1] = IP_UNASSIGNED[15:0];   // updated when IP address assigned
   PacketBuffer[ID_Rep_UDP_fpgaPort]  = 16'd1394;
   PacketBuffer[ID_Rep_UDP_hostPort]  = 16'd0;      // Needs to be updated
   PacketBuffer[ID_Rep_UDP_Length]    = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   PacketBuffer[ID_Rep_ARP_Oper]      = 16'h0002;   // ARP Operation (OPER): 2 for reply
   // Fill in unused part of packet buffer
   for (i=ID_Reply_End+1; i < 64; i=i+1) PacketBuffer[i] = 16'd0;
end

reg[5:0] recvCnt;                // Index into PacketBuffer
reg[2:0] skipCnt;                // For skipping first 3 words in RXQ

//************************** Ethernet Frame Header ********************************
wire[15:0] Eth_EtherType;
assign Eth_EtherType = PacketBuffer[ID_Frame_Length];

wire isIPv4;
// IPv4 Ethertype is 0x0800
assign isIPv4 = (FrameValid && (Eth_EtherType == 16'h0800)) ? 1'd1 : 1'd0;

wire isARP;
// ARP Ethertype is 0x0806
assign isARP = (FrameValid && (Eth_EtherType == 16'h0806)) ? 1'd1 : 1'd0;

wire isRaw;
// The frame is considered raw if it has a length, rather than an EtherType.
// The Ethernet standard allows lengths up to 1500 bytes, but we limit to
// 512 bytes, which is enough for the largest Firewire packet. Thus, we check
// if the upper 7 bits are 0 (i.e., if length is no more than 9 bits).
assign isRaw = (Eth_EtherType[15:9] == 7'd0) ? 1'd1 : 1'd0;

//********************************* ARP Packet ***********************************
// Word 0: Hardware type (HTYPE):  1 for Ethernet
// Word 1: Protocol type (PTYPE):  0x0800 for IPv4
// Word 2:
//   MSB: Hardware address length (HLEN):  6
//   LSB: Protocol address length (PLEN):  4
// Word 3: Operation (OPER):  1 for ARP request,   2 for ARP reply
//                            3 for RARP request,  4 for RARP reply
//                            8 for InARP request, 9 for InARP reply
// Word 4-6: Sender hardware address (SHA):  MAC address of sender
// Word 7-8: Sender protocol address (SPA):  IPv4 address of sender (0 for ARP Probe)
// Word 9-11: Target hardware address (THA):  MAC address of target (ignored in request)
// Word 12-13: Target protocol address (TPA): IPv4 address of target
wire[31:0] ARP_fpgaIP;
// Byteswapped to match ip_address
assign ARP_fpgaIP = { PacketBuffer[ID_ARP_fpgaIP1][7:0], PacketBuffer[ID_ARP_fpgaIP1][15:8], PacketBuffer[ID_ARP_fpgaIP0][7:0], PacketBuffer[ID_ARP_fpgaIP0][15:8] };

wire isARPValid;  // Whether ARP request is valid
assign isARPValid = (PacketBuffer[ID_ARP_HTYPE] == 16'h0001) &&
                    (PacketBuffer[ID_ARP_PTYPE] == 16'h0800) &&
                    (PacketBuffer[ID_ARP_HLEN_PLEN] == 16'h0604) &&
                    (PacketBuffer[ID_ARP_Oper] == 16'h0001);

// Whether ARP IP address matches this board
wire isARP_ip_equal = (!is_ip_unassigned && (ip_address == ARP_fpgaIP)) ? 1'd1 : 1'd0;

// Whether we should send an ARP response. This will be valid before it is first used in ST_RECEIVE_FLUSH_WAIT,
// and should not get checked in ST_SEND states if isForward is 1.
wire sendARP;
assign sendARP = isARP & isARPValid & isARP_ip_equal;

//******************************** IPv4 HEADER *************************************
// Word 0:
//   Byte 0: Version, should be 4; IHL (Internet Header Length), normally should be 5
//   Byte 1: DSCP and ECN (ignore those)
// Word 1: Total Length
// Word 2: Identification=0 (ignored)
// Word 3: Flags=0, Fragment Offset=0 (ignored)
// Word 4:
//   Byte 0: Time To Live (ignore)
//   Byte 1: Protocol (UDP is 17, ICMP is 1)
// Word 5: Header checksum (ignored, for now)
// Word 6,7: Source IP address (host)
// Word 8,9: Destination IP address (fpga)
wire[3:0] IPv4_Version;
assign IPv4_Version = PacketBuffer[ID_IPv4_Word0][15:12];
wire [3:0] IPv4_IHL;
assign IPv4_IHL = PacketBuffer[ID_IPv4_Word0][11:8];
wire[15:0] IPv4_Length;
assign IPv4_Length = PacketBuffer[ID_IPv4_Length];
wire[7:0] IPv4_Protocol;
assign IPv4_Protocol = PacketBuffer[ID_IPv4_Protocol][7:0];
wire[31:0] IPv4_fpgaIP;
// Byteswapped to match ip_address
assign IPv4_fpgaIP = { PacketBuffer[ID_IPv4_destIP1][7:0], PacketBuffer[ID_IPv4_destIP1][15:8], PacketBuffer[ID_IPv4_destIP0][7:0], PacketBuffer[ID_IPv4_destIP0][15:8] };

wire is_IPv4_Long;
// The following conditional is an efficient alternative to (IPv4_IHL > 5).
assign is_IPv4_Long = (isIPv4 && ((IPv4_IHL[3] == 2'b1) || (IPv4_IHL[2:1] == 2'b11))) ? 1'd1 : 1'd0;

wire is_IPv4_Short;
// IHL should never be less than 5, so this should not happen
assign is_IPv4_Short = (isIPv4 && !is_IPv4_Long && (IPv4_IHL != 4'd5)) ? 1'd1 : 1'd0;

wire isUDP;
assign isUDP = (isIPv4 && (IPv4_Protocol == 8'd17)) ? 1'd1 : 1'd0;

wire isICMP;
assign isICMP = (isIPv4 && (IPv4_Protocol == 8'd1)) ? 1'd1 : 1'd0;

//********************************* UDP Header ****************************************
wire[15:0] UDP_Length;
assign UDP_Length = PacketBuffer[ID_UDP_Length];

wire isPortValid;
assign isPortValid = (PacketBuffer[ID_UDP_destPort] == 16'd1394) ? 1'd1 : 1'd0;

//********************************* ICMP Header ***************************************
// Data received in ICMP Echo packet (ping)
// ICMP packet usually has additional data, with length given by IPv4_Length-20-12
// (i.e., IPv4_Length includes 20 bytes for IPv4 Header and 12 bytes for ICMP Header).
// This data is received in ST_RECEIVE_DMA_ICMP_Data.

wire isEcho;
// Echo request (ping) has Type=8, Code=0
assign isEcho = (isICMP && (PacketBuffer[ID_ICMP_TypeCode] == 16'h0800)) ? 1'd1 : 1'd0;

wire[15:0] icmp_data_length;
// Length of (optional) ICMP data field in bytes: subtract 20 (IPv4 header) and 12 (ICMP header)
assign icmp_data_length = IPv4_Length-16'd32;

//**************************** Final Processing Steps **********************************
// These signals should only be used in ST_RECEIVE_DMA_ETHERNET_HEADERS

wire Frame_Done;
assign Frame_Done = (recvCnt == ID_Frame_End) ? 1'd1 : 1'd0;

// Following duplicates logic in isRaw, except using `ReadDataSwapped instead of Eth_EtherType
// because Eth_EtherType is not yet valid when Frame_Done is true.
wire Frame_Raw;
assign Frame_Raw = (Frame_Done && (`ReadDataSwapped[15:9] == 7'd0)) ? 1'd1 : 1'd0;

wire ARP_Done;
assign ARP_Done = (isARP && (recvCnt == ID_ARP_End)) ? 1'd1 : 1'd0;

wire IPv4_Done;
assign IPv4_Done = (isIPv4 && (recvCnt == ID_IPv4_End)) ? 1'd1 : 1'd0;

wire UDP_Done;
assign UDP_Done = (isUDP && (recvCnt == ID_UDP_End)) ? 1'd1 : 1'd0;

wire ICMP_Done;
assign ICMP_Done = (isICMP && (recvCnt == ID_ICMP_End)) ? 1'd1 : 1'd0;

// A few convenient combinations for error checking
wire Frame_Error;
assign Frame_Error = (Frame_Done && (`ReadDataSwapped[15:9] != 7'd0) && (`ReadDataSwapped != 16'h0800) && (`ReadDataSwapped != 16'h0806)) ? 1'd1 : 1'd0;
wire IPv4_Error;
assign IPv4_Error = (IPv4_Done && (IPv4_Version != 4'h4) && !isUDP && !isICMP) ? 1'd1 : 1'd0;
wire UDP_Error;
assign UDP_Error = (UDP_Done && !isPortValid) ? 1'd1 : 1'd0;
wire ARP_Error;
assign ARP_Error = (ARP_Done && !isARPValid) ? 1'd1 : 1'd0;
wire Any_Error;
assign Any_Error = IPv4_Error|UDP_Error|ARP_Error|Frame_Error;

//******************************* Reply packets *****************************************
// The reply packets can mostly be constructed by returning data from the incoming packets
// (in PacketBuffer), augmented with a few extra data items that have been added to PacketBuffer
// (see entries following ID_Reply_Begin).
// Unlike the received packets (PacketBuffer), it is better to avoid overlap.

localparam[5:0]
   Frame_Reply_Begin  = 6'd0,    // Offset to FrameHeader (words) [length=7]
   Frame_Reply_End    = 6'd6,
   IPv4_Reply_Begin   = 6'd7,    // Offset to IPv4 Header (words) [length=10]
   IPv4_Reply_End     = 6'd16,
   UDP_Reply_Begin    = 6'd17,   // Offset to UDP Header (words)  [length=4]
   UDP_Reply_End      = 6'd20,
   ARP_Reply_Begin    = 6'd21,   // Offset to ARP Packet (words)  [length=14]
   ARP_Reply_End      = 6'd34,
   ICMP_Reply_Begin   = 6'd35,   // Offset to ICMP Header (words) [length=6]
   ICMP_Reply_End     = 6'd40;

// The following array contains the indices (into PacketBuffer) that are used to construct
// the reply packets.
reg[5:0] ReplyIndex[0:63];

initial begin
   ReplyIndex[Frame_Reply_Begin]    = ID_Frame_srcMac0;
   ReplyIndex[Frame_Reply_Begin+1]  = ID_Frame_srcMac1;
   ReplyIndex[Frame_Reply_Begin+2]  = ID_Frame_srcMac2;
   ReplyIndex[Frame_Reply_Begin+3]  = ID_Rep_fpgaMac0;
   ReplyIndex[Frame_Reply_Begin+4]  = ID_Rep_fpgaMac1;
   ReplyIndex[Frame_Reply_Begin+5]  = ID_Rep_fpgaMac2;
   ReplyIndex[Frame_Reply_Begin+6]  = ID_Rep_Frame_Length;

   ReplyIndex[IPv4_Reply_Begin]     = ID_Rep_IPv4_Word0;
   ReplyIndex[IPv4_Reply_Begin+1]   = ID_Rep_IPv4_Length;
   ReplyIndex[IPv4_Reply_Begin+2]   = ID_Rep_Zero;       // Identification
   ReplyIndex[IPv4_Reply_Begin+3]   = ID_Rep_IPv4_Flags;
   ReplyIndex[IPv4_Reply_Begin+4]   = ID_Rep_IPv4_Prot;
   ReplyIndex[IPv4_Reply_Begin+5]   = ID_Rep_Zero;       // Header checksum
   ReplyIndex[IPv4_Reply_Begin+6]   = ID_Rep_IPv4_Address0;
   ReplyIndex[IPv4_Reply_Begin+7]   = ID_Rep_IPv4_Address1;
   ReplyIndex[IPv4_Reply_Begin+8]   = ID_IPv4_hostIP0;
   ReplyIndex[IPv4_Reply_Begin+9]   = ID_IPv4_hostIP1;

   ReplyIndex[UDP_Reply_Begin]      = ID_Rep_UDP_fpgaPort;
   ReplyIndex[UDP_Reply_Begin+1]    = ID_Rep_UDP_hostPort;
   ReplyIndex[UDP_Reply_Begin+2]    = ID_Rep_UDP_Length;
   ReplyIndex[UDP_Reply_Begin+3]    = ID_Rep_Zero;       // Checksum

   ReplyIndex[ARP_Reply_Begin]      = ID_ARP_HTYPE;
   ReplyIndex[ARP_Reply_Begin+1]    = ID_ARP_PTYPE;
   ReplyIndex[ARP_Reply_Begin+2]    = ID_ARP_HLEN_PLEN;
   ReplyIndex[ARP_Reply_Begin+3]    = ID_Rep_ARP_Oper;
   ReplyIndex[ARP_Reply_Begin+4]    = ID_Rep_fpgaMac0;
   ReplyIndex[ARP_Reply_Begin+5]    = ID_Rep_fpgaMac1;
   ReplyIndex[ARP_Reply_Begin+6]    = ID_Rep_fpgaMac2;
   ReplyIndex[ARP_Reply_Begin+7]    = ID_Rep_IPv4_Address0;
   ReplyIndex[ARP_Reply_Begin+8]    = ID_Rep_IPv4_Address1;
   ReplyIndex[ARP_Reply_Begin+9]    = ID_ARP_srcMac0;
   ReplyIndex[ARP_Reply_Begin+10]   = ID_ARP_srcMac1;
   ReplyIndex[ARP_Reply_Begin+11]   = ID_ARP_srcMac2;
   ReplyIndex[ARP_Reply_Begin+12]   = ID_ARP_hostIP0;
   ReplyIndex[ARP_Reply_Begin+13]   = ID_ARP_hostIP1;

   ReplyIndex[ICMP_Reply_Begin]     = ID_Rep_Zero;
   ReplyIndex[ICMP_Reply_Begin+1]   = ID_Rep_Zero;       // ICMP checksum
   ReplyIndex[ICMP_Reply_Begin+2]   = ID_ICMP_Begin+2;
   ReplyIndex[ICMP_Reply_Begin+3]   = ID_ICMP_Begin+3;
   ReplyIndex[ICMP_Reply_Begin+4]   = ID_ICMP_Begin+4;
   ReplyIndex[ICMP_Reply_Begin+5]   = ID_ICMP_Begin+5;

   // Fill in rest of buffer
   for (i=ICMP_Reply_End+1; i < 64; i=i+1) ReplyIndex[i] = ID_Rep_Zero;
end

reg[5:0] replyCnt;                 // Counter for ReplyIndex

// For IP Address register (BoardRegs)
assign ip_address = {PacketBuffer[ID_Rep_IPv4_Address1][7:0], PacketBuffer[ID_Rep_IPv4_Address1][15:8],
                     PacketBuffer[ID_Rep_IPv4_Address0][7:0], PacketBuffer[ID_Rep_IPv4_Address0][15:8]};

//**************************** Firewire Reply Header ***********************************
wire[15:0] Firewire_Header_Reply[0:5];
assign Firewire_Header_Reply[0] = {fw_src_id[7:0], fw_src_id[15:8]};                      // quadlet 0: dest-id
assign Firewire_Header_Reply[1] = {quadRead ? `TC_QRESP : `TC_BRESP, 4'd0, fw_tl, 2'd0};  // quadlet 0: tcode
assign Firewire_Header_Reply[2] = {dest_bus_id[1:0], node_id, dest_bus_id[9:2]};          // src-id
assign Firewire_Header_Reply[3] = 16'd0;   // rcode, reserved
assign Firewire_Header_Reply[4] = 16'd0;   // reserved
assign Firewire_Header_Reply[5] = 16'd0;

//******************************** Debug Counters *************************************

reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[9:0]  numPacketInvalid;  // Number of invalid Ethernet frames received
reg[9:0] numIPv4;            // Number of IPv4 packets received
reg[9:0] numUDP;             // Number of UDP packets received
reg[9:0] numARP;             // Number of ARP packets received
reg[9:0] numICMP;            // Number of ICMP packets received

reg[9:0] numPacketError;     // Number of packet errors (Frame, IPv4 or UDP error)
reg[9:0] numIPv4Mismatch;    // Number of IPv4 packets with different IP address

localparam[31:0] IP_UNASSIGNED = 32'hffffffff;
wire is_ip_unassigned;
assign is_ip_unassigned = (ip_address == IP_UNASSIGNED) ? 1'd1 : 1'd0;

// ----------------------------------------
// Whether packet is being forwarded (to Ethernet) from FireWire receiver
// ----------------------------------------
reg isForward;

wire[31:0] DebugData[0:15];
assign DebugData[0]  = "0GBD";  // DBG0 byte-swapped
assign DebugData[1]  = timestamp;
assign DebugData[2]  = {5'd0, ethUDPError, ethAccessError, ethIPv4Error, 2'd0, node_id, eth_status};
assign DebugData[3]  = { 2'd0, state, 5'd0, retState,
                         sample_start, sample_busy, isLocal, isRemote, FireWirePacketFresh, isEthBroadcast, isEthMulticast, ~ETH_IRQn,
                         isForward, isInIRQ, sendARP, isUDP, isICMP, isEcho, is_IPv4_Long, is_IPv4_Short};
assign DebugData[4]  = { RegISR, RegISROther};
assign DebugData[5]  = { host_fw_addr, FrameCount, fw_count};
assign DebugData[6]  = { 8'h11, maxCountFW, LengthFW };
assign DebugData[7]  = { 4'd0, txPktWords, 4'h0, rxPktWords };
assign DebugData[8]  = { 16'h8877,  16'd0 };
assign DebugData[9]  = { 6'd0, numPacketInvalid, numPacketValid };
assign DebugData[10] = { 6'd0, numUDP, 6'd0, numIPv4 };
assign DebugData[11] = { 6'd0, numICMP, 6'd0, numARP };
assign DebugData[12] = { 6'd0, numIPv4Mismatch, 6'd0, numPacketError };
assign DebugData[13] = { 8'd0, numReset, 6'd0, numStateInvalid };
assign DebugData[14] = 32'd0;
assign DebugData[15] = timestamp;


// Firewire packet received from host
//    - 16 bytes (4 quadlets) for quadlet read request
//    - 20 bytes (5 quadlets) for quadlet write or block read request
//    - (24+block_data_length) bytes for block write
//      - real-time block_data_length = 4*4 = 16 bytes
//        max size in quadlets is (24+16)/4 = 10
//      - HUB block_data_length = 4*4*64 = 1024 (in theory for 64 nodes),
//        but if board ids are limited to 16, then 4*4*16 = 256 bytes
//      - PROM write block_data_length can be up to 260 bytes
//        max size in quadlets is (24+260)/4 = 71
//      - QLA PROM write block_data_length can be up to 16*4 = 64 bytes
//        max size in quadlets is (24+64)/4 = 22
// To summarize, maximum size in quadlets would be 71.
// Allocate pow(2,7) = 128 quadlets

wire[6:0]  mem_raddr;
wire[31:0] mem_rdata;

assign mem_raddr = eth_send_fw_req ? eth_fwpkt_raddr[6:0] :
                   ((state[ST_SEND] || (retState == ST_SEND)) && sendState[ST_SEND_DMA_ICMP_DATA])  ? fw_count[7:1]
                                   : reg_raddr[6:0];
assign eth_fwpkt_rdata = mem_rdata;

reg[31:0] FireWireQuadlet;   // the current quadlet being read

wire[31:0] mem_wdata;
assign mem_wdata = {FireWireQuadlet[31:16], `ReadDataSwapped};

wire mem_wen;   // memory write enable
assign mem_wen = state[ST_RECEIVE] &&
                 ((recvState == ST_RECEIVE_DMA_ICMP_DATA) || (recvState == ST_RECEIVE_DMA_FIREWIRE_PACKET)) &&
                 fw_count[0];

pkt_mem_gen fw_packet(.clka(sysclk),
                      .wea(mem_wen),
                      .addra(fw_count[7:1]),
                      .dina(mem_wdata),
                      .clkb(sysclk),
                      .addrb(mem_raddr),
                      .doutb(mem_rdata)
                     );

reg FireWirePacketFresh;   // 1 -> FireWirePacket data is valid (fresh)

// Write  Or   Addr    Data
//  25    24  23:16    15:0
localparam CMD_WRITE = 1'd1,
           CMD_READ = 1'd0,
           CMD_OR   = 1'd1;

`define WRITE_BIT 25
`define OR_BIT 24
`define ADDR_BITS 23:16
`define DATA_BITS 15:0

reg[25:0] InitProgram[0:16];

initial begin
    // Set MAC address (4 LSB below should be set to board_id)
    InitProgram[0] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_MARL, 12'h940, 4'd0};
    InitProgram[1] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_MARM, 16'h0E13};
    InitProgram[2] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_MARH, 16'hFA61};
    // Enable QMU transmit frame data pointer auto increment
    InitProgram[3] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_TXFDPR, 16'h4000};
    // Enable QMU ICMP/UDP/TCP/IP checksum, transmit flow control, padding, and CRC
    InitProgram[4] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_TXCR, 16'h01EE};
    // B14: Enable QMU receive frame data pointer auto increment
    // B12: Decrease write data valid sample time to 4 nS (max)
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
    InitProgram[5] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_RXFDPR, 16'h5000};
    // Configure receive frame threshold for 1 frame
    InitProgram[6] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_RXFCTR, 16'h0001};
    // 7: enable UDP, TCP, and IP checksums
    // C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
    // E: enable broadcast, multicast, and unicast
    // Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
    InitProgram[7] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_RXCR1, 16'h7CE0};
    // Enable UDP checksums; pass packets with 0 checksum
    InitProgram[8] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_RXCR2, 16'h001C};
    // Following are hard-coded values for which hash register to use and which bit to set
    // for multicast address FB:61:0E:13:19:FF. This is obtained by computing the CRC for
    // this MAC address and then using the first two (most significant) bits to determine
    // the register and the next four bits to determine which bit to set.
    // See code in mainEth1394.cpp.
    InitProgram[9] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_MAHTR1, 16'h0008};
    // RXQCR value
    // B5: RXFCTE enable QMU frame count threshold (1)
    // B4: ADRFE  auto-dequeue
    // Not enabling auto-dequeue because we flush packet
    // instead of reading to end.
    InitProgram[10] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR};
    // Clear all pending interrupts
    InitProgram[11] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_ISR, 16'hFFFF};
    // Enable receive interrupts
    InitProgram[12] = {CMD_WRITE, ~CMD_OR, `ETH_ADDR_IER, ETH_VALUE_IER};
    // Enable transmit
    InitProgram[13] = {CMD_READ, ~CMD_OR, `ETH_ADDR_TXCR, 16'd0};
    InitProgram[14] = {CMD_WRITE, CMD_OR, `ETH_ADDR_TXCR, 15'd0, 1'd1};
    // Enable receive
    InitProgram[15] = {CMD_READ, ~CMD_OR, `ETH_ADDR_RXCR1, 16'd0};
    InitProgram[16] = {CMD_WRITE, CMD_OR, `ETH_ADDR_RXCR1, 15'd0, 1'd1};
end

reg[4:0] progIndex;    // Index into program (program counter)

// Following data is accessible via block read from address `ADDR_ETH (0x4000)
//    Maximum block read size is 64 quadlets (implementation choice)
//    4000 - 407f (128 quadlets) FireWire packet
//    4080 - 408f (16 quadlets) Debug data
//    40a0 - 40bf (32 quadlets) InitProgram
//    40c0 - 40df (32 quadlets) PacketBuffer (64 words)
//    40e0 - 40ff (32 quadlets) ReplyIndex (64 words)
// Note that full address decoding is not done, so other addresses will work too
// (for example, 4f80-4f9f will also give Debug data)
assign reg_rdata = (reg_raddr[7] == 0) ? mem_rdata :
                   (reg_raddr[6:4] == 3'b000) ? DebugData[reg_raddr[3:0]] :
                   (reg_raddr[6:5] == 2'b01) ? {6'd0, InitProgram[reg_raddr[4:0]]} :
                   (reg_raddr[6:5] == 2'b10) ? {PacketBuffer[{reg_raddr[4:0],1'b1}], PacketBuffer[{reg_raddr[4:0],1'b0}]} :
                                               {10'd0, ReplyIndex[{reg_raddr[4:0],1'b1}], 10'd0, ReplyIndex[{reg_raddr[4:0],1'b0}]};

// Data from Firewire packet header
// Quadlet 0
reg[3:0] fw_tcode;            // FireWire transaction code
reg[5:0] fw_tl;               // FireWire transaction label
reg[3:0] fw_pri;              // FireWire priority field
reg[9:0] dest_bus_id;         // FireWire destination bus (first 10 bits)
reg[5:0] dest_node_id;        // FireWire destination node (last 6 bits)
// Quadlet 1
reg[15:0] fw_src_id;          // FireWire source id
// Quadlet 2
reg[15:0] fw_dest_offset;     // FireWire destination offset (only lowest 16 bits used)
// Quadlet 3
reg[15:0] block_data_length;  // Data length (in bytes) for block read/write requests


wire isFwBroadcast = (dest_node_id == 6'h3f) ? 1'd1 : 1'd0;

// Local write if addresses this board or FireWire broadcast.
// Note that the host PC uses the Firewire PRI field to indicate whether the packet should be forwarded.
assign isLocal = (dest_node_id == node_id) || isFwBroadcast;

// assign isRemote = (dest_node_id != node_id) && ~(isEthMulticast||isEthBroadcast);
// Remote write if not addressing this board (note that this check includes Firewire broadcast)
// and if LSB of Firewire PRI field is set. This latter check is a non-standard use of the
// Firewire PRI field, but is supported by the PC software interface (UDP and PCAP).
// Also, note that some packets (e.g., Firewire broadcast) may set both isLocal and isRemote.
assign isRemote = (dest_node_id != node_id) && (fw_pri[0] != 1'd1);

assign quadRead = (fw_tcode == `TC_QREAD) ? 1'd1 : 1'd0;
assign quadWrite = (fw_tcode == `TC_QWRITE) ? 1'd1 : 1'd0;
assign blockRead = (fw_tcode == `TC_BREAD) ? 1'd1 : 1'd0;
assign blockWrite = (fw_tcode == `TC_BWRITE) ? 1'd1 : 1'd0;

assign addrMain = (fw_dest_offset[15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;
assign addrHub = (fw_dest_offset[15:12] == `ADDR_HUB) ? 1'd1 : 1'd0;
assign addrPROM = (fw_dest_offset[15:12] == `ADDR_PROM) ? 1'd1 : 1'd0;
assign addrQLA  = (fw_dest_offset[15:12] == `ADDR_PROM_QLA) ? 1'd1 : 1'd0;


// -------------------------------------------------------
// Ethernet state machine
// -------------------------------------------------------
always @(posedge sysclk) begin

   // Clear eth_send_fw_req flag
   if (eth_send_fw_req && eth_send_fw_ack) begin
      eth_send_fw_req <= 1'd0;
   end

   // Clear sendAck (acknowledge request from Firewire)
   if (sendAck && !sendReq) begin
      sendAck <= 1'd0;
   end

   if (sample_start && sample_busy) begin
      sample_start <= 1'd0;
   end

   // Store request to write to KSZ register (from Firewire), in case
   // we are not in the idle state.
   if (ksz_reg_wen) begin
      if (ksz_req) begin
         // if previous request still pending, set error flag
         eth_error <= 1;
      end
      ksz_req <= 1;
      // Possibly overwrite previous request (note: if current state is ST_IDLE, then
      // previous request will still be executed and current request will be ignored
      // because ksz_wdata is not updated until next cycle).
      ksz_wdata <= fw_reg_wdata;
   end

   // Write to IP address register
   if (ip_reg_wen) begin
      // Following is equivalent to: ip_address <= reg_wdata;
      PacketBuffer[ID_Rep_IPv4_Address0] <= {reg_wdata[7:0], reg_wdata[15:8] };
      PacketBuffer[ID_Rep_IPv4_Address1] <= {reg_wdata[23:16], reg_wdata[31:24] };
   end

   //******************** State Machine ********************
   state <= 6'd0;

   if (state == 6'd0) begin
      // Should never happen, except for programming errors
      numStateInvalid <= numStateInvalid + 10'd1;
      state[ST_IDLE] <= 1;
   end

   // One-hot state machine implementation
   case (1'b1)  // synthesis parallel_case

   state[ST_IDLE]:
   begin
      isDMA <= 0;
      isWord <= 1;       // all transfers are word
      isInIRQ <= 0;
      eth_read_en <= 0;
      eth_reg_wen <= 0;
      eth_block_wen <= 0;
      eth_block_wstart <= 0;
      blockw_active <= 0;
      waitInfo <= WAIT_NONE;
      if (ksz_req) begin
         //****** Access to KSZ8851 registers via Firewire interface ******
         // Format of 32-bit register:
         // 0(4) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
         // bit 28: reset error flag
         // bit 27: DMA
         // bit 26: reset
         // bit 25: R/W Read (0) or Write (1)
         // bit 24: W/B Word or Byte
         // bit 23-16: 8-bit address
         // bit 15-0 : 16-bit data
         // Previously, this was implemented to accept the reset command at any time,
         // but now it will only work in the IDLE state.
         ksz_req <= 0;
         eth_error <= ksz_wdata[28] ? 1'd0 : eth_error;
         if (ksz_wdata[26]) begin   // if reset
            state[ST_RESET] <= 1;
         end
         else begin
            isDMA <= ksz_wdata[27];
            isWrite <= ksz_wdata[25];
            isWord <= ksz_wdata[24];
            RegAddr <= ksz_wdata[23:16];
            WriteData <= ksz_wdata[15:0];
            state[ST_KSZIO] <= 1;
            retState <= ST_IDLE;
         end
      end
      else if (initOK & ~ETH_IRQn) begin
         // If an interrupt transition to ST_IRQ
         isWrite <= 0;
         RegAddr <= `ETH_ADDR_ISR;
         state[ST_KSZIO] <= 1;
         retState <= ST_IRQ;
      end
      else if (initOK & sendReq) begin
         // forward packet from FireWire
         state[ST_SEND] <= 1;
         isForward <= 1;
         sendAck <= 1;
      end
      else begin
         state[ST_IDLE] <= 1;
      end
   end

   //********** States for chip reset and initializing Ethernet *************
   // This is the first state called (note that state is initialized to ST_RESET).
   // It can also be called via the Firewire interface.
   // When done, it sets resetState=ST_RESET_ASSERT (for the next call) and returns to ST_IDLE.
   state[ST_RESET]:
   begin

      case (resetState)

      // Assert the reset and wait 10 ms before removing it.
      ST_RESET_ASSERT:
      begin
         state[ST_RESET] <= 1;
         if (initCount == 21'd491520) begin  // 10 ms (49.152 MHz sysclk)
            ETH_RSTn <= 1;   // Remove the reset
            initCount <= 21'd0;
            resetState <= ST_RESET_WAIT;
            numReset <= numReset + 8'd1;
         end
         else begin
            ETH_RSTn <= 0;
            Cur_WRn <= Init_WRn;
            Cur_RDn <= Init_RDn;
            Cur_CMD <= Init_CMD;
            initOK <= 0;
            ethFrameError <= 0;
            ethIPv4Error <= 0;
            ethUDPError <= 0;
            ethDestError <= 0;
            ethAccessError <= 0;
            FrameValid <= 0;
            isEthMulticast <= 0;
            isEthBroadcast <= 0;
            RegISROther <= 16'd0;
            isForward <= 0;
            numPacketValid <= 16'd0;
            numPacketInvalid <= 10'd0;
            numIPv4 <= 10'd0;
            numUDP <= 10'd0;
            numARP <= 10'd0;
            numICMP <= 10'd0;
            numIPv4Mismatch <= 10'd0;
            numPacketError <= 10'd0;
            FireWirePacketFresh <= 0;
            initCount <= initCount + 21'd1;
         end
      end

      // The reset has ended, wait 50 ms before initializing chip registers
      ST_RESET_WAIT:
      begin
         if (initCount == 21'h1FFFFF) begin
            initCount <= 21'd0;
            InitProgram[0][3:0] <= board_id;
            PacketBuffer[ID_Rep_fpgaMac2][3:0] <= board_id;
            isDMA <= 0;
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_CIDER;   // Read Chip ID
            state[ST_KSZIO] <= 1;
            retState <= ST_RESET;
            resetState <= ST_INIT_CHECK_CHIPID;
         end
         else begin
            initCount <= initCount + 21'd1;
            state[ST_RESET] <= 1;
         end
      end

      //*************** States for initializing Ethernet ******************

      ST_INIT_CHECK_CHIPID:
      begin
         if (ReadData[15:4] == 12'h887) begin
            // Chip ID is ok, go to next state
            progIndex <= 5'd0;
            resetState <= ST_INIT_RUN_PROGRAM;
            state[ST_RESET] <= 1;
         end
         else begin
            initOK <= 0;
            resetState <= ST_RESET_ASSERT;  // init for next time
            state[ST_IDLE] <= 1;
         end
      end

      ST_INIT_RUN_PROGRAM:
      begin
         isWrite <= InitProgram[progIndex][`WRITE_BIT];
         RegAddr <= InitProgram[progIndex][`ADDR_BITS];
         WriteData <= InitProgram[progIndex][`OR_BIT] ? (ReadData|InitProgram[progIndex][`DATA_BITS])
                                                      : InitProgram[progIndex][`DATA_BITS];
         progIndex <= progIndex + 5'd1;
         state[ST_KSZIO] <= 1;
         if (progIndex == 5'd16) begin
            initOK <= 1;
            resetState <= ST_RESET_ASSERT;  // init for next time
            retState <= ST_IDLE;
         end
         else begin
            retState <= ST_RESET;
         end
      end
      endcase
   end

   //*************** States for handling IRQs ******************
   state[ST_IRQ]:
   begin
      // There are two states:  ST_IRQ_HANDLER and ST_IRQ_DISPATCH
      //
      //   ST_IDLE transitions to ST_IRQ when ETH_IRQn is asserted (0) and assumes that irqState=ST_IRQ_HANDLER
      //   ST_IRQ_DISPATCH transitions to ST_IDLE (via retState)  when all interrupts are cleared, and
      //       sets irqState=ST_IRQ_HANDLER
      //
      //   ST_IRQ_DISPATCH transitions to ST_RECEIVE (via retState) when the receive interrupt bit is set
      //   ST_RECEIVE transitions to ST_IRQ:ST_IRQ_DISPATCH from three places:
      //       when ST_RECEIVE_FRAME_COUNT reads 0 frames
      //       when ST_RECEIVE_FLUSH_WAIT has 0 frames left and there is no reply (e.g., write command)
      //       when ST_SEND_END has 0 frames left
      //
      //   ST_IRQ also transitions to ST_IDLE and sets irqState=ST_IRQ_HANDLER if an invalid state is encountered

      case (irqState)

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
         isInIRQ <= 1;
         if (~(ReadData[15] || ReadData[13])) begin
            // Record unexpected interrupt
            RegISROther <= ReadData;
         end
         // Disable interrupts
         isWrite <= 1;
         RegAddr <= `ETH_ADDR_IER;
         WriteData <= 16'd0;
         state[ST_KSZIO] <= 1;
         retState <= ST_IRQ;
         irqState <= ST_IRQ_DISPATCH;
      end

      ST_IRQ_DISPATCH:
      begin
         isWrite <= 1;
         if (RegISR[15] == 1'b1) begin
            // Handle link change (TBD)
            RegAddr <= `ETH_ADDR_ISR;
            WriteData <= 16'h8000;    // Clear interrupt
            RegISR[15] <= 1'b0;       // Clear RegISR
            state[ST_KSZIO] <= 1;
            retState <= ST_IRQ;
         end
         else if (RegISR[13] == 1'b1) begin
            // Handle receive
            RegAddr <= `ETH_ADDR_ISR;
            WriteData <= 16'h2000;  // clear interrupt
            RegISR[13] <= 1'b0;     // clear ISR receive IRQ bit
            state[ST_KSZIO] <= 1;
            irqState <= ST_IRQ_HANDLER;  // init for next time
            retState <= ST_RECEIVE;      // Go to ST_RECEIVE
         end
         else if (RegISR[14] || RegISR[11] || RegISR[9] || RegISR[8] || RegISR[6]) begin
            // These interrupts are not handled and are disabled, so clear them
            // if they somehow occurred.
            RegAddr <= `ETH_ADDR_ISR;
            WriteData <= RegISR&16'b0100101101000000;
            RegISR <= RegISR&16'b1011010010111111;    // Clear RegISR bits
            state[ST_KSZIO] <= 1;
            retState <= ST_IRQ;
         end
         else if (RegISR[5] || RegISR[4] || RegISR[3] || RegISR[2]) begin
            // These interrupts are also not handled and are disabled, but are
            // cleared differently (by writing to PMECR)
            RegAddr <= `ETH_ADDR_PMECR;
            WriteData <= RegISR&16'h003c;
            RegISR    <= RegISR&16'hffc3;    // Clear RegISR bits
            state[ST_KSZIO] <= 1;
            retState <= ST_IRQ;
         end
         else begin
            // Done IRQ handle, clear flag
            isInIRQ <= 0;
            // Enable interrupts
            RegAddr <= `ETH_ADDR_IER;
            WriteData <= ETH_VALUE_IER;
            state[ST_KSZIO] <= 1;
            retState <= ST_IDLE;                  // Go to ST_IDLE
            irqState <= ST_IRQ_HANDLER;           // init for next time
         end
      end

      default:
      begin
         numStateInvalid <= numStateInvalid + 10'd1;
         state[ST_IDLE] <= 1;
         irqState <= ST_IRQ_HANDLER;      // init for next time
      end

      endcase
   end

   //*************** States for receiving Ethernet packets ******************
   // ST_IRQ:ST_IRQ_DISPATCH transitions to ST_RECEIVE (via retState) when the receive interrupt bit is set,
   //    assuming that recvState=ST_RECEIVE_FRAME_COUNT. Note that isWrite is 1.
   // ST_SEND:ST_SEND_END transitions to ST_RECEIVE:ST_RECEIVE_FRAME_STATUS when FrameCount is greater than 0.
   //
   // ST_RECEIVE_FLUSH_WAIT transitions to ST_SEND if the processed packet requires a response, assuming
   //    that sendState=ST_SEND_ENABLE_DMA.
   //
   // ST_RECEIVE transitions to ST_IRQ:ST_IRQ_DISPATCH from three places:
   //    when ST_RECEIVE_FRAME_COUNT reads 0 frames
   //    when ST_RECEIVE_FLUSH_WAIT has 0 frames left and there is no reply (e.g., write command)
   //    when ST_SEND_END has 0 frames left
   //
   // ST_RECEIVE also transitions to ST_IDLE and sets recvState=ST_RECEIVE_FRAME_COUNT if an invalid state
   // is encountered.

   state[ST_RECEIVE]:
   begin
      retState <= ST_RECEIVE;    // Default return state

      case (recvState)

      ST_RECEIVE_FRAME_COUNT:
      begin
         // Assumes isWrite==1 on entry
         if (isWrite) begin
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_RXFCTR;
            state[ST_KSZIO] <= 1;
         end
         else begin
            FrameCount <= ReadData[15:8];
            if (ReadData[15:8] == 0) begin
               state[ST_IRQ] <= 1;
               // recvState is still ST_RECEIVE_FRAME_COUNT
            end
            else begin
               // isWrite already 0
               RegAddr <= `ETH_ADDR_RXFHSR;
               state[ST_KSZIO] <= 1;
               recvState <= ST_RECEIVE_FRAME_STATUS;
            end
         end
      end

      ST_RECEIVE_FRAME_STATUS:
      begin
         FrameCount <= FrameCount-8'd1;
         FireWirePacketFresh <= 1'd0;
         // Check if packet valid:
         // B15: RXFV  receive frame valid
         // B13: ICMP checksum invalid
         // B12: IP checksum invalid
         // B11: TCP checksum invalid
         // B10: UDP checksum invalid
         // B07: Received broadcast frame
         // B06: Received multicast frame
         // B05: Received unicastframe
         // B04: Received MII error
         // B03: Indicates Ethernet-type frame (length > 1500 bytes)
         // B02: RXFTL receive frame too long
         // B01: RXRF  receive runt frame, damaged by collision
         // B00: RXCE  receive CRC error
         if (~ReadData[15] || (ReadData&16'b0011110000010111 != 16'h0)) begin
            // Error detected, so flush frame
            FrameValid <= 0;
            isEthMulticast <= 0;
            isEthBroadcast <= 0;
            numPacketInvalid <= numPacketInvalid + 10'd1;
            state[ST_RECEIVE] <= 1;
            recvState <= ST_RECEIVE_FLUSH_START;
         end
         else begin
            // Valid frame, so start processing
            FrameValid <= 1;
            isEthBroadcast <= ReadData[7];
            isEthMulticast <= ReadData[6];
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_RXFHBCR;
            state[ST_KSZIO] <= 1;
            recvState <= ST_RECEIVE_FRAME_LENGTH;
            numPacketValid <= numPacketValid + 16'd1;
         end
      end

      ST_RECEIVE_FRAME_LENGTH:
      begin
         if (ReadData[11:0] == 12'd0) begin
            numPacketInvalid <= numPacketInvalid + 10'd1;
            state[ST_RECEIVE] <= 1;
            recvState <= ST_RECEIVE_FLUSH_START;
         end
         else begin
             rxPktWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
             // Set QMU RXQ frame pointer to 0, also decrease write sample time
             isWrite <= 1;
             RegAddr <= `ETH_ADDR_RXFDPR;
             WriteData <= 16'h5000;
             state[ST_KSZIO] <= 1;
             recvState <= ST_RECEIVE_ENABLE_DMA;
         end
      end

      ST_RECEIVE_ENABLE_DMA:
      begin
         // Enable DMA transfers
         isWrite <= 1;
         RegAddr <= `ETH_ADDR_RXQCR;
         WriteData <= {ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
         state[ST_KSZIO] <= 1;
         skipCnt <= 3'd4;  // Skip first 3 words in packet when receiving
                           // ignore(1) + status(1) + byte-count(1)
                           // Add 1 to skipCnt because DMA read will not start
                           // until next state.
         recvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
         fw_count <= 8'd0;
      end

      ST_RECEIVE_DMA_ETHERNET_HEADERS:
      begin
         isDMA <= 1;
         isWrite <= 0;
         if (Any_Error) begin
            state[ST_RECEIVE] <= 1;
            recvState <= ST_RECEIVE_FLUSH_START;
         end
         else begin
            state[ST_KSZIO] <= 1;
            recvState <= ICMP_Done ? ST_RECEIVE_DMA_ICMP_DATA :
                         (ARP_Done ? ST_RECEIVE_DMA_FRAME_CRC :
                         ((UDP_Done || Frame_Raw) ? ST_RECEIVE_DMA_FIREWIRE_PACKET :
                         ST_RECEIVE_DMA_ETHERNET_HEADERS));
         end
         skipCnt <= (skipCnt == 3'd0) ? 3'd0 : skipCnt - 3'd1;
         recvCnt <= (skipCnt != 3'd0) ? ID_Frame_Begin :
                    (Frame_Done && (`ReadDataSwapped == 16'h0806)) ? ID_ARP_Begin :
                    recvCnt + 6'd1;
         PacketBuffer[recvCnt] <= `ReadDataSwapped;
         numPacketError <= numPacketError + {9'd0, Frame_Error|IPv4_Error|UDP_Error};
         ethFrameError <= Frame_Error ? 1'd1 : ethFrameError;
         ethIPv4Error <= IPv4_Error ? 1'd1 : ethIPv4Error;
         ethUDPError <= UDP_Error ? 1'd1 : ethUDPError;
         // At some point, could check for IHL > 5
         // maxCount <= IPv4_Header_Begin + {IHL,1'd0}-5'd1;
         if (recvCnt == ID_IPv4_End+1) begin
            // This check is done just after the IPv4 packet is processed so we can use
            // IPv4_fpgaIP; otherwise, the last word (ID_IPv4_destIP1) would not yet be
            // assigned to PacketBuffer.
            if (is_ip_unassigned && (IPv4_fpgaIP[31:24] != 8'hff)) begin
               // This case can occur when the host PC already has an ARP
               // cache entry for this board, in which case we just assign
               //  the IP address, as long as it is not a broadcast address
               //  (we only check whether the last byte is 255).
               PacketBuffer[ID_Rep_IPv4_Address0] <= PacketBuffer[ID_IPv4_destIP0];
               PacketBuffer[ID_Rep_IPv4_Address1] <= PacketBuffer[ID_IPv4_destIP1];
            end
            else if ((ip_address != IPv4_fpgaIP) && !isEthBroadcast && !isEthMulticast) begin
               // If IP assigned, but not equal, we process the packet anyway,
               // but keep track of the number of times this occurred.
               // We could decide to update ip_address.
               numIPv4Mismatch <= numIPv4Mismatch + 10'd1;
            end
         end
         else if (UDP_Done && !UDP_Error) begin
            // Save the UDP host port because UDP_hostPort may get overwritten if an ARP packet is received, which
            // would be a problem if the ARP packet is followed by a request to forward a packet from FireWire via UDP.
            // This may not be necessary if ARP and UDP packets were not allowed to overlap in PacketBuffer,
            // but that would require a much larger PacketBuffer. Also, even separating ARP and UDP in PacketBuffer
            // would not handle the (unlikely) case where an invalid UDP packet is received prior to the request to
            // forward a packet from FireWire.
            PacketBuffer[ID_Rep_UDP_hostPort] <= PacketBuffer[ID_UDP_hostPort];
         end
      end

      ST_RECEIVE_DMA_ICMP_DATA:
      begin
         state[ST_KSZIO] <= 1;
         if (fw_count == icmp_data_length[7:0])
            recvState <= ST_RECEIVE_DMA_FRAME_CRC;
         fw_count <= fw_count + 8'd1;
         // For now, read ICMP data into FireWirePacket memory (fw_packet). If memory resources available,
         // it would be cleaner to instantiate a separate 16-bit memory.
         if (fw_count[0] == 0)
            FireWireQuadlet[31:16] <= `ReadDataSwapped;
         else
            FireWireQuadlet[15:0] <= `ReadDataSwapped;
      end

      ST_RECEIVE_DMA_FIREWIRE_PACKET:
      begin
         state[ST_KSZIO] <= 1;
         fw_count <= fw_count + 8'd1;

         // Read FireWire packet, byteswap to make it easier to work with;
         // might need to byteswap again if sending it out via FireWire.
         if (fw_count[0] == 0)
            FireWireQuadlet[31:16] <= `ReadDataSwapped;
         else
            FireWireQuadlet[15:0] <= `ReadDataSwapped;

         // Following handles state transitions, incrementing fw_count and local quadlet
         // and block writes.
         // Note that isLocal, quadWrite, and blockWrite are not valid right away,
         // but will be valid for the counts that are used below.
         // All FireWire packets have a CRC at the end, so we are sure to process the last data packet.
         // Note that we do not check the FireWire CRC because we assume that the Ethernet
         // checksum has already guaranteed that the data is valid.

         if (fw_count == 8'd2) begin
            // Save important fields from Quadlet 0
            fw_tl <= FireWireQuadlet[15:10];
            fw_tcode <= FireWireQuadlet[7:4];
            fw_pri <= FireWireQuadlet[3:0];
            dest_bus_id <= FireWireQuadlet[31:22];
            dest_node_id <= FireWireQuadlet[21:16];
            // Valid destination address: check if first 10 bits are FFC (i.e., all 1)
            if (FireWireQuadlet[31:22] != 10'h3FF) begin
               // invalid destination address, flush packet
               ethDestError <= 1;
               recvState <= ST_RECEIVE_FLUSH_START;
            end
         end
         else if (fw_count == 8'd4) begin
            // Save important fields from Quadlet 1
            fw_src_id <= FireWireQuadlet[31:16];
         end
         else if (fw_count == 8'd6) begin
            // Save important fields from Quadlet 2
            fw_dest_offset <= FireWireQuadlet[15:0];
         end
         else if (fw_count == 8'd8) begin
            // Does not hurt to update block_data_length, even if not a block read/write
            block_data_length <= FireWireQuadlet[31:16];
            if (isLocal) begin
               if (quadWrite) begin
                  eth_reg_waddr <= fw_dest_offset;
                  eth_reg_wdata <= FireWireQuadlet;
                  // Special case: write to FireWire PHY register
                  if (addrMain && (fw_dest_offset[11:0] == {8'h0, `REG_PHYCTRL})) begin
                     // check the RW bit to determine access type (bit 12, after byte-swap)
                     lreq_type <= (FireWireQuadlet[12] ? `LREQ_REG_WR : `LREQ_REG_RD);
                     lreq_trig <= 1;
                  end
               end
               else if (blockWrite) begin
                  // Set and clear eth_block_wstart before starting block write
                  // (arbitrarily chose to set it at fw_count==8).
                  eth_block_wstart <= 1;
               end
               else if (blockRead && addrMain) begin
                  // Set and clear sample_start to trigger sampling data for block read
                  // (arbitrarily chose to set it at fw_count==8; just needs to be early enough that
                  // sampling is finished before we access it in ST_SEND_DMA_PACKETDATA_BLOCK_MAIN).
                  sample_start <= 1;
               end
            end
         end
         else if (fw_count == 8'd11) begin
            // Following only required if (isLocal && blockWrite)
            eth_block_wstart <= 0;
         end
         else if (fw_count == 8'd12) begin
            if (isLocal && blockWrite) begin
               // First quadlet of block write data
               eth_reg_waddr[15:12] <= fw_dest_offset[15:12];
               if (addrMain) begin
                  eth_reg_waddr[7:4] <= 4'd1;  // start with channel 1
                  eth_reg_waddr[3:0] <= `OFF_DAC_CTRL;
                  eth_reg_wdata <= {1'b0, FireWireQuadlet[30:0]};
               end
               else begin
                  eth_reg_waddr[11:0] <= fw_dest_offset[11:0];
                  eth_reg_wdata <= FireWireQuadlet;
               end
               blockw_active <= 1;
            end
         end

         // Remaining contents of block write (for fw_count=13...maxCountFW)
         // Note that blockw_active is only non-zero when (isLocal && blockWrite)
         // so we do not need to check those.
         // The sequence is as follows:
         //    fw_count even (starting at 12): latch address and data
         //    fw_count odd (starting at 13): set write enable (wen)
         if (blockw_active) begin
            if (fw_count[0] == 0) begin      // (even)
               eth_reg_wen <= 0;
               if (addrMain) begin
                  eth_reg_waddr[7:4] <= eth_reg_waddr[7:4] + 4'd1;
                  eth_reg_wdata <= {1'b0, FireWireQuadlet[30:0]};
               end
               else begin
                  eth_reg_waddr <= eth_reg_waddr + 16'd1;
                  eth_reg_wdata <= FireWireQuadlet;
               end
            end
            else begin                    // (odd)
               // MSB is "valid" bit for DAC write (addrMain)
               eth_reg_wen <= addrMain ? FireWireQuadlet[31] : 1'b1;
            end
         end

         if (fw_count == maxCountFW) begin
            // normal completion
            FireWirePacketFresh <= 1;
            useUDP <= isUDP;
            // Allow reading of FireWire CRC
            recvState <= ST_RECEIVE_DMA_FRAME_CRC;
            if (isLocal) begin
               if (quadWrite) begin
                  eth_reg_wen <= 1;
                  eth_block_wen <= 1;
                  lreq_trig <= 0;     // Clear lreq_trig in case it was set
               end
               blockw_active <= 0;
            end
            if (isRemote) begin
               // Request to forward pkt
               eth_send_fw_req <= 1;
               host_fw_addr <= fw_src_id;
            end
         end

      end

      ST_RECEIVE_DMA_FRAME_CRC:
      begin
         // FrameCRC_High <= `ReadDataSwapped;
         // We can read the second word to get the 4-byte CRC, but flushing the
         // packet works better. We decrement rxPktWords by 1, but that
         // variable is just for debugging. In most cases, rxPktWords should
         // be 0 after this -- the exception is when the packet is smaller than
         // the minimum Ethernet frame (64 bytes), in which case it is padded
         // (this happens with raw Ethernet quadlet read/write commands).
         // Note: rxPktWords does not seem to be predictable, so ignoring it for now.
         //rxPktWords <= rxPktWords-12'd1;

         // Update IP address in response to valid ARP packet. We do this here so
         // that ARP_fpgaIP is valid (the last word is read at end of previous state).
         // Note: this feature (setting IP address based on ARP packet received) will
         //       be removed in the future, since it is better to set the IP address
         //       by a broadcast write to register `REG_IPADDR (11).
         if (isARP && isARPValid && is_ip_unassigned) begin
            // If our IP address not yet set, update it
            PacketBuffer[ID_Rep_IPv4_Address0] <= PacketBuffer[ID_ARP_fpgaIP0];
            PacketBuffer[ID_Rep_IPv4_Address1] <= PacketBuffer[ID_ARP_fpgaIP1];
         end
         // Clean up from quadlet/block writes
         eth_reg_wen <= 0;
         eth_block_wen <= 0;
         state[ST_RECEIVE] <= 1;
         recvState <= ST_RECEIVE_FLUSH_START;
      end

      ST_RECEIVE_FLUSH_START:
      begin
         // Increment counters
         numIPv4 <= numIPv4 + {9'd0, isIPv4};
         numARP <= numARP + {9'd0, isARP};
         numICMP <= numICMP + {9'd0, isICMP};
         numUDP <= numUDP + {9'd0, isUDP};
         // Flush the rest of the packet:
         //    1. Clear DMA bit (bit 3)
         //    2. Set flush bit (bit 0)
         isDMA <= 0;
         isWrite <= 1;
         RegAddr <= `ETH_ADDR_RXQCR;
         WriteData <= {ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:1],1'b1};
         state[ST_KSZIO] <= 1;
         recvState <= ST_RECEIVE_FLUSH_WAIT;
         fw_count <= 8'd0;
      end

      ST_RECEIVE_FLUSH_WAIT:
      begin
         // Wait for bit 0 in Register RXQCR to be cleared;
         // Then enable interrupt
         //   - if a read command, start sending response
         //     (check FrameCount after send complete)
         //   - else if more frames available, receive status of next frame
         //   - else go to idle state
         isWrite <= 0;
         if ((isWrite == 0) && (ReadData[0] == 1'b0)) begin
            if ((FireWirePacketFresh && (quadRead || blockRead) && isLocal) || sendARP || isEcho) begin
               state[ST_SEND] <= 1;
               recvState <= ST_RECEIVE_FRAME_COUNT;     // init for next time
               // Could instead set to ST_RECEIVE_FRAME_STATUS
            end
            else begin
               eth_block_wen <= 0;                       // cleanup from block write
               if (FrameCount == 8'd0) begin
                  state[ST_IRQ] <= 1;
                  recvState <= ST_RECEIVE_FRAME_COUNT;   // init for next time
                  // irqState is already set to ST_IRQ_DISPATCH
               end
               else begin
                  // isWrite is already 0
                  RegAddr <= `ETH_ADDR_RXFHSR;
                  state[ST_KSZIO] <= 1;
                  recvState <= ST_RECEIVE_FRAME_STATUS;
               end
            end
            waitInfo <= WAIT_NONE;
         end
         else begin
            // RegAddr is already set to RXQCR
            state[ST_KSZIO] <= 1;
            waitInfo <= WAIT_FLUSH;
            if (blockWrite)
               eth_block_wen <= 1;
         end
      end

      default:
      begin
         numStateInvalid <= numStateInvalid + 10'd1;
         state[ST_IDLE] <= 1;
         recvState <= ST_RECEIVE_FRAME_COUNT;      // init for next time
      end

      endcase
   end

   //*************** States for sending Ethernet packets ******************
   // First, should check if enough memory on QMU TXQ
   //
   // ST_IDLE transitions to ST_SEND when sendReq is asserted (used by Firewire module
   //    to forward packets to Ethernet). In this case, isInIRQ==0.
   // ST_RECEIVE:ST_RECEIVE_FLUSH_WAIT transitions to ST_SEND if the processed packet requires a response.
   //    In this case, isInIRQ==1, since the receive occurs in response to an interrupt.
   //
   // ST_SEND:ST_SEND_END transitions to ST_RECEIVE:ST_RECEIVE_FRAME_STATUS (via retState) when FrameCount
   //    is greater than 0 (and isInIRQ==1).
   // Otherwise, ST_SEND:ST_SEND_END transitions to ST_IDLE (via retState).

   state[ST_SEND]:
   begin
      retState <= ST_SEND;    // Default return state
      sendState <= 16'd0;

      if (sendState == 16'd0) begin
         // Should never happen, except for programming errors
         numStateInvalid <= numStateInvalid + 10'd1;
         sendState[ST_SEND_ENABLE_DMA] <= 1;
         state[ST_IDLE] <= 1;
      end

      // One-hot state machine implementation
      case (1'b1)  // synthesis parallel_case

      sendState[ST_SEND_ENABLE_DMA]:
      begin
         if (!isInIRQ) begin
            sendAck <= 0;  // TEMP
         end
         // Enable DMA transfers
         isWrite <= 1;
         RegAddr <= `ETH_ADDR_RXQCR;
         WriteData <= {ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
         state[ST_KSZIO] <= 1;
         sendState[ST_SEND_DMA_CONTROLWORD] <= 1;
         fw_count <= 8'd0;
      end

      sendState[ST_SEND_DMA_CONTROLWORD]:
      begin
         // Reset pkt words count
         txPktWords <= 12'd0;
         // TX Control word
         // B15  : TXIC transmit interrupt on completion
         // B0-B5: TXFID transmit frame ID
         isDMA <= 1;
         WriteData <= 16'h0;  // Control word = 0
         state[ST_KSZIO] <= 1;
         sendState[ST_SEND_DMA_BYTECOUNT] <= 1;
      end

      sendState[ST_SEND_DMA_BYTECOUNT]:
      begin
         if (isForward && !useUDP) begin
            // Forwarding raw data from FireWire
            //   + 14 for frame header
            WriteData <= 16'd14 + sendLen;
            PacketBuffer[ID_Rep_Frame_Length] <= sendLen;
         end
         else if (isForward && useUDP) begin
            // Forwarding data from FireWire
            //   + 14 for frame header
            //   + 28 for UDP: IPv4 header (20) + UDP header (8)
            WriteData <= 16'd42 + sendLen;
            PacketBuffer[ID_Rep_Frame_Length] <= 16'h0800; // IPv4 EtherType
            PacketBuffer[ID_Rep_IPv4_Length] <= 16'd28 + sendLen;
            PacketBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd17;  // UDP protocol
            PacketBuffer[ID_Rep_UDP_Length] <= 16'd8 + sendLen;
         end
         else if (sendARP) begin
            // ARP response: 14 + 28
            WriteData <= 16'd42;
            PacketBuffer[ID_Rep_Frame_Length] <= 16'h0806; // ARP EtherType
         end
         else if (isEcho) begin
            // Echo (ICMP) response: 14 + IPv4_Length
            WriteData <= 16'd14 + IPv4_Length;
            PacketBuffer[ID_Rep_Frame_Length] <= 16'h0800;   // IPv4 EtherType
            PacketBuffer[ID_Rep_IPv4_Length] <= IPv4_Length; // Same length as request
            PacketBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd1;     // ICMP protocol
         end
         else if (useUDP) begin
            // Byte count for !useUDP (see below) + 28 for UDP:
            //   IPv4 header (20) + UDP header (8)
            WriteData <= quadRead ? 16'd62 : 16'd66 + block_data_length;
            PacketBuffer[ID_Rep_Frame_Length] <= 16'h0800; // IPv4 EtherType (UDP or ICMP)
            PacketBuffer[ID_Rep_IPv4_Length] <= quadRead ? 16'd48 : (16'd52 + block_data_length);
            PacketBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd17;  // UDP protocol
            // UDP Length:
            //   Quadlet read response: 8 (UDP header) + 20 (data)
            //   Block read response: 8 (UDP header) + 24 + block_data_length
            PacketBuffer[ID_Rep_UDP_Length] <= quadRead ? 16'd28 : (16'd32 + block_data_length);
         end
         else begin
            // Local raw packet
            // Set byte count:
            //   * 34 for quadlet read response (14+20)
            //   * (14+24+block_data_length) for block read response
            //     (block_data_length must be a multiple of 4)
            WriteData <= quadRead ? 16'd34 : 16'd38 + block_data_length;
            // Quadlet read response (Length = 20) or block read response
            PacketBuffer[ID_Rep_Frame_Length] <= quadRead ? 16'd20 : (16'd24 + block_data_length);
         end
         state[ST_KSZIO] <= 1;
         sendState[ST_SEND_DMA_ETHERNET_HEADERS] <= 1;
         replyCnt <= Frame_Reply_Begin;
      end

      sendState[ST_SEND_DMA_ETHERNET_HEADERS]:
      begin
         fw_count <= 8'd0;
         state[ST_KSZIO] <= 1;
         replyCnt <= replyCnt + 6'd1;
         `WriteDataSwapped <= PacketBuffer[ReplyIndex[replyCnt]];
         if (replyCnt == Frame_Reply_End) begin
            if (isForward && !useUDP) begin
               sendState[ST_SEND_DMA_FWD] <= 1;
               sendAddr <= 7'd0;
               isForward <= 1'd0;
            end
            else if (sendARP) begin
               replyCnt <= ARP_Reply_Begin;
               sendState[ST_SEND_DMA_ETHERNET_HEADERS] <= 1;
            end
            else if (!(isUDP || isEcho || isForward)) begin
               // Raw packet
               sendState[ST_SEND_DMA_PACKETDATA_HEADER] <= 1;
               replyCnt <= 6'd0;
            end
            else begin
               sendState[ST_SEND_DMA_ETHERNET_HEADERS] <= 1;
            end
         end
         else if (replyCnt == IPv4_Reply_End) begin
            replyCnt <= isEcho ? ICMP_Reply_Begin : UDP_Reply_Begin;
            sendState[ST_SEND_DMA_ETHERNET_HEADERS] <= 1;
         end
         else if (replyCnt == UDP_Reply_End) begin
            if (isForward) begin
               sendState[ST_SEND_DMA_FWD] <= 1;
               sendAddr <= 7'd0;
               isForward <= 1'd0;
            end
            else begin
               sendState[ST_SEND_DMA_PACKETDATA_HEADER] <= 1;
            end
         end
         else if (replyCnt == ARP_Reply_End) begin
            sendState[ST_SEND_DMA_STOP] <= 1;
         end
         else if (replyCnt == ICMP_Reply_End) begin
            sendState[ST_SEND_DMA_ICMP_DATA] <= 1;
         end
         else begin
            sendState[ST_SEND_DMA_ETHERNET_HEADERS] <= 1;
         end
      end

      sendState[ST_SEND_DMA_ICMP_DATA]:
      begin
         state[ST_KSZIO] <= 1;
         `WriteDataSwapped <= (fw_count[0] == 0) ? mem_rdata[31:16]
                                                 : mem_rdata[15:0];
         fw_count <= fw_count + 8'd1;
         if (fw_count == icmp_data_length[7:0])
            sendState[ST_SEND_DMA_STOP] <= 1;
         else
            sendState[ST_SEND_DMA_ICMP_DATA] <= 1;
      end

      // Send first 6 words (3 quadlets), which are nearly identical between quadlet read response
      // and block read response (only difference is tcode).
      sendState[ST_SEND_DMA_PACKETDATA_HEADER]:
      begin
         state[ST_KSZIO] <= 1;
         WriteData <= Firewire_Header_Reply[fw_count[2:0]];
         if (fw_count[2:0] == 3'd5) begin
            fw_count[2:0] <= 3'd0;
            eth_reg_raddr <= fw_dest_offset;
            if (quadRead) begin
               // Get ready to read data from the board.
               ethAccessError <= sample_busy ? 1'd1 : ethAccessError;
               eth_read_en <= 1;
               sendState[ST_SEND_DMA_PACKETDATA_QUAD] <= 1;
            end
            else  // blockRead
               sendState[ST_SEND_DMA_PACKETDATA_BLOCK_START] <= 1;
         end
         else begin
            // stay in this state
            fw_count[2:0] <= fw_count[2:0]+3'd1;
            sendState[ST_SEND_DMA_PACKETDATA_HEADER] <= 1;
         end
      end

      sendState[ST_SEND_DMA_PACKETDATA_QUAD]:
      begin
         state[ST_KSZIO] <= 1;
         if (fw_count[0] == 0) begin
            WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};
            fw_count[0] <= 1;
            // stay in this state
            sendState[ST_SEND_DMA_PACKETDATA_QUAD] <= 1;
         end
         else begin
            WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};
            // Stop accessing FPGA registers
            eth_read_en <= 0;
            fw_count[0] <= 0;
            sendState[ST_SEND_DMA_PACKETDATA_CHECKSUM] <= 1;
         end
      end

      // All block reads start with length, extended_tcode, and header_CRC
      sendState[ST_SEND_DMA_PACKETDATA_BLOCK_START]:
      begin
         state[ST_KSZIO] <= 1;
         if (fw_count[1:0] == 2'd0) begin
            WriteData <= {block_data_length[7:0], block_data_length[15:8]};    // data_length
         end
         else begin
            //1:  WriteData <= 16'h0;     // extended_tcode (0)
            //2:  WriteData <= 16'h0;     // header_CRC
            //3:  WriteData <= 16'h0;     // header_CRC
            WriteData <= 16'h0;
         end
         if (fw_count[1:0] == 2'd3) begin
            fw_count[1:0] <= 2'd0;

            case (fw_dest_offset[15:12])
            `ADDR_MAIN: 
            begin
               fw_count[5:0] <= 6'd0;
               sendState[ST_SEND_DMA_PACKETDATA_BLOCK_MAIN] <= 1;
            end
            `ADDR_PROM_QLA, `ADDR_PROM:
            begin
               // Get ready to read data
               ethAccessError <= sample_busy ? 1'd1 : ethAccessError;
               eth_read_en <= 1;
               eth_reg_raddr[7:0] <= 8'd0;  // Just to be sure
               sendState[ST_SEND_DMA_PACKETDATA_BLOCK_PROM] <= 1;
            end
            `ADDR_HUB, `ADDR_ETH, `ADDR_FW:
            begin
               // TODO: implement read from Hub (for now, abort)
               ethAccessError <= sample_busy ? 1'd1 : ethAccessError;
               eth_read_en <= 1;
               sendState[ST_SEND_DMA_PACKETDATA_BLOCK_PROM] <= 1;
            end
            default:
            begin
               // Abort and let the KSZ8851 chip pad the packet
               sendState[ST_SEND_DMA_STOP] <= 1;
            end
            endcase
         end
         else begin
            fw_count[1:0] <= fw_count[1:0]+2'd1;
            sendState[ST_SEND_DMA_PACKETDATA_BLOCK_START] <= 1;
         end
      end

      sendState[ST_SEND_DMA_PACKETDATA_BLOCK_MAIN]:
      begin
         state[ST_KSZIO] <= 1;
         `WriteDataSwapped <= (fw_count[0] == 1'b0) ? sample_rdata[31:16]
                                                    : sample_rdata[15:0];
         // Reading 28 quadlets means max count will reach 55
         fw_count[5:0] <= (fw_count[5:0] == 6'd55) ? 6'd0 :  fw_count[5:0] + 6'd1;
         if (fw_count[5:0] == 6'd55)
            sendState[ST_SEND_DMA_PACKETDATA_CHECKSUM] <= 1;
         else
            sendState[ST_SEND_DMA_PACKETDATA_BLOCK_MAIN] <= 1;
      end

      sendState[ST_SEND_DMA_PACKETDATA_BLOCK_PROM]:
      begin
         state[ST_KSZIO] <= 1;
         if (fw_count[0] == 0) begin
            fw_count[0] <= 1;
            WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};
            // stay in this state
            sendState[ST_SEND_DMA_PACKETDATA_BLOCK_PROM] <= 1;
         end
         else begin
            fw_count[0] <= 0;
            WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};
            eth_reg_raddr[5:0] <= eth_reg_raddr[5:0] + 6'd1;
            // eth_reg_raddr increments quadlets (32-bits), whereas block_data_length
            // is in bytes (8-bits). Note that maximum PROM read is 256 bytes,
            // or 64 quadlets. The second term below takes care of the overflow
            // case in the first term.
            if (((eth_reg_raddr[5:0] + 6'd1) == block_data_length[7:2]) ||
                (eth_reg_raddr[5:0] == 6'h3f)) begin
               sendState[ST_SEND_DMA_PACKETDATA_CHECKSUM] <= 1;
               eth_read_en <= 0; // we are done
            end
            else
               sendState[ST_SEND_DMA_PACKETDATA_BLOCK_PROM] <= 1;
         end
      end

      sendState[ST_SEND_DMA_PACKETDATA_CHECKSUM]:
      begin
         state[ST_KSZIO] <= 1;
         fw_count[0] <= 1;
         WriteData <= 16'd0;    // Checksum currently not set
         if (fw_count[0] == 1)
            sendState[ST_SEND_DMA_STOP] <= 1;
         else
            sendState[ST_SEND_DMA_PACKETDATA_CHECKSUM] <= 1;
      end

      sendState[ST_SEND_DMA_FWD]:
      begin
         fw_count <= fw_count + 8'd1;
         WriteData <= (fw_count[0] == 0) ? {sendData[23:16], sendData[31:24]} : {sendData[7:0], sendData[15:8]};
         if (fw_count[0] == 1) sendAddr <= sendAddr + 7'd1;
         state[ST_KSZIO] <= 1;
         if (fw_count == (sendLen[8:1]-8'd1))
            sendState[ST_SEND_DMA_STOP] <= 1;
         else
            sendState[ST_SEND_DMA_FWD] <= 1;
      end

      sendState[ST_SEND_DMA_STOP]:
      begin
         // If an odd number of words, first send a dummy word (not sure if this is necessary).
         // Note that ST_KSZIO increments txPktWords.
         if (txPktWords[0]) begin
            WriteData <= 16'd0;
            // stay in this state
            sendState[ST_SEND_DMA_STOP] <= 1;
         end
         else begin
            // Disable DMA transfers
            isDMA <= 0;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:0]};
            sendState[ST_SEND_TXQ_ENQUEUE] <= 1;
         end
         state[ST_KSZIO] <= 1;
      end

      sendState[ST_SEND_TXQ_ENQUEUE]:
      begin
         RegAddr <= `ETH_ADDR_TXQCR;
         WriteData <= 16'h0001;
         // For now, wait for the frame to be transmitted. According to the datasheet,
         // "the software should wait for the bit to be cleared before setting up another
         // new TX frame," so this check could be moved elsewhere for efficiency.
         state[ST_KSZIO] <= 1;
         sendState[ST_SEND_TXQ_ENQUEUE_WAIT] <= 1;
      end

      sendState[ST_SEND_TXQ_ENQUEUE_WAIT]:
      begin
         isWrite <= 0;
         // RegAddr is already set to TXQCR
         // Wait for bit 0 in Register TXQCR (0x80) to be cleared
         state[ST_KSZIO] <= 1;
         if ((isWrite == 0) && (ReadData[0] == 1'b0))
            sendState[ST_SEND_END] <= 1;
         else
            sendState[ST_SEND_TXQ_ENQUEUE_WAIT] <= 1;
      end

      sendState[ST_SEND_END]:
      begin
         if (isInIRQ) begin
            if (FrameCount == 8'd0) begin
               state[ST_IRQ] <= 1;
               // irqState is already set to ST_IRQ_DISPATCH;
            end
            else begin
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_RXFHSR;
               state[ST_KSZIO] <= 1;
               retState <= ST_RECEIVE;
               recvState <= ST_RECEIVE_FRAME_STATUS;
            end
         end
         else begin
            state[ST_IDLE] <= 1;
         end
         sendState[ST_SEND_ENABLE_DMA] <= 1;   // init for next time
      end

      endcase
   end

   //******************* States for I/O to/from KSZ8851 **********************
   // There are two states: ST_WAVEFORM_OUTPUT_INIT and ST_WAVEFORM_OUTPUT_EXECUTE.
   // Many other states call ST_KSZIO, assuming that ioState==ST_WAVEFORM_OUTPUT_INIT.
   // This state always transitions from ST_WAVEFORM_OUTPUT_EXECUTE to whatever state
   // is in retState, which usually is the calling state.
   state[ST_KSZIO]:
   begin

      if (ioState == ST_WAVEFORM_OUTPUT_INIT) begin
         state[ST_KSZIO] <= 1;
         ioState <= ST_WAVEFORM_OUTPUT_EXECUTE;
         case ({isDMA, isWrite})
         2'b00: begin   // Register Read
                ShiftCnt <= 4'd9;
                Cur_WRn <= Read_WRn;
                Cur_RDn <= Read_RDn;
                Cur_CMD <= Read_CMD;
                SDReg <= Addr16;
                end
         2'b01: begin   // Register Write
                ShiftCnt <= 4'd7;
                Cur_WRn <=  Write_WRn;
                Cur_RDn <=  Write_RDn;
                Cur_CMD <=  Write_CMD;
                SDReg <= Addr16;
                end
         2'b10: begin   // DMA Read
                ShiftCnt <= 4'd4;
                Cur_WRn <= DMA_Read_WRn;
                Cur_RDn <= DMA_Read_RDn;
                Cur_CMD <= DMA_Read_CMD;
                //rxPktWords <= rxPktWords - 12'd1;
                end
         2'b11: begin   // DMA Write
                ShiftCnt <= 4'd3;
                Cur_WRn <= DMA_Write_WRn;
                Cur_RDn <= DMA_Write_RDn;
                Cur_CMD <= DMA_Write_CMD;
                SDReg <= WriteData;
                txPktWords <= txPktWords + 12'd1;
                end
         endcase
      end
      else begin  // ST_WAVEFORM_OUTPUT_EXECUTE
         if (ShiftCnt != 4'd0) begin
            state[ST_KSZIO] <= 1;
            Cur_WRn <= Cur_WRn << 1;
            Cur_RDn <= Cur_RDn << 1;
            Cur_CMD <= Cur_CMD << 1;
            ShiftCnt <= ShiftCnt - 4'd1;
            // If CMD high and WRn is going to transition high to low
            // on this cycle, then write address to the bus
            // (currently done in ST_WAVEFORM_OUTPUT_INIT).
            //if ((Cur_CMD[9:8] == 2'b11) && (Cur_WRn[9:8] == 2'b10))
            //   SDReg <= Addr16;  // Addr16 is output of address translator
            // If writing and CMD is going to transition low on
            // this cycle, then write data to the bus (Register Read)
            if (isWrite && (Cur_CMD[9:8] == 2'b10))
               SDReg <= WriteData;
            // If reading and RDn is going to transition high on
            // next cycle, then read data from the bus
            else if (~isWrite && (Cur_RDn[8:7] == 2'b01))
               eth_data <= SD;
         end
         else begin
            // All done, return to previous (or next) state
            state[retState] <= 1;
            ioState <= ST_WAVEFORM_OUTPUT_INIT;
         end
      end
   end

   endcase // case (state)
end

endmodule
