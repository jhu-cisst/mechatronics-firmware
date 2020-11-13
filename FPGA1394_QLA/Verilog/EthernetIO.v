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
`define ETH_ADDR_P1SR    8'hF8     // Port 1 status register

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
    output reg[31:0] reg_rdata,
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
    input  wire[8:0] eth_fwpkt_raddr,
    output wire[31:0] eth_fwpkt_rdata,
    output wire[15:0] eth_fwpkt_len,   // eth received fw pkt length
    output reg[15:0] host_fw_addr,     // Firewire address of host (e.g., ffd0)

    // Interface from Firewire (for sending packets via Ethernet)
    // Note that sendAck is asserted when the Ethernet module is accessing the Firewire
    // packet memory via sendAddr and sendData.
    input wire sendReq,              // Send request from FireWire
    output reg sendAck,              // Ack from Ethernet
    output reg[8:0] sendAddr,        // Address into packet memory
    input wire[31:0] sendData,       // Packet data from memory
    input wire[15:0] sendLen,        // Packet size (bytes)

    input wire fw_bus_reset,         // Firewire bus reset in process

    // Interface for sampling data (for block read)
    output reg sample_start,         // 1 -> start sampling for block read
    input wire sample_busy,          // Sampling in process
    output reg sample_read,          // Reading from memory in process
    output wire[4:0] sample_raddr,   // Read address for sampled data
    input wire[31:0] sample_rdata,   // Sampled data (for block read)
    input wire[31:0] timestamp,      // Timestamp (for debugging)
    output reg writeHub              // 1 -> write to Hub after sampling
);

reg initOK;            // 1 -> Initialization successful
reg isWrite;           // 0 -> Read, 1 -> Write
reg isWord;            // 0 -> Byte, 1 -> Word
reg[7:0] RegAddr;      // Register address (N/A for DMA mode)
reg[15:0] WriteData;   // Data to be written to chip (N/A for read)
wire[15:0] ReadData;   // Data read from chip (N/A for write)
reg eth_error;         // 1 -> I/O request received when not in idle state
reg linkStatus;        // 1 -> Ethernet link good (cable connected)

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
reg[15:0] SDRegDWR;  // For DMA write
assign SD = (ETH_RDn&~isDMARead) ? (isDMAWrite ? SDRegDWR : SDReg) : 16'hz;

`define SDSwapped {SD[7:0], SD[15:8]}
`define SDRegSwapped {SDReg[7:0], SDReg[15:8]}
`define SDRegDWRSwapped {SDRegDWR[7:0], SDRegDWR[15:8]}

// address decode for KSZ8851 I/O access
wire   ksz_reg_wen;
assign ksz_reg_wen = (fw_reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHRES}) ? fw_reg_wen : 1'b0;

reg       ksz_req;    // External request pending for KSZ I/O
reg[31:0] ksz_wdata;  // Cached register for KSZ I/O request

// Following registers hold address/data for requested register reads/writes
// (note: eth_data is declared above, as parameter)
//reg[7:0]  eth_addr;     // I/O register address (0-0xFF)

reg recvDMAreq;     // 1 -> Request DMA write
reg sendDMAreq;     // 1 -> Request DMA write
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

