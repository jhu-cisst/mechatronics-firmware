/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2019 ERC CISST, Johns Hopkins University.
 *
 * This module implements the higher-level Ethernet I/O, which interfaces
 * to the KSZ8851 MAC/PHY chip.
 *
 * Revision history
 *     12/21/15    Peter Kazanzides    Initial Revision
 *     11/28/16    Zihan Chen          Added Disable/Enable in RECEIVE
 *     11/5/19     Peter Kazanzides    Added UDP support
 * 
 */

// global constant e.g. register & device address
`include "Constants.v"

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
    // global clock and reset
    input wire sysclk,
    input wire reset,

    // board id (rotary switch)
    input wire[3:0] board_id,
    input wire[5:0] node_id,

    // KSZ8851 interrupt
    input wire ETH_IRQn,          // interrupt request

    // Debugging
    output wire[31:16] eth_status,
    input wire sendReq,
    output reg sendAck,
    output reg[6:0] sendAddr,
    input wire[31:0] sendData,
    input wire[15:0] sendLen,
    input wire ksz_isIdle,

    // Register interface
    input  wire[15:0] reg_raddr,
    output wire[31:0] reg_rdata,
    input  wire[31:0] reg_wdata,
    input  wire ip_reg_wen,
    output reg[31:0] ip_address,

    // Interface to/from board registers
    // Ethernet module drives
    input wire[31:0] eth_reg_rdata,
    output reg[15:0] eth_reg_raddr,
    output reg       eth_read_en,
    output reg[31:0] eth_reg_wdata,
    output reg[15:0] eth_reg_waddr,
    output reg       eth_reg_wen,
    output reg       eth_block_wen,
    output reg       eth_block_wstart,

    // Interface to lower layer (KSZ8851)
    input wire initReq,           // 1 -> Chip has been reset; initialization requested
    output reg initAck,           // 1 -> Acknowledge (clear) initReq
    output reg cmdReq,            // 1 -> higher-level requesting a command
    input wire cmdAck,            // 1 -> command accepted (can request next command)
    input wire readValid,         // 1 -> ReadData is valid
    output reg isDMA,             // 1 -> DMA mode active
    output reg isWrite,           // 0 -> Read, 1 -> Write
    output reg isWord,            // 0 -> Byte, 1 -> Word
    output reg[7:0] RegAddr,      // Register address (N/A for DMA mode)
    output reg[15:0] WriteData,   // Data to be written to chip (N/A for read)
    input wire[15:0] ReadData,    // Data read from chip (N/A for write)
    output reg initOK,            // 1 -> Initialization successful
    input wire eth_error,         // 1 -> I/O request received when not in idle state

    output reg lreq_trig,         // trigger signal for a FireWire phy request
    output reg[2:0] lreq_type,    // type of request to give to the FireWire phy

    // Interface to/from FireWire module
    output reg eth_send_fw_req,   // reqest to send firewire packet
    input wire eth_send_fw_ack,   // ack from firewire module
    input  wire[6:0] eth_fwpkt_raddr,
    output wire[31:0] eth_fwpkt_rdata,
    output wire[15:0] eth_fwpkt_len      // eth received fw pkt length

`ifdef USE_CHIPSCOPE
    ,
    // Interface to Chipscope icon
    output wire[6:0] dbg_state_eth,
    output wire[6:0] dbg_nextState_eth,

    // Input debug
    input wire[31:0] dbg_reg_debug
`endif
);

`define ReadDataSwapped {ReadData[7:0], ReadData[15:8]}
`define WriteDataSwapped {WriteData[7:0], WriteData[15:8]}

parameter num_channels = 4;

// Error flags
reg ethIoError;        // 1 -> Ethernet I/O error
reg ethPacketError;    // 1 -> Packet too long, unsupported packet type, IPv4 header error,
                       //      unsupported IPv4 protocol, unexpected UDP port (not 1394)
reg ethDestError;      // 1 -> Incorrect destination (FireWire destination does not begin with 0xFFC)

// Current state and next state
reg[6:0] state;
reg[6:0] nextState;

reg[15:0] numStateInvalid;   // Number of invalid states (for debugging)

`ifdef USE_CHIPSCOPE
assign dbg_state_eth = state;
assign dbg_nextState_eth = nextState;
`endif

// IER value
// B15: LCIE link change interrupt enable
// B14: TXIE transmit interrupt enable
// B13: RXIE receive interrupt enable
`ifdef USE_CHIPSCOPE
`define ETH_VALUE_IER dbg_reg_debug[15:0]
`else
`define ETH_VALUE_IER 16'h2000
`endif

// RXQCR value
// B5: RXFCTE enable QMU frame count threshold (1)
// B4: ADRFE  auto-dequeue
// Not enabling auto-dequeue because we flush packet
// instead of reading to end.
localparam[15:0] ETH_VALUE_RXQCR = 16'h0020;
   
// state machine states
localparam [6:0]
    ST_IDLE = 7'd0,
    ST_WAIT_ACK = 7'd1,
    ST_WAIT_ACK_CLEAR = 7'd2,
    ST_INIT_CHECK_CHIPID = 7'd3,      // Read chip ID
    ST_INIT_WRITE_MAC_LOW = 7'd4,     // Write MAC address low
    ST_INIT_WRITE_MAC_MID = 7'd5,     // Write MAC address middle
    ST_INIT_WRITE_MAC_HIGH = 7'd6,    // Write MAC address high
    ST_INIT_REG_TXFDPR = 7'd7,
    ST_INIT_REG_TXCR = 7'd8,
    ST_INIT_REG_RXFDPR = 7'd9,
    ST_INIT_REG_RXFCTR = 7'd10,
    ST_INIT_REG_RXCR1 = 7'd11,
    ST_INIT_REG_RXCR2 = 7'd12,
    ST_INIT_MULTICAST = 7'd13,
    ST_INIT_REG_RXQCR = 7'd14,
    ST_INIT_IRQ_CLEAR = 7'd15,
    ST_INIT_IRQ_ENABLE = 7'd16,
    ST_INIT_TRANSMIT_ENABLE_READ = 7'd17,
    ST_INIT_TRANSMIT_ENABLE_WRITE = 7'd18,
    ST_INIT_RECEIVE_ENABLE_READ = 7'd19,
    ST_INIT_RECEIVE_ENABLE_WRITE = 7'd20,
    ST_INIT_DONE = 7'd21,
    ST_IRQ_HANDLER = 7'd22,
    ST_IRQ_DISPATCH = 7'd23,
    ST_IRQ_CLEAR_OTHER = 7'd24,
    ST_IRQ_CLEAR_LCIS = 7'd25,
    ST_IRQ_CLEAR_RXIS = 7'd26,
    ST_RECEIVE_FRAME_COUNT = 7'd27,
    ST_RECEIVE_FRAME_STATUS = 7'd28,
    ST_RECEIVE_FRAME_LENGTH = 7'd29,
    ST_RECEIVE_DMA_START = 7'd30,
    ST_RECEIVE_DMA_SKIP = 7'd31,
    ST_RECEIVE_DMA_FRAME_HEADER = 7'd32,
    ST_RECEIVE_DMA_ARP = 7'd33,
    ST_RECEIVE_DMA_IPV4_HEADER = 7'd34,
    ST_RECEIVE_DMA_ICMP_HEADER = 7'd35,
    ST_RECEIVE_DMA_UDP_HEADER = 7'd36,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 7'd37,
    ST_RECEIVE_DMA_FRAME_CRC = 7'd38,
    ST_RECEIVE_FLUSH_START = 7'd39,
    ST_RECEIVE_FLUSH_EXECUTE = 7'd40,
    ST_RECEIVE_FLUSH_WAIT_START = 7'd41,
    ST_RECEIVE_FLUSH_WAIT_CHECK = 7'd42,
    ST_SEND_START = 7'd43,
    ST_SEND_TXMIR_READ = 7'd44,
    ST_SEND_DMA_START = 7'd45,
    ST_SEND_DMA_CONTROLWORD = 7'd46,
    ST_SEND_DMA_BYTECOUNT = 7'd47,
    ST_SEND_DMA_DESTADDR = 7'd48,
    ST_SEND_DMA_SRCADDR = 7'd49,
    ST_SEND_DMA_LENGTH = 7'd50,
    ST_SEND_DMA_ARP = 7'd51,
    ST_SEND_DMA_IPV4_HEADER = 7'd52,
    ST_SEND_DMA_ICMP_HEADER = 7'd53,
    ST_SEND_DMA_UDP_HEADER = 7'd54,
    ST_SEND_DMA_PACKETDATA_HEADER = 7'd55,
    ST_SEND_DMA_PACKETDATA_QUAD = 7'd56,
    ST_SEND_DMA_PACKETDATA_BLOCK_START = 7'd57,
    ST_SEND_DMA_PACKETDATA_BLOCK_MAIN = 7'd58,
    ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL = 7'd59,
    ST_SEND_DMA_PACKETDATA_BLOCK_PROM = 7'd60,
    ST_SEND_DMA_PACKETDATA_CHECKSUM = 7'd61,
    ST_SEND_DMA_FWD = 7'd62,
    ST_SEND_DMA_DUMMY_DWORD = 7'd63,
    ST_SEND_DMA_STOP = 7'd64,
    ST_SEND_TXQ_ENQUEUE_START = 7'd65,
    ST_SEND_TXQ_ENQUEUE_END = 7'd66,
    ST_SEND_TXQ_ENQUEUE_WAIT_START = 7'd67,
    ST_SEND_TXQ_ENQUEUE_WAIT_CHECK = 7'd68,
    ST_SEND_END = 7'd69;


