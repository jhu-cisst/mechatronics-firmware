/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2023 ERC CISST, Johns Hopkins University.
 *
 * This module implements the higher-level (network layer) Ethernet I/O, which
 * interfaces to the link layer for the KSZ8851 MAC/PHY chip (FPGA V2) or the
 * link layer for the RTL8211F PHY chip (FPGA V3).
 *
 * There are two parameters to the module:
 *   IPv4_CSUM    Default is 0 (FPGA V2), set to 1 for FPGA V3
 *   IS_V3        Default is 0 (FPGA V2), set to 1 for FPGA V3
 * Since both parameter settings are based on FPGA version, they could be combined,
 * but are kept separate for greater flexibility in the future.
 *
 * Revision history
 *     12/21/15    Peter Kazanzides    Initial Revision
 *     11/28/16    Zihan Chen          Added Disable/Enable in RECEIVE
 *     11/5/19     Peter Kazanzides    Added UDP support
 *     1/13/20     Peter Kazanzides    Incorporated low-level interface from KSZ8851.v
 *     8/27/22     Peter Kazanzides    Moved low-level interface back to KSZ8851.v
 */

// global constant e.g. register & device address
`include "Constants.v"

// Sizes of packet headers (in bytes)
`define ETH_FRAME_SIZE  16'd14     // Ethernet frame
`define IPv4_HDR_SIZE   16'd20     // IPv4 Header
`define UDP_HDR_SIZE     16'd8     // UDP Header
`define FW_EXTRA_SIZE    16'd8     // Extra data (after Firewire packet)
`define UDP_EXTRA_SIZE  (`UDP_HDR_SIZE+`FW_EXTRA_SIZE)
`define IPv4_UDP_EXTRA_SIZE  (`IPv4_HDR_SIZE+`UDP_HDR_SIZE+`FW_EXTRA_SIZE)

`define FW_QREAD_SIZE   16'd16     // Firewire quadlet read request
`define FW_QRESP_SIZE   16'd20     // Firewire quadlet read response
`define FW_QWRITE_SIZE  16'd20     // Firewire quadlet write
`define FW_BRESP_SIZE   16'd24     // Firewire block read response header and CRCs
`define FW_BWRITE_SIZE  16'd24     // Firewire block write header and CRCs
`define FW_BWRITE_HDR_SIZE 16'd20  // Firewire block write header size

module EthernetIO
    #(parameter IPv4_CSUM = 0,     // Set to 1 to generate IPv4 header checksum
      parameter IS_V3 = 0)         // Set to 1 to indicate FPGA V3 timing
(
    // global clock
    input wire sysclk,

    // board id (rotary switch)
    input wire[3:0] board_id,
    input wire[5:0] node_id,

    // Register interface to Ethernet memory space and IP address register
    input  wire[15:0] reg_raddr_in,
    output reg[31:0] reg_rdata_out,
    input  wire[31:0] reg_wdata_in,
    input  wire ip_reg_wen,
    input  wire ctrl_reg_wen,
    output wire[31:0] ip_address,

    // Interface to/from board registers. These enable the Ethernet module to drive
    // the internal bus on the FPGA. In particular, they are used to read registers
    // to respond to quadlet read and block read commands.
    input wire[31:0] reg_rdata,
    output reg[15:0] reg_raddr,
    output reg       req_read_bus,     // 1 -> request read bus (reg_raddr)
    input wire       grant_read_bus,   // 1 -> read bus granted
    input wire       reg_rvalid,       // 1 -> reg_rdata should be valid
    output reg[31:0] reg_wdata,
    output reg[15:0] reg_waddr,
    output reg       reg_wen,
    output reg       blk_wen,
    output reg       blk_wstart,
    output reg       req_blk_rt_rd,    // request to start real-time block read
    output wire      blk_rt_rd,        // real-time block read
    output wire      req_write_bus,
    input wire       grant_write_bus,

    // Low-level Firewire PHY access
    output reg lreq_trig,         // trigger signal for a FireWire phy request
    output reg[2:0] lreq_type,    // type of request to give to the FireWire phy

    // Interface to FireWire module (for sending packets via FireWire)
    output reg eth_send_fw_req,   // request to send firewire packet
    input wire eth_send_fw_ack,   // ack from firewire module
    input  wire[8:0] eth_fwpkt_raddr,
    output wire[31:0] eth_fwpkt_rdata,
    output wire[15:0] eth_fwpkt_len,   // eth received fw pkt length
    output reg[15:0] host_fw_addr,     // Firewire address of host (e.g., ffd0)

    // Interface from Firewire (for sending packets via Ethernet)
    // Note that sendAck is asserted when the Ethernet module is accessing the Firewire
    // packet memory via sendAddr and sendData.
    output reg sendAck,              // Ack from Ethernet
    output reg[8:0] sendAddr,        // Address into packet memory
    input wire[31:0] sendData,       // Packet data from memory
    input wire[15:0] sendLen,        // Packet size (bytes)

    input wire fw_bus_reset,         // Firewire bus reset in process

    // Timestamp
    input wire[31:0] timestamp,

    // Interface to KSZ8851 or EthSwitchRt (2 x RTL8211F)
    input wire resetActive,          // Indicates that reset is active
    input wire isForward,            // Indicates that FireWire receiver is forwarding to Ethernet
    output wire responseRequired,    // Indicates that the received packet requires a response
    output wire[15:0] responseByteCount,  // Number of bytes in required response
    // Ethernet receive
    input wire recvRequest,          // Request EthernetIO to start receiving
    output reg recvBusy,             // To KSZ8851
    input wire recvReady,            // Indicates that recv_word is valid
    input wire[15:0] recv_word,      // Word received via Ethernet (`SDSwapped for KSZ8851)
    // Ethernet send
    input wire sendRequest,          // Request EthernetIO to get ready to start sending
    output reg sendBusy,             // To KSZ8851
    input wire sendReady,            // Request EthernetIO to provide next send_word
    output reg[15:0] send_word,      // Word to send via Ethernet (SDRegDWR for KSZ8851)
    // Timing measurements
    input wire[15:0] timeReceive,    // Time when receive portion finished
    input wire[15:0] timeNow,        // Running time counter since start of packet receive
    // Feedback bits
    output reg bw_active,            // Indicates that block write module is active
    input wire ethLLError,           // Error summary bit to EthernetIO (from low-level)
    output wire[7:0] eth_status      // Status feedback
);