assign ETH_WRn = isDMARead ? 1'b1    : (isDMAWrite ? DMA_WRn : Reg_WRn);
assign ETH_RDn = isDMARead ? DMA_RDn : (isDMAWrite ? 1'b1 : Reg_RDn);
assign ETH_CMD = (isDMAWrite|isDMARead) ? 1'b0 : Reg_CMD;

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

reg resetRequest;      // 1 -> reset requested (e.g., when Ethernet cable unplugged)
reg resetActive;       // Indicates that reset is active

// Firewire bus generation. Incremented each time fw_bus_reset is cleared.
reg[7:0] fw_bus_gen;

always @(negedge fw_bus_reset)
begin
    fw_bus_gen <= fw_bus_gen + 8'd1;
end

localparam[31:0] IP_UNASSIGNED = 32'hffffffff;

// maximum quadlet index for real-time feedback broadcast packet
localparam[5:0] MAX_BBC_QUAD = (`NUM_BC_READ_QUADS-1);

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
    ST_SEND_DMA_WAIT = 5'd16,
    ST_SEND_TXQ_ENQUEUE = 5'd17,
    ST_SEND_TXQ_ENQUEUE_WAIT = 5'd18,
    ST_SEND_END = 5'd19,
    // KSZIO states
    ST_WAVEFORM_ADDR = 5'd20,    // write the address to the KSZ8851
    ST_WAVEFORM_DATA = 5'd21;    // read/write data from/to the KSZ8851

// Current state (one-hot encoding)
reg[21:0] state = (22'd1 << ST_RESET_ASSERT);
reg[21:0] lastState;
// Current state (not one-hot)
reg[4:0] stateIndex = ST_RESET_ASSERT;
// For error checking
reg[21:0] testState;
// Next state
reg[4:0] nextState;
reg[21:0] nextStateVector;
// State to return to after ST_WAVEFORM_DATA
reg[4:0] retState = ST_IDLE;

// Following indicates an error in the one-hot state encoding, i.e., either no bits
// are set or more than one bit is set. Note that testState is assigned in the
// always block that also sets nextState.
wire stateError;
assign stateError  = (state == 22'd0) || (testState != 22'd0) ? 1'b1 : 1'b0;
reg[31:0] errorStateInfo;

// Debugging support
assign eth_io_isIdle = state[ST_IDLE];
assign eth_send_isIdle = (sendState == ST_SEND_DMA_IDLE) ? 1'd1 : 1'd0;
assign eth_recv_isIdle = (recvState == ST_RECEIVE_DMA_IDLE) ? 1'd1 : 1'd0;

// Keep track of areas where state machine may wait
// for unknown amount of time (for debugging)
localparam [1:0]
    WAIT_NONE = 2'd0,
    WAIT_RECEIVE_DMA = 2'd1,
    WAIT_SEND_DMA = 2'd2,
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

wire addrMain;

reg FrameValid;
reg isEthMulticast;
reg isEthBroadcast;

// Whether to use UDP (1) or raw Ethernet frames (0).
// This mode is set each time a valid packet is received
// (i.e., set if a valid UDP packet received, cleared if
// a valid raw Ethernet frame is received).
reg useUDP;

// Whether Firewire packet was dropped, rather than being forwarded,
// due to Firewire bus reset or mismatch on bus generation number.
reg fwPacketDropped;

// Whether to send a response packet with just ExtraData.
// This is done when a (remote) packet is dropped and it is not
// a broadcast packet (i.e., not also local).
wire sendExtra;
assign sendExtra = fwPacketDropped&(~isFwBroadcast);

// Non-zero initial values
initial begin
   //ETH_RSTn = 1'd1;
   isWord = 1'd1;
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
assign eth_status[19] = linkStatus;      // 19: Link status
assign eth_status[18] = eth_io_isIdle;   // 18: Ethernet I/O state machine is idle
assign eth_status[17:16] = waitInfo;     // 17-16: Wait points in EthernetIO.v


reg isInIRQ;           // True if IRQ handle routing
reg[15:0] RegISR;      // 16-bit ISR register
reg[15:0] RegISROther; // Unexpected ISR value (for debugging)
reg[7:0] FrameCount;   // Number of received frames
reg[11:0] txPktWords;  // Num of words sent
reg[11:0] rxPktWords;  // Num of words in receive queue
reg[1:0] genCnt;       // Generic counter

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

// Read address for sampled data (32-bit data)
assign sample_raddr = sfw_count[5:1];

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
   ID_Rep_IPv4_Address0 = ID_Reply_Begin+9,  // Source (FPGA) IP address (MSW)
   ID_Rep_IPv4_Address1 = ID_Reply_Begin+10, // Source (FPGA) IP address (LSW)
   ID_Rep_UDP_fpgaPort  = ID_Reply_Begin+11, // UDP port on FPGA (1394)
   ID_Rep_UDP_hostPort  = ID_Reply_Begin+12, // UDP port on host (ID_UDP_hostPort)
   ID_Rep_UDP_Length    = ID_Reply_Begin+13, // UDP Reply Length
   ID_Rep_ARP_Oper      = ID_Reply_Begin+14, // ARP reply operation = 2
   ID_Rep_Unused        = ID_Reply_Begin+15, // unused
   ID_Reply_End         = ID_Reply_Begin+15; // ******** End of all data (14) ***********

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
   ReplyBuffer[ID_Rep_IPv4_Address0] = IP_UNASSIGNED[31:16];  // updated when IP address assigned
   ReplyBuffer[ID_Rep_IPv4_Address1] = IP_UNASSIGNED[15:0];   // updated when IP address assigned
   ReplyBuffer[ID_Rep_UDP_fpgaPort]  = 16'd1394;
   ReplyBuffer[ID_Rep_UDP_hostPort]  = 16'd0;      // Needs to be updated
   ReplyBuffer[ID_Rep_UDP_Length]    = 16'd0;      // updated in ST_SEND_DMA_BYTECOUNT
   ReplyBuffer[ID_Rep_ARP_Oper]      = 16'h0002;   // ARP Operation (OPER): 2 for reply
   ReplyBuffer[ID_Rep_Unused]        = 16'd0;
end

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
assign isRaw = (FrameValid && (Eth_EtherType[15:9] == 7'd0)) ? 1'd1 : 1'd0;

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
   ReplyIndex[IPv4_Reply_Begin+5]   = {isReply,  ID_Rep_Zero};       // Header checksum
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

reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[9:0]  numPacketInvalid;  // Number of invalid Ethernet frames received
reg[9:0] numIPv4;            // Number of IPv4 packets received
reg[9:0] numUDP;             // Number of UDP packets received
reg[7:0] numARP;             // Number of ARP packets received
reg[7:0] numICMP;            // Number of ICMP packets received
reg[7:0] numPacketSent;      // Number of packets sent to host PC

reg[9:0] numPacketError;     // Number of packet errors (Frame, IPv4 or UDP error)
reg[9:0] numIPv4Mismatch;    // Number of IPv4 packets with different IP address

reg[15:0] timeSinceIRQ;      // Time counter since last IRQ
reg[15:0] timeReceive;       // Time when receive portion finished
reg[15:0] timeSend;          // Time when send portion finished

wire is_ip_unassigned;
assign is_ip_unassigned = (ip_address == IP_UNASSIGNED) ? 1'd1 : 1'd0;

// Request a local write to be performed (quadWrite or blockWrite)
reg writeRequestPending;
reg writeRequestBlock;
reg writeRequestQuad;

// ----------------------------------------
// Whether packet is being forwarded (to Ethernet) from FireWire receiver
// ----------------------------------------
reg isForward;

// -----------------------------------------------
// Extra data sent to PC with every Firewire packet
// -----------------------------------------------
wire[15:0] ExtraData[0:3];
assign ExtraData[0] = {6'd0, fwPacketDropped, fw_bus_reset, fw_bus_gen};
assign ExtraData[1] = {numStateInvalid[7:0], numPacketError[7:0]};
assign ExtraData[2] = timeReceive;
assign ExtraData[3] = timeSinceIRQ;

// -----------------------------------------------
// Debug data
// -----------------------------------------------
wire[31:0] DebugData[0:15];
assign DebugData[0]  = "0GBD";  // DBG0 byte-swapped
assign DebugData[1]  = timestamp;
assign DebugData[2]  = { writeRequestQuad, writeRequestBlock, writeRequestPending, eth_send_isIdle,
                         eth_recv_isIdle, ethUDPError, ethAccessError, ethIPv4Error,
                         isDMAWrite, sendDMAreq, node_id, eth_status};
assign DebugData[3]  = { state[7:0], eth_send_fw_ack, eth_send_fw_req, linkStatus, retState,
                         sample_start, sample_busy, isLocal, isRemote,
                         FireWirePacketFresh, isEthBroadcast, isEthMulticast, ~ETH_IRQn,
                         isForward, isInIRQ, sendARP, isUDP,
                         isICMP, isEcho, is_IPv4_Long, is_IPv4_Short};
assign DebugData[4]  = { fw_ctrl, RegISROther};
assign DebugData[5]  = { host_fw_addr, FrameCount, numPacketSent};
assign DebugData[6]  = { 1'b0, nextState, maxCountFW, LengthFW };
assign DebugData[7]  = { sendState, txPktWords, nextSendState, rxPktWords };
assign DebugData[8]  = { timeSend, timeReceive };
assign DebugData[9]  = { 1'd0, runPC, numPacketInvalid, numPacketValid };
assign DebugData[10] = { 6'd0, numUDP, 6'd0, numIPv4 };
assign DebugData[11] = { 8'd0, numICMP, fw_bus_gen, numARP };
assign DebugData[12] = { fw_bus_reset, runPCsaved, numIPv4Mismatch, 6'd0, numPacketError };
assign DebugData[13] = { numSendStateInvalid, numReset, 6'd0, numStateInvalid };
assign DebugData[14] = { 16'd0, 16'd0 };
assign DebugData[15] = errorStateInfo;

// For debugging block write. Note that in the current implementation, this buffer can
// only be written via the Ethernet interface, but it can be read via Ethernet or Firewire.
// The address range is 4090-409f.
reg[31:0] DebugBuffer[0:15];

// Firewire packets received from host:
//    - 16 bytes (4 quadlets) for quadlet read request
//    - 20 bytes (5 quadlets) for quadlet write or block read request
//    - (24+block_data_length) bytes for block write
//      - real-time block_data_length = 4*5 = 20 bytes (Rev 7+)
//        max size in quadlets is (24+20)/4 = 11
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

assign mem_raddr = eth_send_fw_ack   ? eth_fwpkt_raddr :
                   writeRequestBlock ? local_raddr :
                   icmp_read_en      ? sfw_count[9:1]
                                     : reg_raddr[8:0];
assign eth_fwpkt_rdata = mem_rdata;

reg[31:0] FireWireQuadlet;   // the current quadlet being read

reg mem_wen;   // memory write enable

// packet module (used to store Ethernet packet that will be forwarded to Firewire)
// This is 512 quadlets (512 x 32), which is the maximum possible Firewire packet size at 400 Mbits/sec
// (actually, could add a few quadlets because 512 limit probably does not include header and CRC).
// This memory is much larger than currently needed (could get by with 128 quadlets), but the FPGA
// contains more than enough memory primitives.
hub_mem_gen fw_packet(.clka(sysclk),
                      .wea(mem_wen),
                      .addra(rfw_count[9:1]),
                      .dina(FireWireQuadlet),
                      .clkb(sysclk),
                      .addrb(mem_raddr),
                      .doutb(mem_rdata)
                     );

reg FireWirePacketFresh;   // 1 -> FireWirePacket data is valid (fresh)

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
// the contents of the ID_CLEAR_INTERRUPT instruction.
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
reg[25:0] RunProgram[0:31];

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

initial begin
    // Read Chip ID
    RunProgram[ID_CHIP_ID] = {CMD_READ, CMD_NOP, `ETH_ADDR_CIDER, 11'd0, ST_INIT_CHECK_CHIPID};
    // Set MAC address (4 LSB below should be set to board_id)
    RunProgram[ID_MAC_LOW] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MARL, 12'h940, 4'd0};
    RunProgram[ID_MAC_MID] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MARM, 16'h0E13};
    RunProgram[ID_MAC_HIGH] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MARH, 16'hFA61};
    // Enable QMU transmit frame data pointer auto increment
    RunProgram[4] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXFDPR, 16'h4000};
    RunProgram[5] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXCR, ETH_VALUE_TXCR};
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
    RunProgram[6] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXFDPR, 16'h4000};
    // Configure receive frame threshold for 1 frame
    RunProgram[7] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXFCTR, 16'h0001};
    // 7: enable UDP, TCP, and IP checksums
    // C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
    // E: enable broadcast, multicast, and unicast
    // Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
    RunProgram[8] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXCR1, ETH_VALUE_RXCR1};
    // Enable UDP checksums; pass packets with 0 checksum
    RunProgram[9] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXCR2, 16'h001C};
    // Following are hard-coded values for which hash register to use and which bit to set
    // for multicast address FB:61:0E:13:19:FF. This is obtained by computing the CRC for
    // this MAC address and then using the first two (most significant) bits to determine
    // the register and the next four bits to determine which bit to set.
    // See code in mainEth1394.cpp.
    RunProgram[10] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_MAHTR1, 16'h0008};
    // RXQCR value
    // B5: RXFCTE enable QMU frame count threshold (1)
    // B4: ADRFE  auto-dequeue
    // Not enabling auto-dequeue because we flush packet
    // instead of reading to end.
    RunProgram[11] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR};
    // Clear all pending interrupts
    RunProgram[12] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_ISR, 16'hFFFF};
    // Enable receive and link change interrupts
    RunProgram[13] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_IER, ETH_VALUE_IER};
    // Enable transmit
    RunProgram[14] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXCR, ETH_VALUE_TXCR[15:1], 1'd1};
    // Enable receive
    RunProgram[15] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXCR1, ETH_VALUE_RXCR1[15:1], 1'd1};
    // Check link status. This is the last command for initialization, but will also be called
    // in response to a link change interrupt. Note that ST_HANDLE_PORT_STATUS will transition
    // to ST_IDLE if called during initialization and to ST_IRQ_DISPATCH if called as a result
    // of the interrupt (isInIRQ).
    RunProgram[ID_READ_PORT1SR]      = {CMD_READ,  CMD_NOP, `ETH_ADDR_P1SR,  11'd0, ST_HANDLE_PORT_STATUS};
    // The following commands are used at runtime
    RunProgram[ID_READ_INTERRUPT]    = {CMD_READ,  CMD_NOP, `ETH_ADDR_ISR, 11'd0, ST_IRQ_HANDLER};
    RunProgram[ID_DISABLE_INTERRUPT] = {CMD_WRITE, CMD_BRA, `ETH_ADDR_IER, 16'd0};
    // Clear interrupt (data field updated in ST_IRQ_DISPATCH)
    RunProgram[ID_CLEAR_INTERRUPT]   = {CMD_WRITE, CMD_BRA, `ETH_ADDR_ISR, 16'd0};
    RunProgram[ID_READ_FRAME_COUNT]  = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXFCTR, 11'd0, ST_RECEIVE_FRAME_COUNT};
    RunProgram[ID_READ_FRAME_STATUS] = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXFHSR, 11'd0, ST_RECEIVE_FRAME_STATUS};
    RunProgram[ID_READ_FRAME_LENGTH] = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXFHBCR, 11'd0, ST_RECEIVE_FRAME_LENGTH};
    // Set QMU RXQ frame pointer to 0 (not decreasing write sample time)
    RunProgram[ID_SET_FRAME_POINTER] = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXFDPR, 16'h4000};
    RunProgram[ID_ENABLE_DMA_RECV]   = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
    // Flush the rest of the packet: Clear DMA bit (bit 3) and set flush bit (bit 0)
    RunProgram[ID_FLUSH_FRAME]       = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:1],1'b1};
    RunProgram[ID_READ_CMD_REG]      = {CMD_READ,  CMD_NOP, `ETH_ADDR_RXQCR, 11'd0, ST_RECEIVE_FLUSH_WAIT};
    RunProgram[ID_ENABLE_INTERRUPT]  = {CMD_WRITE, CMD_NOP, `ETH_ADDR_IER, ETH_VALUE_IER};
    RunProgram[ID_ENABLE_DMA_SEND]   = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b1,ETH_VALUE_RXQCR[2:0]};
    RunProgram[ID_DISABLE_DMA]       = {CMD_WRITE, CMD_NOP, `ETH_ADDR_RXQCR, ETH_VALUE_RXQCR[15:4],1'b0,ETH_VALUE_RXQCR[2:0]};
    RunProgram[ID_TXQ_ENQUEUE]       = {CMD_WRITE, CMD_NOP, `ETH_ADDR_TXQCR, 16'h0001};
    RunProgram[ID_TXQ_READ]          = {CMD_READ,  CMD_NOP, `ETH_ADDR_TXQCR, 11'd0, ST_SEND_TXQ_ENQUEUE_WAIT};
end

reg[4:0] runPC;    // Program counter for RunProgram
reg[4:0] runPCsaved;

// Following data is accessible via block read from address `ADDR_ETH (0x4000)
//    4000 - 407f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4080 - 408f (16 quadlets) Debug data
//    4090 - 409f (16 quadlets) Debug buffer (R/W)
//    40a0 - 40bf (32 quadlets) RunProgram
//    40c0 - 40df (32 quadlets) PacketBuffer/ReplyBuffer (64 words)
//    40e0 - 40ff (32 quadlets) ReplyIndex (64 words)
// Note that full address decoding is not done, so other addresses will work too
// (for example, 4f80-4f9f will also give Debug data)
always @(*)
begin
   if (reg_raddr[7] == 0)
      reg_rdata = mem_rdata;
   else begin
      case (reg_raddr[6:5])
      2'b00:
         reg_rdata = (reg_raddr[4]==0) ? DebugData[reg_raddr[3:0]] : DebugBuffer[reg_raddr[3:0]];
      2'b01:
         reg_rdata = {6'd0, RunProgram[reg_raddr[4:0]]};
      2'b10:
         reg_rdata = (reg_raddr[4]==0) ? {PacketBuffer[{reg_raddr[3:0],1'b1}], PacketBuffer[{reg_raddr[3:0],1'b0}]} :
                                         {ReplyBuffer[{reg_raddr[2:0],1'b1}],  ReplyBuffer[{reg_raddr[2:0],1'b0}]};
      2'b11:
         reg_rdata = {10'd0, ReplyIndex[{reg_raddr[4:0],1'b1}], 10'd0, ReplyIndex[{reg_raddr[4:0],1'b0}]};
      endcase
   end