// Debugging support
assign eth_io_isIdle = (state == ST_IDLE) ? 1'b1 : 1'b0;

// Keep track of areas where state machine may wait
// for unknown amount of time (for debugging)
localparam [1:0]
    WAIT_NONE = 0,
    WAIT_ACK = 1,
    WAIT_ACK_CLEAR = 2,
    WAIT_FLUSH = 3;

reg[1:0] waitInfo;

// Following flags are set based on the destination address. Note that
// a FireWire broadcast packet will set both isLocal and isRemote.
wire isLocal;       // 1 -> FireWire packet should be processed locally
wire isRemote;      // 1 -> FireWire packet should be forwarded

wire quadRead;
wire quadWrite;
wire blockRead;
wire blockWrite;

reg isMulticast;
reg isBroadcast;

// Whether to use UDP (1) or raw Ethernet frames (0).
// This mode is set each time a valid packet is received
// (i.e., set if a valid UDP packet received, cleared if
// a valid raw Ethernet frame is received).
reg useUDP;

// Following flags have limited duration (set and cleared
// during packet processing).
reg sendARP;
reg isUDP;
reg isICMP;
reg sendEcho;

// Data received in ICMP Echo packet (ping)
reg[15:0] echo_id;
reg[15:0] echo_seq;
reg[31:0] echo_payload;

wire[17:0] icmp_checksum;
assign icmp_checksum = {2'd0, echo_id} + {2'd0, echo_seq} + {2'd0, echo_payload[31:16]} + {2'd0, echo_payload[15:0]};

reg ipv4_long;  // IP frame longer than default (ok)
reg ipv4_short; // IP frame too short (error)

// Ethernet status:
//   Bit 31: 1 to indicate that Ethernet is present -- must be kept for backward compatibility
//   Bit 30: 1 to indicate that an error occurred in KSZ8851 -- must be kept for backward compatibility
//   Other fields can be assigned as needed
assign eth_status[31] = 1'b1;            // 31: 1 -> Ethernet is present
assign eth_status[30] = eth_error;       // 30: 1 -> error occurred
assign eth_status[29] = initOK;          // 29: 1 -> Initialization OK
assign eth_status[28] = initReq;         // 28: 1 -> Reset executed, init requested
assign eth_status[27] = ethIoError;      // 27: 1 -> ethernet I/O error (higher layer)
assign eth_status[26] = ethPacketError;  // 26: 1 -> ethernet packet too long (higher layer)
assign eth_status[25] = ethDestError;    // 25: 1 -> ethernet destination error (higher layer)
//assign eth_status[26] = cmdReq;          // 26: 1 -> command requested by higher level
//assign eth_status[25] = cmdAck;          // 25: 1 -> command acknowledged by lower level
//assign eth_status[26] = isLocal;         // 26: 1 -> command requested by higher level
//assign eth_status[25] = isRemote;        // 25: 1 -> command acknowledged by lower level
assign eth_status[24] = quadRead;        // 24: quadRead (debugging)
assign eth_status[23] = quadWrite;       // 23: quadWrite (debugging)
assign eth_status[22] = blockRead;       // 22: blockRead (debugging)
assign eth_status[21] = blockWrite;      // 21: blockWrite (debugging)
//assign eth_status[20] = isMulticast;   // 20: multicast received
assign eth_status[20] = useUDP;          // 20: multicast received
assign eth_status[19] = ksz_isIdle;      // 19: KSZ8851 state machine is idle
assign eth_status[18] = eth_io_isIdle;   // 18: Ethernet I/O state machine is idle
assign eth_status[17:16] = waitInfo;     // 17-16: Wait points in EthernetIO.v


reg isInIRQ;           // True if IRQ handle routing
reg[15:0] RegISR;      // 16-bit ISR register
reg[15:0] RegISROther; // Unexpected ISR value (for debugging)
reg[7:0] FrameCount;   // Number of received frames
reg[7:0] count;        // General use counter
reg[3:0] readCount;    // Wait for read valid
reg[7:0] maxCount;     // For reading FireWire packets
reg[2:0] next_addr;    // Address of next device (for block read)
reg[6:0] block_index;  // Index into data block (5-70)
reg[15:0] txPktWords;  // Num of words sent
reg[11:0] rxPktWords;  // Num of words received

reg[15:0] destMac[0:2];  // Not currently used
reg[15:0] srcMac[0:2];
reg[15:0] LengthFW;        // fw packet length in bytes
assign eth_fwpkt_len = LengthFW;

reg[31:0] hostIP;       // IP address of host (PC)
reg[31:0] fpgaIP;       // tentative IP address of FPGA (will compare to ip_address)
reg[15:0] hostPort;     // UDP port number for host (PC)

reg[15:0] ipv4_length;    // Length field of IPv4 header (not currently used)
reg[18:0] ipv4_checksum;  // Checksum for IPv4 header

reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[15:0] numPacketInvalid;  // Number of invalid Ethernet frames received
reg[15:0] numIPv4;           // Number of IPv4 packets received
reg[15:0] numUDP;            // Number of UDP packets received
reg[15:0] numARP;            // Number of ARP packets received
reg[15:0] numICMP;           // Number of ICMP packets received
reg[15:0] numPacketError;    // Number of packet errors
reg[15:0] numIPv4Mismatch;   // Number of IPv4 packets with different IP address

localparam[31:0] IP_UNASSIGNED = 32'hffffffff;
wire is_ip_unassigned;
assign is_ip_unassigned = (ip_address == IP_UNASSIGNED) ? 1 : 0;

// Following checks whether IP address received in packet (fpgaIP) is equal
// to stored IP address (ip_address). Note that it is assumed that this check
// will be performed when the LSW of the IP address is being read, which is
// why ReadData is used below.
wire is_ip_equal;
assign is_ip_equal = (ip_address == {ReadData, fpgaIP[31:16]}) ? 1 : 0;

// ----------------------------------------
// Forward forward packet
// ----------------------------------------
reg isForward;

