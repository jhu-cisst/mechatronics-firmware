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
    output reg[31:0] ip_address,

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
    input wire[15:0] sendLen
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

// Current state and next state
reg[5:0] state;
reg[5:0] nextState;

reg[9:0] numStateInvalid;   // Number of invalid states (for debugging)

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
   
// state machine states
localparam [5:0]
    ST_IDLE = 6'd0,
    ST_RESET_ASSERT = 6'd1,         // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 6'd2,           // wait after bringing reset high -- 50 msec
    ST_INIT_CHECK_CHIPID = 6'd3,    // Read chip ID
    ST_INIT_RUN_PROGRAM = 6'd4,
    ST_IRQ_HANDLER = 6'd5,
    ST_IRQ_DISPATCH = 6'd6,
    ST_RECEIVE_FRAME_COUNT = 6'd7,
    ST_RECEIVE_FRAME_STATUS = 6'd8,
    ST_RECEIVE_FRAME_LENGTH = 6'd9,
    ST_ENABLE_DMA = 6'd10,
    ST_RECEIVE_DMA_SKIP = 6'd11,
    ST_RECEIVE_DMA_ETHERNET_HEADERS = 6'd12,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 6'd13,
    ST_RECEIVE_DMA_FRAME_CRC = 6'd14,
    ST_RECEIVE_FLUSH_START = 6'd15,
    ST_RECEIVE_FLUSH_WAIT = 6'd16,
    ST_SEND_DMA_CONTROLWORD = 6'd17,
    ST_SEND_DMA_BYTECOUNT = 6'd18,
    ST_SEND_DMA_ETHERNET_HEADERS = 6'd19,
    ST_SEND_DMA_PACKETDATA_HEADER = 6'd20,
    ST_SEND_DMA_PACKETDATA_QUAD = 6'd21,
    ST_SEND_DMA_PACKETDATA_BLOCK_START = 6'd22,
    ST_SEND_DMA_PACKETDATA_BLOCK_MAIN = 6'd23,
    ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL = 6'd24,
    ST_SEND_DMA_PACKETDATA_BLOCK_PROM = 6'd25,
    ST_SEND_DMA_PACKETDATA_CHECKSUM = 6'd26,
    ST_SEND_DMA_FWD = 6'd27,
    ST_SEND_DMA_DUMMY_DWORD = 6'd28,
    ST_SEND_DMA_STOP = 6'd29,
    ST_SEND_TXQ_ENQUEUE = 6'd30,
    ST_SEND_TXQ_ENQUEUE_WAIT = 6'd31,
    ST_SEND_END = 6'd32,
    ST_WAVEFORM_OUTPUT = 6'd33,            // set up read/write waveforms
    ST_WAVEFORM_OUTPUT_EXECUTE = 6'd34,    // generate read/write waveforms
    ST_RECEIVE_DMA_ICMP_DATA = 6'd35,
    ST_SEND_DMA_ICMP_DATA = 6'd36;

// Debugging support
assign eth_io_isIdle = (state == ST_IDLE) ? 1'b1 : 1'b0;

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

// Whether currently sending or receiving
// (used in ST_ENABLE_DMA).
reg isSending;

// Non-zero initial values
initial begin
   isWord = 1'd1;
   ip_address = IP_UNASSIGNED;
   Last_hostIP = IP_UNASSIGNED;
   Cur_WRn = Init_WRn;
   Cur_RDn = Init_RDn;
   Cur_CMD = Init_CMD;
   state = ST_RESET_ASSERT;
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
reg[7:0] count;        // General use counter
reg[5:0] maxCount;     // Maximum count (in ST_SEND_DMA_ETHERNET_HEADERS)
reg[2:0] next_addr;    // Address of next device (for block read)
reg[6:0] block_index;  // Index into data block (5-70)
reg[11:0] txPktWords;  // Num of words sent
reg[11:0] rxPktWords;  // Num of words in receive queue

wire[7:0] maxCountFW;  // Maximum count (of words) when reading FireWire packets
// Subtract 4 words for UDP header (nBytes/2-4-1); otherwise, just subtract 1 word
assign maxCountFW = isUDP ? (UDP_Length[8:1]-8'd5) : (Eth_EtherType[8:1]-8'd1);

wire[15:0] LengthFW;   // Firewire packet length in bytes
// Subtract 8 bytes for UDP header
assign LengthFW = isUDP ? UDP_Length-8'd8 : Eth_EtherType;

assign eth_fwpkt_len = LengthFW;

//************************ Large buffer to hold various packets **************************
// Note that it is fine for some buffers to overlap. For example, an ARP packet does not
// use an IPv4 header.
reg[15:0] PacketBuffer[0:22];

localparam[4:0]
   Frame_Header_Begin = 5'd0,    // Offset to FrameHeader (words) [length=7]
   Frame_Header_End   = 5'd6,
   ARP_Packet_Begin   = 5'd7,    // Offset to ARP Packet (words)  [length=14]
   ARP_Packet_End     = 5'd20,
   IPv4_Header_Begin  = 5'd7,    // Offset to IPv4 Header (words) [length=10]
   IPv4_Header_End    = 5'd16,
   UDP_Header_Begin   = 5'd17,   // Offset to UDP Header (words)  [length=4]
   UDP_Header_End     = 5'd20,
   ICMP_Header_Begin  = 5'd17,   // Offset to ICMP Header (words) [length=6]
   ICMP_Header_End    = 5'd22;