end

// Following is only for debugging
always @(posedge sysclk)
begin
   if (eth_reg_wen && (eth_reg_waddr[15:12] == `ADDR_ETH) && (eth_reg_waddr[7:4] == 4'b1001))
      DebugBuffer[eth_reg_waddr[3:0]] <= eth_reg_wdata;
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

// assign isRemote = (dest_node_id != node_id) && ~(isEthMulticast||isEthBroadcast);
// Remote write if not addressing this board (note that this check includes Firewire broadcast)
// and if noForwardFlag is false.
// Also, note that some packets (e.g., Firewire broadcast) may set both isLocal and isRemote.
assign isRemote = (dest_node_id != node_id) && (!noForwardFlag);

assign quadRead = (fw_tcode == `TC_QREAD) ? 1'd1 : 1'd0;
assign quadWrite = (fw_tcode == `TC_QWRITE) ? 1'd1 : 1'd0;
assign blockRead = (fw_tcode == `TC_BREAD) ? 1'd1 : 1'd0;
assign blockWrite = (fw_tcode == `TC_BWRITE) ? 1'd1 : 1'd0;

assign addrMain = (fw_dest_offset[15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;

// Reg_CMD is 0 except when writing address to the KSZ8851
assign Reg_CMD = state[ST_WAVEFORM_ADDR];
// Reg_WRn is sequenced 1001 for writing address or data; held at 1 when reading data
assign Reg_WRn = (Reg_CMD|isWrite) ? RWcnt[0]^~RWcnt[1] : 1'b1;
// Reg_RDn is sequenced 100001 for reading data; held at 1 when writing address or data
assign Reg_RDn = (Reg_CMD|isWrite) ? 1'b1 :~RWcnt[1]&(RWcnt[0]^~RWcnt[2]);

// -------------------------------------------------------------
// Ethernet top-level state machine
//
// This design uses two always blocks:
//   1) Combinatorial, to set nextState (and testState)
//   2) Sequential, to update state based on nextState and set outputs.
//
// -------------------------------------------------------------

// Combinatorial always block to set nextState. Also sets testState for error checking.
always @(*)
begin

   // Default value of nextState. This should get reassigned below,
   // unless there is an error (i.e., if no bits in state are set).
   nextState = ST_IDLE;

   // Following is for error checking (i.e., to check if more than 1 bit
   // in state is set).
   testState = state;

   case (1'b1)

   state[ST_IDLE]:
   begin
      testState[ST_IDLE] = 0;
      if (ksz_req) begin
         if (ksz_wdata[26])
            nextState = ST_RESET_ASSERT;
         else
            nextState = ksz_wdata[27] ? ST_WAVEFORM_DATA : ST_WAVEFORM_ADDR;
      end
      else if (~ETH_IRQn|sendReq) begin
         nextState = ST_RUN_PROGRAM_EXECUTE;
      end
      else if (resetRequest) begin
         nextState = ST_RESET_ASSERT;
      end
      else
         nextState = ST_IDLE;
   end

   //******************* RESET STATES ***********************
   state[ST_RESET_ASSERT]:
   begin
      testState[ST_RESET_ASSERT] = 0;
      // 10 ms (49.152 MHz sysclk)
      nextState = (initCount == 21'd491520) ? ST_RESET_WAIT : ST_RESET_ASSERT;
   end

   state[ST_RESET_WAIT]:
   begin
      testState[ST_RESET_WAIT] = 0;
      nextState = (initCount == 21'h1FFFFF) ? ST_RUN_PROGRAM_EXECUTE : ST_RESET_WAIT;
   end

   state[ST_INIT_CHECK_CHIPID]:
   begin
      testState[ST_INIT_CHECK_CHIPID] = 0;
      nextState = (ReadData[15:4] == 12'h887) ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
   end

   state[ST_HANDLE_PORT_STATUS]:
   begin
      testState[ST_HANDLE_PORT_STATUS] = 0;
      nextState = isInIRQ ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
   end

   //********************* RUN PROGRAM ************************

   state[ST_RUN_PROGRAM_EXECUTE]:
   begin
      testState[ST_RUN_PROGRAM_EXECUTE] = 0;
      nextState = ST_WAVEFORM_ADDR;
   end

   //********************* IRQ STATES *************************

   state[ST_IRQ_HANDLER]:
   begin
      testState[ST_IRQ_HANDLER] = 0;
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end

   state[ST_IRQ_DISPATCH]:
   begin
      testState[ST_IRQ_DISPATCH] = 0;
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end


   //******************* RECEIVE STATES ***********************

   state[ST_RECEIVE_FRAME_COUNT]:
   begin
      testState[ST_RECEIVE_FRAME_COUNT] = 0;
      nextState = (ReadData[15:8] == 0) ? ST_IRQ_DISPATCH : ST_RUN_PROGRAM_EXECUTE;
   end

   state[ST_RECEIVE_FRAME_STATUS]:
   begin
      testState[ST_RECEIVE_FRAME_STATUS] = 0;
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end

   state[ST_RECEIVE_FRAME_LENGTH]:
   begin
      testState[ST_RECEIVE_FRAME_LENGTH] = 0;
      nextState = ST_RUN_PROGRAM_EXECUTE;
   end

   state[ST_RECEIVE_DMA_REQUEST]:
   begin
      testState[ST_RECEIVE_DMA_REQUEST] = 0;
      nextState = ST_RECEIVE_DMA_WAIT;
   end

   state[ST_RECEIVE_DMA_WAIT]:
   begin
      testState[ST_RECEIVE_DMA_WAIT] = 0;
      nextState = ~(recvDMAreq|isDMARead) ? ST_RUN_PROGRAM_EXECUTE : ST_RECEIVE_DMA_WAIT;
   end

   state[ST_RECEIVE_FLUSH_WAIT]:
   begin
      testState[ST_RECEIVE_FLUSH_WAIT] = 0;
      if (ReadData[0] == 1'b0) begin
         if ((FireWirePacketFresh && (quadRead || blockRead) && isLocal) || sendARP || isEcho) begin
            nextState = ST_RUN_PROGRAM_EXECUTE;
         end
         else begin
            if (FrameCount == 8'd0)
               nextState = ST_IRQ_DISPATCH;
            else
               nextState = ST_RUN_PROGRAM_EXECUTE;
         end
      end
      else begin
         nextState = ST_RUN_PROGRAM_EXECUTE;
      end
   end

   state[ST_SEND_DMA_REQUEST]:
   begin
      testState[ST_SEND_DMA_REQUEST] = 0;
      nextState = ST_SEND_DMA_WAIT;
   end

   state[ST_SEND_DMA_WAIT]:
   begin
      testState[ST_SEND_DMA_WAIT] = 0;
      nextState = ~(sendDMAreq|isDMAWrite) ? ST_RUN_PROGRAM_EXECUTE : ST_SEND_DMA_WAIT;
   end

   state[ST_SEND_TXQ_ENQUEUE_WAIT]:
   begin
      testState[ST_SEND_TXQ_ENQUEUE_WAIT] = 0;
      nextState = (ReadData[0] == 1'b0) ? ST_SEND_END : ST_RUN_PROGRAM_EXECUTE;
   end

   state[ST_SEND_END]:
   begin
      testState[ST_SEND_END] = 0;
      if (isInIRQ)
         nextState = (FrameCount == 8'd0) ? ST_IRQ_DISPATCH : ST_RUN_PROGRAM_EXECUTE;
      else
         nextState = ST_IDLE;
   end

   state[ST_WAVEFORM_ADDR]:
   begin
      testState[ST_WAVEFORM_ADDR] = 0;
      nextState = (RWcnt == 3'd3) ? ST_WAVEFORM_DATA : ST_WAVEFORM_ADDR;
   end

   state[ST_WAVEFORM_DATA]:
   begin
      testState[ST_WAVEFORM_DATA] = 0;
      nextState = ((isWrite && (RWcnt == 3'd3)) || (RWcnt == 3'd5)) ? retState : ST_WAVEFORM_DATA;
   end

   endcase // case (1'b1)

   nextStateVector <= (22'd1 << nextState);

end

always @(posedge sysclk) begin

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

   if (resetActive) begin
      resetRequest <= 0;
      FrameValid <= 0;
      isEthMulticast <= 0;
      isEthBroadcast <= 0;
      RegISROther <= 16'd0;
      isForward <= 0;
      numPacketValid <= 16'd0;
      numPacketInvalid <= 10'd0;
      numIPv4 <= 10'd0;
      numUDP <= 10'd0;
      numARP <= 8'd0;
      numICMP <= 8'd0;
      numPacketSent <= 8'd0;
   end

   //******************** State Machine ********************

   timeSinceIRQ <= timeSinceIRQ + 16'd1;

   if (stateError) begin
      // Should never happen, except for programming errors or glitches
      numStateInvalid <= numStateInvalid + 10'd1;
      errorStateInfo <= {nextState, stateIndex, state};
      runPCsaved <= runPC;
      // Go back and try again. We restore lastState because it was the
      // last error-free state. We also restore RWcnt because the determination
      // of nextState can depend on it. It can also depend on ReadData (which should
      // not have changed) and initCount (used only during initialization).
      state <= lastState;
      RWcnt <= lastRWcnt;
      // Note that the state machine is skipped this cycle
   end
   else begin

   //state <= 22'd0;
   //state[nextState] <= 1;
   lastState <= state;
   lastRWcnt <= RWcnt;
   state <= nextStateVector;
   stateIndex <= nextState;

   // One-hot state machine implementation
   case (1'b1)

   state[ST_IDLE]:
   begin
      isWord <= 1;       // all transfers are word
      isInIRQ <= 0;
      resetActive <= 0;
      recvDMAreq <= 0;
      sendDMAreq <= 0;
      RWcnt <= 3'd0;
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
         if (!ksz_wdata[26]) begin   // if not reset
            isWrite <= ksz_wdata[25];
            isWord <= ksz_wdata[24];
            RegAddr <= ksz_wdata[23:16];
            WriteData <= ksz_wdata[15:0];
            retState <= ST_IDLE;
         end
      end
      else if (~ETH_IRQn) begin
         // If an interrupt transition to ST_RUN_PROGRAM_EXECUTE
         runPC <= ID_READ_INTERRUPT;
         timeSinceIRQ <= 16'd0;
      end
      else if (sendReq) begin
         // forward packet from FireWire
         isForward <= 1;
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
         runPC <= ID_ENABLE_DMA_SEND;
      end
   end

   //********** States for chip reset and initializing Ethernet *************
   // This is the first state called.
   // It can also be called via the Firewire interface.
   // When done, it returns to ST_IDLE.

   // Assert the reset and wait 10 ms before removing it.
   // (For the first time, we could skip asserting the reset because it is already asserted)
   state[ST_RESET_ASSERT]:
   begin
      if (initCount == 21'd491520) begin  // 10 ms (49.152 MHz sysclk)
         ETH_RSTn <= 1;   // Remove the reset
         initCount <= 21'd0;
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
   state[ST_RESET_WAIT]:
   begin
      if (initCount == 21'h1FFFFF) begin
         initCount <= 21'd0;
         RunProgram[ID_MAC_LOW][3:0] <= board_id;
         ReplyBuffer[ID_Rep_fpgaMac2][3:0] <= board_id;
         runPC <= ID_CHIP_ID;
      end
      else begin
         initCount <= initCount + 21'd1;
      end
   end

   state[ST_INIT_CHECK_CHIPID]:
   begin
      // Can set initOK now, since the rest of initialization will
      // proceed without any further checks.
      initOK <= (ReadData[15:4] == 12'h887) ? 1'b1 : 1'b0;
   end

   //*************** State for the run-time program ******************

   state[ST_RUN_PROGRAM_EXECUTE]:
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

   state[ST_IRQ_HANDLER]:
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
      if (~(ReadData[15]|ReadData[13])) begin
         // Record unexpected interrupt
         RegISROther <= ReadData;
      end
   end

   state[ST_IRQ_DISPATCH]:
   begin
      if (RegISR[13] == 1'b1) begin
         // Handle receive
         isInIRQ <= 1;
         runPC <= ID_CLEAR_INTERRUPT;
         RunProgram[ID_CLEAR_INTERRUPT][`MOD_BIT] <= 1'b0;
         RunProgram[ID_CLEAR_INTERRUPT][`ADDR_BITS] <= `ETH_ADDR_ISR;
         RunProgram[ID_CLEAR_INTERRUPT][`DATA_BITS] <= 16'h2000;
         RegISR[13] <= 1'b0;     // clear ISR receive IRQ bit
      end
      else if (RegISR[15] == 1'b1) begin
         // Handle link change
         isInIRQ <= 1;
         runPC <= ID_READ_PORT1SR;
         // ST_HANDLE_PORT_STATUS will set runPC to ID_CLEAR_INTERRUPT
         RunProgram[ID_CLEAR_INTERRUPT][`MOD_BIT] <= 1'b1;
         RunProgram[ID_CLEAR_INTERRUPT][`ADDR_BITS] <= `ETH_ADDR_ISR;
         RunProgram[ID_CLEAR_INTERRUPT][`DATA_BITS] <= 16'h8000;
         RegISR[15] <= 1'b0;       // Clear RegISR
      end
      else if (RegISR[14] || RegISR[11] || RegISR[9] || RegISR[8] || RegISR[6]) begin
         // These interrupts are not handled and are disabled, so clear them
         // if they somehow occurred.
         runPC <= ID_CLEAR_INTERRUPT;
         RunProgram[ID_CLEAR_INTERRUPT][`MOD_BIT] <= 1'b1;
         RunProgram[ID_CLEAR_INTERRUPT][`ADDR_BITS] <= `ETH_ADDR_ISR;
         RunProgram[ID_CLEAR_INTERRUPT][`DATA_BITS] <= RegISR&16'b0100101101000000;
         RegISR <= RegISR&16'b1011010010111111;    // Clear RegISR bits
      end
      else if (RegISR[5] || RegISR[4] || RegISR[3] || RegISR[2]) begin
         // These interrupts are also not handled and are disabled, but are
         // cleared differently (by writing to PMECR)
         runPC <= ID_CLEAR_INTERRUPT;
         RunProgram[ID_CLEAR_INTERRUPT][`MOD_BIT] <= 1'b1;
         RunProgram[ID_CLEAR_INTERRUPT][`ADDR_BITS] <= `ETH_ADDR_PMECR;
         RunProgram[ID_CLEAR_INTERRUPT][`DATA_BITS] <= RegISR&16'h003c;
         RegISR    <= RegISR&16'hffc3;    // Clear RegISR bits
      end
      else begin
         // Done IRQ handle, clear flag
         isInIRQ <= 0;
         // Enable interrupts
         runPC <= ID_ENABLE_INTERRUPT;
      end
   end

   state[ST_HANDLE_PORT_STATUS]:
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

   state[ST_RECEIVE_FRAME_COUNT]:
   begin
      FrameCount <= ReadData[15:8];
   end

   state[ST_RECEIVE_FRAME_STATUS]:
   begin
      FrameCount <= FrameCount-8'd1;
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
         runPC <= ID_FLUSH_FRAME;
      end
      else begin
         // Valid frame, so start processing
         FrameValid <= 1;
         isEthBroadcast <= ReadData[7];
         isEthMulticast <= ReadData[6];
         numPacketValid <= numPacketValid + 16'd1;
      end
   end

   state[ST_RECEIVE_FRAME_LENGTH]:
   begin
      if (ReadData[11:0] == 12'd0) begin
         numPacketInvalid <= numPacketInvalid + 10'd1;
         runPC <= ID_FLUSH_FRAME;
      end
      else begin
         rxPktWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
      end
   end

   state[ST_RECEIVE_DMA_REQUEST]:
   begin
      // set request flag
      recvDMAreq <= 1;
      waitInfo <= WAIT_RECEIVE_DMA;
   end

   state[ST_RECEIVE_DMA_WAIT]:
   begin
      // On entry, recvDMAreq==1
      // When isDMARead==1, set recvDMAreq=0
      // Then, when isDMARead==0, go to next state
      if (recvDMAreq&isDMARead) begin
         recvDMAreq <= 0;
      end
      else if (~(recvDMAreq|isDMARead)) begin
         waitInfo <= WAIT_NONE;
         // Increment counters
         numIPv4 <= numIPv4 + {9'd0, isIPv4};
         numARP <= numARP + {7'd0, isARP};
         numICMP <= numICMP + {7'd0, isICMP};
         numUDP <= numUDP + {9'd0, isUDP};
         runPC <= ID_FLUSH_FRAME;
      end
   end

   state[ST_RECEIVE_FLUSH_WAIT]:
   begin
      // Wait for bit 0 in Register RXQCR to be cleared;
      // Then enable interrupt
      //   - if a read command, start sending response
      //     (check FrameCount after send complete)
      //   - else if more frames available, receive status of next frame
      //   - else go to idle state
      if (ReadData[0] == 1'b0) begin
         timeReceive <= timeSinceIRQ;
         if (sendARP) begin
            ReplyBuffer[ID_Rep_Frame_Length] <= 16'h0806; // ARP EtherType
            runPC <= ID_ENABLE_DMA_SEND;
         end
         else if (isEcho) begin
            // Echo (ICMP) response
            ReplyBuffer[ID_Rep_Frame_Length] <= 16'h0800;   // IPv4 EtherType
            ReplyBuffer[ID_Rep_IPv4_Length] <= IPv4_Length; // Same length as request
            ReplyBuffer[ID_Rep_IPv4_Prot][7:0] <= 8'd1;     // ICMP protocol
            runPC <= ID_ENABLE_DMA_SEND;
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
            runPC <= ID_ENABLE_DMA_SEND;
         end
         else begin
            if (FrameCount != 8'd0) begin
               runPC <= ID_READ_FRAME_STATUS;
            end
         end
         waitInfo <= WAIT_NONE;
      end
      else begin
         runPC <= ID_READ_CMD_REG;  // Check again
         waitInfo <= WAIT_FLUSH;
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

   state[ST_SEND_DMA_REQUEST]:
   begin
      // Set request flag
      sendDMAreq <= 1;
      waitInfo <= WAIT_SEND_DMA;
   end

   state[ST_SEND_DMA_WAIT]:
   begin
      // On entry, sendDMAreq==1
      // When isDMAWrite==1, set sendDMAreq=0
      // Then, when isDMAWrite==0, go to next state
      if (sendDMAreq&isDMAWrite) begin
         sendDMAreq <= 0;
      end
      else if (~(sendDMAreq|isDMAWrite)) begin
         waitInfo <= WAIT_NONE;
         isForward <= 1'd0;
         runPC <= ID_DISABLE_DMA;
      end
   end

   state[ST_SEND_TXQ_ENQUEUE_WAIT]:
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

   state[ST_SEND_END]:
   begin
      numPacketSent <= numPacketSent + 8'd1;
      timeSend <= timeSinceIRQ;
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

   state[ST_WAVEFORM_ADDR]:
   begin
      SDReg <= Addr16;
      RWcnt <= (RWcnt == 3'd3) ? 3'd0 : RWcnt + 3'd1;
   end

   state[ST_WAVEFORM_DATA]:
   begin
      RWcnt <= ((isWrite && (RWcnt == 3'd3)) || (RWcnt == 3'd5)) ? 3'd0 : RWcnt + 3'd1;
      if (isWrite) begin
         SDReg <= WriteData;
      end
      else if (RWcnt == 3'd4) begin
         eth_data <= SD;
      end
   end

   endcase // case (1'b1)

   end // else: !if(stateError)

end

//*****************************************************************
//  ETHERNET Receive DMA state machine
//*****************************************************************

parameter[1:0]
    ST_RECEIVE_DMA_IDLE = 2'd0,
    ST_RECEIVE_DMA_ETHERNET_HEADERS = 2'd1,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 2'd2,
    ST_RECEIVE_DMA_ICMP_DATA = 2'd3;

reg[1:0] recvState = ST_RECEIVE_DMA_IDLE;
reg[1:0] nextRecvState = ST_RECEIVE_DMA_IDLE;

reg[5:0] recvCnt;       // Index into PacketBuffer
reg[1:0] skipCnt;       // For skipping first 3 words in RXQ
reg[9:0] rfw_count;     // Counts words in FireWire packets (max is 1024 words, or 2048 bytes)

// Shift register for I/O control. The register is shifted left with each clock, with the left-most
// bit placed on the right (shift and rotate). Each state (except IDLE) is entered with
// recvCtrl==5'b00001 and goes through the following sequence:
//   00001   (DMA_RDn=0), wait
//   00010   (DMA_RDn=0), wait
//   00100   (DMA_RDn=0), read data (dataReady=1)
//   01000   (DMA_RDn=0), use data (dataValid=1)
//   10000   (DMA_RDn=1), transition to next state
reg[4:0] recvCtrl = 5'b00001;

assign DMA_RDn = recvCtrl[4];
// We sample the data after two cycles
wire dataReady;
assign dataReady = recvCtrl[2];
// We use the data after three cycles
wire dataValid;
assign dataValid = recvCtrl[3];

// Transition to next state when recvCtrl=10000, so that we enter each new state with
// recvCtrl=00001. Note that nextRecvState must be set before recvTransition -- usually
// it is set when dataValid, though it can be set earlier if the next state transition
// does not depend on the data read from the KSZ8851.
wire recvTransition;
assign recvTransition = recvCtrl[4];

always @(posedge sysclk)
begin

   if (sample_start && sample_busy) begin
      sample_start <= 1'd0;
      writeHub <= 1'd0;
   end

   // Clear eth_send_fw_req flag
   if (eth_send_fw_req & eth_send_fw_ack) begin
      eth_send_fw_req <= 1'd0;
      // Note pending local write request
      writeRequestPending <= isLocal&blockWrite;
   end

   if (writeRequestPending && !eth_send_fw_ack) begin
      // Now, we can access the packet memory.
      // This assumes that another Ethernet packet is not
      // received before we finish the local write request.
      writeRequestPending <= 1'b0;
      writeRequestBlock <= 1'b1;
   end

   if (eth_block_wen) begin
      writeRequestQuad <= 1'b0;
      writeRequestBlock <= 1'b0;
   end

   // Write to IP address register
   if (ip_reg_wen) begin
      // Following is equivalent to: ip_address <= reg_wdata;
      ReplyBuffer[ID_Rep_IPv4_Address0] <= {reg_wdata[7:0], reg_wdata[15:8] };
      ReplyBuffer[ID_Rep_IPv4_Address1] <= {reg_wdata[23:16], reg_wdata[31:24] };
   end

   // Left shift and rotate recvCtrl when not in IDLE state
   recvCtrl <= ((recvState == ST_RECEIVE_DMA_IDLE) && !recvDMAreq) ? 5'b00001 :
               { recvCtrl[3:0], recvCtrl[4] };

   if (recvTransition) begin
      recvState <= nextRecvState;
   end

   case (recvState)

   ST_RECEIVE_DMA_IDLE:
   begin
      isDMARead <= 0;
      mem_wen <= 0;
      rfw_count <= 10'd0;
      skipCnt <= 2'd3;  // Skip first 3 words in packet when receiving
                        // ignore(1) + status(1) + byte-count(1)
      nextRecvState <= ST_RECEIVE_DMA_IDLE;
      if (resetActive) begin
         FireWirePacketFresh <= 0;
         fwPacketDropped <= 0;
         writeRequestBlock <= 0;
         writeRequestQuad <= 0;
         writeRequestPending <= 0;
         numIPv4Mismatch <= 10'd0;
         numPacketError <= 10'd0;
         ethFrameError <= 0;
         ethIPv4Error <= 0;
         ethUDPError <= 0;
         ethDestError <= 0;
      end
      if (recvDMAreq) begin
         isDMARead <= 1;
         FireWirePacketFresh <= 0;
         fwPacketDropped <= 0;
         recvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
      end
   end

   ST_RECEIVE_DMA_ETHERNET_HEADERS:
   begin
      if (dataReady) PacketBuffer[recvCnt] <= `SDSwapped;

      if (dataValid) begin
         if ((recvCnt == ID_Frame_End) && !(isRaw|isIPv4|isARP)) begin
            ethFrameError <= 1'd1;
            numPacketError <= numPacketError + 10'd1;
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
               numPacketError <= numPacketError + 10'd1;
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
               else if ((ip_address != IPv4_fpgaIP) && !isEthBroadcast && !isEthMulticast) begin
                  // If IP assigned, but not equal, we process the packet anyway,
                  // but keep track of the number of times this occurred.
                  // We could decide to update ip_address.
                  numIPv4Mismatch <= numIPv4Mismatch + 10'd1;
               end
               nextRecvState <= ST_RECEIVE_DMA_ETHERNET_HEADERS;
            end
         end
         else if ((recvCnt == ID_UDP_End) && isUDP) begin
            if (!isPortValid) begin
               ethUDPError <= 1'd1;
               numPacketError <= numPacketError + 10'd1;
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
         skipCnt <= (skipCnt == 2'd0) ? 2'd0 : skipCnt - 2'd1;
         recvCnt <= (skipCnt != 2'd0) ? ID_Frame_Begin :
                    ((recvCnt == ID_Frame_End) && isARP) ? ID_ARP_Begin :
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
      if (dataReady) begin
         if (rfw_count[0] == 0)
            FireWireQuadlet[31:16] <= `SDSwapped;
         else
            FireWireQuadlet[15:0] <= `SDSwapped;
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
      if (dataReady) begin
         if (rfw_count[0] == 0) begin
            FireWireQuadlet[31:16] <= `SDSwapped;
            if (rfw_count[9:1] == 9'd0)
               {dest_bus_id, dest_node_id} <= `SDSwapped;
            else if (rfw_count[9:1] == 9'd1)
               fw_src_id <= `SDSwapped;
            else if (rfw_count[9:1] == 9'd3)
               block_data_length <= `SDSwapped;
         end
         else begin
            FireWireQuadlet[15:0] <= `SDSwapped;
            if (rfw_count[9:1] == 9'd0)
               {fw_tl, fw_tcode, fw_pri} <= {`SDSwapped[15:10], `SDSwapped[7:0]};
            else if (rfw_count[9:1] == 9'd2)
               fw_dest_offset <= `SDSwapped;  // only using 16 lowest bits
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
         else if ((rfw_count == 10'd5) && quadWrite && (fw_dest_offset == {`ADDR_HUB, 12'h800 })) begin
            // If broadcast read request, start sampling feedback data
            sample_start <= 1;
            writeHub <= 1;
         end
         else if ((rfw_count == 10'd7) && quadWrite) begin
            fw_quadlet_data <= FireWireQuadlet;
         end
         else if (rfw_count == maxCountFW) begin
            nextRecvState <= ST_RECEIVE_DMA_IDLE;  // was ST_RECEIVE_DMA_FRAME_CRC;
            useUDP <= isUDP;
            FireWirePacketFresh <= 1;
            // Set sample_start to trigger sampling data for block read.
            // Just needs to be early enough that sampling is finished before we access it
            // in ST_SEND_DMA_PACKETDATA_BLOCK.
            sample_start <= blockRead&isLocal&addrMain;
            // Set writeRequest for local quadlet and block write.
            // Note that for block write, we do not set it here if isRemote is true,
            // so that the Firewire module can access the packet memory first
            // (isLocal and isRemote are both true for broadcast packets).
            // This is not an issue for quadlet writes because we cache the data
            // in fw_quadlet_data so we do not need to access packet memory.
            writeRequestQuad <= isLocal&quadWrite;
            writeRequestBlock <= isLocal&(~isRemote)&blockWrite;
            if (isRemote) begin
               // Request to forward pkt
               // We drop the packet if Firewire bus is in reset or if bus generation number
               // specified in packet does not match.
               if (fw_bus_reset || (host_fw_bus_gen != fw_bus_gen)) begin
                  fwPacketDropped <= 1;
               end
               else begin
                  eth_send_fw_req <= 1;
                  host_fw_addr <= fw_src_id;
               end
            end
         end
         else begin
            nextRecvState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
         end
      end
   end

   endcase // case (recvState)
end


//*****************************************************************
//  ETHERNET Send DMA state machine
//*****************************************************************

parameter[3:0]
    ST_SEND_DMA_IDLE = 4'd0,
    ST_SEND_DMA_CONTROLWORD = 4'd1,
    ST_SEND_DMA_BYTECOUNT = 4'd2,
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
reg[7:0] numSendStateInvalid;

reg[9:0] sfw_count;     // Counts words in FireWire packets (max is 1024 words, or 2048 bytes)
reg[1:0] xcnt;          // Counts words in extra packet

// sendCtrl==100 in the IDLE state.
// When entering a state, sendCtrl==100 (DMA_WRn inactive)
//    Writing data (via SDRegDWR) will coincide with falling edge of DMA_WRn
// Transition to next state (or increment sfw_count or replyCnt) when sendCtrl==010
//    (with rising edge of DMA_WRn)
reg [2:0] sendCtrl = 3'b100;
assign DMA_WRn = sendCtrl[2];

wire   sendTransition;
assign sendTransition = sendCtrl[1];
// 1 cycle before the transition
wire sendPreTransition;
assign sendPreTransition = sendCtrl[0];

always @(posedge sysclk)
begin

   // Shift register for sequencing DMA send operations
   sendCtrl <= (sendState == ST_SEND_DMA_IDLE) ? 3'b100 : {sendCtrl[1:0], sendCtrl[2] };

   if (sendTransition) begin
      sendState <= nextSendState;
      txPktWords <= txPktWords + 12'd1;
   end

   case (sendState)

   ST_SEND_DMA_IDLE:
   begin
      isDMAWrite <= 0;
      eth_read_en <= 0;
      sample_read <= 0;
      icmp_read_en <= 0;
      txPktWords <= 12'd0;
      sfw_count <= 10'd0;
      xcnt <= 2'd0;
      if (resetActive) begin
         ethAccessError <= 0;
      end
      if (sendDMAreq) begin
         isDMAWrite <= 1;
         sendState <= ST_SEND_DMA_CONTROLWORD;
      end
   end

   ST_SEND_DMA_CONTROLWORD:
   begin
      // TX Control word
      // B15  : TXIC transmit interrupt on completion
      // B0-B5: TXFID transmit frame ID
      SDRegDWR <= 16'h0;  // Control word = 0
      nextSendState <= ST_SEND_DMA_BYTECOUNT;
   end

   ST_SEND_DMA_BYTECOUNT:
   begin
      if (isForward && !useUDP) begin
         // Forwarding raw data from FireWire
         SDRegDWR <= `ETH_FRAME_SIZE + `FW_EXTRA_SIZE + sendLen;
      end
      else if (isForward && useUDP) begin
         // Forwarding data from FireWire
         SDRegDWR <= `ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE + sendLen;
      end
      else if (sendARP) begin
         // ARP response: 14 + 28
         SDRegDWR <= 16'd42;
      end
      else if (isEcho) begin
         // Echo (ICMP) response: 14 + IPv4_Length
         SDRegDWR <= 16'd14 + IPv4_Length;
      end
      else if (useUDP) begin
         SDRegDWR <= sendExtra ? (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE) :
                      quadRead ? (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE + `FW_QRESP_SIZE)
                               : (`ETH_FRAME_SIZE + `IPv4_UDP_EXTRA_SIZE + `FW_BRESP_SIZE) + block_data_length;
      end
      else begin
         // Byte count for local raw packet
         // (block_data_length must be a multiple of 4)
         SDRegDWR <= sendExtra ? (`ETH_FRAME_SIZE + `FW_EXTRA_SIZE) :
                      quadRead ? (`ETH_FRAME_SIZE + `FW_QRESP_SIZE + `FW_EXTRA_SIZE)
                               : (`ETH_FRAME_SIZE + `FW_BRESP_SIZE + `FW_EXTRA_SIZE) + block_data_length;
      end
      nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
      replyCnt <= Frame_Reply_Begin;
   end

   ST_SEND_DMA_ETHERNET_HEADERS:
   begin
      if (sendTransition) replyCnt <= replyCnt + 6'd1;
      `SDRegDWRSwapped <= (ReplyIndex[replyCnt][5]==isPacket) ?
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
            nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
         end
         else if (!(isUDP || isEcho || isForward)) begin
            // Raw packet
            nextSendState <= sendExtra ? ST_SEND_DMA_EXTRA : ST_SEND_DMA_PACKETDATA_HEADER;
         end
         else begin
            nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
         end
      end
      else if (replyCnt == IPv4_Reply_End) begin
         if (sendTransition) replyCnt <= isEcho ? ICMP_Reply_Begin : UDP_Reply_Begin;
         nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
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
      else begin
         nextSendState <= ST_SEND_DMA_ETHERNET_HEADERS;
      end
   end

   ST_SEND_DMA_ICMP_DATA:
   begin
      `SDRegDWRSwapped <= (sfw_count[0] == 0) ? mem_rdata[31:16]
                                              : mem_rdata[15:0];
      // Increment a little earlier due to reading from memory
      if (sendPreTransition) sfw_count <= sfw_count + 10'd1;
      // sfw_count is in words, icmp_data_length is in bytes
      if (sfw_count[9:0] == icmp_data_length[10:1])
         nextSendState <= ST_SEND_DMA_FINISH;
      else
         nextSendState <= ST_SEND_DMA_ICMP_DATA;
   end

   // Send first 6 words (3 quadlets), which are nearly identical between quadlet read response
   // and block read response (only difference is tcode).
   // For block read response, send an additional 4 words (2 quadlets), which are block data length
   // and header CRC.
   ST_SEND_DMA_PACKETDATA_HEADER:
   begin
      SDRegDWR <= Firewire_Header_Reply[sfw_count[3:0]];
      if ((sfw_count[3:0] == 4'd5) && quadRead) begin
         eth_reg_raddr <= fw_dest_offset;
         // Get ready to read data from the board.
         ethAccessError <= sample_busy ? 1'd1 : ethAccessError;
         eth_read_en <= 1;
         if (sendTransition) sfw_count <= 10'd0;
         nextSendState <= ST_SEND_DMA_PACKETDATA_QUAD;
      end
      else if (sfw_count[3:0] == 4'd9) begin  // block read
         if (blockRead) begin
            sample_read <= addrMain;
            eth_read_en <= ~addrMain;
            ethAccessError <= (~addrMain&sample_busy) ? 1'd1 : ethAccessError;
            if (sendTransition) sfw_count <= 10'd0;
            nextSendState <= ST_SEND_DMA_PACKETDATA_BLOCK;
         end
         else  // Should not happen
            nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
      end
      else begin
         // stay in this state
         if (sendTransition) sfw_count <= sfw_count + 10'd1;
         nextSendState <= ST_SEND_DMA_PACKETDATA_HEADER;
      end
   end

   ST_SEND_DMA_PACKETDATA_QUAD:
   begin
      if (sfw_count[0] == 0) begin
         `SDRegDWRSwapped <= eth_reg_rdata[31:16];
         if (sendTransition) sfw_count[0] <= 1;
         // stay in this state
         nextSendState <= ST_SEND_DMA_PACKETDATA_QUAD;
      end
      else begin
         `SDRegDWRSwapped <= eth_reg_rdata[15:0];
         if (sendTransition) sfw_count[0] <= 0;
         nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
      end
   end

   ST_SEND_DMA_PACKETDATA_BLOCK:
   begin
      if (sendTransition) sfw_count <= sfw_count + 10'd1;
      if (sfw_count[0] == 0) begin
         `SDRegDWRSwapped <= (addrMain ? sample_rdata[31:16] : eth_reg_rdata[31:16]);
         // stay in this state
         nextSendState <= ST_SEND_DMA_PACKETDATA_BLOCK;
      end
      else begin
         `SDRegDWRSwapped <= (addrMain ? sample_rdata[15:0] : eth_reg_rdata[15:0]);
         // 12-bit address increment, even though Firewire limited to 512 quadlets (9 bits)
         // because this way we can support non-zero starting addresses.
         if (sendTransition) eth_reg_raddr[11:0] <= eth_reg_raddr[11:0] + 12'd1;
         // sfw_count is in words and block_data_length is in bytes, but we compare in quadlets
         if ((sfw_count[9:1] + 8'd1) == block_data_length[10:2])
            nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
         else
            nextSendState <= ST_SEND_DMA_PACKETDATA_BLOCK;
      end
   end

   ST_SEND_DMA_PACKETDATA_CHECKSUM:
   begin
      eth_read_en <= 0;    // Relinquish control of read bus
      sample_read <= 0;    // Relinquish control of sample read bus
      if (sendTransition) sfw_count[0] <= 1;
      SDRegDWR <= 16'd0;    // Checksum currently not set
      if (sfw_count[0] == 1)
         nextSendState <= ST_SEND_DMA_EXTRA;
      else
         nextSendState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
   end

   ST_SEND_DMA_FWD:
   begin
      if (sendTransition) sfw_count <= sfw_count + 10'd1;
      `SDRegDWRSwapped <= (sfw_count[0] == 0) ? sendData[31:16] : sendData[15:0];
      // Increment a little earlier due to reading from memory
      if (sendPreTransition && (sfw_count[0] == 1)) sendAddr <= sendAddr + 9'd1;
      // sfw_count is in words, sendLen is in bytes
      if (sfw_count == (sendLen[10:1]-10'd1))
         nextSendState <= ST_SEND_DMA_EXTRA;
      else
         nextSendState <= ST_SEND_DMA_FWD;
   end

   ST_SEND_DMA_EXTRA:
   begin
      if (sendTransition) xcnt <= xcnt + 2'd1;
      `SDRegDWRSwapped <= ExtraData[xcnt];
      nextSendState <= (xcnt == 2'd3) ? ST_SEND_DMA_FINISH : ST_SEND_DMA_EXTRA;
   end

   ST_SEND_DMA_FINISH:
   begin
      icmp_read_en <= 0;
      sendAck <= 0;
      // If an odd number of words, first send a dummy word (not sure if this is necessary).
      if (txPktWords[0]) begin
         SDRegDWR <= 16'd0;
         // we are done
         nextSendState <= ST_SEND_DMA_IDLE;
      end
      else begin
         // Otherwise, go directly to IDLE state
         isDMAWrite <= 0;
         sendState <= ST_SEND_DMA_IDLE;
      end
   end

   default:
   begin
      numSendStateInvalid <= numSendStateInvalid + 8'd1;
      sendState <= ST_SEND_DMA_IDLE;
   end

   endcase // case (sendState)
end

// Following handles writing to board registers

parameter[2:0]
   BW_IDLE = 0,
   BW_WSTART = 1,
   BW_WRITE = 2,
   BW_WRITE_GAP = 3,
   BW_BLK_WEN = 4;

reg[2:0] bwState = BW_IDLE;
reg[1:0] bwCnt;
reg dac_local;         // Indicates that DAC entries in block write are for this board_id

always @(posedge sysclk)
begin

   case (bwState)

   BW_IDLE:
   begin
      bwCnt <= 2'd0;
      if (writeRequestQuad) begin
         eth_reg_waddr <= fw_dest_offset;
         eth_reg_wdata <= fw_quadlet_data;
         // Special case: write to FireWire PHY register
         if (addrMain && (fw_dest_offset[11:0] == {8'h0, `REG_PHYCTRL})) begin
            // check the RW bit to determine access type (bit 12, after byte-swap)
            lreq_type <= (fw_quadlet_data[12] ? `LREQ_REG_WR : `LREQ_REG_RD);
            lreq_trig <= 1;
         end
         eth_reg_wen <= 1;
         eth_block_wen <= 1;
      end
      else if (writeRequestBlock) begin
         bwState <= BW_WSTART;
         // Assert eth_block_wstart for 80 ns before starting local block write
         // (same timing as in Firewire module)
         eth_block_wstart <= 1;
         // Set up for writing
         eth_reg_waddr <= fw_dest_offset;
         local_raddr <= 9'd5;   // block write data starts at quadlet 5
         eth_reg_waddr[15:12] <= fw_dest_offset[15:12];
         if (addrMain) begin
            eth_reg_waddr[7:4] <= 4'd0;  // will start with channel 1
            eth_reg_waddr[3:0] <= `OFF_DAC_CTRL;
            dac_local <= 1;
         end
         else begin
            eth_reg_waddr[11:0] <= fw_dest_offset[11:0] - 12'd1;
         end
      end
      else begin
         eth_reg_wen <= 0;    // Clean up from quadlet/block writes
         eth_block_wen <= 0;
         eth_block_wstart <= 0;
         lreq_trig <= 0;      // Clear lreq_trig in case it was set
      end
   end

   BW_WSTART:
   begin
      bwCnt <= bwCnt + 2'd1;
      if (bwCnt == 2'd3) begin
         eth_block_wstart <= 0;
         bwState <= BW_WRITE;
         // bwCnt will be set to 0 (overflow)
      end
   end

   BW_WRITE:
   begin
      local_raddr <= local_raddr + 9'd1;
      if (addrMain) begin
         // Real-time block write.
         // Starting with Rev 7, the first 4 entries are the DAC (same as Rev 1-6),
         // but that is followed by the status register (for power control).
         // Note that for broadcast write, the packet will have data for all boards;
         // thus, we check for consecutive DAC entries that match our board_id and
         // assume that the next entry is the status register for this board.
         if (eth_reg_waddr[7:4] == `NUM_CHANNELS) begin
            // Status write
            eth_reg_waddr[7:0] <= 8'd0;
            if (dac_local) begin
               // Write status register. Note that we only write the lowest 20 bits,
               // so that we do not accidentally make other changes, such as requesting
               // an FPGA reboot.
               eth_reg_wdata <= {12'd0, mem_rdata[19:0]};
               eth_reg_wen <= 1;
               bwState <= BW_WRITE_GAP;
            end
            dac_local <= 0;
         end
         else begin
            // DAC write
            if (eth_reg_waddr[7:4] == 4'd0) begin
               // Restart with DAC channel 1
               eth_reg_waddr[7:4] <= 4'd1;
               eth_reg_waddr[3:0] <= `OFF_DAC_CTRL;
               dac_local <= 1;
            end
            else
               eth_reg_waddr[7:4] <= eth_reg_waddr[7:4] + 4'd1;
            // only respond to bit 27-24 == board_id
            if (mem_rdata[27:24] == board_id) begin
               eth_reg_wdata <= {1'b0, mem_rdata[30:0]};
               // MSB is "valid" bit for DAC write (addrMain)
               if (mem_rdata[31]) begin
                  eth_reg_wen <= 1;
                  bwState <= BW_WRITE_GAP;
               end
            end
            else
               dac_local <= 0;
         end
      end
      else begin
         // All other local block writes (except addrMain)
         eth_reg_waddr[11:0] <= eth_reg_waddr[11:0] + 12'd1;
         eth_reg_wdata <= mem_rdata;
         eth_reg_wen <= 1;
         bwState <= BW_WRITE_GAP;
      end
   end

   BW_WRITE_GAP:
   begin
      // hold reg_wen low for 60 nsec (3 cycles)
      bwCnt <= bwCnt + 2'd1;
      eth_reg_wen <= 1'b0;
      if (bwCnt == 2'd3) begin
         // bwCnt will be set to 0 (overflow)
         // block_data_length is in bytes
         if (local_raddr == (block_data_length[10:2] + 9'd5))
            bwState <= BW_BLK_WEN;
         else
            bwState <= BW_WRITE;
      end
   end

   BW_BLK_WEN:
   begin
      // Wait 60 nsec before asserting eth_block_wen
      bwCnt <= bwCnt + 2'd1;
      if (bwCnt == 2'd3)
         eth_block_wen <= 1'b1;
      // Asserting eth_block_wen will cause writeRequestBlock to be cleared
      if (~writeRequestBlock)
         bwState <= BW_IDLE;
      // Restore the DAC device address for blk_wen because the block write
      // processing ends by addressing the status/control register instead of the DAC.
      if (addrMain)
         eth_reg_waddr[3:0] <= `OFF_DAC_CTRL;    // set dac device address
   end

   default:
   begin
      // Could note this as an error
      bwState <= BW_IDLE;
   end

   endcase // case (bwState)
end

endmodule