`define send_word_swapped {send_word[7:0], send_word[15:8]}

// TEMP for V2 (should figure out why eth_write_en still needed)
reg eth_write_en;
reg eth_req_write_reg;
assign req_write_bus = eth_write_en | eth_req_write_reg;

// Error flags
reg ethFrameError;     // 1 -> Frame is not Raw, IPv4 or ARP
reg ethIPv4Error;      // 1 -> IPv4 header error (protocol not UDP or ICMP; header version != 4)
reg ethUDPError;       // 1 -> Wrong UDP port (not 1394)
reg ethDestError;      // 1 -> Incorrect destination (FireWire destination does not begin with 0xFFC)
reg ethSendStateError; // 1 -> Invalid Ethernet state in Send state machine
reg ethRecvStateError; // 1 -> Invalid Ethernet state in Receive state machine

// Summary of packet-related error bits
wire ethSummaryError;
assign ethSummaryError = ethFrameError | ethIPv4Error | ethUDPError | ethDestError;

// Summary of internal error bits
wire ethInternalError;
assign ethInternalError = ethSendStateError | ethRecvStateError | ethLLError;

// Firewire bus generation. Incremented each time fw_bus_reset is cleared.
reg[7:0] fw_bus_gen;

always @(negedge fw_bus_reset)
begin
    fw_bus_gen <= fw_bus_gen + 8'd1;
end

localparam[31:0] IP_UNASSIGNED = 32'hffffffff;

`ifdef HAS_DEBUG_DATA
wire eth_send_isIdle;
assign eth_send_isIdle = (sendState == ST_SEND_DMA_IDLE) ? 1'd1 : 1'd0;
wire eth_recv_isIdle;
assign eth_recv_isIdle = (recvState == ST_RECEIVE_DMA_IDLE) ? 1'd1 : 1'd0;
`endif

// Following flags are set based on the destination address. Note that
// a FireWire broadcast packet will set both isLocal and isRemote.
wire isLocal;       // 1 -> FireWire packet should be processed locally
wire isRemote;      // 1 -> FireWire packet should be forwarded

wire quadRead;
wire quadWrite;
wire blockRead;
wire blockWrite;

wire addrMain;

wire isRebootCmd;   // 1 -> Reboot FPGA command received

// Whether to use UDP (1) or raw Ethernet frames (0).
// This mode is set each time a valid packet is received
// (i.e., set if a valid UDP packet received, cleared if
// a valid raw Ethernet frame is received).
reg useUDP;

assign eth_status[7] = ethFrameError;      // 1 -> Ethernet frame unsupported
assign eth_status[6] = ethIPv4Error;       // 1 -> IPv4 header error
assign eth_status[5] = ethUDPError;        // 1 -> Wrong UDP port (not 1394)
assign eth_status[4] = ethDestError;       // 1 -> Ethernet destination error
assign eth_status[3] = 1'b0;               // 1 -> Unable to access internal bus
assign eth_status[2] = (ethSendStateError|ethRecvStateError);  // 1 -> Invalid send/receive state
assign eth_status[1] = 1'b0;
assign eth_status[0] = useUDP;             // 1 -> Using UDP, 0 -> Raw Ethernet

// Whether Firewire packet was dropped, rather than being processed,
// due to Firewire bus reset or mismatch on bus generation number.
reg fwPacketDropped;

// Whether to send a response packet with just ExtraData.
// This is done when a packet is dropped.
wire sendExtra;
assign sendExtra = fwPacketDropped;

// Flag set by host to clear error bits and counters
reg clearErrors;

reg[11:0] txPktWords;  // Num of words sent

wire[15:0] Eth_EtherType;
wire[15:0] UDP_Length; // UDP packet length (bytes)

wire[9:0] maxCountFW;  // Maximum count (of words) when reading FireWire packets
// Maximum count, in words, is (nBytes/2-1), assuming nBytes is an even number
//   - Subtract 4 words for UDP header
//   - Subtract 1 word for FwCtrl
// Following assumes that UDP_Length is an even number.
// Note that IEEE-1394 specification indicates that maximum asynchronous packet size is
//  2048 bytes (1024 words, 512 quadlets) at 400 Mbits/sec.
assign maxCountFW = isUDP ? (UDP_Length[10:1]-10'd6) : (Eth_EtherType[10:1]-10'd2);

wire[15:0] LengthFW;   // Firewire packet length in bytes
// Subtract 8 bytes for UDP header and 2 bytes for FwCtrl
assign LengthFW = isUDP ? (UDP_Length-8'd10) : (Eth_EtherType-8'd2);

assign eth_fwpkt_len = LengthFW;

//************************ Large buffer to hold various packets **************************
// Note that it is fine for some buffers to overlap. Below, the UDP, ICMP and ARP buffers
// all start after the IPv4 Header. Technically, the ARP buffer could start after the
// Ethernet Frame Header (since it does not use IPv4), but it is more convenient to
// not overlap with the IPv4 Header so that part of the IPv4 Header can be used in
// reply packets.

// Following are word offsets into PacketBuffer
localparam[4:0]
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
   ID_FwCtrl            = ID_UDP_End+1,      // Firewire Control word, Raw or UDP (21)
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
   ID_Packet_End        = ID_ARP_End;        // ****** End of Packet Data (30) **********
   // The Frame checksum is not actually read
   //ID_Csum_Begin        = ID_ARP_End+1,      // ***** Frame Checksum (31) [length=2] ****
   //ID_Frame_Checksum0   = ID_Csum_Begin,     // Ethernet frame checksum (MSW)
   //ID_Frame_Checksum1   = ID_Csum_Begin+1,   // Ethernet frame checksum (LSW)
   //ID_Csum_End          = ID_Csum_Begin+1,   // ***** End of Frame Checksum (32) ********
   //ID_Packet_End        = ID_Csum_End;        // ****** End of Packet Data (32) **********

reg[15:0] PacketBuffer[0:31];

// Following is data that is used when constructing the Reply packet
localparam[3:0]
   ID_Reply_Begin       = 0,                 // ****** Start of Reply Data (0) *********
   ID_Rep_Zero          = ID_Reply_Begin,    // Value of 0 for generic use
   ID_Rep_fpgaMac0      = ID_Reply_Begin+1,  // FPGA MAC address (FA61)
   ID_Rep_fpgaMac1      = ID_Reply_Begin+2,  // FPGA MAC address (0E13)
   ID_Rep_fpgaMac2      = ID_Reply_Begin+3,  // FPGA MAC address (940N)
   ID_Rep_Frame_Length  = ID_Reply_Begin+4,  // Frame EtherType/Length
   ID_Rep_IPv4_Word0    = ID_Reply_Begin+5,  // IPv4 Word 0 (in case different)
   ID_Rep_IPv4_Length   = ID_Reply_Begin+6,  // IPv4 Flags (in case different)
   ID_Rep_IPv4_Flags    = ID_Reply_Begin+7,  // IPv4 Flags (in case different)
   ID_Rep_IPv4_Prot     = ID_Reply_Begin+8,  // IPv4 Protocol (UDP or ICMP)
   ID_Rep_IPv4_Csum     = ID_Reply_Begin+9,  // IPv4 Header checksum
   ID_Rep_IPv4_Address0 = ID_Reply_Begin+10, // Source (FPGA) IP address (MSW)
   ID_Rep_IPv4_Address1 = ID_Reply_Begin+11, // Source (FPGA) IP address (LSW)
   ID_Rep_UDP_fpgaPort  = ID_Reply_Begin+12, // UDP port on FPGA (1394)
   ID_Rep_UDP_hostPort  = ID_Reply_Begin+13, // UDP port on host (ID_UDP_hostPort)
   ID_Rep_UDP_Length    = ID_Reply_Begin+14, // UDP Reply Length
   ID_Rep_ARP_Oper      = ID_Reply_Begin+15, // ARP reply operation = 2
   ID_Reply_End         = ID_Reply_Begin+15; // ******** End of all data (15) ***********

reg[15:0] ReplyBuffer[0:15];

integer i;
initial begin
   for (i = ID_Packet_Begin; i <= ID_Packet_End; i=i+1) PacketBuffer[i] = 16'd0;
   ReplyBuffer[ID_Rep_Zero]          = 16'd0;
   ReplyBuffer[ID_Rep_fpgaMac0]      = 16'hFA61;
   ReplyBuffer[ID_Rep_fpgaMac1]      = 16'h0E13;
   ReplyBuffer[ID_Rep_fpgaMac2]      = 16'h9400;   // board_num updated in ST_RESET_WAIT
   ReplyBuffer[ID_Rep_Frame_Length]  = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   ReplyBuffer[ID_Rep_IPv4_Word0]    = {4'd4, 4'd5, 6'd0, 2'd0};  // 0x4500
   ReplyBuffer[ID_Rep_IPv4_Length]   = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   ReplyBuffer[ID_Rep_IPv4_Flags]    = {3'b010, 13'd0};  // 0x4000
   ReplyBuffer[ID_Rep_IPv4_Prot]     = {8'd64, 8'd17};   // TTL=64; Prot updated in ST_SEND_DMA_BYTECOUNT
   ReplyBuffer[ID_Rep_IPv4_Csum]     = 16'd0;
   ReplyBuffer[ID_Rep_IPv4_Address0] = IP_UNASSIGNED[31:16];  // updated when IP address assigned
   ReplyBuffer[ID_Rep_IPv4_Address1] = IP_UNASSIGNED[15:0];   // updated when IP address assigned
   ReplyBuffer[ID_Rep_UDP_fpgaPort]  = 16'd1394;
   ReplyBuffer[ID_Rep_UDP_hostPort]  = 16'd0;      // Needs to be updated
   ReplyBuffer[ID_Rep_UDP_Length]    = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   ReplyBuffer[ID_Rep_ARP_Oper]      = 16'h0002;   // ARP Operation (OPER): 2 for reply
end

wire[15:0] Rep_IPv4_Csum16;

generate
if (IPv4_CSUM) begin
    wire[18:0] Rep_IPv4_Csum19;
    assign Rep_IPv4_Csum19 = {3'd0, ReplyBuffer[ID_Rep_IPv4_Word0]} +
                             {3'd0, ReplyBuffer[ID_Rep_IPv4_Length]} +
                             {3'd0, ReplyBuffer[ID_Rep_IPv4_Flags]} +
                             {3'd0, ReplyBuffer[ID_Rep_IPv4_Prot]} +
                             {3'd0, ReplyBuffer[ID_Rep_IPv4_Address0]} +
                             {3'd0, ReplyBuffer[ID_Rep_IPv4_Address1]} +
                             {3'd0, PacketBuffer[ID_IPv4_hostIP0]} +
                             {3'd0, PacketBuffer[ID_IPv4_hostIP1]};

    // First part of IPv4 checksum carry
    wire[16:0] Rep_IPv4_Csum17;
    assign Rep_IPv4_Csum17 = { 1'd0, Rep_IPv4_Csum19[15:0]} + {14'd0, Rep_IPv4_Csum19[18:16]};

    // Second part of IPv4 checksum carry, with ones complement of result
    assign Rep_IPv4_Csum16 = ~(Rep_IPv4_Csum17[15:0] + {15'd0, Rep_IPv4_Csum17[16]});
end
else begin
    assign Rep_IPv4_Csum16 = 16'd0;
end
endgenerate

//************************** Ethernet Frame Header ********************************
assign Eth_EtherType = PacketBuffer[ID_Frame_Length];

wire isIPv4;
// IPv4 Ethertype is 0x0800
assign isIPv4 = (Eth_EtherType == 16'h0800) ? 1'd1 : 1'd0;

wire isARP;
// ARP Ethertype is 0x0806
assign isARP = (Eth_EtherType == 16'h0806) ? 1'd1 : 1'd0;

wire isRaw;
// The frame is considered raw if it has a length, rather than an EtherType.
// The Ethernet standard allows lengths up to 1500 bytes, but we limit to 1024 bytes.
// Thus, we check if the upper 6 bits are 0 (i.e., if length is no more than 10 bits).
assign isRaw = (Eth_EtherType[15:10] == 6'd0) ? 1'd1 : 1'd0;

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
`ifdef HAS_DEBUG_DATA
wire [3:0] IPv4_IHL;
assign IPv4_IHL = PacketBuffer[ID_IPv4_Word0][11:8];
`endif
wire[15:0] IPv4_Length;
assign IPv4_Length = PacketBuffer[ID_IPv4_Length];
wire[7:0] IPv4_Protocol;
assign IPv4_Protocol = PacketBuffer[ID_IPv4_Protocol][7:0];
wire[31:0] IPv4_fpgaIP;
// Byteswapped to match ip_address
assign IPv4_fpgaIP = { PacketBuffer[ID_IPv4_destIP1][7:0], PacketBuffer[ID_IPv4_destIP1][15:8], PacketBuffer[ID_IPv4_destIP0][7:0], PacketBuffer[ID_IPv4_destIP0][15:8] };

`ifdef HAS_DEBUG_DATA
wire is_IPv4_Long;
// The following conditional is an efficient alternative to (IPv4_IHL > 5).
assign is_IPv4_Long = (isIPv4 && ((IPv4_IHL[3] == 2'b1) || (IPv4_IHL[2:1] == 2'b11))) ? 1'd1 : 1'd0;