//************************** Ethernet Frame Header ********************************
// Dest MAC (3 words), Src MAC (3 words), Ethertype/Length (1 word)
wire[15:0] Eth_destMac[0:2];
assign Eth_destMac[0] = PacketBuffer[Frame_Header_Begin+5'd0];
assign Eth_destMac[1] = PacketBuffer[Frame_Header_Begin+5'd1];
assign Eth_destMac[2] = PacketBuffer[Frame_Header_Begin+5'd2];
wire[15:0] Eth_srcMac[0:2];
assign Eth_srcMac[0] = PacketBuffer[Frame_Header_Begin+5'd3];
assign Eth_srcMac[1] = PacketBuffer[Frame_Header_Begin+5'd4];
assign Eth_srcMac[2] = PacketBuffer[Frame_Header_Begin+5'd5];
wire[15:0] Eth_EtherType;
assign Eth_EtherType = PacketBuffer[Frame_Header_End];

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
wire[15:0] ARP_srcMac[0:2];
assign ARP_srcMac[0] = PacketBuffer[ARP_Packet_Begin+5'd4];
assign ARP_srcMac[1] = PacketBuffer[ARP_Packet_Begin+5'd5];
assign ARP_srcMac[2] = PacketBuffer[ARP_Packet_Begin+5'd6];
wire[31:0] ARP_hostIP;
assign ARP_hostIP = { PacketBuffer[ARP_Packet_Begin+5'd7], PacketBuffer[ARP_Packet_Begin+5'd8] };
wire[31:0] ARP_fpgaIP;
assign ARP_fpgaIP = { PacketBuffer[ARP_Packet_Begin+5'd12], PacketBuffer[ARP_Packet_Begin+5'd13] };
wire isARPValid;  // Whether ARP request is valid
assign isARPValid = (PacketBuffer[ARP_Packet_Begin+5'd0] == 16'h0001) &&
                    (PacketBuffer[ARP_Packet_Begin+5'd1] == 16'h0800) &&
                    (PacketBuffer[ARP_Packet_Begin+5'd2] == 16'h0604) &&
                    (PacketBuffer[ARP_Packet_Begin+5'd3] == 16'h0001);

// Whether ARP IP address matches this board
wire isARP_ip_equal = (!is_ip_unassigned &&
                      (ip_address == {ARP_fpgaIP[7:0], ARP_fpgaIP[15:8], ARP_fpgaIP[23:16], ARP_fpgaIP[31:24]})) ? 1'd1 : 1'd0;

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
assign IPv4_Version = PacketBuffer[IPv4_Header_Begin+5'd0][15:12];
wire [3:0] IPv4_IHL;
assign IPv4_IHL = PacketBuffer[IPv4_Header_Begin+5'd0][11:8];
wire[15:0] IPv4_Length;
assign IPv4_Length = PacketBuffer[IPv4_Header_Begin+5'd1];
wire[7:0] IPv4_Protocol;
assign IPv4_Protocol = PacketBuffer[IPv4_Header_Begin+5'd4][7:0];
wire[31:0] IPv4_hostIP;
assign IPv4_hostIP = { PacketBuffer[IPv4_Header_Begin+5'd6], PacketBuffer[IPv4_Header_Begin+5'd7] };
wire[31:0] IPv4_fpgaIP;
assign IPv4_fpgaIP = { PacketBuffer[IPv4_Header_Begin+5'd8], PacketBuffer[IPv4_Header_Begin+5'd9] };

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

// Save last host IP address; important for isForward case because the Firewire module may
// request to forward a packet when isIPv4 is false (e.g., if an ARP packet was just processed).
reg [31:0] Last_hostIP;

//********************************* UDP Header ****************************************
// Word 0:  Source port
// Word 1:  Destination port
// Word 2:  Length
// Word 3:  Checksum
wire[15:0] UDP_hostPort;
assign UDP_hostPort = PacketBuffer[UDP_Header_Begin+5'd0];
wire[15:0] UDP_destPort;
assign UDP_destPort = PacketBuffer[UDP_Header_Begin+5'd1];
wire[15:0] UDP_Length;
assign UDP_Length = PacketBuffer[UDP_Header_Begin+5'd2];

wire isPortValid;
assign isPortValid = (UDP_destPort == 16'd1394) ? 1'd1 : 1'd0;

//********************************* ICMP Header ***************************************
// Data received in ICMP Echo packet (ping)
// ICMP packet usually has additional data, with length given by IPv4_Length-20-12
// (i.e., IPv4_Length includes 20 bytes for IPv4 Header and 12 bytes for ICMP Header).
// This data is received in ST_RECEIVE_DMA_ICMP_Data.
wire[15:0] Echo_id;
assign Echo_id = PacketBuffer[ICMP_Header_Begin+5'd2];
wire[15:0] Echo_seq;
assign Echo_seq = PacketBuffer[ICMP_Header_Begin+5'd3];
wire[31:0] Echo_payload;
assign Echo_payload = {PacketBuffer[ICMP_Header_Begin+5'd4],  PacketBuffer[ICMP_Header_Begin+5'd5]};

wire isEcho;
// Echo request (ping) has Type=8, Code=0
assign isEcho = (isICMP && (PacketBuffer[ICMP_Header_Begin] == 16'h0800)) ? 1'd1 : 1'd0;

wire[15:0] icmp_data_length;
// Length of (optional) ICMP data field in bytes: subtract 20 (IPv4 header) and 12 (ICMP header)
assign icmp_data_length = IPv4_Length-16'd32;

//**************************** Final Processing Steps **********************************
// These signals should only be used in ST_RECEIVE_DMA_ETHERNET_HEADERS

wire Frame_Done;
assign Frame_Done = (count == Frame_Header_End) ? 1'd1 : 1'd0;

// Following duplicates logic in isRaw, except using `ReadDataSwapped instead of Eth_EtherType
// because Eth_EtherType is not yet valid when Frame_Done is true.
wire Frame_Raw;
assign Frame_Raw = (Frame_Done && (`ReadDataSwapped[15:9] == 7'd0)) ? 1'd1 : 1'd0;

wire ARP_Done;
assign ARP_Done = (isARP && (count == ARP_Packet_End)) ? 1'd1 : 1'd0;

wire IPv4_Done;
assign IPv4_Done = (isIPv4 && (count == IPv4_Header_End)) ? 1'd1 : 1'd0;

wire UDP_Done;
assign UDP_Done = (isUDP && (count == UDP_Header_End)) ? 1'd1 : 1'd0;

wire ICMP_Done;
assign ICMP_Done = (isICMP && (count == ICMP_Header_End)) ? 1'd1 : 1'd0;

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
// Unlike the received packets (PacketBuffer), it is easier to avoid overlap
wire[15:0] ReplyBuffer[0:40];

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

//************************* Ethernet Frame Reply Header *********************************
assign ReplyBuffer[Frame_Reply_Begin+0] = Eth_srcMac[0];
assign ReplyBuffer[Frame_Reply_Begin+1] = Eth_srcMac[1];
assign ReplyBuffer[Frame_Reply_Begin+2] = Eth_srcMac[2];
assign ReplyBuffer[Frame_Reply_Begin+3] = 16'hFA61;
assign ReplyBuffer[Frame_Reply_Begin+4] = 16'h0E13;
// Rather than using destAddr from last received packet, use our own MAC addr.
assign ReplyBuffer[Frame_Reply_Begin+5] = {8'h94, 4'h0, board_id};  // 0x940n (n = board id)
// Ethertype/Length field, cases are:
//     1) Forwarding raw packet from FireWire (Length = sendLen)
//     2) ARP response (Ethertype = 0x0806)
//     3) UDP response, including ICMP echo (Ethertype = 0x0800)
//     4) Local raw packet, quadlet read response (Length = 20) or block read response
assign ReplyBuffer[Frame_Reply_Begin+6] = (isForward && !useUDP) ? sendLen :
                                          sendARP ? 16'h0806 :
                                          (isUDP || isEcho || isForward) ? 16'h0800 :
                                          quadRead ? 16'd20 : (16'd24 + block_data_length);

//***************************** IPv4 Reply Header ************************************
// Word 0: Version=4, Internet Header Length (IHL)=5, DSCP=0, ECN=0
assign ReplyBuffer[IPv4_Reply_Begin+0] = {4'd4, 4'd5, 6'd0, 2'd0};  // 0x4500
// Word 1: Total length (header and data)
//     ICMP reply (echo): same size as request
//     Quadlet read response: 20 (IPv4 header) + 8 (UDP header) + 20 (data)
//     FW forward: 20 (IPv4 header) + 8 (UDP header) + sendLen
//     Block read response: 20 (IPv4 header) + 8 (UDP header) + 24 + block_data_length
assign ReplyBuffer[IPv4_Reply_Begin+1] = isEcho ? IPv4_Length :
                              isForward ? 16'd28 + sendLen :
                              quadRead ? 16'd48 : (16'd52 + block_data_length);
// Word 2: Identification (supposed to be unique within packet lifetime)
assign ReplyBuffer[IPv4_Reply_Begin+2] = 16'd0;
// Word 3: Flags, Fragment Offset
//     Set the DF (do not fragment) bit
assign ReplyBuffer[IPv4_Reply_Begin+3] = {3'b010, 13'd0};   // 0x4000
// Word 4: Time To Live=64 (recommended default), Protocol= 1 (ICMP) or 17 (UDP)
assign ReplyBuffer[IPv4_Reply_Begin+4] = {8'd64, (isEcho ? 8'd1: 8'd17)};     // 0x4001 or 0x4011
// Word 5: Header Checksum: will be computed by KSZ8851
assign ReplyBuffer[IPv4_Reply_Begin+5] = 16'd0;
// Words 6,7: Source IP
assign ReplyBuffer[IPv4_Reply_Begin+6] = is_ip_unassigned ? IPv4_fpgaIP[31:16] : {ip_address[7:0], ip_address[15:8] };
assign ReplyBuffer[IPv4_Reply_Begin+7] = is_ip_unassigned ? IPv4_fpgaIP[15:0]  : {ip_address[23:16], ip_address[31:24] };
// Words 8,9: Destination IP
assign ReplyBuffer[IPv4_Reply_Begin+8] = Last_hostIP[31:16];
assign ReplyBuffer[IPv4_Reply_Begin+9] = Last_hostIP[15:0];

//****************************** UDP Reply Header *************************************
assign ReplyBuffer[UDP_Reply_Begin+0] = 16'd1394;       // Source Port = 1394
assign ReplyBuffer[UDP_Reply_Begin+1] = UDP_hostPort;   // Destination Port
// Word 2: Length (header and data)
//     Quadlet read response: 8 (UDP header) + 20 (data)
//     Block read response: 8 (UDP header) + 24 + block_data_length
assign ReplyBuffer[UDP_Reply_Begin+2] = quadRead ? 16'd28 : (16'd32 + block_data_length);
assign ReplyBuffer[UDP_Reply_Begin+3] = 16'd0;   // Checksum (optional, will be generated by KSZ8851)

//********************************** ARP Reply *****************************************
assign ReplyBuffer[ARP_Reply_Begin+0] = 16'h0001;  // Hardware type (HTYPE): 1 for Ethernet
assign ReplyBuffer[ARP_Reply_Begin+1] = 16'h0800;  // Protocol type (PTYPE): 0x0800 for IPv4
assign ReplyBuffer[ARP_Reply_Begin+2] = 16'h0604;  // HLEN (6) and PLEN (4)
assign ReplyBuffer[ARP_Reply_Begin+3] = 16'h0002;  // Operation (OPER): 2 for reply
// Word 4-6: Sender hardware address (SHA):  MAC address of sender
assign ReplyBuffer[ARP_Reply_Begin+4] = 16'hFA61;  // 0xFA61
assign ReplyBuffer[ARP_Reply_Begin+5] = 16'h0E13;  // 0x0E13
assign ReplyBuffer[ARP_Reply_Begin+6] = {8'h94,4'h0,board_id}; // 0x940n (n = board id)
// Word 7-8: Sender protocol address (SPA):  IPv4 address of sender (0 for ARP Probe)
assign ReplyBuffer[ARP_Reply_Begin+7] = {ip_address[7:0], ip_address[15:8]};
assign ReplyBuffer[ARP_Reply_Begin+8] = {ip_address[23:16], ip_address[31:24]};
// Word 9-11: Target hardware address (THA):  MAC address of target (ignored in request)
assign ReplyBuffer[ARP_Reply_Begin+9] = ARP_srcMac[0];
assign ReplyBuffer[ARP_Reply_Begin+10] = ARP_srcMac[1];
assign ReplyBuffer[ARP_Reply_Begin+11] = ARP_srcMac[2];
// Word 12-13: Target protocol address (TPA): IPv4 address of target
assign ReplyBuffer[ARP_Reply_Begin+12] = ARP_hostIP[31:16];
assign ReplyBuffer[ARP_Reply_Begin+13] = ARP_hostIP[15:0];

//********************************** ICMP Reply *****************************************
assign ReplyBuffer[ICMP_Reply_Begin+0] = 16'd0;  // Echo Reply: Type=0, Code=0
assign ReplyBuffer[ICMP_Reply_Begin+1] = 16'd0;  // ICMP Checksum will be generated by KSZ8851
assign ReplyBuffer[ICMP_Reply_Begin+2] = Echo_id;
assign ReplyBuffer[ICMP_Reply_Begin+3] = Echo_seq;
assign ReplyBuffer[ICMP_Reply_Begin+4] = Echo_payload[31:16];
assign ReplyBuffer[ICMP_Reply_Begin+5] = Echo_payload[15:0];

//**************************** Firewire Reply Header ***********************************
wire[15:0] Firewire_Header_Reply[0:5];
assign Firewire_Header_Reply[0] = {FireWirePacket[1][23:16], FireWirePacket[1][31:24]};   // quadlet 0: dest-id
assign Firewire_Header_Reply[1] = {quadRead ? `TC_QRESP : `TC_BRESP, 4'd0, fw_tl, 2'd0};  // quadlet 0: tcode
assign Firewire_Header_Reply[2] = {FireWirePacket[0][23:22], node_id, FireWirePacket[0][31:24]};   // src-id
assign Firewire_Header_Reply[3] = 16'd0;   // rcode, reserved
assign Firewire_Header_Reply[4] = 16'd0;   // reserved
assign Firewire_Header_Reply[5] = 16'd0;

//******************************** Debug Counters *************************************

reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[9:0 ] numPacketInvalid;  // Number of invalid Ethernet frames received
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

wire [31:0] DebugData[0:31];
assign DebugData[0]  = "0GBD";  // DBG0 byte-swapped
assign DebugData[1]  = timestamp;
assign DebugData[2]  = {5'd0, ethUDPError, 1'd0, ethIPv4Error, 2'd0, node_id, eth_status};
assign DebugData[3]  = { 2'd0, state, 2'd0, nextState,
                         2'h0, isLocal, isRemote, FireWirePacketFresh, isEthBroadcast, isEthMulticast, ~ETH_IRQn,
                         isForward, isInIRQ, sendARP, isUDP, isICMP, isEcho, is_IPv4_Long, is_IPv4_Short};
assign DebugData[4]  = { RegISR, RegISROther};
assign DebugData[5]  = { host_fw_addr, FrameCount, count};
assign DebugData[6]  = { Eth_destMac[1][7:0], Eth_destMac[1][15:8], Eth_destMac[0][7:0], Eth_destMac[0][15:8] };
assign DebugData[7]  = { Eth_srcMac[0][7:0], Eth_srcMac[0][15:8], Eth_destMac[2][7:0], Eth_destMac[2][15:8] };
assign DebugData[8]  = { Eth_srcMac[2][7:0], Eth_srcMac[2][15:8], Eth_srcMac[1][7:0], Eth_srcMac[1][15:8] };
assign DebugData[9]  = { 8'h11, maxCountFW, LengthFW };
assign DebugData[10] = { IPv4_hostIP[7:0], IPv4_hostIP[15:8], IPv4_hostIP[23:16], IPv4_hostIP[31:24] };
assign DebugData[11] = { IPv4_fpgaIP[7:0], IPv4_fpgaIP[15:8], IPv4_fpgaIP[23:16], IPv4_fpgaIP[31:24] };
assign DebugData[12] = { IPv4_Length, 4'h0, rxPktWords };
assign DebugData[13] = { 16'h8877, 4'd0, txPktWords };
assign DebugData[14] = { 6'd0, numPacketInvalid, numPacketValid };
assign DebugData[15] = { 6'd0, numUDP, 6'd0, numIPv4 };
assign DebugData[16] = { 6'd0, numICMP, 6'd0, numARP };
assign DebugData[17] = { 6'd0, numIPv4Mismatch, 6'd0, numPacketError };
assign DebugData[18] = { UDP_Length, 6'd0, numStateInvalid };
assign DebugData[19] = { UDP_hostPort, UDP_destPort };
assign DebugData[20] = timestamp;


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
// For now, we will make the buffer big enough to hold 71 quadlets.
// reg[31:0] FireWirePacket[0:70];  // FireWire packet memory (max 71 quadlets)
// Allocate pow(2,7) = 128 quadlets
reg [31:0] FireWirePacket[0:127];
assign eth_fwpkt_rdata = FireWirePacket[eth_fwpkt_raddr[6:0]];
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

// Following data is accessible via block read from address `ADDR_ETH (0x4000)
//    Maximum block read size is 64 quadlets (implementation choice)
//    4000 - 4007f (128 quadlets) FireWire packet
//    4080 - 4009f (32 quadlets) Debug data
// Note that full address decoding is not done, so other addresses will work too
// (for example, 40c0-40cf will also give Debug data, as will 4f80-4f9f)
assign reg_rdata = (reg_raddr[7] == 0) ? FireWirePacket[reg_raddr[6:0]] :
                   (reg_raddr[6] == 0) ? DebugData[reg_raddr[4:0]] : {6'd0, InitProgram[reg_raddr[4:0]]};


wire[3:0] fw_tcode;            // FireWire transaction code
wire[5:0] fw_tl;               // FireWire transaction label
wire[3:0] fw_pri;              // FireWire priority field
wire[15:0] block_data_length;  // Data length (in bytes) for block read/write requests

assign fw_tl = FireWirePacket[0][15:10];
assign fw_tcode = FireWirePacket[0][7:4];
assign fw_pri = FireWirePacket[0][3:0];
assign block_data_length = FireWirePacket[3][31:16];

// Valid destination address: check if first 10 bits are FFC (i.e., all 1)
wire valid_dest_id;
assign valid_dest_id = (FireWirePacket[0][31:22] == 10'h3FF) ? 1'd1 : 1'd0;
wire[5:0] dest_node_id;
assign dest_node_id = FireWirePacket[0][21:16];

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

assign addrMain = (FireWirePacket[2][15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;
assign addrHub = (FireWirePacket[2][15:12] == `ADDR_HUB) ? 1'd1 : 1'd0;
assign addrPROM = (FireWirePacket[2][15:12] == `ADDR_PROM) ? 1'd1 : 1'd0;
assign addrQLA  = (FireWirePacket[2][15:12] == `ADDR_PROM_QLA) ? 1'd1 : 1'd0;


// Registers in block read
reg[7:0] BlockRegAddr[0:3];
initial begin
   BlockRegAddr[0] = {4'd0, `REG_STATUS};
   BlockRegAddr[1] = {4'd0, `REG_DIGIN};
   BlockRegAddr[2] = {4'd0, `REG_TEMPSNS};
   BlockRegAddr[3] = {4'd1, 4'd0 };   // Channel 1 start
end

// TEMP: Timestamp copied from Firewire.v -- should consolidate
reg[31:0]  timestamp;          // timestamp counter register
reg ts_reset;                 // timestamp counter reset signal
// -------------------------------------------------------
// Timestamp
// -------------------------------------------------------
// timestamp counts number of clocks between block reads
always @(posedge(sysclk) or posedge(ts_reset))
begin
    if (ts_reset)
        timestamp <= 0;
    else
        timestamp <= timestamp + 1'b1;
end


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

       // Write to IP address register
       if (ip_reg_wen) begin
          ip_address <= reg_wdata;
       end

       if (ksz_reg_wen) begin
          //****** Access to KSZ8851 registers via Firewire interface ******
          // Format of 32-bit fw_reg_wdata:
          // 0(4) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
          // bit 27: DMA
          // bit 26: reset
          // bit 25: R/W Read (0) or Write (1)
          // bit 24: W/B Word or Byte
          // bit 23-16: 8-bit address
          // bit 15-0 : 16-bit data
          // The initialization request is processed any time, but other
          // request are only processed if received in the IDLE state.
          // If not in the IDLE state, then eth_error is set.
          if (fw_reg_wdata[26]) begin   // if reset
             initCount <= 21'd0;        // Clear counter
             state <= ST_RESET_ASSERT;
             eth_error <= 0;
          end
          else if (state == ST_IDLE) begin
             eth_error <= 0;
             isDMA <= fw_reg_wdata[27];
             isWrite <= fw_reg_wdata[25];
             isWord <= fw_reg_wdata[24];
             RegAddr <= fw_reg_wdata[23:16];
             WriteData <= fw_reg_wdata[15:0];
             count <= 8'd0;
             state <= ST_WAVEFORM_OUTPUT;
             nextState <= ST_IDLE;
          end
          else begin
             eth_error <= 1;
          end
       end

       //******************** State Machine ********************
       case (state)
         ST_IDLE:
         begin
            isDMA <= 0;
            isWord <= 1;       // all transfers are word
            isInIRQ <= 0;
            eth_read_en <= 0;
            eth_reg_wen <= 0;
            eth_block_wen <= 0;
            eth_block_wstart <= 0;
            block_index <= 0;
            waitInfo <= WAIT_NONE;
            if (~ETH_IRQn) begin
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_ISR;
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_IRQ_HANDLER;
            end
            else if (sendReq) begin
               // forward packet from FireWire
               state <= ST_ENABLE_DMA;
               isForward <= 1;
               isSending <= 1;
               sendAck <= 1;
            end
         end

         // Assert the reset and wait 10 ms before removing it.
         ST_RESET_ASSERT:
         begin
            if (initCount == 21'd491520) begin  // 10 ms (49.152 MHz sysclk)
               ETH_RSTn <= 1;   // Remove the reset
               initCount <= 21'd0;
               state <= ST_RESET_WAIT;
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
               numStateInvalid <= 10'd0;
               FireWirePacketFresh <= 0;
               initCount <= initCount + 21'd1;
            end
         end

         // The reset has ended, wait 50 ms before initializing chip registers
         ST_RESET_WAIT:
         begin
            if (initCount == 21'h1FFFFF) begin
               initCount <= 21'd0;
               isDMA <= 0;
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_CIDER;   // Read Chip ID
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_INIT_CHECK_CHIPID;
            end
            else
               initCount <= initCount + 21'd1;
         end

         //*************** States for initializing Ethernet ******************

         ST_INIT_CHECK_CHIPID:
         begin
            if (ReadData[15:4] == 12'h887) begin
               // Chip ID is ok, go to next state
               count[4:0] <= 5'd0;
               InitProgram[0][3:0] <= board_id;
               state <= ST_INIT_RUN_PROGRAM;
            end
            else begin
               initOK <= 0;
               state <= ST_IDLE;
            end
         end

         ST_INIT_RUN_PROGRAM:
         begin
            isWrite <= InitProgram[count[4:0]][`WRITE_BIT];
            RegAddr <= InitProgram[count[4:0]][`ADDR_BITS];
            WriteData <= InitProgram[count[4:0]][`OR_BIT] ? (ReadData|InitProgram[count[4:0]][`DATA_BITS])
                                                          : InitProgram[count[4:0]][`DATA_BITS];
            count[4:0] <= count[4:0] + 5'd1;
            state <= ST_WAVEFORM_OUTPUT;
            if (count[4:0] == 5'd16) begin
               initOK <= 1;
               nextState <= ST_IDLE;
            end
            else begin
               nextState <= ST_INIT_RUN_PROGRAM;
            end
         end

         //*************** States for handling IRQs ******************
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
            state <= ST_IRQ_DISPATCH;
            isInIRQ <= 1;
            if (~(ReadData[15] || ReadData[13])) begin
               // Record unexpected interrupt
               RegISROther <= ReadData;
            end
         end

         ST_IRQ_DISPATCH:
         begin
            if (RegISR[15] == 1'b1) begin
               // Handle link change (TBD)
               isWrite <= 1;
               RegAddr <= `ETH_ADDR_ISR;
               WriteData <= 16'h8000;    // Clear interrupt
               RegISR[15] <= 1'b0;       // Clear RegISR
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_IRQ_DISPATCH;
            end
            else if (RegISR[13] == 1'b1) begin
               // Handle receive
               isWrite <= 1;
               RegAddr <= `ETH_ADDR_ISR;
               WriteData <= 16'h2000;  // clear interrupt
               RegISR[13] <= 1'b0;     // clear ISR receive IRQ bit
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_RECEIVE_FRAME_COUNT;
               count <= 8'd0;
            end
            else if (RegISR[14] || RegISR[11] || RegISR[9] || RegISR[8] || RegISR[6]) begin
               // These interrupts are not handled and are disabled, so clear them
               // if they somehow occurred.
               isWrite <= 1;
               RegAddr <= `ETH_ADDR_ISR;
               WriteData <= RegISR&16'b0100101101000000;
               RegISR <= RegISR&16'b1011010010111111;    // Clear RegISR bits
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_IRQ_DISPATCH;             // Return to this state in case other bits set
            end
            else if (RegISR[5] || RegISR[4] || RegISR[3] || RegISR[2]) begin
               // These interrupts are also not handled and are disabled, but are
               // cleared differently (by writing to PMECR)
               isWrite <= 1;
               RegAddr <= `ETH_ADDR_PMECR;
               WriteData <= RegISR&16'h003c;
               RegISR    <= RegISR&16'hffc3;    // Clear RegISR bits
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_IDLE;
            end
            else begin
               // Done IRQ handle, clear flag
               isInIRQ <= 0;
               state <= ST_IDLE;
            end
         end

         //*************** States for receiving Ethernet packets ******************

         ST_RECEIVE_FRAME_COUNT:
         begin
            if (count[0] == 1'b0) begin
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_RXFCTR;
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_RECEIVE_FRAME_COUNT;
               count[0] <= 1'd1;
            end
            else begin
               FrameCount <= ReadData[15:8];
               count[0] <= 1'd0;
               if (ReadData[15:8] == 0) begin
                  state <= isInIRQ ? ST_IRQ_DISPATCH : ST_IDLE;
               end
               else begin
                  state <= ST_RECEIVE_FRAME_STATUS;
               end
            end
         end

         ST_RECEIVE_FRAME_STATUS:
         begin
            if (count[0] == 1'b0) begin
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_RXFHSR;
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_RECEIVE_FRAME_STATUS;
               count[0] <= 1'd1;
            end
            else begin
               FrameCount <= FrameCount-8'd1;
               count[0] <= 1'd0;
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
                  state <= ST_RECEIVE_FLUSH_START;
               end
               else begin
                  // Valid frame, so start processing
                  FrameValid <= 1;
                  isEthBroadcast <= ReadData[7];
                  isEthMulticast <= ReadData[6];
                  isWrite <= 0;
                  RegAddr <= `ETH_ADDR_RXFHBCR;
                  state <= ST_WAVEFORM_OUTPUT;
                  nextState <= ST_RECEIVE_FRAME_LENGTH;
                  numPacketValid <= numPacketValid + 16'd1;
               end
            end
         end

         ST_RECEIVE_FRAME_LENGTH:
         begin
            if (ReadData[11:0] == 12'd0) begin
               numPacketInvalid <= numPacketInvalid + 10'd1;
               state <= ST_RECEIVE_FLUSH_START;
            end
            else begin
                rxPktWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
                // Set QMU RXQ frame pointer to 0, also decrease write sample time
                isWrite <= 1;
                RegAddr <= `ETH_ADDR_RXFDPR;
                WriteData <= 16'h5000;
                state <= ST_WAVEFORM_OUTPUT;
                nextState <= ST_ENABLE_DMA;
                isSending <= 0;
            end
         end

         ST_ENABLE_DMA:
         begin
            if (isSending && !isInIRQ) begin
               sendAck <= 0;  // TEMP
            end
            // Enable DMA transfers
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= isSending ? ST_SEND_DMA_CONTROLWORD : ST_RECEIVE_DMA_SKIP;
            count <= 8'd0;
         end

         ST_RECEIVE_DMA_SKIP:
         begin
            isDMA <= 1;
            isWrite <= 0;
            state <= ST_WAVEFORM_OUTPUT;
            // Skip first 3 words in the packet
            // ignore(1) + status(1) + byte-count(1)
            if (count[1:0] == 2'd3) begin
               nextState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
               count[4:0] <= Frame_Header_Begin;
            end
            else begin
               nextState <= ST_RECEIVE_DMA_SKIP;
               count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_RECEIVE_DMA_ETHERNET_HEADERS:
         begin
            if (Any_Error) begin
               state  <= ST_RECEIVE_FLUSH_START;
               count[4:0] <= 5'd0;
            end
            else begin
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ICMP_Done ? ST_RECEIVE_DMA_ICMP_DATA :
                            (ARP_Done ? ST_RECEIVE_DMA_FRAME_CRC :
                             ((UDP_Done || Frame_Raw) ? ST_RECEIVE_DMA_FIREWIRE_PACKET :
                             ST_RECEIVE_DMA_ETHERNET_HEADERS));
               count[4:0] <= (ICMP_Done || ARP_Done || UDP_Done || Frame_Raw) ? 5'd0 : count[4:0]+5'd1;
            end
            PacketBuffer[count[4:0]] <= `ReadDataSwapped;
            numPacketError <= numPacketError + {9'd0, Frame_Error|IPv4_Error|UDP_Error};
            ethFrameError <= Frame_Error ? 1'd1 : ethFrameError;
            ethIPv4Error <= IPv4_Error ? 1'd1 : ethIPv4Error;
            ethUDPError <= UDP_Error ? 1'd1 : ethUDPError;
            if (IPv4_Done && !IPv4_Error) begin
               // Can check for IHL > 5
               // maxCount <= IPv4_Header_Begin + {ReadData[3:0],1'd0}-5'd1;
               Last_hostIP <= IPv4_hostIP;
               if (is_ip_unassigned && (IPv4_fpgaIP[7:0] != 8'hff)) begin
                  // This case can occur when the host PC already has an ARP
                  // cache entry for this board, in which case we just assign
                  //  the IP address, as long as it is not a broadcast address
                  //  (we only check whether the last byte is 255).
                  ip_address[31:16] <= {IPv4_fpgaIP[7:0], IPv4_fpgaIP[15:8] };
                  ip_address[15:0] <= {IPv4_fpgaIP[23:16], IPv4_fpgaIP[31:24] };
               end
               else if ((ip_address != {IPv4_fpgaIP[7:0], IPv4_fpgaIP[15:8], IPv4_fpgaIP[23:16], IPv4_fpgaIP[31:24]})
                        && !isEthBroadcast && !isEthMulticast) begin
                  // If IP assigned, but not equal, we process the packet anyway,
                  // but keep track of the number of times this occurred.
                  // We could decide to update ip_address.
                  numIPv4Mismatch <= numIPv4Mismatch + 10'd1;
               end
            end
            else if (ARP_Done && isARPValid && is_ip_unassigned) begin
               // If our IP address not yet set, update it
               ip_address[31:16] <= ReadData;
               ip_address[15:0] <= {ARP_fpgaIP[23:16], ARP_fpgaIP[31:24] };
            end
         end

         ST_RECEIVE_DMA_ICMP_DATA:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= (count == icmp_data_length[7:0]) ? ST_RECEIVE_DMA_FRAME_CRC : ST_RECEIVE_DMA_ICMP_DATA;
            count <= count + 8'd1;
            // For now, read ICMP data into FireWirePacket buffer
            if (count[0] == 0)
               FireWirePacket[count[7:1]][31:16] <= `ReadDataSwapped;
            else
               FireWirePacket[count[7:1]][15:0] <= `ReadDataSwapped;
         end

         ST_RECEIVE_DMA_FIREWIRE_PACKET:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
            count <= count + 8'd1;

            // Read FireWire packet, byteswap to make it easier to work with;
            // might need to byteswap again if sending it out via FireWire.
            if (count[0] == 0)
               FireWirePacket[count[7:1]][31:16] <= `ReadDataSwapped;
            else
               FireWirePacket[count[7:1]][15:0] <= `ReadDataSwapped;

            // Following handles state transitions, incrementing count and local quadlet
            // and block writes.
            // Note that isLocal, quadWrite, and blockWrite are not valid right away,
            // but will be valid for the counts that are used below.
            // Also, the counts are set so that the referenced FireWirePacket data is valid;
            // for example, count==8 corresponds to the start of reading FireWirePacket[4],
            // so FireWirePacket[0:3] are valid. This works because all FireWire packets have
            // a CRC at the end, so we are sure to process the last data packet.
            // Note that we do not check the FireWire CRC because we assume that the Ethernet
            // checksum has already guaranteed that the data is valid.

            if ((count == 8'd2) && !valid_dest_id) begin
               // invalid destination address, flush packet
               ethDestError <= 1;
               state <= ST_RECEIVE_FLUSH_START;
            end
            else if (count == 8'd8) begin
               if (isLocal) begin
                  if (quadWrite) begin
                     eth_block_wen <= 1;
                     eth_reg_waddr <= FireWirePacket[2][15:0];
                     eth_reg_wdata <= FireWirePacket[3];
                     // Special case: write to FireWire PHY register
                     if (addrMain && (FireWirePacket[2][11:0] == {8'h0, `REG_PHYCTRL})) begin
                        // check the RW bit to determine access type (bit 12, after byte-swap)
                        lreq_type <= (FireWirePacket[3][12] ? `LREQ_REG_WR : `LREQ_REG_RD);
                        lreq_trig <= 1;
                     end
                  end
                  else if (blockWrite) begin
                     // Set and clear eth_block_wstart before starting block write
                     // (arbitrarily chose to set it at count==8).
                     eth_block_wstart <= 1;
                  end
               end
            end
            else if (count == 8'd11) begin
               // Following only required if (isLocal && blockWrite)
               eth_block_wstart <= 0;
            end
            else if (count == 8'd12) begin
               if (isLocal && blockWrite) begin
                  eth_reg_waddr[15:12] <= FireWirePacket[2][15:12];
                  if (addrMain) begin
                     eth_reg_waddr[7:4] <= 4'd1;  // start with channel 1
                     eth_reg_waddr[3:0] <= `OFF_DAC_CTRL;
                     //eth_reg_wdata[15:0] <= FireWirePacket[5][15:0];
                     //PK: why just 15:0 above?
                     eth_reg_wdata <= FireWirePacket[5];
                  end
                  else begin
                     eth_reg_waddr[11:0] <= FireWirePacket[2][11:0];
                     eth_reg_wdata <= FireWirePacket[5];
                  end
                  block_index <= 7'd5;
               end
            end

            if (count == maxCountFW) begin
               // normal completion
               FireWirePacketFresh <= 1;
               useUDP <= isUDP;
               // Allow reading of FireWire CRC
               nextState <= ST_RECEIVE_DMA_FRAME_CRC;
               if (isLocal) begin
                  if (quadWrite) begin
                      eth_reg_wen <= 1;
                      lreq_trig <= 0;     // Clear lreq_trig in case it was set
                  end
                  else if (blockWrite) begin
                      eth_block_wen <= 1;
                  end
               end
               if (isRemote) begin
                  // Request to forward pkt
                  eth_send_fw_req <= 1;
                  host_fw_addr <= FireWirePacket[1][31:16];
               end
            end

            // Remaining contents of block write (for count=13...maxCountFW)
            // Note that block_index is only non-zero when (isLocal && blockWrite)
            // so we do not need to check those.
            if (block_index != 7'd0) begin   // count > 12
               if (count[0] == 0) begin      // (even)
                  eth_reg_wen <= 0;
                  if (addrMain) begin
                     eth_reg_waddr[7:4] <= eth_reg_waddr[7:4] + 4'd1;
                     //eth_reg_wdata[15:0] <= FireWirePacket[block_index][15:0];
                     //PK: why just 15:0 above?
                     eth_reg_wdata <= FireWirePacket[block_index];
                  end
                  else begin
                     eth_reg_waddr <= eth_reg_waddr + 16'd1;
                     eth_reg_wdata <= FireWirePacket[block_index];
                  end
               end
               else begin                    // (odd)
                  // MSB is "valid" bit for DAC write (addrMain)
                  eth_reg_wen <= addrMain ? FireWirePacket[block_index][31] : 1'b1;
                  block_index <= block_index + 7'd1;
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
            state <= ST_RECEIVE_FLUSH_START;
         end

         ST_RECEIVE_FLUSH_START:
         begin
            // Increment counters
            numIPv4 <= numIPv4 + {9'd0, isIPv4};
            numARP <= numARP + {9'd0, isARP};
            numICMP <= numICMP + {9'd0, isICMP};
            numUDP <= numUDP + {9'd0, isUDP};
            // Clean up from quadlet/block writes
            eth_reg_wen <= 0;
            eth_block_wen <= 0;
            // Flush the rest of the packet:
            //    1. Clear DMA bit (bit 3)
            //    2. Set flush bit (bit 0)
            isDMA <= 0;
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:1],1'b1};
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_RECEIVE_FLUSH_WAIT;
            count <= 8'd0;
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
                  isSending <= 1;
                  state <= ST_ENABLE_DMA;
               end
               else begin
                  if (FrameCount == 8'd0) begin
                     state <= isInIRQ ? ST_IRQ_DISPATCH : ST_IDLE;
                  end
                  else begin
                     state <= ST_RECEIVE_FRAME_STATUS;
                  end
               end
               waitInfo <= WAIT_NONE;
            end
            else begin
               // RegAddr is already set to RXQCR
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_RECEIVE_FLUSH_WAIT;
               waitInfo <= WAIT_FLUSH;
            end
         end

         //*************** States for sending Ethernet packets ******************
         // First, should check if enough memory on QMU TXQ

         ST_SEND_DMA_CONTROLWORD:
         begin
            // Reset pkt words count
            txPktWords <= 12'd0;
            // TX Control word
            // B15  : TXIC transmit interrupt on completion
            // B0-B5: TXFID transmit frame ID
            isDMA <= 1;
            WriteData <= 16'h0;  // Control word = 0
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_SEND_DMA_BYTECOUNT;
         end

         ST_SEND_DMA_BYTECOUNT:
         begin
            if (isForward) begin
               // Forwarding data from FireWire
               //   + 14 for frame header
               //   + 28 for UDP: IPv4 header (20) + UDP header (8)
               WriteData <= (useUDP ? 16'd42 : 16'd14) + sendLen;
            end
            else if (sendARP) begin
               // ARP response: 14 + 28
               WriteData <= 16'd42;
            end
            else if (isEcho) begin
               // Echo (ICMP) response: 14 + IPv4_Length
               WriteData <= 16'd14 + IPv4_Length;
            end
            else begin
               // Set byte count:
               //   * 34 for quadlet read response (14+20)
               //   * (14+24+block_data_length) for block read response
               //     (block_data_length must be a multiple of 4)
               //   + 28 for UDP: IPv4 header (20) + UDP header (8)
               case ({useUDP, quadRead})
                 2'b00: WriteData <= 16'd38 + block_data_length; // block read response
                 2'b01: WriteData <= 16'd34;                     // quadlet read response
                 2'b10: WriteData <= 16'd66 + block_data_length; // UDP, block read response
                 2'b11: WriteData <= 16'd62;                     // UDP, quadlet read response
               endcase
            end
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_SEND_DMA_ETHERNET_HEADERS;
            count[5:0] <= Frame_Reply_Begin;
            maxCount <= UDP_Reply_End;   // nominal value (may get updated)
         end

         ST_SEND_DMA_ETHERNET_HEADERS:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_SEND_DMA_ETHERNET_HEADERS;
            count[5:0] <= (count[5:0] == maxCount) ? 6'd0 : (count[5:0] + 6'd1);
            `WriteDataSwapped <= ReplyBuffer[count];
            if (count[5:0] == Frame_Reply_End) begin
               if (isForward && !useUDP) begin
                  nextState <= ST_SEND_DMA_FWD;
                  sendAddr <= 7'd0;
                  isForward <= 1'd0;
               end
               else if (sendARP) begin
                  count[5:0] <= ARP_Reply_Begin;
                  maxCount <= ARP_Reply_End;
               end
               else if (!(isUDP || isEcho || isForward)) begin
                  // Raw packet
                  nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
                  count[5:0] <= 6'd0;
               end
            end
            else if (count[5:0] == IPv4_Reply_End) begin
               count[5:0] <= isEcho ? ICMP_Reply_Begin : UDP_Reply_Begin;
               maxCount <= isEcho ? ICMP_Reply_End : UDP_Reply_End;
            end
            else if (count[5:0] == UDP_Reply_End) begin
               if (isForward) begin
                  nextState <= ST_SEND_DMA_FWD;
                  sendAddr <= 7'd0;
                  isForward <= 1'd0;
               end
               else begin
                  nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
               end
            end
            else if (count[5:0] == ARP_Reply_End) begin
               nextState <= ST_SEND_DMA_STOP;
            end
            else if (count[5:0] == ICMP_Reply_End) begin
               nextState <= ST_SEND_DMA_ICMP_DATA;
            end
         end

         ST_SEND_DMA_ICMP_DATA:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            `WriteDataSwapped <= (count[0] == 0) ? FireWirePacket[count[7:1]][31:16]
                                                 : FireWirePacket[count[7:1]][15:0];
            count <= count + 8'd1;
            nextState <= (count == icmp_data_length[7:0]) ? ST_SEND_DMA_STOP : ST_SEND_DMA_ICMP_DATA;
         end

         // Send first 6 words (3 quadlets), which are nearly identical between quadlet read response
         // and block read response (only difference is tcode).
         ST_SEND_DMA_PACKETDATA_HEADER:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            WriteData <= Firewire_Header_Reply[count[2:0]];
            if (count[2:0] == 3'd5) begin
               count[2:0] <= 3'd0;
               eth_reg_raddr <= FireWirePacket[2][15:0];
               if (quadRead) begin
                  // Get ready to read data from the board.
                  eth_read_en <= 1;
                  nextState <= ST_SEND_DMA_PACKETDATA_QUAD;
               end
               else  // blockRead
                  nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_START;
            end
            else begin
               nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
               count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_QUAD:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            if (count[0] == 0) begin
               WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};
               count[0] <= 1;
               nextState <= ST_SEND_DMA_PACKETDATA_QUAD;
            end
            else begin
               WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};
               // Stop accessing FPGA registers
               eth_read_en <= 0;
               count[0] <= 0;
               nextState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
            end
         end

         // All block reads start with length, extended_tcode, and header_CRC
         ST_SEND_DMA_PACKETDATA_BLOCK_START:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            if (count[1:0] == 2'd0) begin
                WriteData <= {block_data_length[7:0], block_data_length[15:8]};    // data_length
            end
            else begin
                //1:  WriteData <= 16'h0;     // extended_tcode (0)
                //2:  WriteData <= 16'h0;     // header_CRC
                //3:  WriteData <= 16'h0;     // header_CRC
                WriteData <= 16'h0;
            end
            if (count[1:0] == 2'd3) begin
               count[1:0] <= 2'd0;

               case (FireWirePacket[2][15:12])
               `ADDR_MAIN: 
               begin
                  nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_MAIN;
               end
               `ADDR_PROM_QLA, `ADDR_PROM:
               begin
                  // Get ready to read data
                  eth_read_en <= 1;
                  eth_reg_raddr[7:0] <= 8'd0;  // Just to be sure
                  nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
               end
               `ADDR_HUB, `ADDR_ETH, `ADDR_FW:
               begin
                  // TODO: implement read from Hub (for now, abort)
                  eth_read_en <= 1;
                  nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
               end
               default:
               begin
                  // Abort and let the KSZ8851 chip pad the packet
                  nextState <= ST_SEND_DMA_DUMMY_DWORD;
               end
               endcase
            end
            else begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_START;
                count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_BLOCK_MAIN:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            eth_reg_raddr <= (count[0] == 1) ? {8'd0, BlockRegAddr[count[2:1]]} : eth_reg_raddr;
            `WriteDataSwapped <= (count[2:1] == 2'b00) ?
                                 ((count[0] == 1'b0) ? timestamp[31:16] : timestamp[15:0]) :
                                 ((count[0] == 1'b0) ? eth_reg_rdata[31:16] : eth_reg_rdata[15:0]);
            // count==1: Reset timestamp and get ready to read from board
            {ts_reset, eth_read_en} <= (count[2:0] == 3'd1) ? 2'b11 : {1'b0, eth_read_en};
            if (count[2:0] == 3'd7) begin
               nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
               // NOTE: Following is hard-coded to first read from channel 0,
               //       and then from 5,6,7. This is correct, but less flexible
               //       than the implementation in Firewire.v, which uses dev_addr[].
               next_addr <= 3'd5;             // set next device address
               count[2:0] <= 3'd0;
            end
            else begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_MAIN;
                count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            if (count[0] == 0) begin
                count[0] <= 1;
                WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
            end
            else begin
                count[0] <= 0;
                WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};
                if (eth_reg_raddr[7:4] == `NUM_CHANNELS) begin
                    if (next_addr == 3'd7) begin
                        eth_read_en <= 0;  // we are done
                        nextState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
                    end
                    else begin
                        eth_reg_raddr[7:4] <= 4'd1;
                        eth_reg_raddr[2:0] <= next_addr;
                        next_addr <= next_addr + 3'd1;
                        nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
                    end
                end
                else begin
                    eth_reg_raddr[7:4] <= eth_reg_raddr[7:4] + 4'd1;
                    nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
                end
            end
         end

         ST_SEND_DMA_PACKETDATA_BLOCK_PROM:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            if (count[0] == 0) begin
                count[0] <= 1;
                WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
            end
            else begin
                count[0] <= 0;
                WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};
                eth_reg_raddr[5:0] <= eth_reg_raddr[5:0] + 6'd1;
                // eth_reg_raddr increments quadlets (32-bits), whereas block_data_length
                // is in bytes (8-bits). Note that maximum PROM read is 256 bytes,
                // or 64 quadlets. The second term below takes care of the overflow
                // case in the first term.
                if (((eth_reg_raddr[5:0] + 6'd1) == block_data_length[7:2]) ||
                    (eth_reg_raddr[5:0] == 6'h3f)) begin
                    nextState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
                    eth_read_en <= 0; // we are done
                end
                else
                    nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
            end
         end

         ST_SEND_DMA_PACKETDATA_CHECKSUM:
         begin
            state <= ST_WAVEFORM_OUTPUT;
            count[0] <= 1;
            WriteData <= 16'd0;    // Checksum currently not set
            nextState <= (count[0] == 0) ? ST_SEND_DMA_PACKETDATA_CHECKSUM : ST_SEND_DMA_DUMMY_DWORD;
         end

         ST_SEND_DMA_FWD:
         begin
            count <= count + 8'd1;
            WriteData <= (count[0] == 0) ? {sendData[23:16], sendData[31:24]} : {sendData[7:0], sendData[15:8]};
            if (count[0] == 1) sendAddr <= sendAddr + 7'd1;
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= (count == (sendLen[8:1]-8'd1)) ? ST_SEND_DMA_DUMMY_DWORD : ST_SEND_DMA_FWD;
         end

         ST_SEND_DMA_DUMMY_DWORD:
         begin
            count <= 8'd0;
            if (txPktWords[0]) begin
               WriteData <= 16'd0;
               state <= ST_WAVEFORM_OUTPUT;
               nextState <= ST_SEND_DMA_STOP;
            end
            else begin
               state <= ST_SEND_DMA_STOP;
            end
         end

         ST_SEND_DMA_STOP:
         begin
            // Disable DMA transfers
            isDMA <= 0;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:0]};
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_SEND_TXQ_ENQUEUE;
         end

         ST_SEND_TXQ_ENQUEUE:
         begin
            RegAddr <= `ETH_ADDR_TXQCR;
            WriteData <= 16'h0001;
            // For now, wait for the frame to be transmitted. According to the datasheet,
            // "the software should wait for the bit to be cleared before setting up another
            // new TX frame," so this check could be moved elsewhere for efficiency.
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ST_SEND_TXQ_ENQUEUE_WAIT;
         end

         ST_SEND_TXQ_ENQUEUE_WAIT:
         begin
            isWrite <= 0;
            // RegAddr is already set to TXQCR
            count[0] <= 1'd0;
            // Wait for bit 0 in Register TXQCR (0x80) to be cleared
            state <= ST_WAVEFORM_OUTPUT;
            nextState <= ((isWrite == 0) && (ReadData[0] == 1'b0)) ? ST_SEND_END : ST_SEND_TXQ_ENQUEUE_WAIT;
         end

         ST_SEND_END:
         begin
            if (isInIRQ) begin
               if (FrameCount == 8'd0) begin
                  state <= ST_IRQ_DISPATCH;
               end
               else begin
                  state <= ST_RECEIVE_FRAME_STATUS;
               end
            end
            else begin
               state <= ST_IDLE;
            end
         end

         ST_WAVEFORM_OUTPUT:
         begin
            state <= ST_WAVEFORM_OUTPUT_EXECUTE;
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

         ST_WAVEFORM_OUTPUT_EXECUTE:
         begin
            if (ShiftCnt != 4'd0) begin
               Cur_WRn <= Cur_WRn << 1;
               Cur_RDn <= Cur_RDn << 1;
               Cur_CMD <= Cur_CMD << 1;
               ShiftCnt <= ShiftCnt - 4'd1;
               // If CMD high and WRn is going to transition high to low
               // on this cycle, then write address to the bus
               // (currently done in ST_WAVEFORM_OUTPUT).
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
               // All done
               state <= nextState;
            end
         end

         default:
         begin
            numStateInvalid <= numStateInvalid + 10'd1;
            state <= ST_IDLE;
         end

         endcase // case (state)
end

endmodule
