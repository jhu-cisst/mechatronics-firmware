/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2024 ERC CISST, Johns Hopkins University.
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

`define FW_CTRL_SIZE    16'd2      // Firewire control word

`define FW_QREAD_SIZE   16'd16     // Firewire quadlet read request
`define FW_QRESP_SIZE   16'd20     // Firewire quadlet read response
`define FW_QWRITE_SIZE  16'd20     // Firewire quadlet write
`define FW_BRESP_SIZE   16'd24     // Firewire block read response header and CRCs
`define FW_BWRITE_SIZE  16'd24     // Firewire block write header and CRCs
`define FW_BWRITE_HDR_SIZE 16'd20  // Firewire block write header size

module EthernetIO
    #(parameter IPv4_CSUM = 0,     // Set to 1 to generate IPv4 (and ICMP) header checksum
      parameter IS_V3 = 0,         // Set to 1 to indicate FPGA V3
      parameter NUM_BC_READ_QUADS = 33,
      parameter USE_RXTX_CLK = 1'b0)
(
    // global clock
    input wire sysclk,
    input wire RxTxClk,            // Rx/Tx clock (if configured)

    // board id (rotary switch)
    input wire[3:0] board_id,
    input wire[5:0] node_id,

    // Register interface to Ethernet memory space and IP address register
    input  wire[15:0] reg_raddr_in,
    output reg[31:0] reg_rdata_out,
    input  wire[31:0] reg_wdata_in,
    input  wire ip_reg_wen,
    input  wire ctrl_reg_wen,
    output reg[31:0] ip_address,

    // Interface to/from board registers. These enable the Ethernet module to drive
    // the internal bus on the FPGA. In particular, they are used to read registers
    // to respond to quadlet read and block read commands.
    input wire[31:0] reg_rdata,
    output reg[15:0] reg_raddr,
    output reg       req_read_bus,     // 1 -> request read bus (reg_raddr)
    input wire       grant_read_bus,   // 1 -> read bus granted
    input wire       reg_rvalid,       // 1 -> reg_rdata should be valid
    output reg[31:0] reg_wdata,
    output wire[15:0] eth_reg_waddr,
    output wire      eth_reg_wen,
    output reg       blk_wen,
    output reg       blk_wstart,
    output reg       req_blk_rt_rd,    // request to start real-time block read
    output wire      blk_rt_rd,        // real-time block read
    output wire      blk_rt_wr,        // real-time block write
    output reg       req_write_bus,
    input wire       grant_write_bus,
    output wire      wdog_refresh,     // watchdog refresh

    // Interface to FireWire module (for sending packets via FireWire)
    output wire eth_send_fw_req,   // request to send firewire packet
    input wire eth_send_fw_ack,    // ack from firewire module
    input  wire[8:0] eth_fwpkt_raddr,
    output wire[31:0] eth_fwpkt_rdata,
    output wire[15:0] eth_fwpkt_len,   // eth received fw pkt length
    output reg[15:0] host_fw_addr,     // Firewire address of host (e.g., ffd0)

    // Interface from Firewire (for sending packets via Ethernet)
    // sendAck is in sysclk domain
    // sendAddr and sendData are in RxTxClk domain
    // sendLen is in RxTxClk domain, but it is set in advance and therefore
    // clock domain crossing not necessary
    output wire sendAck,             // Ack from Ethernet
    output reg[8:0] sendAddr,        // Address into packet memory
    input wire[31:0] sendData,       // Packet data from memory
    input wire[15:0] sendLen,        // Packet size (bytes)

    input wire fw_bus_reset,         // Firewire bus reset in process

    // Timestamp
    input wire[31:0] timestamp,

    // Interface to KSZ8851 or EthRtInterface
    // Note that these are assumed to be in the RxTxClk domain
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
    output reg sendBusy,             // To KSZ8851 or EthRtInterface
    input wire sendReady,            // Request EthernetIO to provide next send_word
    output reg[15:0] send_word,      // Word to send via Ethernet (SDRegDWR for KSZ8851)
    // Broadcast response (FPGA V3 only)
    output wire bcRespReady,         // Broadcast read response is ready to be sent
    input wire bcResp,               // Broadcast read response is active
    output wire[15:0] bcBoardMask,   // Board mask for broadcast read
    // Timing measurements
    input wire[15:0] timeReceive,    // Time when receive portion finished
    input wire[15:0] timeNow,        // Running time counter since start of packet receive
    input wire[1:0] srcPort,         // Source port (0 for FPGA V2, 0-2 for FPGA V3)
    input wire isHub,                // Whether this board might be the Ethernet hub
    input wire isBcHub,              // Whether this board is the Ethernet broadcast read hub
    // Feedback bits
    // bw_active is provided to lower-level module so that other actions (e.g., flushing KSZ8851
    // queue for FPGA V2) can happen in parallel; however, the lower-level module should wait until
    // bw_active is no longer asserted before setting recvRequest to process the next packet.
    output wire bw_active,           // Indicates that block write module is active
    input wire ethLLError,           // Error summary bit to EthernetIO (from low-level)
    output wire[7:0] eth_status,     // Status feedback
    output reg clearErrors           // Flag set by host to clear error bits and counters
);

// Clocks for Rx and Tx processes
wire RxClk;
wire TxClk;
if (USE_RXTX_CLK) begin
   assign RxClk = RxTxClk;
   assign TxClk = RxTxClk;
end
else begin
   assign RxClk = sysclk;
   assign TxClk = sysclk;
end

`define send_word_swapped {send_word[7:0], send_word[15:8]}

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

initial ip_address = IP_UNASSIGNED;