wire is_IPv4_Short;
// IHL should never be less than 5, so this should not happen
assign is_IPv4_Short = (isIPv4 && !is_IPv4_Long && (IPv4_IHL != 4'd5)) ? 1'd1 : 1'd0;
`endif

wire isUDP;
assign isUDP = (isIPv4 && (IPv4_Protocol == 8'd17)) ? 1'd1 : 1'd0;

wire isICMP;
assign isICMP = (isIPv4 && (IPv4_Protocol == 8'd1)) ? 1'd1 : 1'd0;

//********************************* UDP Header ****************************************
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
// Length of (optional) ICMP data field in bytes: subtract 20 (IPv4 header) and 12 (ICMP header).
// Note that maximum ping data size is 1472 bytes (1500-28) because we do not fragment packets.
assign icmp_data_length = IPv4_Length-16'd32;

//**************************** Firewire Control Word ************************************
// The Raw or UDP header is followed by one control word, which includes the expected Firewire
// generation.
wire[15:0] fw_ctrl;
assign fw_ctrl = PacketBuffer[ID_FwCtrl];
wire noForwardFlag;
assign noForwardFlag = fw_ctrl[8];
wire[7:0] host_fw_bus_gen;
assign host_fw_bus_gen = fw_ctrl[7:0];

//******************************* Reply packets *****************************************
// The reply packets can mostly be constructed by returning data from the incoming packets
// (in PacketBuffer), augmented with a few extra data items that have been added to ReplyBuffer
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

// The following array contains the indices (into PacketBuffer or ReplyBuffer) that are used
//  to construct the reply packets.
reg[5:0] ReplyIndex[0:63];

localparam isPacket = 1'b0;
localparam isReply  = 2'b10;

initial begin
   ReplyIndex[Frame_Reply_Begin]    = {isPacket, ID_Frame_srcMac0};
   ReplyIndex[Frame_Reply_Begin+1]  = {isPacket, ID_Frame_srcMac1};
   ReplyIndex[Frame_Reply_Begin+2]  = {isPacket, ID_Frame_srcMac2};
   ReplyIndex[Frame_Reply_Begin+3]  = {isReply,  ID_Rep_fpgaMac0};
   ReplyIndex[Frame_Reply_Begin+4]  = {isReply,  ID_Rep_fpgaMac1};
   ReplyIndex[Frame_Reply_Begin+5]  = {isReply,  ID_Rep_fpgaMac2};
   ReplyIndex[Frame_Reply_Begin+6]  = {isReply,  ID_Rep_Frame_Length};

   ReplyIndex[IPv4_Reply_Begin]     = {isReply,  ID_Rep_IPv4_Word0};
   ReplyIndex[IPv4_Reply_Begin+1]   = {isReply,  ID_Rep_IPv4_Length};
   ReplyIndex[IPv4_Reply_Begin+2]   = {isReply,  ID_Rep_Zero};       // Identification
   ReplyIndex[IPv4_Reply_Begin+3]   = {isReply,  ID_Rep_IPv4_Flags};
   ReplyIndex[IPv4_Reply_Begin+4]   = {isReply,  ID_Rep_IPv4_Prot};
   ReplyIndex[IPv4_Reply_Begin+5]   = {isReply,  ID_Rep_IPv4_Csum};  // Header checksum
   ReplyIndex[IPv4_Reply_Begin+6]   = {isReply,  ID_Rep_IPv4_Address0};
   ReplyIndex[IPv4_Reply_Begin+7]   = {isReply,  ID_Rep_IPv4_Address1};
   ReplyIndex[IPv4_Reply_Begin+8]   = {isPacket, ID_IPv4_hostIP0};
   ReplyIndex[IPv4_Reply_Begin+9]   = {isPacket, ID_IPv4_hostIP1};

   ReplyIndex[UDP_Reply_Begin]      = {isReply,  ID_Rep_UDP_fpgaPort};
   ReplyIndex[UDP_Reply_Begin+1]    = {isReply,  ID_Rep_UDP_hostPort};
   ReplyIndex[UDP_Reply_Begin+2]    = {isReply,  ID_Rep_UDP_Length};
   ReplyIndex[UDP_Reply_Begin+3]    = {isReply,  ID_Rep_Zero};       // Checksum

   ReplyIndex[ARP_Reply_Begin]      = {isPacket, ID_ARP_HTYPE};
   ReplyIndex[ARP_Reply_Begin+1]    = {isPacket, ID_ARP_PTYPE};
   ReplyIndex[ARP_Reply_Begin+2]    = {isPacket, ID_ARP_HLEN_PLEN};
   ReplyIndex[ARP_Reply_Begin+3]    = {isReply,  ID_Rep_ARP_Oper};
   ReplyIndex[ARP_Reply_Begin+4]    = {isReply,  ID_Rep_fpgaMac0};
   ReplyIndex[ARP_Reply_Begin+5]    = {isReply,  ID_Rep_fpgaMac1};
   ReplyIndex[ARP_Reply_Begin+6]    = {isReply,  ID_Rep_fpgaMac2};
   ReplyIndex[ARP_Reply_Begin+7]    = {isReply,  ID_Rep_IPv4_Address0};
   ReplyIndex[ARP_Reply_Begin+8]    = {isReply,  ID_Rep_IPv4_Address1};
   ReplyIndex[ARP_Reply_Begin+9]    = {isPacket, ID_ARP_srcMac0};
   ReplyIndex[ARP_Reply_Begin+10]   = {isPacket, ID_ARP_srcMac1};
   ReplyIndex[ARP_Reply_Begin+11]   = {isPacket, ID_ARP_srcMac2};
   ReplyIndex[ARP_Reply_Begin+12]   = {isPacket, ID_ARP_hostIP0};
   ReplyIndex[ARP_Reply_Begin+13]   = {isPacket, ID_ARP_hostIP1};

   ReplyIndex[ICMP_Reply_Begin]     = {isReply,  ID_Rep_Zero};
   ReplyIndex[ICMP_Reply_Begin+1]   = {isReply,  ID_Rep_Zero};       // ICMP checksum
   ReplyIndex[ICMP_Reply_Begin+2]   = {isPacket, ID_ICMP_Begin+2};
   ReplyIndex[ICMP_Reply_Begin+3]   = {isPacket, ID_ICMP_Begin+3};
   ReplyIndex[ICMP_Reply_Begin+4]   = {isPacket, ID_ICMP_Begin+4};
   ReplyIndex[ICMP_Reply_Begin+5]   = {isPacket, ID_ICMP_Begin+5};

   // Fill in rest of buffer
   for (i=ICMP_Reply_End+1; i < 64; i=i+1) ReplyIndex[i] = {isReply, ID_Rep_Zero};
end

reg[5:0] replyCnt;                 // Counter for ReplyIndex

// For IP Address register (BoardRegs)
assign ip_address = {ReplyBuffer[ID_Rep_IPv4_Address1][7:0], ReplyBuffer[ID_Rep_IPv4_Address1][15:8],
                     ReplyBuffer[ID_Rep_IPv4_Address0][7:0], ReplyBuffer[ID_Rep_IPv4_Address0][15:8]};

//**************************** Firewire Reply Header ***********************************
wire[15:0] Firewire_Header_Reply[0:9];
assign Firewire_Header_Reply[0] = {fw_src_id[7:0], fw_src_id[15:8]};                      // quadlet 0: dest-id
assign Firewire_Header_Reply[1] = {quadRead ? `TC_QRESP : `TC_BRESP, 4'd0, fw_tl, 2'd0};  // quadlet 0: tcode
assign Firewire_Header_Reply[2] = {dest_bus_id[1:0], node_id, dest_bus_id[9:2]};          // src-id
assign Firewire_Header_Reply[3] = 16'd0;   // rcode, reserved
assign Firewire_Header_Reply[4] = 16'd0;   // reserved
assign Firewire_Header_Reply[5] = 16'd0;
assign Firewire_Header_Reply[6] = {block_data_length[7:0], block_data_length[15:8]};      // data_length
assign Firewire_Header_Reply[7] = 16'd0;   // extended_tcode (0)
assign Firewire_Header_Reply[8] = 16'd0;   // header_CRC
assign Firewire_Header_Reply[9] = 16'd0;   // header_CRC

//******************************** Debug Counters *************************************

`ifdef HAS_DEBUG_DATA
reg[9:0] numIPv4;            // Number of IPv4 packets received
reg[9:0] numUDP;             // Number of UDP packets received
reg[7:0] numARP;             // Number of ARP packets received
reg[7:0] numICMP;            // Number of ICMP packets received
`endif

reg[7:0] numPacketError;     // Number of packet errors (Frame, IPv4 or UDP error)

wire is_ip_unassigned;
assign is_ip_unassigned = (ip_address == IP_UNASSIGNED) ? 1'd1 : 1'd0;

// Request a local write to be performed (quadWrite or blockWrite)
reg writeRequestBlock;
reg writeRequestQuad;

reg[8:0] bwStart;      // Starting offset in bw_packet for RT write block (for this board)
reg[8:0] bwLen;        // Number of quadlets in the RT write block in bw_packet (for this board)
wire[8:0] bwEnd;       // Ending offset in bw_packet for RT write block (for this board)

assign bwEnd = bwStart + bwLen;

// Word number at which to request a block write and Firewire packet forward, so that
// reader and writer can overlap. See explanation below (search for writeRequestTrigger).
// bwLen is in quadlets, so 2*bwLen is in words. LengthFW is in bytes.
wire[9:0] writeRequestTrigger;
// (2*bwStart)  == {bwStart, 1'd0}    --> word offset for block write header
// (2*bwLen)>>1 == {1'd0, bwLen}      --> equivalent to numWords/2
// (2*bwLen)>>3 == {3'd0, bwLen[8:2]} --> equivalent to numWords/8
// (2*bwLen)>>6 == {6'd0, bwLen[8:5]} --> equivalent to numWords/64
wire[9:0] fwRequestTrigger;
// Following assumes that LengthFW is not more than 12 bits
// (LengthFw>>1)>>1 == LengthFW[11:2]           --> numWords/2
// (LengthFw>>1)>>3 == { 2'd0, LengthFW[11:4] } --> numWords/8
// (LengthFw>>1)>>6 == { 5'd0, LengthFW[11:7] } --> numWords/64
//   Quadlet read:  N=16 --> M = (3/5)*N = 10
//   Quadlet write: N=20 --> M = (3/5)*N = 12
// In both cases, we add 2 words to provide some margin and handle round-off.
generate
if (IS_V3) begin
  assign writeRequestTrigger = {bwStart, 1'd0} + {1'd0, bwLen} + 10'd2;
  assign fwRequestTrigger    = LengthFW[11:2] + 10'd2;
end
else begin
  assign writeRequestTrigger = {bwStart, 1'd0} + {1'd0, bwLen} +
                               {3'd0, bwLen[8:2]} - {6'd0, bwLen[8:5]} + 10'd2;
  assign fwRequestTrigger    = LengthFW[11:2] + {2'd0, LengthFW[11:4]} +
                               {5'd0, LengthFW[11:7]} + 10'd2;
end
endgenerate

reg      bw_err;     // Block write error (block write not active when expected)
reg[8:0] bw_left;    // Number of quadlets left to write when processing last Firewire quadlet

reg      fw_err;     // Firewire forward error (Firewire forward not active when expected)
reg[8:0] fw_left;    // Number of quadlets left to forward when processing last quadlet

reg[7:0] fw_wait_cnt;   // Number of clocks waiting for Firewire forward to finish

// -----------------------------------------------
// Extra data sent to PC with every Firewire packet
// -----------------------------------------------

wire[15:0] ExtraData[0:3];
assign ExtraData[0] = {4'd0, ethSummaryError, ethInternalError, fwPacketDropped, fw_bus_reset, fw_bus_gen};
`ifdef DEBOUNCE_STATES
assign ExtraData[1] = {numStateGlitch, numPacketError};
`else
assign ExtraData[1] = {8'd0, numPacketError};
`endif
assign ExtraData[2] = timeReceive;
assign ExtraData[3] = timeNow;

// -----------------------------------------------
// Debug data
// -----------------------------------------------
`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:15];
assign DebugData[0]  = "2GBD";  // DBG2 byte-swapped
assign DebugData[1]  = timestamp;
assign DebugData[2]  = { writeRequestQuad, writeRequestBlock, bw_active, eth_send_isIdle,  // 31:28
                         eth_recv_isIdle, ethUDPError, 1'b0, ethIPv4Error,                 // 27:24
                         sendBusy, sendRequest, eth_send_fw_ack, eth_send_fw_req,                // 23:20
                         2'd0, isLocal, isRemote,                                                // 19:16
                         FireWirePacketFresh, isForward, sendARP, isUDP,                         // 15:12
                         isICMP, isEcho, is_IPv4_Long, is_IPv4_Short,                            // 11:8
                         fw_bus_reset, 3'd0,                                                     //  7:4
                         4'd0 };                                                                 //  3:0
assign DebugData[3]  = { node_id, maxCountFW, LengthFW };                  // 6, 10, 16
assign DebugData[4]  = { fw_ctrl, host_fw_addr };                          // 16, 16
assign DebugData[5]  = { sendState, txPktWords, nextSendState, 12'd0 };    // 4, 12, 4, 12 (rxPktWords)
assign DebugData[6]  = { 6'd0, numUDP, 6'd0, numIPv4 };                    // 6, 10, 6, 10
assign DebugData[7]  = { 8'd0, numICMP, fw_bus_gen, numARP };              // 8, 8, 8, 8
assign DebugData[8]  = { 7'd0, bw_left, bw_err, 4'd0, bwState, numPacketError };   // 7, 9, 1, 4, 3, 8
assign DebugData[9]  = { 7'd0, fw_left, fw_err, 7'd0, fw_wait_cnt };
assign DebugData[10] = 32'd0;
assign DebugData[11] = 32'd0;
assign DebugData[12] = 32'd0;
assign DebugData[13] = 32'd0;
assign DebugData[14] = 32'd0;
assign DebugData[15] = 32'd0;
`endif

// Firewire packets received from host:
//    - 16 bytes (4 quadlets) for quadlet read request
//    - 20 bytes (5 quadlets) for quadlet write or block read request
//    - (24+block_data_length) bytes for block write
//      - real-time block_data_length = 4*5 = 20 bytes for QLA (Rev 7+)
//                                    = 4*9 = 36 bytes for DQLA
//                                    = 4*11 = 44 bytes for DRAC
//        max size in quadlets is (24+44)/4 = 17
//      - real-time broadcast write = 16*(4*5) = 320 bytes (Rev 7+)
//        max size in quadlets is (24+320)/4 = 86
//      - PROM write block_data_length can be up to 260 bytes
//        max size in quadlets is (24+260)/4 = 71
//      - QLA PROM write block_data_length can be up to 16*4 = 64 bytes
//        max size in quadlets is (24+64)/4 = 22
// To summarize, maximum receive size in quadlets is 86.
// Note that the broadcast block read (HUB) response is larger than this,
// but is not received from the host (only sent to the host):
//      - HUB block_data_length = 16*(4+4*6+1) = 16*29 = 464 quadlets,
//        assuming no more than 16 boards
// Anyway, since the FPGA contains abundant RAM primitives, we allocate
// 512 quadlets (see below).

wire[8:0]  mem_raddr;
wire[31:0] mem_rdata;
reg[8:0] local_raddr;
reg      icmp_read_en;    // 1 -> ICMP needs to read from memory

assign mem_raddr = bw_active     ? local_raddr :
                   icmp_read_en  ? sfw_count[9:1]
                                 : {2'd0, reg_raddr_in[6:0]};
reg[31:0] FireWireQuadlet;   // the current quadlet being read

reg mem_wen;   // memory write enable

// packet memories: these store the received Ethernet packet. There currently are two memories to support
// simultaneous access:
//   fw_packet:  read by the Firewire module for packets that need to be forwarded
//   bw_packet:  primarily used for local block writes, but is also used for ICMP response and is
//               available for reading (for debugging)
// These are 512 quadlets (512 x 32), which is the maximum possible Firewire packet size at 400 Mbits/sec
// (actually, could add a few quadlets because the 512 limit does not include header and CRC).
// The block write process is already set up to run in parallel with packet reception (see writeRequestTrigger).
// This is not yet implemented for forwarding to Firewire (would be necessary to set eth_send_fw_req earlier).
hub_mem_gen fw_packet(.clka(sysclk),
                      .wea(mem_wen),
                      .addra(rfw_count[9:1]),
                      .dina(FireWireQuadlet),
                      .clkb(sysclk),
                      .addrb(eth_fwpkt_raddr),
                      .doutb(eth_fwpkt_rdata)
                     );

hub_mem_gen bw_packet(.clka(sysclk),
                      .wea(mem_wen),
                      .addra(rfw_count[9:1]),
                      .dina(FireWireQuadlet),
                      .clkb(sysclk),
                      .addrb(mem_raddr),
                      .doutb(mem_rdata)
                     );

reg FireWirePacketFresh;   // 1 -> FireWirePacket data is valid (fresh)

// Following data is accessible via block read from address `ADDR_ETH (0x4000),
// where 'x' specifies the port number.
//   FPGA V2 (1 Ethernet port):  Set x=0
//   FPGA V3 (2 Ethernet ports): Set x=1 or 2
// Note that some data is provided by this module (EthernetIO) whereas other
// data is provided by the low-level interface (KSZ8851 for FPGA V2, or RTL8211F
// for FPGA V3).
//    4x00 - 4x7f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4x80 - 4x8f (16 quadlets) EthernetIO DebugData
//    4x90 - 4x9f (16 quadlets) Lower-level module debug data
//    4xa0 - 4xbf (32 quadlets) Used by lower-level module
//    4xc0 - 4xcf (16 quadlets) PacketBuffer (32 words)
//    4xd0 - 4xdf (16 quadlets) ReplyBuffer (32 words)
//    4xe0 - 4xff (32 quadlets) ReplyIndex (64 words)
// Note that full address decoding is not done, so other addresses will work too
// (for example, 4f80-4f9f will also give Debug data).
// TODO: This will need to be changed to properly decode the port number.
always @(*)
begin
   if (reg_raddr_in[7] == 0) begin               // 4x00-4x7f
      reg_rdata_out = mem_rdata;
   end
   else if (reg_raddr_in[6:4] == 3'b000) begin   // 4x80-4x8f
`ifdef HAS_DEBUG_DATA
         reg_rdata_out = DebugData[reg_raddr_in[3:0]];
`else
         reg_rdata_out = "0GBD";
`endif
   end
   else if (reg_raddr_in[6:4] == 3'b100) begin   // 4xc0-4xcf
         reg_rdata_out = {PacketBuffer[{reg_raddr_in[3:0],1'b1}], PacketBuffer[{reg_raddr_in[3:0],1'b0}]};
   end
   else if (reg_raddr_in[6:4] == 3'b101) begin   // 4xd0-4xdf
         reg_rdata_out = {ReplyBuffer[{reg_raddr_in[2:0],1'b1}],  ReplyBuffer[{reg_raddr_in[2:0],1'b0}]};
   end
   else if (reg_raddr_in[6:5] == 2'b11) begin    // 4xe0-4xff
         reg_rdata_out = {10'd0, ReplyIndex[{reg_raddr_in[4:0],1'b1}], 10'd0, ReplyIndex[{reg_raddr_in[4:0],1'b0}]};
   end
   else begin
         reg_rdata_out = 32'd0;
   end
end

// Data from Firewire packet header
// Quadlet 0
reg[9:0] dest_bus_id;         // FireWire destination bus (first 10 bits)
reg[5:0] dest_node_id;        // FireWire destination node (last 6 bits)
reg[5:0] fw_tl;               // FireWire transaction label
reg[3:0] fw_tcode;            // FireWire transaction code
reg[3:0] fw_pri;              // FireWire priority field
// Quadlet 1
reg[15:0] fw_src_id;          // FireWire source id
// Quadlet 2
reg[15:0] fw_dest_offset;     // FireWire destination offset (only lowest 16 bits used)
// Quadlet 3
reg[15:0] block_data_length;  // Data length (in bytes) for block read/write requests

reg[31:0] fw_quadlet_data;    // Quadlet data to write

wire isFwBroadcast = (dest_node_id == 6'h3f) ? 1'd1 : 1'd0;

// Local write if addresses this board or FireWire broadcast.
// Note that the host PC uses the Firewire PRI field to indicate whether the packet should be forwarded.
assign isLocal = (dest_node_id == node_id) || isFwBroadcast;

// Remote write if not addressing this board (note that this check includes Firewire broadcast)
// and if noForwardFlag is false.
// Also, note that some packets (e.g., Firewire broadcast) may set both isLocal and isRemote.
assign isRemote = (dest_node_id != node_id) && (!noForwardFlag);

assign quadRead = (fw_tcode == `TC_QREAD) ? 1'd1 : 1'd0;
assign quadWrite = (fw_tcode == `TC_QWRITE) ? 1'd1 : 1'd0;
assign blockRead = (fw_tcode == `TC_BREAD) ? 1'd1 : 1'd0;
assign blockWrite = (fw_tcode == `TC_BWRITE) ? 1'd1 : 1'd0;

assign addrMain = (fw_dest_offset[15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;

// Following signal indicates whether real-time block read
assign blk_rt_rd = addrMain & blockRead & req_read_bus;

wire timestamp_rd;
assign timestamp_rd = (blk_rt_rd && (reg_raddr[7:0] == 8'd0)) ? 1'd1 : 1'd0;

assign isRebootCmd = (addrMain && (fw_dest_offset[11:0] == 12'd0) && quadWrite
                      && (fw_quadlet_data[21:20] == 2'b11)) ? 1'd1 : 1'd0;

// For reading the timestamp
reg[31:0] timestamp_latched;
reg[31:0] timestamp_prev;

//*****************************************************************
//  Write to Ethernet control register
//*****************************************************************

always @(posedge sysclk)
begin
   if (ctrl_reg_wen) begin
      clearErrors <= reg_wdata_in[29];
   end
   else begin
      clearErrors <= 0;
   end
end

//*****************************************************************
//  ETHERNET Receive state machine
//*****************************************************************

localparam[2:0]
    ST_RECEIVE_DMA_IDLE = 3'd0,
    ST_RECEIVE_DMA_ETHERNET_HEADERS = 3'd1,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 3'd2,
    ST_RECEIVE_DMA_ICMP_DATA = 3'd3,
    ST_RECEIVE_DMA_WAIT = 3'd4,
    ST_RECEIVE_DMA_REBOOT = 3'd5;

reg[2:0] recvState = ST_RECEIVE_DMA_IDLE;
reg[2:0] nextRecvState = ST_RECEIVE_DMA_IDLE;

// recvReady (aka dataReady) -->  dataValid  -->  recvTransition
reg dataValid;          // Data has been stored in PacketBuffer
reg recvTransition;     // Transition to next state

reg[5:0] recvCnt;       // Index into PacketBuffer
reg[9:0] rfw_count;     // Counts words in FireWire packets (max is 1024 words, or 2048 bytes)
reg[5:0] rebootCnt;     // Counter used to delay reboot command (could reuse recvCnt)

// Registers for processing of the real-time block write, which consists of one or more
// groups of 5 quadlets, where the first 4 quadlets are DAC values and the 5th quadlet is
// for power control. For the sequential write protocol, the block should only contain one
// group of 5 quadlets, whereas for the broadcast write protocol, it will contain a group
// of 5 quadlets for each board, where the targeted board ID is encoded in bits 27:24.
reg doRtBlock;         // Indicates that we are processing a real-time block write
reg dac_local;         // Indicates that DAC entries in block write are for this board_id
reg[7:0] RtCnt;        // Counter for real-time block quadlets
reg[7:0] RtLen;        // Number of quadlets in the RT write block being processed

assign responseRequired = ((FireWirePacketFresh && (quadRead || blockRead) && (isLocal || sendExtra))
                          || sendARP || isEcho) ? 1'b1 : 1'b0;

always @(posedge sysclk)
begin

   dataValid <= recvReady;           // 1 clock after recvReady
   recvTransition <= dataValid;      // 1 clock after dataValid

   if (writeRequestQuad && eth_write_en) begin
      writeRequestQuad <= 1'd0;
   end

   if (writeRequestBlock && eth_write_en) begin
      writeRequestBlock <= 1'd0;
   end

   if (eth_send_fw_ack) begin
      eth_send_fw_req <= 0;
   end

   if (resetActive|clearErrors) begin
      numPacketError <= 8'd0;
      ethFrameError <= 0;
      ethIPv4Error <= 0;
      ethUDPError <= 0;
      ethDestError <= 0;
   end

   // Write to IP address register
   if (ip_reg_wen) begin
      // Following is equivalent to: ip_address <= reg_wdata_in;
      ReplyBuffer[ID_Rep_IPv4_Address0] <= {reg_wdata_in[7:0], reg_wdata_in[15:8] };
      ReplyBuffer[ID_Rep_IPv4_Address1] <= {reg_wdata_in[23:16], reg_wdata_in[31:24] };
   end

   if (recvTransition) begin
      recvState <= nextRecvState;
   end

   case (recvState)

   ST_RECEIVE_DMA_IDLE:
   begin
      mem_wen <= 0;
      doRtBlock <= 0;
      req_blk_rt_rd <= 1'b0;
      rfw_count <= 10'd0;
      bwStart <= 9'd0;
      bwLen <= 9'h1ff;      // Large value to avoid spurious writeRequestTrigger
      recvCnt <= 6'd0;
      nextRecvState <= ST_RECEIVE_DMA_IDLE;
      recvBusy <= 0;
      writeRequestQuad <= 1'b0;
      writeRequestBlock <= 1'b0;
      eth_req_write_reg <= 1'b0;
      eth_send_fw_req <= 0;

      if (resetActive|clearErrors) begin
         FireWirePacketFresh <= 0;
         fwPacketDropped <= 0;
         ethRecvStateError <= 0;
      end

      if (recvRequest) begin
         recvBusy <= 1;
         FireWirePacketFresh <= 0;
         fwPacketDropped <= 0;
         recvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
      end
   end

   ST_RECEIVE_DMA_ETHERNET_HEADERS:
   begin
      if (recvReady) PacketBuffer[recvCnt] <= recv_word;  // `SDSwapped for KSZ8851

      if (dataValid) begin
         if ((recvCnt == ID_Frame_End) && !(isRaw|isIPv4|isARP)) begin
            ethFrameError <= 1'd1;
            numPacketError <= numPacketError + 8'd1;
            nextRecvState <= ST_RECEIVE_DMA_IDLE;
         end
         else if ((recvCnt == ID_ARP_End) && isARP) begin
            // Update IP address in response to valid ARP packet.
            // Note: this feature (setting IP address based on ARP packet received) will
            //       be removed in the future, since it is better to set the IP address
            //       by a broadcast write to register `REG_IPADDR (11).
            if (isARPValid && is_ip_unassigned) begin
               // If our IP address not yet set, update it
               ReplyBuffer[ID_Rep_IPv4_Address0] <= PacketBuffer[ID_ARP_fpgaIP0];
               ReplyBuffer[ID_Rep_IPv4_Address1] <= PacketBuffer[ID_ARP_fpgaIP1];
            end
            nextRecvState <= ST_RECEIVE_DMA_IDLE;
         end
         else if ((recvCnt == ID_IPv4_End) && isIPv4) begin
            if ((IPv4_Version != 4'h4) || !(isUDP|isICMP)) begin
               ethIPv4Error <= 1'd1;
               numPacketError <= numPacketError + 8'd1;
               nextRecvState <= ST_RECEIVE_DMA_IDLE;
            end
            else begin
               if (is_ip_unassigned && (IPv4_fpgaIP[31:24] != 8'hff)) begin
                  // This case can occur when the host PC already has an ARP
                  // cache entry for this board, in which case we just assign
                  //  the IP address, as long as it is not a broadcast address
                  //  (we only check whether the last byte is 255).
                  ReplyBuffer[ID_Rep_IPv4_Address0] <= PacketBuffer[ID_IPv4_destIP0];
                  ReplyBuffer[ID_Rep_IPv4_Address1] <= PacketBuffer[ID_IPv4_destIP1];
               end
               nextRecvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
            end
         end
         else if ((recvCnt == ID_UDP_End) && isUDP) begin
            if (!isPortValid) begin
               ethUDPError <= 1'd1;
               numPacketError <= numPacketError + 8'd1;
               nextRecvState <= ST_RECEIVE_DMA_IDLE;
            end
            else begin
               // Save the UDP host port because UDP_hostPort may get overwritten if an ARP packet is received, which
               // would be a problem if the ARP packet is followed by a request to forward a packet from FireWire via UDP.
               // This may not be necessary if ARP and UDP packets were not allowed to overlap in PacketBuffer,
               // but that would require a much larger PacketBuffer. Also, even separating ARP and UDP in PacketBuffer
               // would not handle the (unlikely) case where an invalid UDP packet is received prior to the request to
               // forward a packet from FireWire.
               ReplyBuffer[ID_Rep_UDP_hostPort] <= PacketBuffer[ID_UDP_hostPort];
               nextRecvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
            end
         end
         else if ((recvCnt == ID_FwCtrl) && (isUDP||isRaw)) begin
            nextRecvState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
         end
         else if ((recvCnt == ID_ICMP_End) && isICMP) begin
            nextRecvState <= ST_RECEIVE_DMA_ICMP_DATA;
         end
         else begin
            nextRecvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
         end
      end

      if (recvTransition) begin
         recvCnt <= ((recvCnt == ID_Frame_End) && isARP) ? ID_ARP_Begin :
                    ((recvCnt == ID_Frame_End) && isRaw) ? ID_FwCtrl :
                    recvCnt + 6'd1;
      end
   end

   ST_RECEIVE_DMA_ICMP_DATA:
   begin
      if (recvTransition) rfw_count <= rfw_count + 10'd1;
      // rfw_count is in words, icmp_data_length is in bytes
      if (rfw_count[9:0] == icmp_data_length[10:1])
         nextRecvState <= ST_RECEIVE_DMA_IDLE;   // was ST_RECEIVE_DMA_FRAME_CRC;
      else
         nextRecvState <= ST_RECEIVE_DMA_ICMP_DATA;
      // For now, read ICMP data into FireWirePacket memory (fw_packet). If memory resources available,
      // it would be cleaner to instantiate a separate 16-bit memory.
      if (recvReady) begin
         if (rfw_count[0] == 0)
            FireWireQuadlet[31:16] <= recv_word;
         else
            FireWireQuadlet[15:0] <= recv_word;
      end
      // Data is actually valid longer, but this is sufficient
      mem_wen <= (rfw_count[0]&dataValid) ? 1'b1 : 1'b0;
   end

   // Read Firewire header; also handles quadlet read/write
   ST_RECEIVE_DMA_FIREWIRE_PACKET:
   begin
      if (recvTransition) rfw_count <= rfw_count + 10'd1;

      // Read FireWire packet, byteswap to make it easier to work with.
      // Also save parts of first 4 quadlets for later use.
      if (recvReady) begin
         if (rfw_count[0] == 0) begin
            FireWireQuadlet[31:16] <= recv_word;
            if (rfw_count[9:1] == 9'd0)
               {dest_bus_id, dest_node_id} <= recv_word;
            else if (rfw_count[9:1] == 9'd1)
               fw_src_id <= recv_word;
            else if (rfw_count[9:1] == 9'd3)
               block_data_length <= recv_word;
         end
         else begin
            FireWireQuadlet[15:0] <= recv_word;
            if (rfw_count[9:1] == 9'd0)
               {fw_tl, fw_tcode, fw_pri} <= {recv_word[15:10], recv_word[7:0]};
            else if (rfw_count[9:1] == 9'd2)
               fw_dest_offset <= recv_word;  // only using 16 lowest bits
         end
      end

      // Data is actually valid longer, but this is sufficient
      mem_wen <= (rfw_count[0]&dataValid) ? 1'b1 : 1'b0;

      if (dataValid) begin
         if ((rfw_count == 10'd0) && (dest_bus_id != 10'h3FF)) begin
            // Invalid destination address (first 10 bits are not FFC), flush packet
            ethDestError <= 1;
            nextRecvState <= ST_RECEIVE_DMA_IDLE;
         end
         else if (rfw_count == 10'd5) begin
            FireWirePacketFresh <= 1;
            useUDP <= isUDP;
            if (fw_bus_reset || ((host_fw_bus_gen != fw_bus_gen) && ~isFwBroadcast)) begin
               // if Firewire bus is in reset OR (bus generation does not match AND not a broadcast
               // packet), then flush packet. Note that we do not check if the bus goes into reset
               // or the generation changes while we are processing the packet.
               fwPacketDropped <= 1;
               nextRecvState <= ST_RECEIVE_DMA_IDLE;
            end
         end
         else if ((rfw_count == 10'd7) && quadWrite) begin
            fw_quadlet_data <= FireWireQuadlet;
            // Set writeRequestQuad for local quadlet write, if not also remote (i.e., not broadcast).
            // For broadcast quadlet write, we first forward to Firewire, then set writeRequestQuad
            // when we receive the ack (eth_send_fw_ack).
            // The only case where this is necessary is for the broadcast query command, but we do
            // it consistently for all broadcast quadlet writes.
            // It is necessary for the broadcast query command to make sure that all boards are ready for
            // the sequential update of Hub memory (especially if this board is the lowest numbered board)
            writeRequestQuad <= isLocal&(~isRemote);
         end
         else if ((rfw_count == 10'd9) && blockWrite) begin
            if (addrMain) begin
               doRtBlock <= isLocal;
               RtCnt <= 8'd0;
               // bwStart and bwLen will be set later, since just a subset of the data
               // will be sent for a broadcast block write.
            end
            else begin
               bwStart <= 9'd5;
               bwLen <= block_data_length[10:2];
            end
         end
         else if (rfw_count == maxCountFW) begin
            nextRecvState <= ST_RECEIVE_DMA_WAIT;  // was ST_RECEIVE_DMA_FRAME_CRC;
            doRtBlock <= 0;
            if (isLocal) begin
               // Latch timestamp if a block read from ADDR_MAIN or a broadcast read request
               // (quadlet write to ADDR_HUB).
               if ((addrMain && blockRead) || ((fw_dest_offset == {`ADDR_HUB, 12'h800 }) && quadWrite)) begin
                  // TODO: Subtracting 1 for backward compatibility; may eliminate that for Firmware Rev 9
                  timestamp_latched <= (timestamp-timestamp_prev)-32'd1;
                  timestamp_prev <= timestamp;
                  req_blk_rt_rd <= 1'b1;
               end
               if (blockWrite) begin
                  // writeRequestBlock should have been set earlier (using writeRequestTrigger) for all
                  // local block writes (even broadcast). We expect write to still be active.
                  bw_err <= ~eth_write_en;
                  // Number of quadlets left to write to registers; should be greater than 1,
                  // otherwise the register writer may have overtaken the Ethernet reader.
                  bw_left <= bwEnd - local_raddr;
               end
            end
            if (isRemote) begin
               // Request to forward should already have been set (using fwRequestTrigger).
               // We expect that it would still be active.
               fw_err <= ~eth_send_fw_ack;
               // Number of quadlets left to write to registers; should be greater than 1,
               // otherwise the Firewire writer may have overtaken the Ethernet reader.
               fw_left <= eth_fwpkt_len[10:2] - eth_fwpkt_raddr;
            end
         end
         else begin
            nextRecvState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
         end

         if (rfw_count == writeRequestTrigger) begin
            writeRequestBlock <= blockWrite&isLocal;
            eth_req_write_reg <= blockWrite&isLocal;
         end
         if ((rfw_count == fwRequestTrigger) && isRemote) begin
            eth_send_fw_req <= 1'b1;
            fw_wait_cnt <= 8'd0;
            host_fw_addr <= fw_src_id;
         end

         if (doRtBlock&rfw_count[0]) begin
            // Real-time block write.
            // Starting with Rev 8, the first entry is a header that specifies which
            // board is being addressed. If this is a sequential block write, it
            // addresses this board and we rely on the host PC to send a Rev 8 packet.
            // Similarly, if a broadcast write (to multiple boards), we can assume
            // that the host PC will only use broadcast write if all boards are Rev 8+.
            // The header will also specify the number of motors being addressed
            // (4 for QLA and 10 for dRAC). The last quadlet is for power control.
            // The protocol uses 8 bits for the length (RtLen), even though currently
            // the largest block write is 12 quadlets (for dRAC).
            if ((RtCnt == 8'h0) || (RtCnt == RtLen)) begin
               RtLen <= FireWireQuadlet[7:0];
               RtCnt <= 8'h1;
               dac_local <= (FireWireQuadlet[11:8] == board_id) ? 1'b1 : 1'b0;
            end
            else begin
               RtCnt <= RtCnt + 8'd1;
               if (dac_local && (RtCnt == 8'h1)) begin
                   bwStart <= rfw_count[9:1];        // Start offset for block write
                   bwLen <= { 1'd0, (RtLen-8'd1)};   // Length for block write (-1 for header)
               end
            end
         end
      end
   end

   ST_RECEIVE_DMA_WAIT:
   begin
      if (eth_send_fw_req | eth_send_fw_ack) begin
         // Waiting for Ethernet forward to finish
         fw_wait_cnt <= fw_wait_cnt + 8'd1;
      end
      else begin
`ifdef HAS_DEBUG_DATA
         // Increment counters
         numIPv4 <= numIPv4 + {9'd0, isIPv4};
         numARP <= numARP + {7'd0, isARP};
         numICMP <= numICMP + {7'd0, isICMP};
         numUDP <= numUDP + {9'd0, isUDP};
`endif
         if (isRebootCmd&isRemote&isLocal) begin
            // Special case handling of broadcast reboot
            rebootCnt <= 6'd1;
            recvState <= ST_RECEIVE_DMA_REBOOT;
         end
         else begin
            // If any other broadcast quadlet write (local and remote),
            // write it to the hardware now.
            eth_req_write_reg <= quadWrite&isLocal;
            writeRequestQuad <= quadWrite&isLocal;
            recvState <= ST_RECEIVE_DMA_IDLE;
         end
      end
   end

   ST_RECEIVE_DMA_REBOOT:
   begin
      // Wait an additional 1.3 us after eth_send_fw_ack removed to
      // make sure Firewire packet has been transmitted
      rebootCnt <= rebootCnt + 6'd1;
      if (rebootCnt == 6'h3f) begin
         eth_req_write_reg <= 1'b1;
         writeRequestQuad <= 1'b1;
         recvState <= ST_RECEIVE_DMA_IDLE;
      end
   end

   default:
   begin
      ethRecvStateError <= 1;
      recvState <= ST_RECEIVE_DMA_IDLE;
      nextRecvState <= ST_RECEIVE_DMA_IDLE;
   end

   endcase // case (recvState)
end


//*****************************************************************
//  ETHERNET Send DMA state machine
//*****************************************************************

localparam[3:0]
    ST_SEND_DMA_IDLE = 4'd0,
    ST_SEND_DMA_ETHERNET_HEADERS = 4'd3,
    ST_SEND_DMA_PACKETDATA_HEADER = 4'd4,
    ST_SEND_DMA_PACKETDATA_QUAD = 4'd5,
    ST_SEND_DMA_PACKETDATA_BLOCK = 4'd6,
    ST_SEND_DMA_PACKETDATA_CHECKSUM = 4'd7,
    ST_SEND_DMA_FWD = 4'd8,
    ST_SEND_DMA_ICMP_DATA = 4'd9,
    ST_SEND_DMA_EXTRA = 4'd10,
    ST_SEND_DMA_FINISH = 4'd11;

reg[3:0] sendState = ST_SEND_DMA_IDLE;
reg[3:0] nextSendState = ST_SEND_DMA_IDLE;

reg sendTransition;

reg[9:0] sfw_count;     // Counts words in FireWire packets (max is 1024 words, or 2048 bytes)
reg[1:0] xcnt;          // Counts words in extra packet

// Following needed by KSZ8851
// (block_data_length must be a multiple of 4)
assign responseByteCount =
       (isForward && !useUDP) ? (`ETH_FRAME_SIZE + `FW_EXTRA_SIZE + sendLen) :       // Forwarding raw data from FireWire
       (isForward && useUDP) ? (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE + sendLen) :  // Forwarding UDP data from FireWire
       sendARP ? (16'd42) :                                                          // ARP response: 14 + 28
       isEcho ? (16'd14 + IPv4_Length) :                                             // Echo (ICMP) response: 14 + IPv4_Length
       useUDP ? sendExtra ? (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE) :               // UDP
                 quadRead ? (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE + `FW_QRESP_SIZE) :
                            (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE + `FW_BRESP_SIZE) + block_data_length :
       sendExtra ? (`ETH_FRAME_SIZE + `FW_EXTRA_SIZE) :                              // Local raw packet
       quadRead ? (`ETH_FRAME_SIZE + `FW_QRESP_SIZE + `FW_EXTRA_SIZE) :
                  (`ETH_FRAME_SIZE + `FW_BRESP_SIZE + `FW_EXTRA_SIZE) + block_data_length;

always @(posedge sysclk)
begin

   // sendTransition is 1 clock after sendReady
   sendTransition <= sendReady;

   if (sendTransition) begin
      sendState <= nextSendState;
      txPktWords <= txPktWords + 12'd1;
   end

   if (resetActive|clearErrors) begin
      ethSendStateError <= 0;
   end

   case (sendState)

   ST_SEND_DMA_IDLE:
   begin
      sendBusy <= 0;
      req_read_bus <= 0;
      icmp_read_en <= 0;
      txPktWords <= 12'd0;
      sfw_count <= 10'd0;
      xcnt <= 2'd0;
      if (sendRequest) begin
         sendBusy <= 1;
         ReplyBuffer[ID_Rep_fpgaMac2][3:0] <= board_id;
         if (isForward) begin
            if (!useUDP) begin
               // Forwarding raw data from FireWire
               ReplyBuffer[ID_Rep_Frame_Length] <= sendLen + `FW_EXTRA_SIZE;
            end
            else begin
               // Forwarding data from FireWire
               ReplyBuffer[ID_Rep_Frame_Length] <= 16'h0800; // IPv4 EtherType
               ReplyBuffer[ID_Rep_IPv4_Length] <= `IPv4_UDP_EXTRA_SIZE + sendLen;
               ReplyBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd17;  // UDP protocol
               ReplyBuffer[ID_Rep_UDP_Length] <= `UDP_EXTRA_SIZE + sendLen;
            end
         end
         else if (sendARP) begin
            ReplyBuffer[ID_Rep_Frame_Length] <= 16'h0806; // ARP EtherType
         end
         else if (isEcho) begin
            // Echo (ICMP) response
            ReplyBuffer[ID_Rep_Frame_Length] <= 16'h0800;   // IPv4 EtherType
            ReplyBuffer[ID_Rep_IPv4_Length] <= IPv4_Length; // Same length as request
            ReplyBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd1;     // ICMP protocol
         end
         else if ((FireWirePacketFresh && (quadRead || blockRead) && (isLocal || sendExtra))) begin
            if (useUDP) begin
               ReplyBuffer[ID_Rep_Frame_Length] <= 16'h0800; // IPv4 EtherType (UDP or ICMP)
               ReplyBuffer[ID_Rep_IPv4_Length] <= sendExtra ? `IPv4_UDP_EXTRA_SIZE :
                                                   quadRead ? (`IPv4_UDP_EXTRA_SIZE + `FW_QRESP_SIZE)
                                                            : (`IPv4_UDP_EXTRA_SIZE + `FW_BRESP_SIZE) + block_data_length;
               ReplyBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd17;  // UDP protocol
               ReplyBuffer[ID_Rep_UDP_Length] <= sendExtra ? `UDP_EXTRA_SIZE :
                                                  quadRead ? (`UDP_EXTRA_SIZE + `FW_QRESP_SIZE)
                                                           : (`UDP_EXTRA_SIZE + `FW_BRESP_SIZE) + block_data_length;
            end
            else begin
               // Local raw packet
               ReplyBuffer[ID_Rep_Frame_Length] <= sendExtra ? `FW_EXTRA_SIZE :
                                                    quadRead ? (`FW_QRESP_SIZE + `FW_EXTRA_SIZE)
                                                             : (`FW_BRESP_SIZE + `FW_EXTRA_SIZE) + block_data_length;
            end
         end
         sendState <= ST_SEND_DMA_ETHERNET_HEADERS;
         nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
         replyCnt <= Frame_Reply_Begin;
      end
   end

   ST_SEND_DMA_ETHERNET_HEADERS:
   begin
      ReplyBuffer[ID_Rep_IPv4_Csum] <= Rep_IPv4_Csum16;
      if (sendTransition) replyCnt <= replyCnt + 6'd1;
      `send_word_swapped <= (ReplyIndex[replyCnt][5]==isPacket) ?
                             PacketBuffer[ReplyIndex[replyCnt][4:0]] :
                             ReplyBuffer[ReplyIndex[replyCnt][3:0]];
      if (replyCnt == Frame_Reply_End) begin
         if (isForward && !useUDP) begin
            nextSendState <= ST_SEND_DMA_FWD;
            sendAck <= 1;
            sendAddr <= 9'd0;
         end
         else if (sendARP && !isForward) begin
            if (sendTransition) replyCnt <= ARP_Reply_Begin;
            //nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
         end
         else if (!(isUDP || isEcho || isForward)) begin
            // Raw packet
            nextSendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
         end
         //else begin
         //   nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
         //end
      end
      else if (replyCnt == IPv4_Reply_End) begin
         if (sendTransition) replyCnt <= isEcho ? ICMP_Reply_Begin : UDP_Reply_Begin;
         //nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
      end
      else if (replyCnt == UDP_Reply_End) begin
         if (isForward) begin
            nextSendState <= ST_SEND_DMA_FWD;
            sendAck <= 1;
            sendAddr <= 9'd0;
         end
         else begin
            nextSendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
         end
      end
      else if (replyCnt == ARP_Reply_End) begin
         nextSendState <= ST_SEND_DMA_FINISH;
      end
      else if (replyCnt == ICMP_Reply_End) begin
         nextSendState <= ST_SEND_DMA_ICMP_DATA;
         icmp_read_en <= 1;
      end
      //else begin
      //   nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
      //end
   end

   ST_SEND_DMA_ICMP_DATA:
   begin
      `send_word_swapped <= (sfw_count[0] == 0) ? mem_rdata[31:16]
                                              : mem_rdata[15:0];
      // Increment a little earlier due to reading from memory
      if (sendReady) sfw_count <= sfw_count + 10'd1;
      // sfw_count is in words, icmp_data_length is in bytes
      if (sfw_count[9:0] == icmp_data_length[10:1])
         nextSendState <= ST_SEND_DMA_FINISH;
      //else
      //   nextSendState <= ST_SEND_DMA_ICMP_DATA;
   end

   // Send first 6 words (3 quadlets), which are nearly identical between quadlet read response
   // and block read response (only difference is tcode).
   // For block read response, send an additional 4 words (2 quadlets), which are block data length
   // and header CRC.
   ST_SEND_DMA_PACKETDATA_HEADER:
   begin
      send_word <= Firewire_Header_Reply[sfw_count[3:0]];
      req_read_bus <= quadRead | blockRead;         // Request access to read bus
      if ((sfw_count[3:0] == 4'd5) && quadRead) begin
         reg_raddr <= fw_dest_offset;
         // Get ready to read data from the board.
         if (sendTransition) sfw_count <= 10'd0;
         nextSendState <= ST_SEND_DMA_PACKETDATA_QUAD;
      end
      else if (sfw_count[3:0] == 4'd9) begin  // block read
         if (blockRead) begin
            reg_raddr <= fw_dest_offset;
            if (sendTransition) sfw_count <= 10'd0;
            nextSendState <= ST_SEND_DMA_PACKETDATA_BLOCK;
         end
         else  // Should not happen
            nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
      end
      else begin
         // stay in this state
         if (sendTransition) sfw_count <= sfw_count + 10'd1;
         //nextSendState <= ST_SEND_DMA_PACKETDATA_HEADER;
      end
   end

   ST_SEND_DMA_PACKETDATA_QUAD:
   begin
      if (grant_read_bus&reg_rvalid) begin
         if (sfw_count[0] == 0) begin
            `send_word_swapped <= reg_rdata[31:16];
            if (sendTransition) sfw_count[0] <= 1;
         end
         else begin
            `send_word_swapped <= reg_rdata[15:0];
            if (sendTransition) sfw_count[0] <= 0;
            nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
         end
      end
      else begin
         // Can note that read was interrupted/delayed
      end
   end

   ST_SEND_DMA_PACKETDATA_BLOCK:
   begin
      if ((sfw_count[0] == 1) && sendReady) begin
         // 12-bit address increment, even though Firewire limited to 512 quadlets (9 bits)
         // because this way we can support non-zero starting addresses.
         // We have to increment reg_raddr during sendReady so that it works
         // correctly when reading from memory -- otherwise, the upper word (even sfw_count
         // case below) will not yet be retrieved from the memory.
         reg_raddr[11:0] <= reg_raddr[11:0] + 12'd1;
      end
      // TODO
      // if (grant_read_bus&reg_rvalid) begin
      if (grant_read_bus) begin
         if (sendTransition) sfw_count <= sfw_count + 10'd1;
         if (sfw_count[0] == 0) begin   // even count (upper word)
            // Since we are not incrementing reg_raddr, writing to SDReg does not need
            // to be conditioned on ~sendTransition, as in the odd sfw_count case above.
            `send_word_swapped <= timestamp_rd ? timestamp_latched[31:16] : reg_rdata[31:16];
         end
         else begin   // odd count (lower word)
            // For general block read (not real-time block read) cannot write to SDReg during
            //  sendTransition so that the code works for both register reads (no delay) and
            //  memory reads (1 clk delay).
            if (addrMain)                    // real-time block read
               `send_word_swapped <= timestamp_rd ? timestamp_latched[15:0] : reg_rdata[15:0];
            else if (~sendTransition)        // general block read
               `send_word_swapped <= reg_rdata[15:0];
            // sfw_count is in words and block_data_length is in bytes, but we compare in quadlets
            if ((sfw_count[9:1] + 8'd1) == block_data_length[10:2])
               nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
         end
      end
      else begin
         // Can note that read was interrupted/delayed
      end
   end

   ST_SEND_DMA_PACKETDATA_CHECKSUM:
   begin
      req_read_bus <= 0; // Relinquish control of read bus
      if (sendTransition) sfw_count[0] <= 1;
      send_word <= 16'd0;    // Checksum currently not set
      if (sfw_count[0] == 1)
         nextSendState <= ST_SEND_DMA_EXTRA;
      //else
      //   nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
   end

   ST_SEND_DMA_FWD:
   begin
      if (sendTransition) sfw_count <= sfw_count + 10'd1;
      `send_word_swapped <= (sfw_count[0] == 0) ? sendData[31:16] : sendData[15:0];
      // Increment a little earlier due to reading from memory
      if (sendReady && (sfw_count[0] == 1)) sendAddr <= sendAddr + 9'd1;
      // sfw_count is in words, sendLen is in bytes
      if (sfw_count == (sendLen[10:1]-10'd1))
         nextSendState <= ST_SEND_DMA_EXTRA;
      //else
      //   nextSendState <= ST_SEND_DMA_FWD;
   end

   ST_SEND_DMA_EXTRA:
   begin
      if (sendTransition) xcnt <= xcnt + 2'd1;
      `send_word_swapped <= ExtraData[xcnt];
      //nextSendState <= (xcnt == 2'd3) ? ST_SEND_DMA_FINISH : ST_SEND_DMA_EXTRA;
      if (xcnt == 2'd3)
         nextSendState <= ST_SEND_DMA_FINISH;
   end

   ST_SEND_DMA_FINISH:
   begin
      icmp_read_en <= 0;
      sendAck <= 0;
      sendBusy <= 0;
      sendState <= ST_SEND_DMA_IDLE;
      nextSendState <= ST_SEND_DMA_IDLE;
   end

   default:
   begin
      ethSendStateError <= 1;
      sendState <= ST_SEND_DMA_IDLE;
      nextSendState <= ST_SEND_DMA_IDLE;
   end

   endcase // case (sendState)
end

// Following handles writing to board registers via quadlet or block write.
//
// For the KSZ8851,
// the DMA receive process requires 5 sysclk for reading each word (16-bits)
// for a total of 10 sysclk (~200 nsec) per quadlet.
// Thus, quadlet N is available at t = 10*N*sysclk, relative to when the
// first quadlet (N=0) is stored in memory. Note that for a block write,
// the first 5 quadlets are the block write header, which do not get written
// to the registers.
//
// For the RTL8211F, the receive process uses 4 sysclk for reading each word,
// so data is available faster. It is ok (though not optimal) to use the
// KSZ8851 timing, so the IS_V3 parameter is used to improve the timing.
// In this case, quadlet N is available at t = 8*N*sysclk.
//
// The register block write process (below) is timed as follows:
//   4 sysclk (80 nsec) for blk_wstart at beginning
//   1 sysclk (20 nsec) for reg_wen for each quadlet
//   3 sysclk (60 nsec) gap after each quadlet
//   1 sysclk (20 nsec) for blk_wen at end
// Thus, it will start writing the Nth quadlet at
//    t = (4+(1+3)*N)*sysclk = 4(N+1)*sysclk
// relative to when writeRequestBlock is set.
//
// If we want to overlap reading and writing, we need to ensure that the
// reader stays ahead of the writer. We do this by setting the time when
// writeRequestBlock is set; specifically when quadlet M is being stored
// (see writeRequestTrigger).
//
// For KSZ8851:
//   10(N-M)*sysclk < 4(N+1)*sysclk
//   M > (3N-2)/5
//
//   This is not the most convenient computationally on an FPGA, so we choose
//   a more conservative bound.
//       3/5 == 1/2 + 1/10 (0.6), which is less than 1/2 + 1/8 - 1/64 = 0.609.
//   Thus, it is sufficient to choose M = N/2 + N/8 - N/64, which can be
//   implemented by shifting and adding/subtracting.
//
// For RTL8211F:
//   8(N-M)*sysclk < 4(N+1)*sysclk
//   M > (N-1)/2
//
//   Thus, it is sufficient to choose M = N/2, which can easily be implemented
//   in an FPGA (shift by 2).
//
// The reader actually works with words, rather than quadlets, and has to add the
// length of the block write header. In addition, we add 2 to provide some margin (and
// handle round-off), which leads to the equation above for setting writeRequestTrigger.
//
// Forwarding packets via Firewire has similar timing. The Firewire module requires
// 4 clocks per quadlet, whereas the KSZ8851 requires 10 clocks and the RTL8211F requires
// 8 clocks. Thus, we can start the Firewire transfer when we are M of the
// way through a packet of size N:
//   KSZ8851:  (N-M)*10 < N*4  --> 6*N < 10*M --> M > (3/5)*N
//   RTL8211F: (N-M)*8 < N*4   --> 4*N < 8*M  --> M > (1/2)*N
//
localparam[2:0]
   BW_IDLE = 0,
   BW_WSTART = 1,
   BW_WRITE = 2,
   BW_WRITE_GAP = 3,
   BW_BLK_WEN = 4;

reg[2:0] bwState = BW_IDLE;
reg[1:0] bwCnt;
reg bwAddrMain;        // 1 -> real-time block write

always @(posedge sysclk)
begin

   bwCnt <= (bwState == BW_IDLE)  ? 2'd0 :
            (bwState == BW_WRITE) ? 2'd1 :
                                    (bwCnt + 2'd1);

   case (bwState)

   BW_IDLE:
   begin
      if (writeRequestQuad) begin
         reg_waddr <= fw_dest_offset;
         reg_wdata <= fw_quadlet_data;
         // Special case: write to FireWire PHY register
         if (addrMain && (fw_dest_offset[11:0] == {8'h0, `REG_PHYCTRL})) begin
            // check the RW bit to determine access type (bit 12, after byte-swap)
            lreq_type <= (fw_quadlet_data[12] ? `LREQ_REG_WR : `LREQ_REG_RD);
            lreq_trig <= 1;
         end
         eth_write_en <= 1;
         reg_wen <= 1;
         blk_wen <= 1;
      end
      else if (writeRequestBlock) begin
         bw_active <= 1;
         eth_write_en <= 1;
         // Assert blk_wstart for 80 ns before starting local block write
         // (same timing as in Firewire module).
         blk_wstart <= 1;
         bwState <= BW_WSTART;
         local_raddr <= bwStart;
         bwAddrMain <= addrMain;
         if (addrMain) begin
             // real-time block write
             reg_waddr[15:0] <= { `ADDR_MAIN, 8'd0, `OFF_DAC_CTRL };
         end
         else begin
             // other block write
             reg_waddr[15:12] <= fw_dest_offset[15:12];
             reg_waddr[11:0] <= fw_dest_offset[11:0] - 12'd1;
         end
      end
      else begin
         bw_active <= 0;
         eth_write_en <= 0;
         reg_wen <= 0;    // Clean up from quadlet/block writes
         blk_wen <= 0;
         blk_wstart <= 0;
         lreq_trig <= 0;      // Clear lreq_trig in case it was set
      end
   end

   BW_WSTART:
   begin
      if (bwCnt == 2'd3) begin
         blk_wstart <= 0;
         bwState <= BW_WRITE;
      end
   end

   BW_WRITE:
   begin
      if (grant_write_bus) begin
         local_raddr <= local_raddr + 9'd1;
         if (bwAddrMain) begin
             if (local_raddr == (bwEnd - 9'd1)) begin
                 reg_waddr[7:0] <= { 4'd0, `REG_STATUS };  // Power control
                 reg_wdata <= {12'd0, mem_rdata[19:0] };
             end
             else begin
                 reg_waddr[7:4] <= reg_waddr[7:4] + 4'd1;  // DAC
                 reg_wdata <= mem_rdata;
             end
         end
         else begin
             reg_waddr[11:0] <= reg_waddr[11:0] + 12'd1;
             reg_wdata <= mem_rdata;
         end
         reg_wen <= 1;
         bwState <= BW_WRITE_GAP;
      end
   end

   BW_WRITE_GAP:
   begin
      // hold reg_wen low for 60 nsec (3 cycles)
      reg_wen <= 1'b0;
      if (bwCnt == 2'd3) begin
         if (local_raddr == bwEnd)
            bwState <= BW_BLK_WEN;
         else
            bwState <= BW_WRITE;
      end
   end

   BW_BLK_WEN:
   begin
      bw_active <= 0;   // Stop accessing memory
      // Wait 60 nsec before asserting blk_wen
      if (bwCnt == 2'd3) begin
         blk_wen <= 1'b1;
         bwState <= BW_IDLE;
      end
   end

   default:
   begin
      // Could note this as an error
      bwState <= BW_IDLE;
   end

   endcase // case (bwState)
end

endmodule