wire [31:0] DebugData[0:31];
assign DebugData[0]  = "0GBD";  // DBG0 byte-swapped
assign DebugData[1]  = timestamp;
assign DebugData[2]  = {11'd0, node_id, eth_status};
assign DebugData[3]  = { 1'd0, state, 1'd0, nextState, 4'h0, FireWirePacketFresh, isBroadcast, isMulticast, ~ETH_IRQn,
                         isForward, isInIRQ, sendARP, isUDP, isICMP, sendEcho, ipv4_long, ipv4_short};
assign DebugData[4]  = { RegISR, RegISROther};
assign DebugData[5]  = { 16'h2233, FrameCount, count};
assign DebugData[6]  = { destMac[1][7:0], destMac[1][15:8], destMac[0][7:0], destMac[0][15:8] };
assign DebugData[7]  = { srcMac[0], destMac[2][7:0], destMac[2][15:8] };
assign DebugData[8]  = { srcMac[2], srcMac[1] };
assign DebugData[9]  = { 8'h11, maxCount, LengthFW };
assign DebugData[10]  = { hostIP[15:0], hostIP[31:16] };
assign DebugData[11] = { fpgaIP[15:0], fpgaIP[31:16] };
assign DebugData[12] = { ipv4_length, 4'h0, rxPktWords };
assign DebugData[13] = { 16'h4455, txPktWords };
assign DebugData[14] = { numPacketInvalid, numPacketValid };
assign DebugData[15] = { numUDP, numIPv4 };
assign DebugData[16] = { numICMP, numARP };
assign DebugData[17] = { numIPv4Mismatch, numPacketError };
assign DebugData[18] = { 16'd0, numStateInvalid };
assign DebugData[19] = timestamp;


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


// Following data is accessible via block read from address `ADDR_ETH (0x4000)
//    Maximum block read size is 64 quadlets (implementation choice)
//    4000 - 4007f (128 quadlets) FireWire packet
//    4080 - 4009f (32 quadlets) Debug data
// Note that full address decoding is not done, so other addresses will work too
// (for example, 40c0-40cf will also give Debug data, as will 4f80-4f9f)
assign reg_rdata = (reg_raddr[7] == 0) ? FireWirePacket[reg_raddr[6:0]] : DebugData[reg_raddr[4:0]];

wire[3:0] fw_tcode;            // FireWire transaction code
wire[5:0] fw_tl;               // FireWire transaction label
wire[15:0] block_data_length;  // Data length (in bytes) for block read/write requests

assign fw_tl = FireWirePacket[0][15:10];
assign fw_tcode = FireWirePacket[0][7:4];
assign block_data_length = FireWirePacket[3][31:16];

// Valid destination address
wire valid_dest_id;
assign valid_dest_id = (FireWirePacket[0][31:20] == 12'hFFC) ? 1'd1 : 1'd0;
wire[5:0] dest_node_id;
assign dest_node_id = FireWirePacket[0][21:16];

// wire[3:0] dest_board;
// assign dest_board = FireWirePacket[0][19:16];
// assign isLocal = isMulticast || (dest_board == board_id) || (dest_board == 4'hf);
// assign isRemote = (dest_board != board_id) && (~isMulticast);

// Local write if Ethernet broadcast or multicast, addresses this board, or FireWire broadcast
// Note: maybe use 8'hff for FireWire broadcast
assign isLocal = isMulticast || isBroadcast || (dest_node_id == node_id) || (dest_node_id == 6'h3f);
// TODO: Might be useful to forward some multicast or broadcast packets
assign isRemote = (dest_node_id != node_id) && ~(isMulticast||isBroadcast);

assign quadRead = (fw_tcode == `TC_QREAD) ? 1'd1 : 1'd0;
assign quadWrite = (fw_tcode == `TC_QWRITE) ? 1'd1 : 1'd0;
assign blockRead = (fw_tcode == `TC_BREAD) ? 1'd1 : 1'd0;
assign blockWrite = (fw_tcode == `TC_BWRITE) ? 1'd1 : 1'd0;

assign addrMain = (FireWirePacket[2][15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;
assign addrHub = (FireWirePacket[2][15:12] == `ADDR_HUB) ? 1'd1 : 1'd0;
assign addrPROM = (FireWirePacket[2][15:12] == `ADDR_PROM) ? 1'd1 : 1'd0;
assign addrQLA  = (FireWirePacket[2][15:12] == `ADDR_PROM_QLA) ? 1'd1 : 1'd0;


// TEMP: Timestamp copied from Firewire.v -- should consolidate
reg[31:0]  timestamp;          // timestamp counter register
reg ts_reset;                 // timestamp counter reset signal
// -------------------------------------------------------
// Timestamp
// -------------------------------------------------------
// timestamp counts number of clocks between block reads
always @(posedge(sysclk) or posedge(ts_reset) or negedge(reset))
begin
    if (reset==0 || ts_reset)
        timestamp <= 0;
    else
        timestamp <= timestamp + 1'b1;
end


// -------------------------------------------------------
// Ethernet state machine
// -------------------------------------------------------
always @(posedge sysclk or negedge reset) begin
    if (reset == 0) begin
       cmdReq <= 0;
       isDMA <= 0;
       isWrite <= 0;
       isWord <= 1;   // all transfers are word
       isInIRQ <= 0;
       state <= ST_IDLE;
       nextState <= ST_IDLE;
       initAck <= 0;
       initOK <= 0;
       ethIoError <= 0;
       ethPacketError <= 0;
       ethDestError <= 0;
       isMulticast <= 0;
       isBroadcast <= 0;
       sendAck <= 0;
       ip_address <= IP_UNASSIGNED;
       srcMac[0] <= 16'd0;
       srcMac[1] <= 16'd0;
       srcMac[2] <= 16'd0;
       LengthFW <= 16'd0;
       eth_read_en <= 0;
       eth_reg_wen <= 0;
       eth_block_wen <= 0;
       eth_block_wstart <= 0;
       ts_reset <= 0;
       waitInfo <= WAIT_NONE;
       lreq_trig <= 0;
       lreq_type <= 0;
       block_index <= 0;
       eth_send_fw_req <= 0;
       useUDP <= 0;
       sendARP <= 0;
       isUDP <= 0;
       isICMP <= 0;
       sendEcho <= 0;
       isForward <= 0;
       ipv4_long <= 0;
       ipv4_short <= 0;
       RegISROther <= 16'd0;
       numPacketValid <= 16'd0;
       numPacketInvalid <= 16'd0;
       numIPv4 <= 16'd0;
       numUDP <= 16'd0;
       numARP <= 16'd0;
       numICMP <= 16'd0;
       numIPv4Mismatch <= 16'd0;
       numPacketError <= 16'd0;
       numStateInvalid <= 16'd0;
       FireWirePacketFresh <= 0;
    end
    else begin

       // Clear eth_send_fw_req flag
       if (eth_send_fw_req && eth_send_fw_ack) begin
          eth_send_fw_req <= 1'd0;
       end

       if (sendAck && !sendReq) begin
          sendAck <= 1'd0;
       end

       if (ip_reg_wen) begin
          ip_address <= reg_wdata;
       end

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
            if (initReq) begin
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_CIDER;  // Read Chip ID
               state <= ST_WAIT_ACK;
               nextState <= ST_INIT_CHECK_CHIPID;
               initAck <= 1;
               initOK <= 0;
               ethIoError <= 0;
               ethPacketError <= 0;
               ethDestError <= 0;
            end
            else if (~ETH_IRQn) begin
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_ISR;
               state <= ST_WAIT_ACK;
               nextState <= ST_IRQ_HANDLER;
            end
            else if (sendReq) begin
               // forward packet from FireWire
               state <= ST_SEND_START;
               isForward <= 1;
               sendAck <= 1;
            end
         end

         ST_WAIT_ACK:
         begin
            if (initReq && !initAck)
               state <= ST_IDLE;
            // else if (cmdAck && cmdReq) begin
            //    cmdReq <= 0;
            //    state <= ST_WAIT_ACK_CLEAR;
            //    readCount <= 4'd0;
            //    if (isWrite && isDMA) begin
            //       txPktWords <= txPktWords + 16'd1;
            //    end
            // end
            else if (cmdAck) begin
               cmdReq <= 0;
               state <= ST_WAIT_ACK_CLEAR;
               readCount <= 4'd0;
               if (isWrite && isDMA) begin
                  txPktWords <= txPktWords + 16'd1;
               end
            end
            else if (!cmdReq) begin
               state <= ST_WAIT_ACK_CLEAR;
               readCount <= 4'd0;
            end
            else begin
               waitInfo <= WAIT_ACK;
            end
         end

         ST_WAIT_ACK_CLEAR:
         begin
            if (initReq && !initAck)
               state <= ST_IDLE;
            // else if (!cmdAck && !cmdReq) begin
            else if (~cmdAck) begin
               if (isWrite || readValid) begin
                   state <= nextState;
                   waitInfo <= WAIT_NONE;
               end
               else begin
                  // Shouldn't take more than 12 cycles to read data.
                  if (readCount == 4'hf) begin
                     ethIoError <= 1;
                     // Moving to IDLE state may not be the best action,
                     // since there may be some cleanup needed, such as
                     // getting out of DMA mode.
                     state <= ST_IDLE;
                     waitInfo <= WAIT_NONE;
                  end
                  readCount <= readCount + 4'd1;
               end
            end
            else begin
               waitInfo <= WAIT_ACK_CLEAR;
            end
         end
         
         //*************** States for initializing Ethernet ******************

         ST_INIT_CHECK_CHIPID:
         begin
            initAck <= 0;   // By now, it is fine to finish acknowledgement of init request
            if (ReadData[15:4] == 12'h887) begin
               // Chip ID is ok, go to next state
               // (could have started next state here, but code would be less readable)
               state <= ST_INIT_WRITE_MAC_LOW;
            end
            else begin
               initOK <= 0;
               state <= ST_IDLE;
            end
         end
         
         ST_INIT_WRITE_MAC_LOW:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_MARL;        // MAC address low
            WriteData <= {12'h940,board_id};  //   0x940n (n = board id)
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_WRITE_MAC_MID;
         end

         ST_INIT_WRITE_MAC_MID:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_MARM;        // MAC address mid
            WriteData <= 16'h0E13;  //   0x0E13
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_WRITE_MAC_HIGH;
         end
         
         ST_INIT_WRITE_MAC_HIGH:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_MARH;       // MAC address high
            WriteData <= 16'hFA61;  //   0xFA61
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_TXFDPR;
         end
              
         ST_INIT_REG_TXFDPR:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_TXFDPR;
            WriteData <= 16'h4000;   // Enable QMU transmit frame data pointer auto increment
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_TXCR;
         end

         ST_INIT_REG_TXCR:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_TXCR;
            WriteData <= 16'h00EE;   // Enable QMU transmit flow control, CRC, and padding
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_RXFDPR;
         end

         ST_INIT_REG_RXFDPR:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_RXFDPR;
            // B14: Enable QMU receive frame data pointer auto increment
            // B12: Decrease write data valid sample time to 4 nS (max)
            //      TODO: Try setting this bit to 0 to increase sample time to 8-16 ns
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
            WriteData <= 16'h5000;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_RXFCTR;
         end

         ST_INIT_REG_RXFCTR:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_RXFCTR;
            WriteData <= 16'h0001;   // Configure receive frame threshold for 1 frame
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_RXCR1;
         end

         ST_INIT_REG_RXCR1:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_RXCR1;
            // 7: enable UDP, TCP, and IP checksums
            // C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
            // E: enable broadcast, multicast, and unicast
            // Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
            WriteData <= 16'h7CE0;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_RXCR2;
         end

         ST_INIT_REG_RXCR2:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_RXCR2;
            WriteData <= 16'h001C;  // Enable UDP checksums; pass packets with 0 checksum
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_MULTICAST;
         end

         ST_INIT_MULTICAST:
         begin
            cmdReq <= 1;
            // Following are hard-coded values for which hash register to use and which bit to set
            // for multicast address FB:61:0E:13:19:FF. This is obtained by computing the CRC for
            // this MAC address and then using the first two (most significant) bits to determine
            // the register and the next four bits to determine which bit to set.
            // See code in mainEth1394.cpp.
            RegAddr <= `ETH_ADDR_MAHTR1;   // MAHTR1
            WriteData <= 16'h0008;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_RXQCR;
         end

         ST_INIT_REG_RXQCR:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= ETH_VALUE_RXQCR;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_IRQ_CLEAR;
         end

         ST_INIT_IRQ_CLEAR:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_ISR;
            WriteData <= 16'hFFFF;   // Clear all pending interrupts
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_IRQ_ENABLE;
         end

         ST_INIT_IRQ_ENABLE:
         begin
            cmdReq <= 1;
            RegAddr <= `ETH_ADDR_IER;
            WriteData <= `ETH_VALUE_IER;   // Enable receive interrupts
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_TRANSMIT_ENABLE_READ;
         end

         ST_INIT_TRANSMIT_ENABLE_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_TXCR;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_TRANSMIT_ENABLE_WRITE;
         end

         ST_INIT_TRANSMIT_ENABLE_WRITE:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_RECEIVE_ENABLE_READ;
         end

         ST_INIT_RECEIVE_ENABLE_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_RXCR1;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_RECEIVE_ENABLE_WRITE;
         end

         ST_INIT_RECEIVE_ENABLE_WRITE:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_DONE;
         end

         ST_INIT_DONE:
         begin
            initOK <= 1;
            sendARP <= 0;
            isUDP <= 0;
            isICMP <= 0;
            sendEcho <= 0;
            isMulticast <= 0;
            isBroadcast <= 0;
            ipv4_long <= 0;
            ipv4_short <= 0;
            RegISROther <= 16'd0;
            isForward <= 0;
            numPacketValid <= 16'd0;
            numPacketInvalid <= 16'd0;
            numIPv4 <= 16'd0;
            numUDP <= 16'd0;
            numARP <= 16'd0;
            numICMP <= 16'd0;
            numIPv4Mismatch <= 16'd0;
            numPacketError <= 16'd0;
            numStateInvalid <= 16'd0;
            FireWirePacketFresh <= 0;
            state <= ST_IDLE;
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
                // Handle link change
                state <= ST_IRQ_CLEAR_LCIS;
            end
            else if (RegISR[13] == 1'b1) begin
                // Handle receive
                state <= ST_IRQ_CLEAR_RXIS;
            end
            else begin
               // Done IRQ handle, clear flag
               isInIRQ <= 0;
               // ST_IRQ_CLEAR_OTHER will clear any other (unexpected) interrupts;
               // if no pending interrupts, will go to ST_IDLE.
               state <= ST_IRQ_CLEAR_OTHER;
            end
         end

         ST_IRQ_CLEAR_OTHER:
         begin
            if (RegISR[14] || RegISR[11] || RegISR[9] || RegISR[8] || RegISR[6]) begin
               // These interrupts are not handled and are disabled, so clear them
               // if they somehow occurred.
               cmdReq <= 1;
               isWrite <= 1;
               RegAddr <= `ETH_ADDR_ISR;
               WriteData <= RegISR&16'b0100101101000000;    // Clear interrupts
               RegISR    <= RegISR&16'b1011010010111111;    // Clear RegISR bits
               state <= ST_WAIT_ACK;
               nextState <= ST_IRQ_CLEAR_OTHER;   // Return to this state in case other bits set
            end
            else if (RegISR[5] || RegISR[4] || RegISR[3] || RegISR[2]) begin
               // These interrupts are also not handled and are disabled, but are
               // cleared differently (by writing to PMECR)
               cmdReq <= 1;
               isWrite <= 1;
               RegAddr <= `ETH_ADDR_PMECR;
               WriteData <= RegISR&16'h003c;    // Clear interrupts
               RegISR    <= RegISR&16'hffc3;    // Clear RegISR bits
               state <= ST_WAIT_ACK;
               nextState <= ST_IDLE;
            end
            else begin
               state <= ST_IDLE;
            end
         end

         ST_IRQ_CLEAR_LCIS:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_ISR;
            WriteData <= 16'h8000;    // Clear interrupt
            RegISR[15] <= 1'b0;       // Clear RegISR
            state <= ST_WAIT_ACK;
            nextState <= ST_IRQ_DISPATCH;
         end

         //*************** States for receiving Ethernet packets ******************
         ST_IRQ_CLEAR_RXIS:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_ISR;
            WriteData <= 16'h2000;  // clear interrupt
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FRAME_COUNT;
            count <= 8'd0;
            RegISR[13] <= 1'b0;   // clear ISR receive IRQ bit
         end

         ST_RECEIVE_FRAME_COUNT:
         begin
            if (count[0] == 1'b0) begin
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_RXFCTR;
               state <= ST_WAIT_ACK;
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
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= `ETH_ADDR_RXFHSR;
               state <= ST_WAIT_ACK;
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
                  isMulticast <= 0;
                  isBroadcast <= 0;
                  numPacketInvalid <= numPacketInvalid + 16'd1;
                  state <= ST_RECEIVE_FLUSH_START;
               end
               else begin
                  // Valid frame, so start processing
                  cmdReq <= 1;
                  isBroadcast <= ReadData[7];
                  isMulticast <= ReadData[6];
                  isWrite <= 0;
                  RegAddr <= `ETH_ADDR_RXFHBCR;
                  state <= ST_WAIT_ACK;
                  nextState <= ST_RECEIVE_FRAME_LENGTH;
                  numPacketValid <= numPacketValid + 16'd1;
               end
            end
         end

         ST_RECEIVE_FRAME_LENGTH:
         begin
            if (ReadData[11:0] == 12'd0) begin
               numPacketInvalid <= numPacketInvalid + 16'd1;
               state <= ST_RECEIVE_FLUSH_START;
            end
            else begin
                rxPktWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
                // Set QMU RXQ frame pointer to 0, also decrease write sample time
                cmdReq <= 1;
                isWrite <= 1;
                RegAddr <= `ETH_ADDR_RXFDPR;
                WriteData <= 16'h5000;
                state <= ST_WAIT_ACK;
                nextState <= ST_RECEIVE_DMA_START;
            end
         end

         ST_RECEIVE_DMA_START:
         begin
            // Enable DMA transfers
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_SKIP;
            count <= 8'd0;
         end

         ST_RECEIVE_DMA_SKIP:
         begin
            // Skip first 3 words in the packet
            // ignore(1) + status(1) + byte-count(1)
            cmdReq <= 1;
            isDMA <= 1;
            isWrite <= 0;
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd3) begin
               nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
               count[1:0] <= 2'd0;
               rxPktWords <= rxPktWords-12'd1;
            end
            else begin
               nextState <= ST_RECEIVE_DMA_SKIP;
               count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_RECEIVE_DMA_FRAME_HEADER:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
            count[2:0] <= count[2:0]+3'd1;
            rxPktWords <= rxPktWords-12'd1;
            // Read dest MAC, source MAC, and length (7 words, byte-swapped).
            // Don't byte swap srcMAC because we need to send it back byte-swapped.
            // 
            case (count[2:0])
              3'd0: destMac[0] <= `ReadDataSwapped;
              3'd1: destMac[1] <= `ReadDataSwapped;
              3'd2: destMac[2] <= `ReadDataSwapped;
              3'd3: srcMac[0] <= ReadData;
              3'd4: srcMac[1] <= ReadData;
              3'd5: srcMac[2] <= ReadData;
            endcase
            if (count[2:0] == 3'd6) begin
               // Maximum data length is currently 284 bytes (block write to PROM); as a sanity
               // check, we flush any packets greater than 512 bytes in length.
               if (`ReadDataSwapped[15:9] == 7'd0) begin
                  nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
                  // Set up maxCount based on number of words (numBytes/2-1).
                  // Note that this can be larger than the current buffer size (142 words or 71 quadlets),
                  // but later on we have a check to prevent buffer overflow.
                  maxCount <= `ReadDataSwapped[8:1]-8'd1;
                  LengthFW <= `ReadDataSwapped;
               end
               else if (`ReadDataSwapped == 16'h0800) begin
                  // IPv4 Ethertype is 0x0800
                  nextState <= ST_RECEIVE_DMA_IPV4_HEADER;
                  numIPv4 <= numIPv4 + 16'd1;
                  // Default value of maxCount (IPv4 header has at least 10 words)
                  maxCount[4:0] <= 5'd9;
               end
               else if (`ReadDataSwapped == 16'h0806) begin
                  // ARP Ethertype is 0x0806
                  numARP <= numARP + 16'd1;
                  nextState <= ST_RECEIVE_DMA_ARP;
               end
               else begin
                  // Unsupported EtherType (or length greater than 512 bytes)
                  ethPacketError <= 1;
                  numPacketError <= numPacketError + 16'd1;
                  state <= ST_RECEIVE_FLUSH_START;
               end
               count <= 8'd0;
            end
         end

         ST_RECEIVE_DMA_IPV4_HEADER:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            count[4:0] <= count[4:0]+5'd1;
            rxPktWords <= rxPktWords-12'd1;
            case (count[4:0])
               // Word 0:
               //   Byte 0: Version, should be 4; IHL (Internet Header Length), normally should be 5
               //   Byte 1: DSCP and ECN (ignore those)
               5'd0: begin
                     if (ReadData[7:4] != 4'h4) begin
                        ethPacketError <= 1;
                        numPacketError <= numPacketError + 16'd1;
                        state <= ST_RECEIVE_FLUSH_START;
                     end
                     else begin
                        // Set up maxCount based on number of words (2*IHL-1).
                        // Note that IHL is normally 5 (its minimum value), in which case maxCount
                        // was already set to 9. The following conditional is an efficient alternative
                        // to (ReadData[3:0] > 5).
                        if ((ReadData[3] == 2'b1) || (ReadData[2:1] == 2'b11)) begin
                           ipv4_long <= 1;   // This is ok, though not typical (IHL usually is 5)
                           maxCount[4:0] <= {ReadData[3:0],1'd0}-5'd1;
                        end
                        else if (ReadData[3:0] != 4'd5)
                           ipv4_short <= 1;  // This should not happen
                     end
                     end
               // Word 1: Total Length (not currently used)
               5'd1: ipv4_length <= `ReadDataSwapped;
               // Word 2: Identification=0 (ignored)
               // Word 3: Flags=0, Fragment Offset=0 (ignored)
               // Word 4:
               //   Byte 0: Time To Live (ignore)
               //   Byte 1: Protocol (UDP is 17, ICMP is 1)
               5'd4: begin
                     if (ReadData[11:8] == 4'd17) begin
                        isUDP <= 1;
                     end
                     else if (ReadData[11:8] == 4'd1) begin
                        isICMP <= 1;
                     end
                     else begin
                        ethPacketError <= 1;
                        numPacketError <= numPacketError + 16'd1;
                        state <= ST_RECEIVE_FLUSH_START;
                     end
                     end
               // Word 5: Header checksum (ignored, for now)
               // Word 6,7: Source IP address (host)
               // Word 8,9: Destination IP address (fpga)
               // Keep the IP addresses byteswapped, since we will need
               // to send them back to the PC.
               5'd6: hostIP[31:16] <= ReadData;
               5'd7: hostIP[15:0] <= ReadData;
               5'd8: fpgaIP[31:16] <= ReadData;
               5'd9: begin
                     fpgaIP[15:0] <= ReadData;
                     if (is_ip_unassigned) begin
                        // This case can occur when the host PC already has
                        // an ARP cache entry for this board, in which case
                        // we just assign the IP address.
                        ip_address[31:16] <= ReadData;
                        ip_address[15:0] <=  fpgaIP[31:16];
                     end
                     else if (!(is_ip_equal || isBroadcast || isMulticast)) begin
                        // If IP assigned, but not equal, we process the packet anyway,
                        // but keep track of the number of times this occurred.
                        // We could decide to update ip_address.
                        numIPv4Mismatch <= numIPv4Mismatch + 16'd1;
                     end
                     end
            endcase
            if (count[4:0] == maxCount[4:0]) begin
               // Reached end of IPv4 header
               if (isUDP) begin
                  numUDP <= numUDP + 16'd1;
                  nextState <= ST_RECEIVE_DMA_UDP_HEADER;
                  count[4:0] <= 5'd0;
               end
               else if (isICMP) begin
                  numICMP <= numICMP + 16'd1;
                  nextState <= ST_RECEIVE_DMA_ICMP_HEADER;
                  count[4:0] <= 5'd0;
                  isICMP <= 0;
               end
               else begin
                  // Should never get here since 5'd4 case flushes packet
                  // if not UDP or ICMP.
                  ethPacketError <= 1;
                  numPacketError <= numPacketError + 16'd1;
                  state <= ST_RECEIVE_FLUSH_START;
               end
            end
            else begin
               nextState <= ST_RECEIVE_DMA_IPV4_HEADER;
            end
         end

         ST_RECEIVE_DMA_ICMP_HEADER:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_ICMP_HEADER;
            count[2:0] <= count[2:0] + 3'd1;
            rxPktWords <= rxPktWords-12'd1;
            // Only handles echo (ping). Echo request has Type=8, Code=0
            case (count[2:0])
              3'd0: if (`ReadDataSwapped != 16'h0800) state <= ST_RECEIVE_FLUSH_START;
              3'd2: echo_id <= ReadData;
              3'd3: echo_seq <= ReadData;
              3'd4: echo_payload[31:16] <= ReadData;
              3'd5: begin
                    echo_payload[15:0] <= ReadData;
                    count[2:0] <= 3'd0;
                    sendEcho <= 1;
                    state <= ST_RECEIVE_FLUSH_START;
                    end
            endcase
         end

         ST_RECEIVE_DMA_UDP_HEADER:
         // Word 0:  Source port
         // Word 1:  Destination port
         // Word 2:  Length
         // Word 3:  Checksum
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_UDP_HEADER;
            count[1:0] <= count[1:0] + 2'd1;
            rxPktWords <= rxPktWords-12'd1;
            if (count[1:0] == 2'd0) begin
               hostPort <= ReadData;
            end
            else if (count[1:0] == 2'd1) begin
               // Make sure destination port is 1394
               if ({ReadData[7:0],ReadData[15:8]} != 16'd1394) begin
                  isUDP <= 0;
                  ethPacketError <= 1;
                  numPacketError <= numPacketError + 16'd1;
                  state <= ST_RECEIVE_FLUSH_START;
               end
            end
            else if (count[1:0] == 2'd2) begin
               maxCount <= `ReadDataSwapped[8:1]-8'd5;  // Subtract 4 words for UDP header
               LengthFW <= `ReadDataSwapped-8'd8;       // Subtract 8 bytes for UDP header
            end
            else if (count[1:0] == 2'd3) begin
               nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
               count[1:0] <= 2'd0;
            end
         end

         ST_RECEIVE_DMA_FIREWIRE_PACKET:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
            count <= count + 8'd1;
            rxPktWords <= rxPktWords-12'd1;

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
               isUDP <= 0;
               ethDestError <= 1;
               cmdReq <= 0;
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

            if (count == maxCount) begin
               // normal completion
               FireWirePacketFresh <= 1;
               useUDP <= isUDP;
               isUDP <= 0;
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
               end
            end
            else if (count[7:0] == 8'hff) begin
               // packet too long; stop here to avoid buffer overflow
               isUDP <= 0;
               ethPacketError <= 1;
               numPacketError <= numPacketError + 16'd1;
               cmdReq <= 0;
               state <= ST_RECEIVE_FLUSH_START;
            end

            // Remaining contents of block write (for count=13...maxCount)
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

         ST_RECEIVE_DMA_ARP:
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
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            count[3:0] <= count[3:0]+4'd1;
            rxPktWords <= rxPktWords-12'd1;
            case (count[3:0])
               4'd0: if (ReadData != 16'h0100) state <= ST_RECEIVE_FLUSH_START;
               4'd1: if (ReadData != 16'h0008) state <= ST_RECEIVE_FLUSH_START;
               4'd2: if (ReadData != 16'h0406) state <= ST_RECEIVE_FLUSH_START;
               4'd3: if (ReadData != 16'h0100) state <= ST_RECEIVE_FLUSH_START;
               4'd4: srcMac[0] <= ReadData;
               4'd5: srcMac[1] <= ReadData;
               4'd6: srcMac[2] <= ReadData;
               4'd7: hostIP[31:16] <= ReadData;
               4'd8: hostIP[15:0] <= ReadData;
               4'd12: fpgaIP[31:16] <= ReadData;
               4'd13: begin
                      // Normal completion
                      fpgaIP[15:0] <= ReadData;
                      // If our IP address not yet set, update it
                      if (is_ip_unassigned) begin
                         ip_address[31:16] <= ReadData;
                         ip_address[15:0] <=  fpgaIP[31:16];
                         sendARP <= 1;
                      end
                      else if (is_ip_equal) begin
                         sendARP <= 1;
                      end
                      count[3:0] <= 4'd0;
                      state <= ST_RECEIVE_DMA_FRAME_CRC;
                      end
            endcase
         end

         ST_RECEIVE_DMA_FRAME_CRC:
         begin
            // We could read two words to get the 4-byte CRC, but flushing the
            // packet works better. We decrement rxPktWords by 2, but that
            // variable is just for debugging. In most cases, rxPktWords should
            // be 0 after this -- the exception is when the packet is smaller than
            // the minimum Ethernet frame (64 bytes), in which case it is padded
            // (this happens with raw Ethernet quadlet read/write commands).
            rxPktWords <= rxPktWords-12'd2;
            state <= ST_RECEIVE_FLUSH_START;
         end

         ST_RECEIVE_FLUSH_START:
         begin
            // Clean up from quadlet/block writes
            eth_reg_wen <= 0;
            eth_block_wen <= 0;
            // Move on to the next state
            cmdReq <= 1;
            isDMA <= 0;
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_RXQCR;  // Could probably eliminate this read
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_EXECUTE;
         end

         ST_RECEIVE_FLUSH_EXECUTE:
         begin
            // Flush the rest of the packet (also clears DMA bit)
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_WAIT_START;
         end

         ST_RECEIVE_FLUSH_WAIT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            // RegAddr is already set to RXQCR
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_WAIT_CHECK;
         end

         ST_RECEIVE_FLUSH_WAIT_CHECK:
         begin
            // Wait for bit 0 in Register RXQCR to be cleared;
            // Then enable interrupt
            //   - if a read command, start sending response
            //     (check FrameCount after send complete)
            //   - else if more frames available, receive status of next frame
            //   - else go to idle state
            // TODO: check node id and forward via FireWire if necessary
            if (ReadData[0] == 1'b0) begin
               if ((FireWirePacketFresh && (quadRead || blockRead) && isLocal) || sendARP || sendEcho) begin
                  state <= ST_SEND_START;
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
               state <= ST_RECEIVE_FLUSH_WAIT_START;
               waitInfo <= WAIT_FLUSH;
            end
         end

         //*************** States for sending Ethernet packets ******************
         // First, should check if enough memory on QMU TXQ

         ST_SEND_START:
         begin
            if (isInIRQ == 1'b0) begin
               sendAck <= 0;  // TEMP
            end
            state <= ST_SEND_TXMIR_READ;
            // Reset pkt words count
            txPktWords <= 16'd0;
         end

         ST_SEND_TXMIR_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_TXMIR;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_START;
         end

         ST_SEND_DMA_START:  // same as ST_RECEIVE_DMA_START
         begin
            // Enable DMA transfers
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= `ETH_ADDR_RXQCR;
            WriteData <= {ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_CONTROLWORD;
         end

         ST_SEND_DMA_CONTROLWORD:
         begin
            cmdReq <= 1;
            isDMA <= 1;
            // TX Control word
            // B15  : TXIC transmit interrupt on completion
            // B0-B5: TXFID transmit frame ID
            WriteData <= 16'h0;  // Control word = 0
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_BYTECOUNT;
         end

         ST_SEND_DMA_BYTECOUNT:
         begin
            cmdReq <= 1;
            if (sendARP) begin
               // ARP response: 14 + 28
               WriteData <= 16'd42;
            end
            else if (sendEcho) begin
               // Echo (ICMP) response: 14 + 20 + 12
               WriteData <= 16'd46;
            end
            else if (~isForward) begin
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
            else begin
               // Forwarding data from FireWire
               //   + 14 for frame header
               //   + 28 for UDP: IPv4 header (20) + UDP header (8)
               WriteData <= (useUDP ? 16'd42 : 16'd14) + sendLen;
            end
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_DESTADDR;
            count <= 8'd0;
         end

         ST_SEND_DMA_DESTADDR:
         begin
            cmdReq <= 1;
            WriteData <= srcMac[count[1:0]];
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd2) begin
               nextState <= ST_SEND_DMA_SRCADDR;
               count[1:0] <= 2'd0;
            end
            else begin
               nextState <= ST_SEND_DMA_DESTADDR;
               count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_SEND_DMA_SRCADDR:
           begin
            // Rather than using destAddr from last received packet,
            // use our own MAC addr.
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd0) begin
               WriteData <= 16'h61FA;    // 0xFA61 (byte-swapped)
               nextState <= ST_SEND_DMA_SRCADDR;
               count[1:0] <= 2'd1;
            end
            else if (count[1:0] == 2'd1) begin
               WriteData <= 16'h130E;    // 0x0E13 (byte-swapped)
               nextState <= ST_SEND_DMA_SRCADDR;
               count[1:0] <= 2'd2;
            end
            else if (count[1:0] == 2'd2) begin
               WriteData <= {4'h0,board_id,8'h94};  // 0x940n (n = board id, byte-swapped)
               nextState <= ST_SEND_DMA_LENGTH;
            end
         end

         // EtherType/Length
         ST_SEND_DMA_LENGTH:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            count <= 8'd0;

            if (sendARP) begin
               `WriteDataSwapped <= 16'h0806;
               nextState <= ST_SEND_DMA_ARP;
            end
            else if (useUDP || sendEcho) begin
               `WriteDataSwapped <= 16'h0800;
               nextState <= ST_SEND_DMA_IPV4_HEADER;
            end
            else if (~isForward) begin
               // 20 bytes for quadlet read response
               // (24 + block_data_length) bytes for block read response
               `WriteDataSwapped <= quadRead ? 16'd20 : (16'd24 + block_data_length);
               nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
            end
            else begin
               `WriteDataSwapped <= sendLen;
               nextState <= ST_SEND_DMA_FWD;
               sendAddr <= 7'd0;
               maxCount <= sendLen[8:1] - 8'd1;
               isForward <= 1'd0;
            end
         end

         ST_SEND_DMA_ARP:
         begin
            // Word 3: Operation (OPER):  1 for request, 2 for reply
            // Word 4-6: Sender hardware address (SHA):  MAC address of sender
            // Word 7-8: Sender protocol address (SPA):  IPv4 address of sender (0 for ARP Probe)
            // Word 9-11: Target hardware address (THA):  MAC address of target (ignored in request)
            // Word 12-13: Target protocol address (TPA): IPv4 address of target
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_ARP;
            count[4:0] <= count[4:0]+5'd1;
            case (count[4:0])
               5'd0: `WriteDataSwapped <= 16'h0001;  // Hardware type (HTYPE): 1 for Ethernet
               5'd1: `WriteDataSwapped <= 16'h0800;  // Protocol type (PTYPE): 0x0800 for IPv4
               5'd2: `WriteDataSwapped <= 16'h0604;  // HLEN (6) and PLEN (4)
               5'd3: `WriteDataSwapped <= 16'h0002;  // Operation (OPER): 2 for reply
               5'd4: `WriteDataSwapped <= 16'hFA61;  // 0xFA61
               5'd5: `WriteDataSwapped <= 16'h0E13;  // 0x0E13
               5'd6: `WriteDataSwapped <= {8'h94,4'h0,board_id}; // 0x940n (n = board id)
               5'd7: WriteData <= ip_address[15:0];
               5'd8: WriteData <= ip_address[31:16];
               5'd9: WriteData <= srcMac[0];
               5'd10: WriteData <= srcMac[1];
               5'd11: WriteData <= srcMac[2];
               5'd12: WriteData <= hostIP[31:16];
               5'd13: begin
                      WriteData <= hostIP[15:0];
                      nextState <= ST_SEND_DMA_STOP;
                      sendARP <= 0;
                      end
            endcase
         end

         ST_SEND_DMA_IPV4_HEADER:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_IPV4_HEADER;
            count[3:0] <= count[3:0]+4'd1;
            case (count[3:0])
               // Word 0: Version=4, Internet Header Length (IHL)=5, DSCP=0, ECN=0
               4'd0: `WriteDataSwapped <= {4'd4, 4'd5, 6'd0, 2'd0};  // 0x4500
               // Word 1: Total length (header and data)
               //     Quadlet read response: 20 (IPv4 header) + 8 (UDP header) + 20 (data)
               //     Block read response: 20 (IPv4 header) + 8 (UDP header) + 24 + block_data_length
               4'd1: `WriteDataSwapped <= quadRead ? 16'd48 : (16'd52 + block_data_length);
               // Word 2: Identification
               4'd2: begin
                     `WriteDataSwapped <= 0;   // ID is supposed to be unique within packet lifetime
                     // Convenient time to compute checksum
                     // Sum of fixed fields = 0x4500 + 0x4011 = 0x8511
                     // WriteDataSwapped contains the Length value
                     // Since Length is small, we assume no more than 4 carries, so sum as an 18-bit number.
                     ipv4_checksum <= 18'h8511 + {2'd0,`WriteDataSwapped} + {2'd0,fpgaIP[31:16]} +
                                      {2'd0,fpgaIP[15:0]} + {2'd0,hostIP[31:16]} + {2'd0,hostIP[15:0]};
               end
               // Word 3: Flags, Fragment Offset
               4'd3: `WriteDataSwapped <= {3'b010, 13'd0};  // Set the DF (do not fragment) bit
               // Word 4: Time To Live=64 (recommended default), Protocol=17 (UDP)
               4'd4: `WriteDataSwapped <= {8'd64,8'd17};  // 0x4011
               // Word 5: Header Checksum: Ones complement of sum of all 16-bit words, with carry added.
               4'd5: `WriteDataSwapped <= ~(ipv4_checksum[15:0] + {14'd0,ipv4_checksum[17:16]});
               // Words 6,7: Source IP
               4'd6: WriteData <= fpgaIP[31:16];
               4'd7: WriteData <= fpgaIP[15:0];
               // Words 8,9: Destination IP
               4'd8: WriteData <= hostIP[31:16];
               4'd9: begin
                     WriteData <= hostIP[15:0];
                     count[3:0] <= 4'd0;
                     nextState <= sendEcho ? ST_SEND_DMA_ICMP_HEADER : ST_SEND_DMA_UDP_HEADER;
                     end
               default: `WriteDataSwapped <= 16'd0;
            endcase
         end

         ST_SEND_DMA_ICMP_HEADER:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_ICMP_HEADER;
            count[2:0] <= count[2:0] + 3'd1;
            // Only handles echo (ping).
            case (count[2:0])
              3'd0: WriteData <= 16'd0;  // Echo Reply: Type=0, Code=0
              3'd1: WriteData <= ~(icmp_checksum[15:0] + {14'd0, icmp_checksum[17:16]});
              3'd2: WriteData <= echo_id;
              3'd3: WriteData <= echo_seq;
              3'd4: WriteData <= echo_payload[31:16];
              3'd5: begin
                    WriteData <= echo_payload[15:0];
                    count[2:0] <= 3'd0;
                    sendEcho <= 0;
                    nextState <= ST_SEND_DMA_STOP;
                    end
            endcase
         end

         ST_SEND_DMA_UDP_HEADER:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_UDP_HEADER;
            count[1:0] <= count[1:0]+2'd1;
            case (count[1:0])
               2'd0: `WriteDataSwapped <= 16'd1394;  // Source Port=1394
               2'd1: WriteData <= hostPort;          // Destination Port
               // Word 2: Length (header and data)
               //     Quadlet read response: 8 (UDP header) + 20 (data)
               //     Block read response: 8 (UDP header) + 24 + block_data_length
               2'd2: `WriteDataSwapped <= quadRead ? 16'd28 : (16'd32 + block_data_length);
               2'd3: begin
                     `WriteDataSwapped <= 16'd0;     // Checksum (optional, 0 if not used)
                     count[1:0] <= 2'd0;
                     nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
                     end
            endcase
         end

         // Send first 5 quadlets, which are nearly identical between quadlet read response
         // and block read response (only difference is tcode).
         ST_SEND_DMA_PACKETDATA_HEADER:
         begin
            cmdReq <= 1;
            case (count[2:0])
               3'd0: WriteData <= FireWirePacket[1][31:16];   // quadlet 0: dest-id
               3'd1: WriteData <= {quadRead ? `TC_QRESP : `TC_BRESP, 4'd0, fw_tl, 2'd0}; // quadlet 0: tcode
               3'd2: WriteData <= FireWirePacket[2][31:16];   // src-id
               3'd3: WriteData <= 16'h0;                      // rcode, reserved
               3'd4: WriteData <= {FrameCount, 8'h2b};        // reserved, but use it for debugging
               3'd5:
                  begin
                     WriteData <= eth_status[31:16]; // normally reserved, but use it for debugging
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
               default: WriteData <= 16'h0;
            endcase
            state <= ST_WAIT_ACK;
            if (count[2:0] != 3'd5) begin
               nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
               count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_QUAD:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
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
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
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
            cmdReq <= 1;
            case (count[2:0])
              3'd0: WriteData <= {timestamp[23:16], timestamp[31:24]};
              3'd1:
                 begin
                    WriteData <= {timestamp[7:0], timestamp[15:8]};
                    // Reset timestamp
                    ts_reset <= 1;
                    // Get ready to read data from the board.
                    eth_read_en <= 1;
                    eth_reg_raddr <= {12'd0, `REG_STATUS};   // address of status register
                 end
              3'd2:
                 begin
                    WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};  // status
                    ts_reset <= 0;
                 end
              3'd3:
                 begin
                    WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};     // status
                    eth_reg_raddr <= {12'd0, `REG_DIGIN};   // address of digital I/O register
                 end
              3'd4:
                 begin
                    WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};  // digital I/O
                 end
              3'd5:
                 begin
                    WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};     // digital I/O
                    eth_reg_raddr <= {12'd0, `REG_TEMPSNS};  // address of temperature sensors
                 end
              3'd6:
                 begin
                    WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};  // temperature sensors
                 end
              3'd7:
                 begin
                    WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};     // temperature sensors
                    eth_reg_raddr[7:4] <= 4'h1;        // start from channel 1
                    // NOTE: Following is hard-coded to first read from channel 0,
                    //       and then from 5,6,7. This is correct, but less flexible
                    //       than the implementation in Firewire.v, which uses dev_addr[].
                    eth_reg_raddr[3:0] <= 4'd0;        // 1st device address
                    next_addr <= 3'd5;             // set next device address
                 end
              default: WriteData <= 16'h0;
            endcase
            state <= ST_WAIT_ACK;
            if (count[2:0] == 3'd7) begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
                count[2:0] <= 3'd0;
            end
            else begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_MAIN;
                count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL:
           begin
              cmdReq <= 1;
              state <= ST_WAIT_ACK;
              if (count[0] == 0) begin
                  count[0] <= 1;
                  WriteData <= {eth_reg_rdata[23:16], eth_reg_rdata[31:24]};
                  nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
              end
              else begin
                  count[0] <= 0;
                  WriteData <= {eth_reg_rdata[7:0], eth_reg_rdata[15:8]};
                  if (eth_reg_raddr[7:4] == num_channels) begin
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
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
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
            cmdReq <= 1;
            count[0] <= 1;
            WriteData <= 16'd0;    // Checksum currently not set
            state <= ST_WAIT_ACK;
            nextState <= (count[0] == 0) ? ST_SEND_DMA_PACKETDATA_CHECKSUM : ST_SEND_DMA_DUMMY_DWORD;
         end

         ST_SEND_DMA_FWD:
         begin
            count <= count + 8'd1;
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= (count[0] == 0) ? {sendData[23:16], sendData[31:24]} : {sendData[7:0], sendData[15:8]};
            if (count[0] == 1) sendAddr <= sendAddr + 7'd1;
            state <= ST_WAIT_ACK;
            nextState <= (count == maxCount) ? ST_SEND_DMA_DUMMY_DWORD : ST_SEND_DMA_FWD;
         end

         ST_SEND_DMA_DUMMY_DWORD:
         begin
            count <= 8'd0;
            if (txPktWords[0]) begin
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= 0;
               state <= ST_WAIT_ACK;
               nextState <= ST_SEND_DMA_STOP;
            end
            else begin
               state <= ST_SEND_DMA_STOP;
            end
         end

         ST_SEND_DMA_STOP:
         begin
            if (count[0] == 0) begin  // could probably eliminate
               cmdReq <= 1;
               isWrite <= 0;
               isDMA <= 0;
               RegAddr <= `ETH_ADDR_RXQCR;
               state <= ST_WAIT_ACK;
               nextState <= ST_SEND_DMA_STOP;
               count[0] <= 1;
            end
            else begin
               // Disable DMA transfers
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:0]};
               state <= ST_WAIT_ACK;
               nextState <= ST_SEND_TXQ_ENQUEUE_START;
               count[0] <= 0;
            end
         end

         ST_SEND_TXQ_ENQUEUE_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= `ETH_ADDR_TXQCR;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_TXQ_ENQUEUE_END;
         end

         ST_SEND_TXQ_ENQUEUE_END:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:1],1'b1};
            state <= ST_WAIT_ACK;
            // For now, wait for the frame to be transmitted. According to the datasheet,
            // "the software should wait for the bit to be cleared before setting up another
            // new TX frame," so this check could be moved elsewhere for efficiency.
            nextState <= ST_SEND_TXQ_ENQUEUE_WAIT_START;
         end

         ST_SEND_TXQ_ENQUEUE_WAIT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            // RegAddr is already set to TXQCR
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_TXQ_ENQUEUE_WAIT_CHECK;
         end

         ST_SEND_TXQ_ENQUEUE_WAIT_CHECK:
         begin
            // Wait for bit 0 in Register 0x80 to be cleared
            if (ReadData[0] == 1'b0) begin
                state <= ST_SEND_END;
            end
            else begin
               state <= ST_SEND_TXQ_ENQUEUE_WAIT_START;
               waitInfo <= WAIT_FLUSH;  // TEMP: use WAIT_FLUSH, but should be WAIT_TXQ_ENQUEUE
            end
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

         default:
         begin
            numStateInvalid <= numStateInvalid + 16'd1;
            state <= ST_IDLE;
         end

         endcase // case (state)
    end
end

endmodule