// FPGA MAC address
wire[47:0] fpga_mac;
assign fpga_mac = { `LCSR_CID, `FPGA_RT_MAC, 4'd0, board_id };

// FPGA Multicast MAC address
wire[47:0] multicast_mac;
assign multicast_mac = { `LCSR_CID_MULTICAST, `FPGA_RT_MAC, 8'hff };

`ifdef HAS_DEBUG_DATA
wire eth_send_isIdle;
assign eth_send_isIdle = (sendState == ST_SEND_DMA_IDLE) ? 1'd1 : 1'd0;
wire eth_recv_isIdle;
assign eth_recv_isIdle = (recvState == ST_RECEIVE_DMA_IDLE) ? 1'd1 : 1'd0;
`endif

// Following flags are set based on the destination address. Note that a FireWire
// broadcast packet will set both isLocal and isRemote, unless noForwardFlag is set.
wire isLocal;            // 1 -> FireWire packet should be processed locally
wire isRemote;           // 1 -> FireWire packet should be forwarded via Firewire

wire quadRead;
wire quadWrite;
wire blockRead;
wire blockWrite;

wire addrMain;

wire isRebootCmd;   // 1 -> Reboot FPGA command received

// Whether last valid packet was UDP (1) or Raw Ethernet (0)
reg useUDP;

// Whether to use UDP (1) or raw Ethernet frames (0) when forwarding packet from
// Firewire.  This flag is updated each time a valid packet is received and needs
// to be forwarded to Firewire (isRemote).
reg fwUseUDP;
initial fwUseUDP = 1'b1;

// Whether to use UDP (1) or raw Ethernet frames (0) when sending broadcast read
// response. This flag is updated when the broadcast query command is received
// (i.e., write to addrHubReg).
reg bcUseUDP;
initial bcUseUDP = 1'b1;

wire[15:0] bc_resp_length;      // Block read response size, in bytes

// Data length for response packets (bc_resp_length or block_data_length)
wire [15:0] reply_data_length;

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

// real-time feedback broadcast packet size, in quadlets and bytes, not including Firewire header/CRC
localparam[7:0] SZ_BBC_QUADS = NUM_BC_READ_QUADS;
localparam[15:0] SZ_BBC_BYTES = (4*NUM_BC_READ_QUADS);

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
   ID_ICMP_Checksum     = ID_ICMP_Begin+1,   // ICMP Checksum
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
   ID_Rep_UDP_Length    = ID_Reply_Begin+14, // UDP Reply Length (shared with ICMP_Checksum)
   ID_Rep_ICMP_Checksum = ID_Reply_Begin+14, // ICMP checksum (shared with UDP_Length)
   ID_Rep_ARP_Oper      = ID_Reply_Begin+15, // ARP reply operation = 2
   ID_Reply_End         = ID_Reply_Begin+15; // ******** End of all data (15) ***********

wire[15:0] ReplyBuffer[0:15];

// Following elements of ReplyBuffer are variable
wire[15:0] Reply_Frame_Length;
wire[15:0] Reply_IPv4_Length;
wire[15:0] Reply_IPv4_Csum;
wire[15:0] Reply_IPv4_Address0;
wire[15:0] Reply_IPv4_Address1;
reg[15:0]  Reply_UDP_hostPort;
wire[15:0] Reply_UDP_Length;
wire[15:0] Reply_ICMP_Checksum;

assign Reply_IPv4_Address0 = { ip_address[7:0],   ip_address[15:8]  };
assign Reply_IPv4_Address1 = { ip_address[23:16], ip_address[31:24] };

wire fw_resp_udp;       // Firewire response using UDP
assign fw_resp_udp = (isUDP & (quadRead | blockRead)) | (fwUseUDP & isForward);

wire sendUDP;
assign sendUDP = (isEcho | fw_resp_udp | (bcResp & bcUseUDP));

assign Reply_UDP_Length = isForward ? (`UDP_EXTRA_SIZE + sendLen) :
                          sendExtra ? `UDP_EXTRA_SIZE :
                          quadRead  ? (`UDP_EXTRA_SIZE + `FW_QRESP_SIZE)
                                    : (`UDP_EXTRA_SIZE + `FW_BRESP_SIZE) + reply_data_length;

assign Reply_IPv4_Length = isEcho   ? IPv4_Length       // Same length as request
                                    : (`IPv4_HDR_SIZE + Reply_UDP_Length);

assign Reply_Frame_Length = sendARP                ? 16'h0806 :
                            sendUDP                ? 16'h0800 :
                            // Forwarding raw data from FireWire
                            isForward              ? sendLen + `FW_EXTRA_SIZE :
                            // Local raw packet
                            ipWrite                ? (`FW_CTRL_SIZE + `FW_QWRITE_SIZE) :
                            hubSend                ? (`FW_CTRL_SIZE + `FW_BWRITE_SIZE + SZ_BBC_BYTES) :
                            sendExtra              ? `FW_EXTRA_SIZE :
                            quadRead               ? (`FW_QRESP_SIZE + `FW_EXTRA_SIZE)
                                                   : (`FW_BRESP_SIZE + `FW_EXTRA_SIZE) + reply_data_length;
integer i;
initial begin
   for (i = ID_Packet_Begin; i <= ID_Packet_End; i=i+1) PacketBuffer[i] = 16'd0;
end
assign ReplyBuffer[ID_Rep_Zero]          = 16'd0;
assign ReplyBuffer[ID_Rep_fpgaMac0]      = fpga_mac[47:32];
assign ReplyBuffer[ID_Rep_fpgaMac1]      = fpga_mac[31:16];
assign ReplyBuffer[ID_Rep_fpgaMac2]      = fpga_mac[15:0];
assign ReplyBuffer[ID_Rep_Frame_Length]  = Reply_Frame_Length;
assign ReplyBuffer[ID_Rep_IPv4_Word0]    = {4'd4, 4'd5, 6'd0, 2'd0};  // 0x4500
assign ReplyBuffer[ID_Rep_IPv4_Length]   = Reply_IPv4_Length;
assign ReplyBuffer[ID_Rep_IPv4_Flags]    = {3'b010, 13'd0};           // 0x4000
assign ReplyBuffer[ID_Rep_IPv4_Prot]     = {8'd64, isEcho ? 8'd1      // TTL=64, PROT=1  (ICMP)
                                                          : 8'd17};   //         PROT=17 (UDP)
assign ReplyBuffer[ID_Rep_IPv4_Csum]     = Reply_IPv4_Csum;
assign ReplyBuffer[ID_Rep_IPv4_Address0] = Reply_IPv4_Address0;          // updated when IP address assigned
assign ReplyBuffer[ID_Rep_IPv4_Address1] = Reply_IPv4_Address1;          // updated when IP address assigned
assign ReplyBuffer[ID_Rep_UDP_fpgaPort]  = 16'd1394;
assign ReplyBuffer[ID_Rep_UDP_hostPort]  = Reply_UDP_hostPort;           // updated in ST_RECEIVE_DMA_ETHERNET_HEADERS
assign ReplyBuffer[ID_Rep_UDP_Length]    = isUDP ? Reply_UDP_Length
                                                 : Reply_ICMP_Checksum;
assign ReplyBuffer[ID_Rep_ARP_Oper]      = 16'h0002;                     // ARP Operation (OPER): 2 for reply

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
    assign Reply_IPv4_Csum = ~(Rep_IPv4_Csum17[15:0] + {15'd0, Rep_IPv4_Csum17[16]});
end
else begin
    assign Reply_IPv4_Csum = 16'd0;
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
assign ARP_fpgaIP = { PacketBuffer[ID_ARP_fpgaIP1][7:0], PacketBuffer[ID_ARP_fpgaIP1][15:8],
                      PacketBuffer[ID_ARP_fpgaIP0][7:0], PacketBuffer[ID_ARP_fpgaIP0][15:8] };

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

reg[15:0] Port_Unknown;

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

if (IPv4_CSUM) begin
    // Checksum on received packet
    wire[15:0] ICMP_Checksum;
    assign ICMP_Checksum = PacketBuffer[ID_ICMP_Checksum];

    // Checksum on ICMP reply
    // We can cheat by using the received checksum, and subtracting the first word (0800),
    // which is the Type (8) and Code (0) because the reply packet has 0 for both.
    // This is more efficiently done by avoiding the one's complement and adding instead
    // of subtracting.
    wire[16:0] Reply_ICMP_Checksum17;
    assign Reply_ICMP_Checksum17 = { 1'b0, ICMP_Checksum } + { 1'b0, 16'h0800 };
    assign Reply_ICMP_Checksum = Reply_ICMP_Checksum17[15:0] + { 15'd0, Reply_ICMP_Checksum17[16] };
end
else begin
    // For FPGA V2, the KSZ8851 will compute this checksum for us
    assign Reply_ICMP_Checksum = 16'd0;
end

// Special case handling of write to IP address register.
wire ipWrite;
assign ipWrite = FireWirePacketFresh && quadWrite && (fw_dest_offset == {`ADDR_MAIN, 8'h0, `REG_IPADDR}) ? 1'b1 : 1'b0;

// Special case for broadcast read on an Ethernet-only network: writing to the Hub register
// (0x1800) causes this module to send an Ethernet multicast write packet to update the
// hub memory on this board and other FPGA boards.
wire hubSend;
wire[15:0] board_mask;                        // Board mask sent with quadlet write to Hub register
assign board_mask = FireWireQuadlet[15:0];    // Only valid for a limited time
reg isBoardMasked;

if (IS_V3)
   assign hubSend = FireWirePacketFresh & quadWrite & addrHubReg & isLocal & (~isRemote) & isBoardMasked;
else
    assign hubSend = 1'b0;

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
wire[5:0] ReplyIndex[0:63];

localparam isPacket = 1'b0;
localparam isReply  = 2'b10;

assign ReplyIndex[Frame_Reply_Begin]    = {isPacket, ID_Frame_srcMac0};
assign ReplyIndex[Frame_Reply_Begin+1]  = {isPacket, ID_Frame_srcMac1};
assign ReplyIndex[Frame_Reply_Begin+2]  = {isPacket, ID_Frame_srcMac2};
assign ReplyIndex[Frame_Reply_Begin+3]  = {isReply,  ID_Rep_fpgaMac0};
assign ReplyIndex[Frame_Reply_Begin+4]  = {isReply,  ID_Rep_fpgaMac1};
assign ReplyIndex[Frame_Reply_Begin+5]  = {isReply,  ID_Rep_fpgaMac2};
assign ReplyIndex[Frame_Reply_Begin+6]  = {isReply,  ID_Rep_Frame_Length};

assign ReplyIndex[IPv4_Reply_Begin]     = {isReply,  ID_Rep_IPv4_Word0};
assign ReplyIndex[IPv4_Reply_Begin+1]   = {isReply,  ID_Rep_IPv4_Length};
assign ReplyIndex[IPv4_Reply_Begin+2]   = {isReply,  ID_Rep_Zero};       // Identification
assign ReplyIndex[IPv4_Reply_Begin+3]   = {isReply,  ID_Rep_IPv4_Flags};
assign ReplyIndex[IPv4_Reply_Begin+4]   = {isReply,  ID_Rep_IPv4_Prot};
assign ReplyIndex[IPv4_Reply_Begin+5]   = {isReply,  ID_Rep_IPv4_Csum};  // Header checksum
assign ReplyIndex[IPv4_Reply_Begin+6]   = {isReply,  ID_Rep_IPv4_Address0};
assign ReplyIndex[IPv4_Reply_Begin+7]   = {isReply,  ID_Rep_IPv4_Address1};
assign ReplyIndex[IPv4_Reply_Begin+8]   = {isPacket, ID_IPv4_hostIP0};
assign ReplyIndex[IPv4_Reply_Begin+9]   = {isPacket, ID_IPv4_hostIP1};

assign ReplyIndex[UDP_Reply_Begin]      = {isReply,  ID_Rep_UDP_fpgaPort};
assign ReplyIndex[UDP_Reply_Begin+1]    = {isReply,  ID_Rep_UDP_hostPort};
assign ReplyIndex[UDP_Reply_Begin+2]    = {isReply,  ID_Rep_UDP_Length};
assign ReplyIndex[UDP_Reply_Begin+3]    = {isReply,  ID_Rep_Zero};       // Checksum

assign ReplyIndex[ARP_Reply_Begin]      = {isPacket, ID_ARP_HTYPE};
assign ReplyIndex[ARP_Reply_Begin+1]    = {isPacket, ID_ARP_PTYPE};
assign ReplyIndex[ARP_Reply_Begin+2]    = {isPacket, ID_ARP_HLEN_PLEN};
assign ReplyIndex[ARP_Reply_Begin+3]    = {isReply,  ID_Rep_ARP_Oper};
assign ReplyIndex[ARP_Reply_Begin+4]    = {isReply,  ID_Rep_fpgaMac0};
assign ReplyIndex[ARP_Reply_Begin+5]    = {isReply,  ID_Rep_fpgaMac1};
assign ReplyIndex[ARP_Reply_Begin+6]    = {isReply,  ID_Rep_fpgaMac2};
assign ReplyIndex[ARP_Reply_Begin+7]    = {isReply,  ID_Rep_IPv4_Address0};
assign ReplyIndex[ARP_Reply_Begin+8]    = {isReply,  ID_Rep_IPv4_Address1};
assign ReplyIndex[ARP_Reply_Begin+9]    = {isPacket, ID_ARP_srcMac0};
assign ReplyIndex[ARP_Reply_Begin+10]   = {isPacket, ID_ARP_srcMac1};
assign ReplyIndex[ARP_Reply_Begin+11]   = {isPacket, ID_ARP_srcMac2};
assign ReplyIndex[ARP_Reply_Begin+12]   = {isPacket, ID_ARP_hostIP0};
assign ReplyIndex[ARP_Reply_Begin+13]   = {isPacket, ID_ARP_hostIP1};

assign ReplyIndex[ICMP_Reply_Begin]     = {isReply,  ID_Rep_Zero};
assign ReplyIndex[ICMP_Reply_Begin+1]   = {isReply,  ID_Rep_ICMP_Checksum};
assign ReplyIndex[ICMP_Reply_Begin+2]   = {isPacket, ID_ICMP_Begin+2};
assign ReplyIndex[ICMP_Reply_Begin+3]   = {isPacket, ID_ICMP_Begin+3};
assign ReplyIndex[ICMP_Reply_Begin+4]   = {isPacket, ID_ICMP_Begin+4};
assign ReplyIndex[ICMP_Reply_Begin+5]   = {isPacket, ID_ICMP_Begin+5};

// Fill in rest of buffer
genvar k;
for (k=ICMP_Reply_End+1; k < 64; k=k+1) begin : reply_index_loop
   assign ReplyIndex[k] = {isReply, ID_Rep_Zero};
end

reg[5:0] replyCnt;                 // Counter for ReplyIndex

wire[5:0] reply_node_id;
assign reply_node_id = noForwardFlag ? { 2'd0, board_id } : node_id;

// Address to use in write response to IP or Hub write
// (see Raw Multicast Packet below)
wire[15:0] Write_Reply_Addr;
assign Write_Reply_Addr = (hubSend | bcResp) ? { `ADDR_HUB, 12'd0 } :
                                    ipWrite  ? { `ADDR_MAIN, 8'd0, `REG_FVERSION }
                                             : 16'd0;

// Quadlet data to use in write response to IP
wire[31:0] Write_Reply_Data;
assign Write_Reply_Data = 32'd9;

// Firewire transaction code for reply packet
wire[3:0] fw_tcode_reply;
assign fw_tcode_reply = ipWrite  ? `TC_QWRITE :
                        hubSend  ? `TC_BWRITE :
                        quadRead ? `TC_QRESP : `TC_BRESP;

//**************************** Firewire Reply Header ***********************************
wire[15:0] Firewire_Header_Reply[0:9];
assign Firewire_Header_Reply[0] = (ipWrite | hubSend) ? 16'hffff :
                                  bcResp              ? {host_fw_addr[7:0], host_fw_addr[15:8]}
                                                      : {fw_src_id[7:0], fw_src_id[15:8]};  // quadlet 0: dest-id
assign Firewire_Header_Reply[1] = {fw_tcode_reply, 4'd0, fw_tl_reply, 2'd0};                // quadlet 0: tcode
assign Firewire_Header_Reply[2] = {dest_bus_id[1:0], reply_node_id, dest_bus_id[9:2]};      // src-id
assign Firewire_Header_Reply[3] = 16'd0;   // rcode, reserved; addr[47:32] for write
assign Firewire_Header_Reply[4] = 16'd0;   // reserved; addr[31:16] for write
assign Firewire_Header_Reply[5] = { Write_Reply_Addr[7:0], Write_Reply_Addr[15:8] };        // addr[15:0] for write
// Quadlet read/write do not use entries below
assign Firewire_Header_Reply[6] = {reply_data_length[7:0], reply_data_length[15:8]};
assign Firewire_Header_Reply[7] = 16'd0;   // extended_tcode (0)
assign Firewire_Header_Reply[8] = 16'd0;   // header_CRC
assign Firewire_Header_Reply[9] = 16'd0;   // header_CRC

//********************************** Raw Multicast Packet *********************************************
// There are two cases where we need to send a raw Multicast packet:
//
// 1) ipWrite: In response to a write to the IP address register (which can be written even if host is
//    using raw Ethernet); it triggers a raw multicast quadlet write so that the Ethernet Switch port
//    forwarding database gets updated. The contents of the quadlet write are in Write_Reply_Addr
//    and Write_Reply_Data. Currently, it writes 9 to address 7 (firmware version), which does nothing
//    because that register is read-only. Note that the FPGA forwarding database can also get updated by
//    the PS Ethernet, which periodically sends Ethernet packets.
//
// 2) hubSend: In response to a write to the Hub register (0x1800); trigger a raw multicast block write
//    to write to the hub memory on all other FPGA boards.

wire[15:0] Multicast_Header[0:7];
assign Multicast_Header[0] = multicast_mac[47:32];
assign Multicast_Header[1] = multicast_mac[31:16];
assign Multicast_Header[2] = multicast_mac[15:0];
assign Multicast_Header[3] = fpga_mac[47:32];
assign Multicast_Header[4] = fpga_mac[31:16];
assign Multicast_Header[5] = fpga_mac[15:0];
assign Multicast_Header[6] = Reply_Frame_Length;
assign Multicast_Header[7] = 16'h0100;             // Set noForward flag

//************************* Broadcast Read Response **********************************

// Broadcast read response header (raw Ethernet and UDP).
// This is only used for FPGA V3 (IS_V3).

wire[15:0] bcResponseHeader[Frame_Reply_Begin:UDP_Reply_End];

//******************************** Debug Counters *************************************

`ifdef HAS_DEBUG_DATA
reg[9:0] numIPv4;            // Number of IPv4 packets received
reg[9:0] numUDP;             // Number of UDP packets received
reg[7:0] numARP;             // Number of ARP packets received
reg[7:0] numICMP;            // Number of ICMP packets received
reg[7:0] numMulticastWrite;  // Number of multicast packets written (ipWrite or hubSend)
`endif

reg[7:0] numPacketError;     // Number of packet errors (Frame, IPv4 or UDP error)

wire is_ip_unassigned;
assign is_ip_unassigned = (ip_address == IP_UNASSIGNED) ? 1'd1 : 1'd0;

// Variables used by block write process. Originally, this was only for the RT block
// write, but it is now used for all block writes. Note that the RT block write relies
// on the WriteAddressTranslation module to translate addresses, as well as to only
// write the data for this board (if a broadcast RT block write).
reg[8:0] bwStart;      // Starting offset in bw_packet for block write data
reg[8:0] bwLen;        // Number of quadlets in the block write data
wire[8:0] bwEnd;       // Ending offset in bw_packet for block write data

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
   if (USE_RXTX_CLK) begin
      assign writeRequestTrigger = {bwStart, 1'd0} + 10'd2;
      assign fwRequestTrigger    = 10'd2;
   end
   else begin
      assign writeRequestTrigger = {bwStart, 1'd0} + {1'd0, bwLen} + 10'd2;
      assign fwRequestTrigger    = LengthFW[11:2] + 10'd2;
   end
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

reg[1:0] srcPortReg;    // Source port from Ethernet Switch (FPGA V3); 0 for FPGA V2

// -----------------------------------------------
// Extra data sent to PC with every Firewire packet
// -----------------------------------------------

wire[15:0] ExtraData[0:3];
assign ExtraData[0] = {1'd0, srcPortReg, noForwardFlag, ethSummaryError, ethInternalError, fwPacketDropped, fw_bus_reset, fw_bus_gen};
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
assign DebugData[2]  = { writeRequest, 1'd0, bw_active_sys, eth_send_isIdle,                     // 31:28
                         eth_recv_isIdle, ethUDPError, 1'b0, ethIPv4Error,                       // 27:24
                         sendBusy, sendRequest, eth_send_fw_ack, eth_send_fw_req,                // 23:20
                         recvBusy, recvRequest, isLocal, isRemote,                               // 19:16
                         FireWirePacketFresh, isForward, sendARP, isUDP,                         // 15:12
                         isICMP, isEcho, is_IPv4_Long, is_IPv4_Short,                            // 11:8
                         fw_bus_reset, ipWrite, hubSend, bcResp,                                 //  7:4
                         4'd0 };                                                                 //  3:0
assign DebugData[3]  = { node_id, maxCountFW, LengthFW };                  // 6, 10, 16
assign DebugData[4]  = { fw_ctrl, host_fw_addr };                          // 16, 16
assign DebugData[5]  = { sendState, 12'd0,                                 // 16
                         1'd0, recvState, 1'd0, nextRecvState, 2'd0, recvCnt };     // 3, 3, 6
assign DebugData[6]  = { 6'd0, numUDP, 6'd0, numIPv4 };                    // 6, 10, 6, 10
assign DebugData[7]  = { br_wait_cnt, numICMP, fw_bus_gen, numARP };       // 8, 8, 8, 8
assign DebugData[8]  = { 7'd0, bw_left, bw_err, 4'd0, bwState, numPacketError };   // 7, 9, 1, 4, 3, 8
assign DebugData[9]  = { 7'd0, fw_left, fw_err, 7'd0, fw_wait_cnt };       // (7,9) (1,7) 8
assign DebugData[10] = { 8'd0, numMulticastWrite, Port_Unknown };
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

reg[31:0] FireWireQuadlet;   // the current quadlet being read

reg mem_wen;   // memory write enable

// packet memories: these store the received Ethernet packet. There currently are two memories to support
// simultaneous access:
//   fw_packet:  read by the Firewire module for packets that need to be forwarded
//   bw_packet:  primarily used for local block writes, but is also used for ICMP response and is
//               available for reading (for debugging)
// These are 512 quadlets (512 x 32), which is the maximum possible Firewire packet size at 400 Mbits/sec
// (actually, could add a few quadlets because the 512 limit does not include header and CRC).
// The block write and Firewire forwarding processes are already set up to run in parallel with packet reception
// (see writeRequestTrigger and fwRequestTrigger).

if (USE_RXTX_CLK) begin
   assign mem_raddr = bw_active_sys ? local_raddr
                                    : {2'd0, reg_raddr_in[6:0]};
   wire[31:0] mem_rdata_icmp;
   wire[31:0] mem_rdata_bw;
   assign mem_rdata = icmp_read_en ? mem_rdata_icmp : mem_rdata_bw;

   DPRAM_32x512_sclk icmp_packet(.clka(RxClk),
                                 .wea(mem_wen),
                                 .addra(rfw_count[9:1]),
                                 .dina(FireWireQuadlet),
                                 .clkb(TxClk),
                                 .addrb(sfw_count[9:1]),
                                 .doutb(mem_rdata_icmp)
                                );

   DPRAM_32x512_aclk fw_packet(.clka(RxClk),
                               .wea(mem_wen),
                               .addra(rfw_count[9:1]),
                               .dina(FireWireQuadlet),
                               .clkb(sysclk),
                               .addrb(eth_fwpkt_raddr),
                               .doutb(eth_fwpkt_rdata)
                               );

   DPRAM_32x512_aclk bw_packet(.clka(RxClk),
                               .wea(mem_wen),
                               .addra(rfw_count[9:1]),
                               .dina(FireWireQuadlet),
                               .clkb(sysclk),
                               .addrb(mem_raddr),
                               .doutb(mem_rdata_bw)
                              );
end
else begin
   assign mem_raddr = bw_active_sys ? local_raddr :
                      icmp_read_en  ? sfw_count[9:1]
                                    : {2'd0, reg_raddr_in[6:0]};

   DPRAM_32x512_sclk fw_packet(.clka(RxClk),
                               .wea(mem_wen),
                               .addra(rfw_count[9:1]),
                               .dina(FireWireQuadlet),
                               .clkb(sysclk),
                               .addrb(eth_fwpkt_raddr),
                               .doutb(eth_fwpkt_rdata)
                              );

   DPRAM_32x512_sclk bw_packet(.clka(RxClk),
                               .wea(mem_wen),
                               .addra(rfw_count[9:1]),
                               .dina(FireWireQuadlet),
                               .clkb(sysclk),
                               .addrb(mem_raddr),
                              .doutb(mem_rdata)
                              );
end

wire addrHub;
assign addrHub = (fw_dest_offset[15:12] == `ADDR_HUB) ? 1'b1 : 1'b0;

wire addrHubReg;
assign addrHubReg = (addrHub && (fw_dest_offset[11:0] == 12'h800)) ? 1'b1 : 1'b0;

wire addrHubMem;
assign addrHubMem = (addrHub && (fw_dest_offset[11:8] == 4'd0)) ? 1'b1 : 1'b0;

// Local hub memory; only used by Ethernet-only network (i.e., when not using
// Ethernet/Firewire bridge), which is only possible with FPGA V3 (IS_V3).
// Since this file is also used for FPGA V2, we define some registers
// and wires for both versions, but note that the memory is only instantiated
// for FPGA V3.

wire[31:0] reg_rdata_hub;  // Data read from local Hub memory
wire reg_rwait_hub;        // Not currently used

wire[15:0] bc_sequence;    // Local Hub sequence number

// Following is used when receiving packets; if set, data should be written to
// local hub (hub_eth) rather than setting writeRequest to write to "shared" hub
reg localHubWrite;

// Following is used when sending response packets; if set, data should be read
// from local hub (hub_eth) rather than from br_packet memory
wire localHubRead;
if (IS_V3)
   assign localHubRead = (addrHub & (quadRead | blockRead) & isLocal & noForwardFlag) | bcResp;
else
   assign localHubRead = 1'b0;

// reg_wen_hub_local is set from the SEND process, when sending the multicast
// packet (hubSend) to the other FPGA boards, so that the local real-time block
// data is also written to the local Hub memory.
reg reg_wen_hub_local;

// The following signals are set from the RECEIVE process, when:
//
//   1) receiving the quadlet write to the Hub register (reg_wen_hub_quad), which
//      sets the board mask and the sequence number.
//
//   2) receiving a multicast packet from another FPGA board (reg_wen_hub_remote),
//      which provides the real-time block data for the local Hub memory.

reg reg_wen_hub_quad;

wire[5:0] fw_tl_reply;

if (IS_V3) begin

   wire reg_wen_hub_remote;
   assign reg_wen_hub_remote = localHubWrite & mem_wen;

   wire[15:0] reg_waddr_hub_remote;
   assign reg_waddr_hub_remote = { `ADDR_HUB, 4'd0, (rfw_count[8:1] - bwStart[7:0]) };

   wire[15:0] reg_waddr_hub_local;
   assign reg_waddr_hub_local = { `ADDR_HUB, 4'd0, (sfw_count[8:1] - 8'd1) };

   // By design, the "local" and "remote" hub writes cannot happen at the same time,
   // so following is fine as long as they are both driven by the same write clock
   // as used for the hub memory.
   wire reg_wen_hub;
   wire[15:0] reg_waddr_hub;
   wire[31:0] reg_wdata_hub;

   assign reg_wen_hub = reg_wen_hub_local | reg_wen_hub_remote | reg_wen_hub_quad;

   assign reg_waddr_hub = reg_wen_hub_local  ? reg_waddr_hub_local :
                          reg_wen_hub_quad   ? fw_dest_offset
                                             : reg_waddr_hub_remote;

   assign reg_wdata_hub = reg_wen_hub_local  ? br_data_out :
                          reg_wen_hub_remote ? FireWireQuadlet :
                          reg_wen_hub_quad   ? fw_quadlet_data
                                             : 32'd0;

   wire[15:0] reg_raddr_hub;
   assign reg_raddr_hub = bcResp ? {`ADDR_HUB, 3'd0, sfw_count[9:1] }
                                 : fw_dest_offset + { 7'd0, sfw_count[9:1] };

   // Set hubclk
   wire hubclk;
   assign hubclk = USE_RXTX_CLK ? RxTxClk : sysclk;

   wire[8:0] bcQuads;              // Block read response size, in quadlets
   assign bc_resp_length = {5'd0, bcQuads, 2'd0};

   wire bcUpdated;                 // 1 -> hub memory updated
   reg  bcRespPending;             // 1 -> block read response is pending

   // Ready to send block read response if pending and hub memory has been updated
   assign bcRespReady = bcRespPending & bcUpdated & (~reg_wen_hub_quad);

   // All signals to/from HubReg are in hubclk domain.
   // The only one used in the sysclk domain is bc_sequence, but this
   // is fine because it is latched well in advance.

   HubReg
       #(.USE_FW(0))
   hub_eth(
       .sysclk(hubclk),
       .reg_wen(reg_wen_hub),
       .reg_raddr(reg_raddr_hub),
       .reg_waddr(reg_waddr_hub),
       .reg_rdata(reg_rdata_hub),
       .reg_wdata(reg_wdata_hub),
       .reg_rwait(reg_rwait_hub),
       .sequence(bc_sequence),
       .board_id(board_id),
       .write_trig_reset(1'b0),
       .fw_idle(1'b1),
       .updated(bcUpdated),
       .bc_quads(bcQuads),
       .board_mask_ext(bcBoardMask)
   );

   reg[47:0] bc_host_mac;  // Broadcast read host MAC
   reg[5:0]  bc_fw_tl;     // Broadcast read transaction label
   reg[15:0] bc_UDP_hostPort;
   reg[31:0] bc_hostIP;

   wire[15:0] bcResp_IPv4_Csum;   // IPv4 Header checksum

   assign bcResponseHeader[Frame_Reply_Begin]   = bc_host_mac[47:32];
   assign bcResponseHeader[Frame_Reply_Begin+1] = bc_host_mac[31:16];
   assign bcResponseHeader[Frame_Reply_Begin+2] = bc_host_mac[15:0];
   assign bcResponseHeader[Frame_Reply_Begin+3] = fpga_mac[47:32];
   assign bcResponseHeader[Frame_Reply_Begin+4] = fpga_mac[31:16];
   assign bcResponseHeader[Frame_Reply_Begin+5] = fpga_mac[15:0];
   assign bcResponseHeader[Frame_Reply_Begin+6] = Reply_Frame_Length;
   assign bcResponseHeader[IPv4_Reply_Begin]    = {4'd4, 4'd5, 6'd0, 2'd0};  // 0x4500
   assign bcResponseHeader[IPv4_Reply_Begin+1]  = Reply_IPv4_Length;
   assign bcResponseHeader[IPv4_Reply_Begin+2]  = 16'd0;
   assign bcResponseHeader[IPv4_Reply_Begin+3]  = {3'b010, 13'd0};           // 0x4000
   assign bcResponseHeader[IPv4_Reply_Begin+4]  = {8'd64, 8'd17};            // TTL=64, PROT=17 (UDP)
   assign bcResponseHeader[IPv4_Reply_Begin+5]  = bcResp_IPv4_Csum;
   assign bcResponseHeader[IPv4_Reply_Begin+6]  = Reply_IPv4_Address0;
   assign bcResponseHeader[IPv4_Reply_Begin+7]  = Reply_IPv4_Address1;
   assign bcResponseHeader[IPv4_Reply_Begin+8]  = bc_hostIP[31:16];
   assign bcResponseHeader[IPv4_Reply_End]      = bc_hostIP[15:0];
   assign bcResponseHeader[UDP_Reply_Begin]     = 16'd1394;
   assign bcResponseHeader[UDP_Reply_Begin+1]   = bc_UDP_hostPort;
   assign bcResponseHeader[UDP_Reply_Begin+2]   = Reply_UDP_Length;
   assign bcResponseHeader[UDP_Reply_End]       = 16'd0;

   if (IPv4_CSUM) begin
       wire[18:0] bcResp_IPv4_Csum19;
       assign bcResp_IPv4_Csum19 = {3'd0, bcResponseHeader[IPv4_Reply_Begin]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+1]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+3]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+4]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+6]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+7]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+8]} +
                                   {3'd0, bcResponseHeader[IPv4_Reply_Begin+9]};

       // First part of IPv4 checksum carry
       wire[16:0] bcResp_IPv4_Csum17;
       assign bcResp_IPv4_Csum17 = { 1'd0, bcResp_IPv4_Csum19[15:0]} + {14'd0, bcResp_IPv4_Csum19[18:16]};

       // Second part of IPv4 checksum carry, with ones complement of result
       assign bcResp_IPv4_Csum = ~(bcResp_IPv4_Csum17[15:0] + {15'd0, bcResp_IPv4_Csum17[16]});
   end
   else begin
       assign bcResp_IPv4_Csum = 16'd0;
   end

   always @(posedge RxClk)
   begin

      if (bcResp) begin
         // Broadcast response in process, so we can clear bcRespPending
         bcRespPending <= 1'b0;
      end

      if (reg_wen_hub_quad) begin
         // Write to broadcast read register (0x1800).
         // Set bcRespPending if this board is the broadcast hub (i.e., closest board to host)
         bcRespPending <= isBcHub;
         // Note whether we are using UDP (or raw Ethernet)
         bcUseUDP <= isUDP;
         // Save the host MAC address, IP address and port, just in case another packet is
         // received before we are able to send the broadcast read response
         bc_host_mac <= { PacketBuffer[ID_Frame_srcMac0], PacketBuffer[ID_Frame_srcMac1],
                          PacketBuffer[ID_Frame_srcMac2] };
         bc_hostIP <= { PacketBuffer[ID_IPv4_hostIP0], PacketBuffer[ID_IPv4_hostIP1] };
         bc_UDP_hostPort <= PacketBuffer[ID_UDP_hostPort];
         // Save the Firewire transaction label to use in the broadcast read response
         bc_fw_tl <= fw_tl;
      end

   end

   assign fw_tl_reply = bcResp ? bc_fw_tl : fw_tl;

end
else begin
   // Assign some default values for FPGA V2
   assign reg_rdata_hub = 32'd0;
   assign reg_rwait_hub = 1'b0;
   assign bc_sequence = 16'd0;
   assign bc_resp_length = 16'd0;
   assign bcRespReady = 1'b0;
   assign bcBoardMask = 16'd0;
   genvar r;
   for (r = Frame_Reply_Begin; r <= UDP_Reply_End; r = r+1) begin : bc_loop
      assign bcResponseHeader[r] = 16'd0;
   end
   assign fw_tl_reply = fw_tl;
end

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

// Whether dest_node_id matches this board. Prior to Rev 9, this would be true if equal
// to node_id.  Starting with Rev 9, check against node_id when forwarding to Firewire and
// against board_id when not forwarding to Firewire.
// Note that prior to adding support for Rev 9, the host software would only set noForwardFlag
// for some Firewire broadcast messages during initialization, so this change is backward
// compatible. Starting with Rev 9, regular packets will also set noForwardFlag when using the
// Ethernet network (provided by FPGA V3) instead of the Ethernet/Firewire bridge.
wire [5:0] expected_node_id;
assign expected_node_id = noForwardFlag ? { 2'd0, board_id } : node_id;
wire id_match;
assign id_match = (dest_node_id == expected_node_id) ? 1'b1 : 1'b0;

// Local if addresses this board or FireWire broadcast write or Firewire broadcast read (and this
// board is the Ethernet hub and noForwardFlag is set)
assign isLocal = id_match | (isFwBroadcast & ((quadWrite | blockWrite) |
                 ((quadRead | blockRead) & noForwardFlag & isHub)));

// Remote read or write if not addressing this board or Firewire broadcast, and if noForwardFlag is false.
// Also, note that some packets (e.g., Firewire broadcast) may set both isLocal and isRemote.
assign isRemote = (~id_match) & (~noForwardFlag);

assign quadRead = (FireWirePacketFresh && (fw_tcode == `TC_QREAD)) ? 1'd1 : 1'd0;
assign quadWrite = (FireWirePacketFresh && (fw_tcode == `TC_QWRITE)) ? 1'd1 : 1'd0;
assign blockRead = (FireWirePacketFresh && (fw_tcode == `TC_BREAD)) ? 1'd1 : 1'd0;
assign blockWrite = (FireWirePacketFresh && (fw_tcode == `TC_BWRITE)) ? 1'd1 : 1'd0;

assign reply_data_length = bcResp ? bc_resp_length : block_data_length;

assign addrMain = (fw_dest_offset[15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;

// For local use
reg[15:0] reg_waddr;
reg reg_wen;

// Following signal indicates whether real-time block read is in process
assign blk_rt_rd = ((addrMain & blockRead) | hubSend) & req_read_bus;

//*********************** Write Address Translation *******************************
//
// Write bus address translation (to support real-time block write).

wire board_equal;
assign board_equal = (reg_wdata[11:8] == board_id) ? 1'b1 : 1'b0;

WriteAddressTranslation EthWriteAddr
(
    .sysclk(sysclk),
    .reg_waddr_in(reg_waddr[7:0]),
    .reg_wen_in(reg_wen),
    .reg_waddr_out(eth_reg_waddr[7:0]),
    .reg_wen_out(eth_reg_wen),
    .blk_rt_wr(blk_rt_wr),
    .reg_wdata_lsb(reg_wdata[7:0]),
    .board_equal(board_equal)
);

assign eth_reg_waddr[15:8] = reg_waddr[15:8];

//*********************************************************************************

// Following signal indicates whether real-time block write in process
assign blk_rt_wr = bwAddrMain & req_write_bus;

assign isRebootCmd = (addrMain && (fw_dest_offset[11:0] == 12'd0) && quadWrite
                      && (fw_quadlet_data[21:20] == 2'b11)) ? 1'd1 : 1'd0;

// For reading the timestamp
reg[31:0] timestamp_latched;
reg[31:0] timestamp_prev;

//*****************************************************************
//  Write to Ethernet IP register or control register
//*****************************************************************

always @(posedge sysclk)
begin
   // Write to IP address register
   if (ip_reg_wen) begin
      ip_address <= desired_ip_address;
   end

   if (ctrl_reg_wen) begin
      clearErrors <= reg_wdata_in[29];
   end
   else begin
      clearErrors <= 0;
   end
end

//**********************************************************************************************
// Clock domain crossing
//
// Following handles possible clock domain crossing between sysclk and RxTxClk. For clarity,
// signals that cross this domain have the name suffix "_rxtx" in the RxTxClk domain, except
// for signals that are provided to the lower-level Ethernet module (KSZ8851 or EthRtInterface),
// since these are assumed to be in the RxTxClk domain. There is one signal, bw_active_sys,
// that is generated in the sysclk domain and provided to the lower-level module as bw_active.
//
// If USE_RXTX_CLK=0, there is no clock domain crossing (sysclk and RxTxClk are the same).
// If USE_RXTX_CLK=1, there is clock domain crossing and we latch the signal using the
// appropriate clock.
//
//**********************************************************************************************

// Signals between sysclk and RxTxClk

// input wire clearErrors
wire clearErrors_rxtx;      // clearErrors input in RxTxClk domain

// output wire eth_send_fw_req
reg  eth_send_fw_req_rxtx;  // request Firewire to send packet (eth_send_fw_req output)

// input wire eth_send_fw_ack
wire eth_send_fw_ack_rxtx;  // eth_send_fw_ack input in RxTxClk domain

// output wire sendAck
reg sendAck_rxtx;

reg  writeRequest_rxtx;     // request register write from RxTxClk domain
wire writeRequest;          // request register write in sysclk domain

reg bw_active_sys;          // register write active in sysclk domain
// output wire bw_active (actually in RxTxClk domain)

reg  br_request_rxtx;       // request register read into br_packet memory from RxTxClk domain
wire br_request;            // request register read into br_packet_memory in sysclk domain

reg  br_ack;                // Acknowledge br_request
wire br_ack_rxtx;           // br_ack in RxTxClk domain

// output wire wdog_refresh (generated from reg_wen_hub_quad)

if (USE_RXTX_CLK) begin
   // Synchronize signals from sysclk to RxTxClk
   reg clearErrors_latched;
   reg eth_send_fw_ack_latched;
   reg bw_active_sys_latched;
   reg br_ack_latched;
   always @(posedge RxTxClk)
   begin
      clearErrors_latched <= clearErrors;
      eth_send_fw_ack_latched <= eth_send_fw_ack;
      bw_active_sys_latched <= bw_active_sys;
      br_ack_latched <= br_ack;
   end
   assign clearErrors_rxtx = clearErrors_latched;
   assign eth_send_fw_ack_rxtx = eth_send_fw_ack_latched;
   assign bw_active = bw_active_sys_latched;
   assign br_ack_rxtx = br_ack_latched;
   // Synchronize signals from RxTxClk to sysclk
   reg eth_send_fw_req_rxtx_latched;
   reg sendAck_rxtx_latched;
   reg writeRequest_rxtx_latched;
   reg br_request_rxtx_latched;
   reg reg_wen_hub_quad_latched;
   always @(posedge sysclk)
   begin
      eth_send_fw_req_rxtx_latched <= eth_send_fw_req_rxtx;
      writeRequest_rxtx_latched <= writeRequest_rxtx;
      sendAck_rxtx_latched <= sendAck_rxtx;
      br_request_rxtx_latched <= br_request_rxtx;
      reg_wen_hub_quad_latched <= reg_wen_hub_quad;
   end
   assign eth_send_fw_req = eth_send_fw_req_rxtx_latched;
   assign sendAck = sendAck_rxtx_latched;
   assign writeRequest = writeRequest_rxtx_latched;
   assign br_request = br_request_rxtx_latched;
   assign wdog_refresh = reg_wen_hub_quad_latched;
end
else begin
   // No clock domain crossing
   assign clearErrors_rxtx = clearErrors;
   assign eth_send_fw_req = eth_send_fw_req_rxtx;
   assign eth_send_fw_ack_rxtx = eth_send_fw_ack;
   assign sendAck = sendAck_rxtx;
   assign writeRequest = writeRequest_rxtx;
   assign bw_active = bw_active_sys;
   assign br_request = br_request_rxtx;
   assign br_ack_rxtx = br_ack;
   assign wdog_refresh = reg_wen_hub_quad;
end

//*****************************************************************
//  ETHERNET Receive state machine
//*****************************************************************

localparam[2:0]
    ST_RECEIVE_DMA_IDLE = 3'd0,
    ST_RECEIVE_DMA_ETHERNET_HEADERS = 3'd1,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 3'd2,
    ST_RECEIVE_DMA_ICMP_DATA = 3'd3,
    ST_RECEIVE_DMA_WAIT_START = 3'd4,
    ST_RECEIVE_DMA_REBOOT = 3'd5,
    ST_RECEIVE_DMA_WAIT_FINISH = 3'd6;

reg[2:0] recvState = ST_RECEIVE_DMA_IDLE;
reg[2:0] nextRecvState = ST_RECEIVE_DMA_IDLE;

// recvReady (aka dataReady) -->  dataValid  -->  recvTransition
reg dataValid;          // Data has been stored in PacketBuffer
reg recvTransition;     // Transition to next state

// This indicates that the lower-level module has stopped providing data; in some cases
// this would be unexpected, so checking this signal can prevent this module from getting
// stuck in a non-idle state. We assume that the lower-level module will keep recvRequest
// asserted until all data is provided. The check below for recvReady|dataValid|recvTransition
// ensures that we will finish processing the last word provided.
wire recvFinish;
assign recvFinish = ((~recvRequest) & ~(recvReady|dataValid|recvTransition)) ? 1'b1 : 1'b0;

reg[5:0] recvCnt;       // Index into PacketBuffer
reg[9:0] rfw_count;     // Counts words in FireWire packets (max is 1024 words, or 2048 bytes)
reg[5:0] rebootCnt;     // Counter used to delay reboot command (could reuse recvCnt)

reg[7:0] br_wait_cnt;   // Number of clocks waiting for block read to finish

assign responseRequired = ((FireWirePacketFresh &
                            ((quadRead | blockRead) & (isLocal | sendExtra)) | ((ipWrite | hubSend) & isLocal))
                           | sendARP | isEcho);

// Previously (up to Firmware Rev 8), set all bits of ip_address (e.g., 169.254.0.100)
// Firmware 9+: Add board_id to last 8 bits (e.g., 169.254.0.{100+board_id})
wire[31:0] desired_ip_address;
assign desired_ip_address = { (reg_wdata_in == IP_UNASSIGNED) ? reg_wdata_in[31:24]
                                                              : (reg_wdata_in[31:24] + {4'd0, board_id}),
                              reg_wdata_in[23:0] };

always @(posedge RxClk)
begin

   dataValid <= recvReady;           // 1 clock after recvReady
   recvTransition <= dataValid;      // 1 clock after dataValid

   if (eth_send_fw_ack_rxtx) begin
      eth_send_fw_req_rxtx <= 1'b0;
   end

   if (bw_active) begin
      writeRequest_rxtx <= 1'b0;
   end

   if (br_ack_rxtx) begin
      br_request_rxtx <= 1'b0;
   end

   // req_blk_rt_rd is asserted for just one sysclk
   req_blk_rt_rd <= 1'b0;

   if (resetActive|clearErrors_rxtx) begin
      numPacketError <= 8'd0;
      ethFrameError <= 0;
      ethIPv4Error <= 0;
      ethUDPError <= 0;
      ethDestError <= 0;
   end

   if (recvTransition) begin
      recvState <= nextRecvState;
   end

   case (recvState)

   ST_RECEIVE_DMA_IDLE:
   begin
      mem_wen <= 0;
      rfw_count <= 10'd0;
      recvCnt <= 6'd0;
      nextRecvState <= ST_RECEIVE_DMA_IDLE;
      recvBusy <= 0;
      writeRequest_rxtx <= 1'b0;
      br_request_rxtx <= 1'b0;
      localHubWrite <= 1'b0;
      eth_send_fw_req_rxtx <= 0;

      if (resetActive|clearErrors_rxtx) begin
         FireWirePacketFresh <= 0;
         fwPacketDropped <= 0;
         ethRecvStateError <= 0;
      end

      if (recvRequest) begin
         recvBusy <= 1;
         bwStart <= 9'd15;    // Large value to prevent early write
         FireWirePacketFresh <= 0;
         fwPacketDropped <= 0;
         srcPortReg <= srcPort;
         recvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
      end

      if (bcResp) begin
         FireWirePacketFresh <= 0;
      end
   end

   ST_RECEIVE_DMA_ETHERNET_HEADERS:
   begin
      // Unexpected end of data from lower-level
      if (recvFinish) recvState <= ST_RECEIVE_DMA_WAIT_FINISH;

      if (recvReady) PacketBuffer[recvCnt] <= recv_word;  // `SDSwapped for KSZ8851

      if (dataValid) begin
         if ((recvCnt == ID_Frame_End) && !(isRaw|isIPv4|isARP)) begin
            ethFrameError <= 1'd1;
            numPacketError <= numPacketError + 8'd1;
            nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;
         end
         else if ((recvCnt == ID_ARP_End) && isARP) begin
`ifdef HAS_DEBUG_DATA
            numARP <= numARP + 8'd1;
`endif
            nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;
         end
         else if ((recvCnt == ID_IPv4_End) && isIPv4) begin
            if ((IPv4_Version != 4'h4) || !(isUDP|isICMP)) begin
               ethIPv4Error <= 1'd1;
               numPacketError <= numPacketError + 8'd1;
               nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;
            end
            else begin
               nextRecvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
            end
         end
         else if ((recvCnt == ID_UDP_End) && isUDP) begin
            if (!isPortValid) begin
               // Port 1534 is used by tcf-agent, which is enabled by default in Petalinux;
               // thus, we just ignore it and do not consider it an unexpected UDP port.
               if (PacketBuffer[ID_UDP_destPort] != 16'd1534) begin
                   ethUDPError <= 1'd1;
                   numPacketError <= numPacketError + 8'd1;
                   Port_Unknown <= PacketBuffer[ID_UDP_destPort];
               end
               nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;
            end
            else begin
               // Save the UDP host port because UDP_hostPort may get overwritten if an ARP packet is received, which
               // would be a problem if the ARP packet is followed by a request to forward a packet from FireWire via UDP.
               // This may not be necessary if ARP and UDP packets were not allowed to overlap in PacketBuffer,
               // but that would require a much larger PacketBuffer. Also, even separating ARP and UDP in PacketBuffer
               // would not handle the (unlikely) case where an invalid UDP packet is received prior to the request to
               // forward a packet from FireWire.
               Reply_UDP_hostPort <= PacketBuffer[ID_UDP_hostPort];
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
      // Unexpected end of data from lower-level
      if (recvFinish) recvState <= ST_RECEIVE_DMA_WAIT_FINISH;

      if (recvTransition) rfw_count <= rfw_count + 10'd1;
      // rfw_count is in words, icmp_data_length is in bytes
      if (rfw_count[9:0] == icmp_data_length[10:1]) begin
`ifdef HAS_DEBUG_DATA
         if (recvTransition) numICMP <= numICMP + 8'd1;
`endif
         nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;   // was ST_RECEIVE_DMA_FRAME_CRC;
      end
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
      // Unexpected end of data from lower-level
      if (recvFinish) recvState <= (eth_send_fw_req_rxtx | br_request_rxtx)
                                   ? ST_RECEIVE_DMA_WAIT_START : ST_RECEIVE_DMA_WAIT_FINISH;
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
      // Note that if localHubWrite is set, this will also write to hub_eth
      mem_wen <= (rfw_count[0]&dataValid) ? 1'b1 : 1'b0;

      if (dataValid) begin
         if ((rfw_count == 10'd0) && (dest_bus_id != 10'h3FF)) begin
            // Invalid destination address (first 10 bits are not FFC), flush packet
            ethDestError <= 1;
            nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;
         end
         else if (rfw_count == 10'd5) begin
            FireWirePacketFresh <= 1;
            useUDP <= isUDP;
            if (isRemote) fwUseUDP <= isUDP;
            if ((~noForwardFlag) &&
                (fw_bus_reset || ((host_fw_bus_gen != fw_bus_gen) && ~isFwBroadcast))) begin
               // If we are using Firewire (~noForwardFlag) and if Firewire bus is in reset OR
               // (bus generation does not match AND not a broadcast packet), then flush packet.
               // Note that we do not check if the bus goes into reset or the generation changes
               // while we are processing the packet. Also, it is important to note that a
               // Firewire bus reset can change node_id, unless noForwardFlag is set, in which
               // case board_id is used instead of the node_id (see expected_node_id).
               fwPacketDropped <= 1;
               nextRecvState <= ST_RECEIVE_DMA_WAIT_FINISH;
            end
         end
         else if ((rfw_count == 10'd7) && quadWrite) begin
            fw_quadlet_data <= FireWireQuadlet;
            // Set writeRequest for local quadlet write, if not also remote (i.e., not broadcast).
            // For broadcast quadlet write, we first forward to Firewire, then set writeRequest
            // when we receive the ack (eth_send_fw_ack).
            // The only case where this is necessary is for the broadcast query command, but we do
            // it consistently for all broadcast quadlet writes.
            // It is necessary for the broadcast query command to make sure that all boards are ready for
            // the sequential update of Hub memory (especially if this board is the lowest numbered board)
            writeRequest_rxtx <= isLocal & (~isRemote) & (~addrHubReg);
            // If Ethernet-only (noForwardFlag), then we write the quadlet data to the local Hub register
            // (the quadlet data contains the sequence number and board mask).
            isBoardMasked <= board_mask[board_id];
            reg_wen_hub_quad <= isLocal & noForwardFlag & addrHubReg & board_mask[board_id];
         end
         else if ((rfw_count == 10'd9) && blockWrite) begin
            bwStart <= 9'd5;
            bwLen <= block_data_length[10:2];
            localHubWrite <= isLocal & noForwardFlag & addrHubMem;
         end
         else if (rfw_count == maxCountFW) begin
            if (reg_wen_hub_quad) begin
               // OK to use host_fw_addr here since Firewire module not active
               host_fw_addr <= fw_src_id;
            end
            reg_wen_hub_quad <= 1'b0;
            nextRecvState <= ST_RECEIVE_DMA_WAIT_START;  // was ST_RECEIVE_DMA_FRAME_CRC;
            if (isLocal & ((addrMain & blockRead) | (addrHubReg & quadWrite & isBoardMasked))) begin
               // Latch timestamp if a block read from ADDR_MAIN or a broadcast read request
               // (quadlet write to ADDR_HUB).
               // TODO: Subtracting 1 for backward compatibility; may eliminate that for Firmware Rev 9
               timestamp_latched <= (timestamp-timestamp_prev)-32'd1;
               timestamp_prev <= timestamp;
               req_blk_rt_rd <= 1'b1;
            end
            if (isLocal & blockWrite & (~(addrHub & (~isRemote)))) begin
              // writeRequest should have been set earlier (using writeRequestTrigger) for all
              // local block writes (even broadcast). We expect write to still be active.
              // The one exception is when we receive a multicast write to the Hub memory.
              bw_err <= ~req_write_bus;
              // Number of quadlets left to write to registers; should be greater than 1,
              // otherwise the register writer may have overtaken the Ethernet reader.
              bw_left <= bwEnd - local_raddr;
           end
           else if (isLocal & (quadRead | blockRead | hubSend)) begin
              br_request_rxtx <= 1'b1;
              br_wait_cnt <= 8'd0;
            end
            if (hubSend) begin
                // Set block_data_length to the size of the hubSend packet
                block_data_length <= SZ_BBC_BYTES;
            end
            if (isRemote) begin
               // Request to forward should already have been set (using fwRequestTrigger).
               // We expect that it would still be active.
               fw_err <= ~eth_send_fw_ack_rxtx;
               // Number of quadlets left to write to registers; should be greater than 1,
               // otherwise the Firewire writer may have overtaken the Ethernet reader.
               fw_left <= eth_fwpkt_len[10:2] - eth_fwpkt_raddr;
            end
         end
         else begin
            nextRecvState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
         end

         if (blockWrite && (rfw_count == writeRequestTrigger)) begin
            writeRequest_rxtx <= isLocal & (~localHubWrite);
         end
         if ((rfw_count == fwRequestTrigger) && isRemote) begin
            eth_send_fw_req_rxtx <= 1'b1;
            fw_wait_cnt <= 8'd0;
            host_fw_addr <= fw_src_id;
         end

      end
   end

   ST_RECEIVE_DMA_WAIT_START:
   begin
      if (eth_send_fw_req_rxtx | eth_send_fw_ack_rxtx) begin
         // Waiting for Ethernet forward to finish
         fw_wait_cnt <= fw_wait_cnt + 8'd1;
      end
      else if (br_request_rxtx | br_ack_rxtx) begin
         // Wait until read from registers finished
         br_wait_cnt <= br_wait_cnt + 8'd1;
      end
      else begin
`ifdef HAS_DEBUG_DATA
         // Increment counters
         numIPv4 <= numIPv4 + {9'd0, isIPv4};
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
            if (quadWrite)
                writeRequest_rxtx <= isRemote&isLocal;
            // Wait for any pending writes to start (including any previously
            // requested quadlet or block writes)
            recvState <= ST_RECEIVE_DMA_WAIT_FINISH;
         end
      end
   end

   ST_RECEIVE_DMA_REBOOT:
   begin
      // Wait an additional 1.3 us after eth_send_fw_ack removed to
      // make sure Firewire packet has been transmitted
      rebootCnt <= rebootCnt + 6'd1;
      if (rebootCnt == 6'h3f) begin
         writeRequest_rxtx <= 1'b1;
         recvState <= ST_RECEIVE_DMA_WAIT_FINISH;
      end
   end

   ST_RECEIVE_DMA_WAIT_FINISH:
   begin
      // First, wait until writeRequest and bw_active are both 0, indicating that any
      // requested register write has completed.
      // Then, perform the final handshaking with the lower-level by clearing recvBusy
      // and waiting for recvRequest to be cleared.
      if ((~writeRequest_rxtx) & (~bw_active)) begin
         recvBusy <= 1'b0;
         if (~recvRequest)
            recvState <= ST_RECEIVE_DMA_IDLE;
      end
   end

   default:
   begin
      ethRecvStateError <= 1;
      recvState <= ST_RECEIVE_DMA_WAIT_FINISH;
      nextRecvState <= ST_RECEIVE_DMA_IDLE;
   end

   endcase // case (recvState)
end


//**********************************************************************
// ETHERNET Send DMA state machine
//
// The lower-level module (KSZ8851.v or EthRtInterface.v) initiates the
// data transfer by setting sendRequest, which then causes this module
// to set sendBusy and transition out of the IDLE state.
//
// Data is transferred in a loop consisting of at least two clocks:
//
//    CLK(0):  lower-level sets sendReady and uses send_word
//             (from previous cycle); this module does nothing
//
//    CLK(1):  lower-level module clears sendReady;
//             this module latches send_word, increments address
//             and/or transitions to new state
//
// Note that this module does nothing until sendReady==1, which happens
// one clock after the lower-level asserts it (sendReady <= 1).
// Thus, the lower-level module can increase the number of clocks per
// loop by the rate at which it sets sendReady.
//
// IMPORTANT: sendReady should never be asserted for more than 1
// consecutive clock.
//
// After the last word is transfered, EthernetIO clears sendBusy. It is
// assumed that the lower-level module will clear sendRequest soon after
// sendBusy is asserted.
//
//**********************************************************************

localparam[3:0]
    ST_SEND_DMA_IDLE = 4'd0,
    ST_SEND_DMA_ETHERNET_HEADERS = 4'd3,
    ST_SEND_DMA_ETHERNET_HEADERS_MC = 4'd4,   // Send multicast headers (TBD)
    ST_SEND_DMA_ETHERNET_HEADERS_BC = 4'd5,   // Send broadcast response headers
    ST_SEND_DMA_PACKETDATA_HEADER = 4'd6,
    ST_SEND_DMA_PACKETDATA_QUAD = 4'd7,
    ST_SEND_DMA_PACKETDATA_BLOCK = 4'd8,
    ST_SEND_DMA_PACKETDATA_CHECKSUM = 4'd9,
    ST_SEND_DMA_FWD = 4'd10,
    ST_SEND_DMA_ICMP_DATA = 4'd11,
    ST_SEND_DMA_EXTRA = 4'd12,
    ST_SEND_DMA_FINISH = 4'd13;

reg[3:0] sendState = ST_SEND_DMA_IDLE;

// Accessing br_packet memory
wire[31:0] br_data_out;

reg[9:0] sfw_count;     // Counts words in FireWire packets (max is 1024 words, or 2048 bytes)
reg[1:0] xcnt;          // Counts words in extra packet

// Following needed by KSZ8851
assign responseByteCount =
             sendARP ? (`ETH_FRAME_SIZE + 16'd28) :                 // ARP response: 14 + 28
             sendUDP ? (`ETH_FRAME_SIZE + Reply_IPv4_Length)        // UDP or ICMP Echo packet
                     : (`ETH_FRAME_SIZE + Reply_Frame_Length);      // Raw packet

always @(posedge TxClk)
begin

   if (resetActive|clearErrors_rxtx) begin
      ethSendStateError <= 0;
   end

   case (sendState)

   ST_SEND_DMA_IDLE:
   begin
      sendBusy <= 0;
      icmp_read_en <= 0;
      sfw_count <= 10'd0;
      xcnt <= 2'd0;
      if (sendRequest) begin
         sendBusy <= 1;
         sendState <= (bcResp & IS_V3) ? ST_SEND_DMA_ETHERNET_HEADERS_BC : ST_SEND_DMA_ETHERNET_HEADERS;
         replyCnt <= Frame_Reply_Begin;
      end
   end

   ST_SEND_DMA_ETHERNET_HEADERS:
   begin
      if (sendReady) begin
         `send_word_swapped <= (ipWrite|hubSend) ? Multicast_Header[replyCnt] :
                               (ReplyIndex[replyCnt][5]==isPacket) ?
                                PacketBuffer[ReplyIndex[replyCnt][4:0]] :
                                ReplyBuffer[ReplyIndex[replyCnt][3:0]];
         replyCnt <= replyCnt + 6'd1;
         if (replyCnt == Frame_Reply_End) begin
            if (isForward & (~fwUseUDP)) begin
               sendState <= ST_SEND_DMA_FWD;
               sendAck_rxtx <= 1;
               sendAddr <= 9'd0;
            end
            else if (sendARP & (~isForward)) begin
               replyCnt <= ARP_Reply_Begin;
            end
            else if (~(isUDP | isEcho | isForward | ipWrite | hubSend)) begin
               // Raw packet (except ipWrite and hubSend, which need an extra word for fw_ctrl)
               sendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
            end
         end
         else if (replyCnt == Frame_Reply_End+1) begin
            if (ipWrite | hubSend) begin
`ifdef HAS_DEBUG_DATA
               numMulticastWrite <= numMulticastWrite + 8'd1;
`endif
               sendState <= ST_SEND_DMA_PACKETDATA_HEADER;
            end
         end
         else if (replyCnt == IPv4_Reply_End) begin
            replyCnt <= isEcho ? ICMP_Reply_Begin : UDP_Reply_Begin;
         end
         else if (replyCnt == UDP_Reply_End) begin
            if (isForward) begin
               sendState <= ST_SEND_DMA_FWD;
               sendAck_rxtx <= 1;
               sendAddr <= 9'd0;
            end
            else begin
               sendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
            end
         end
         else if (replyCnt == ARP_Reply_End) begin
            sendState <= ST_SEND_DMA_FINISH;
         end
         else if (replyCnt == ICMP_Reply_End) begin
            sendState <= ST_SEND_DMA_ICMP_DATA;
            icmp_read_en <= 1;
         end
      end
   end

   ST_SEND_DMA_ETHERNET_HEADERS_BC:
   begin
      if (sendReady) begin
         `send_word_swapped <= bcResponseHeader[replyCnt];
         replyCnt <= replyCnt + 6'd1;
         if ((replyCnt == Frame_Reply_End) && (~bcUseUDP)) begin
             sendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
         end
         else if (replyCnt == UDP_Reply_End) begin
             sendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
         end
      end
   end

   ST_SEND_DMA_ICMP_DATA:
   begin
      if (sendReady) begin
         `send_word_swapped <= (sfw_count[0] == 0) ? mem_rdata[31:16]
                                                   : mem_rdata[15:0];
         sfw_count <= sfw_count + 10'd1;
         // sfw_count is in words, icmp_data_length is in bytes
         if (sfw_count[9:0] == icmp_data_length[10:1])
            sendState <= ST_SEND_DMA_FINISH;
      end
   end

   // Send first 6 words (3 quadlets), which are nearly identical between quadlet read response
   // and block read response (only difference is tcode).
   // For block read response, send an additional 4 words (2 quadlets), which are block data length
   // and header CRC.
   ST_SEND_DMA_PACKETDATA_HEADER:
   begin
      if (sendReady) begin
         send_word <= Firewire_Header_Reply[sfw_count[3:0]];
         if ((sfw_count[3:0] == 4'd5) && (quadRead | ipWrite)) begin
            sfw_count <= 10'd0;
            sendState <= ST_SEND_DMA_PACKETDATA_QUAD;
         end
         else if (sfw_count[3:0] == 4'd9) begin  // block read
            if (blockRead | hubSend | bcResp) begin
               sfw_count <= 10'd0;
               sendState <= ST_SEND_DMA_PACKETDATA_BLOCK;
            end
            else  // Should not happen
               sendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
         end
         else begin
            // stay in this state
            sfw_count <= sfw_count + 10'd1;
         end
      end
   end

   ST_SEND_DMA_PACKETDATA_QUAD:
   begin
      if (sendReady) begin
         if (sfw_count[0] == 0) begin
            `send_word_swapped <= localHubRead ? reg_rdata_hub[31:16] :
                                  ipWrite      ? Write_Reply_Data[31:16]
                                               : br_data_out[31:16];
            sfw_count[0] <= 1;
         end
         else begin
            `send_word_swapped <= localHubRead ? reg_rdata_hub[15:0] :
                                  ipWrite      ? Write_Reply_Data[15:0]
                                               : br_data_out[15:0];
            sfw_count[0] <= 0;
            sendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
         end
      end
   end

   ST_SEND_DMA_PACKETDATA_BLOCK:
   begin

      if (sendReady) begin
         sfw_count <= sfw_count + 10'd1;
         if (sfw_count[0] == 0) begin   // even count (upper word)
            `send_word_swapped <= localHubRead ? reg_rdata_hub[31:16] : br_data_out[31:16];
            reg_wen_hub_local <= 1'b0;
         end
         else begin   // odd count (lower word)
            `send_word_swapped <= localHubRead ? reg_rdata_hub[15:0] : br_data_out[15:0];
            reg_wen_hub_local <= hubSend;
            // sfw_count is in words and reply_data_length is in bytes, but we compare in quadlets
            if ((sfw_count[9:1] + 9'd1) == reply_data_length[10:2])
               sendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
         end
      end
      else begin
         reg_wen_hub_local <= 1'b0;
      end
   end

   ST_SEND_DMA_PACKETDATA_CHECKSUM:
   begin
      reg_wen_hub_local <= 1'b0;
      if (sendReady) begin
         sfw_count[0] <= 1;
         send_word <= 16'd0;    // Checksum currently not set
         if (sfw_count[0] == 1)
            sendState <= (ipWrite | hubSend) ? ST_SEND_DMA_FINISH : ST_SEND_DMA_EXTRA;
      end
   end

   ST_SEND_DMA_FWD:
   begin
      if (sendReady) begin
         sfw_count <= sfw_count + 10'd1;
         `send_word_swapped <= (sfw_count[0] == 0) ? sendData[31:16] : sendData[15:0];
         if (sfw_count[0] == 1) sendAddr <= sendAddr + 9'd1;
         // sfw_count is in words, sendLen is in bytes
         if (sfw_count == (sendLen[10:1]-10'd1))
            sendState <= ST_SEND_DMA_EXTRA;
      end
   end

   ST_SEND_DMA_EXTRA:
   begin
      if (sendReady) begin
         xcnt <= xcnt + 2'd1;
         `send_word_swapped <= ExtraData[xcnt];
         if (xcnt == 2'd3)
            sendState <= ST_SEND_DMA_FINISH;
      end
   end

   ST_SEND_DMA_FINISH:
   begin
      icmp_read_en <= 0;
      sendAck_rxtx <= 0;
      sendBusy <= 0;
      sendState <= ST_SEND_DMA_IDLE;
   end

   default:
   begin
      ethSendStateError <= 1;
      sendState <= ST_SEND_DMA_IDLE;
   end

   endcase // case (sendState)
end

// Following handles writing to board registers via quadlet or block write.
//
// For FPGA V2 (using KSZ8851),
// the DMA receive process requires 5 sysclk for reading each word (16-bits)
// for a total of 10 sysclk (~200 nsec) per quadlet.
// Thus, quadlet N is available at t = 10*N*sysclk, relative to when the
// first quadlet (N=0) is stored in memory. Note that for a block write,
// the first 5 quadlets are the block write header, which do not get written
// to the registers.
//
// For FPGA V3, data is received from EthRtInterface, which reads from a
// FIFO in EthSwitch, using either sysclk (49.152 MHz, USE_RXTX_CLK=0)
// or RxTxClk (125 MHz, USE_RXTX_CLK=1). It currently uses 4 clocks:
// 2 to read the 2 bytes from the FIFO, and 2 for EthernetIO to process.
// For USE_RXTX_CLK=0, quadlet N is available at t = 8*N*sysclk.
// For USE_RXTX_CLK=1, sysclk is replaced by RxTxClk, which is approximately
// sysclk/2.5 (49.125/125), so we can conservatively use 4*N*sysclk.
//
// The register block write process (below) is timed as follows:
//   4 sysclk (80 nsec) for blk_wstart at beginning
//   1 sysclk (20 nsec) for reg_wen for each quadlet
//   3 sysclk (60 nsec) gap after each quadlet
//   1 sysclk (20 nsec) for blk_wen at end
// Thus, it will start writing the Nth quadlet at
//    t = (4+(1+3)*N)*sysclk = 4(N+1)*sysclk
// relative to when writeRequest is set.
//
// If we want to overlap reading and writing, we need to ensure that the
// reader stays ahead of the writer. We do this by setting the time when
// writeRequest is set; specifically when quadlet M is being stored
// (see writeRequestTrigger).
//
// For FPGA V2 (KSZ8851):
//   10(N-M)*sysclk < 4(N+1)*sysclk
//   M > (3N-2)/5
//
//   This is not the most convenient computationally on an FPGA, so we choose
//   a more conservative bound.
//       3/5 == 1/2 + 1/10 (0.6), which is less than 1/2 + 1/8 - 1/64 = 0.609.
//   Thus, it is sufficient to choose M = N/2 + N/8 - N/64, which can be
//   implemented by shifting and adding/subtracting.
//
// For FPGA V3 (EthRtInterface/EthSwitch):
//   X(N-M)*sysclk < 4(N+1)*sysclk   (X = 4 or 8)
//   M > (N-1)/2  (X = 8)
//   M > 0        (X = 4)
//
//   For X=8, it is sufficient to choose M = N/2, which can easily be implemented
//   in an FPGA (shift by 2). For X=4, we can set M = 0.
//
// The reader actually works with words, rather than quadlets, and has to add the
// length of the block write header. In addition, we add 2 to provide some margin (and
// handle round-off), which leads to the equation above for setting writeRequestTrigger.
//
// Forwarding packets via Firewire has similar timing. The Firewire module requires
// 4 clocks per quadlet, whereas FPGA V2 (KSZ8851) requires 10 clocks and FPGA V3 requires
// 8 clocks (or less, if USE_RXTX_CLK=1). Thus, we can start the Firewire transfer when we
// are M of the way through a packet of size N:
//   FPGA V2:  (N-M)*10 < N*4  --> 6*N < 10*M --> M > (3/5)*N
//   FPGA V3: (N-M)*8 < N*4   --> 4*N < 8*M  --> M > (1/2)*N   (USE_RXTX_CLK=0)
//                                               M > 0         (USE_RXTX_CLK=1)
localparam[2:0]
   BW_IDLE = 3'd0,
   BW_WSTART = 3'd1,
   BW_WRITE = 3'd2,
   BW_WRITE_GAP = 3'd3,
   BW_BLK_WEN = 3'd4,
   BW_WAIT = 3'd5;

reg[2:0] bwState = BW_IDLE;
reg[1:0] bwCnt;
reg bwAddrMain;        // 1 -> real-time block write

always @(posedge sysclk)
begin

   case (bwState)

   BW_IDLE:
   begin
      bwCnt <= 2'd0;
      if (quadWrite & writeRequest) begin
         req_write_bus <= 1'b1;
         reg_waddr <= fw_dest_offset;
         reg_wdata <= fw_quadlet_data;
         reg_wen <= 1;
         blk_wen <= 1;
         if (grant_write_bus) begin
            bw_active_sys <= 1;
            bwState <= BW_WAIT;
         end
      end
      else if (blockWrite & writeRequest) begin
         req_write_bus <= 1'b1;
         local_raddr <= bwStart;
         bwAddrMain <= addrMain;
         // Assert blk_wstart for 80 ns before starting local block write
         // (same timing as in Firewire module).
         // Note that timing can vary if the Ethernet module loses the bus
         // (i.e., is pre-empted by the Firewire module)
         blk_wstart <= 1;
         reg_waddr[15:12] <= fw_dest_offset[15:12];
         // Subtract 1 from the address so that the first increment produces the correct
         // starting address. For the real-time block write, we set it to fff so that
         // the first increment causes it to become 0.
         reg_waddr[11:0] <= addrMain ? 12'hfff : (fw_dest_offset[11:0] - 12'd1);
         if (grant_write_bus) begin
            bw_active_sys <= 1;
            bwState <= BW_WSTART;
         end
      end
      else begin
         bw_active_sys <= 0;
         req_write_bus <= 0;
         reg_wen <= 0;    // Clean up from quadlet/block writes
         blk_wen <= 0;
         blk_wstart <= 0;
      end
   end

   BW_WSTART:
   begin
      if (bwCnt == 2'd3) begin
         blk_wstart <= 1'b0;
         // Stay in this state until we get the write bus
         if (grant_write_bus)
            bwState <= BW_WRITE;
      end
      else
         bwCnt <= bwCnt + 2'd1;
   end

   BW_WRITE:
   begin
      bwCnt <= 2'd1;
      if (grant_write_bus) begin
         local_raddr <= local_raddr + 9'd1;
         reg_waddr[11:0] <= reg_waddr[11:0] + 12'd1;
         reg_wdata <= mem_rdata;
         reg_wen <= 1;
         bwState <= BW_WRITE_GAP;
      end
   end

   BW_WRITE_GAP:
   begin
      // hold reg_wen low for 60 nsec (3 cycles)
      reg_wen <= 1'b0;
      if (bwCnt == 2'd3) begin
         // Stay in this state until we get the write bus
         if (grant_write_bus)
            bwState <= (local_raddr == bwEnd) ? BW_BLK_WEN : BW_WRITE;
      end
      else
         bwCnt <= bwCnt + 2'd1;
   end

   BW_BLK_WEN:
   begin
      // Could enable following line to stop memory access, but
      // it may be safer to keep bw_active set until the entire
      // write process (including blk_wen) is finished.
      // bw_active_sys <= 0;

      // Wait 60 nsec before asserting blk_wen
      if (bwCnt == 2'd3) begin
         blk_wen <= 1'b1;
         if (grant_write_bus)
            bwState <= BW_WAIT;
      end
      else
         bwCnt <= bwCnt + 2'd1;
   end

   BW_WAIT:
   begin
      // Wait for Rx process to clear writeRequest (should not have
      // to wait long, since Rx process clears it as soon as bw_active
      // is asserted).
      req_write_bus <= 1'b0;
      if (~writeRequest)
         bwState <= BW_IDLE;
   end

   default:
   begin
      // Could note this as an error
      bwState <= BW_IDLE;
   end

   endcase // case (bwState)
end

//************ READ *******************

localparam[1:0]
   BR_IDLE = 2'd0,
   BR_HUB_HEADER = 2'd1,
   BR_READ = 2'd2;

reg[1:0] brState = BR_IDLE;

wire timestamp_rd;
assign timestamp_rd = (blk_rt_rd && (reg_raddr[7:0] == 8'd0)) ? 1'd1 : 1'd0;

reg hubSendHeader;       // 1 -> write hub header
wire[31:0] hub_header;   // header quadlet for Hub data block
assign hub_header = { bc_sequence, 8'd0, SZ_BBC_QUADS };

reg[8:0] br_addr_in;
wire[31:0] br_data_in;
reg br_wen;

assign br_data_in = hubSendHeader ? hub_header :
                    timestamp_rd  ? timestamp_latched
                                  : reg_rdata;

if (USE_RXTX_CLK) begin
   DPRAM_32x512_aclk br_packet(.clka(sysclk),
                               .wea(br_wen),
                               .addra(br_addr_in),
                               .dina(br_data_in),
                               .clkb(TxClk),
                               .addrb(sfw_count[9:1]),
                               .doutb(br_data_out)
                              );
end
else begin
   DPRAM_32x512_sclk br_packet(.clka(sysclk),
                               .wea(br_wen),
                               .addra(br_addr_in),
                               .dina(br_data_in),
                               .clkb(sysclk),
                               .addrb(sfw_count[9:1]),
                               .doutb(br_data_out)
                              );
end

always @(posedge sysclk)
begin

   case (brState)

   BR_IDLE:
   begin
      br_addr_in <= 9'd0;
      br_wen <= 1'b0;
      if (br_request) begin
         br_ack <= 1'b1;
         req_read_bus <= 1'b1;
         if (hubSend) begin
            reg_raddr <= { `ADDR_MAIN, 12'd0 };
            hubSendHeader <= 1'b1;
            br_wen <= 1'b1;
            brState <= BR_HUB_HEADER;
         end
         else begin
            reg_raddr <= fw_dest_offset;
            brState <= BR_READ;
         end
      end
      else begin
         req_read_bus <= 1'b0;
         br_ack <= 1'b0;
      end
   end

   BR_HUB_HEADER:
   begin
      hubSendHeader <= 1'b0;
      br_wen <= 1'b0;
      br_addr_in <= 9'd1;
      brState <= BR_READ;
   end

   BR_READ:
   begin
      if (br_wen) begin
         br_wen <= 1'b0;
         if (quadRead ||
             ((blockRead | hubSend) && (br_addr_in == (block_data_length[10:2] - 9'd1)))) begin
            // Release bus after quadlet read or last quadlet of block read
            req_read_bus <= 1'b0;
         end
         else begin
            // 12-bit address increment, even though Firewire limited to 512 quadlets (9 bits)
            // because this way we can support non-zero starting addresses.
            reg_raddr <= reg_raddr + 12'd1;
            br_addr_in <= br_addr_in + 9'd1;
         end
      end
      else if (req_read_bus & grant_read_bus & reg_rvalid) begin
         br_wen <= 1'b1;
      end
      else if ((~req_read_bus) & (~br_request)) begin
         // Wait until br_request cleared (for handshake)
         brState <= BR_IDLE;
      end
   end

   default:
   begin
      // Could note this as an error
      brState <= BR_IDLE;
   end

   endcase // case (brState)
end

endmodule
