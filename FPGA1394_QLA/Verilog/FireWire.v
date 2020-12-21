/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2020 ERC CISST, Johns Hopkins University.
 *
 * This module implements the FireWire link layer state machine, which defines
 * the operation of the phy-link interface.  The state machine is triggered on
 * the positive edge of sysclk and makes its transitions based on the input ctl
 * lines and the current state.
 *
 * Inputs to this state machine are sysclk (1 bit) and ctl (2 bits).  data (8
 * bits) is normally data input/output, but does govern the state machine in
 * receive mode, where it indicates received data prefix.
 *
 * Outputs include ctl and data in transmit mode.  This module also outputs
 * state-related data and signals that are used by the main controller.
 *
 * Revision history
 *     04/24/08    Paul Thienphrapa    Initial revision
 *     10/13/10    Paul Thienphrapa    Copied from SnakeFPGA-rev2 and tweaked
 *                                       for Xilinx
 *     10/31/11    Paul Thienphrapa    React to rx packets only when addressed
 *     11/11/11    Paul Thienphrapa    Happy 111111!!11!
 *                                     Fixed mixed blocking/non-blocking issues`
 *     10/16/13    Zihan Chen          Modified to support hub capability
 *     10/28/13    Zihan Chen          Added seperate write address line
 *     08/23/14    Zihan Chen          Added support for Eth1394
 *     12/02/16    Zihan Chen          Added packet forward from Ethernet
 *     05/03/18    Jie Ying Wu         Added additional fields for velocity
 *     07/11/20    Peter Kazanzides    Added status/control register at end of block write
 *     12/08/20    Peter Kazanzides    Removed eth1394 (not needed)
 */

// LLC: link layer controller (implemented in this file)

/**  
 *   NOTE: 
 *      - only part of the FireWire link layer controller is implemented 
 *      - transaction layer and link layer are mixed (not good, works for now)
 *      - ONLY control PC and FPGA_QLA boards can be attached to the same bus
 *
 *   Broadcast Packets (write ONLY)
 *      - bc_qwrite:  broadcast quadlet write
 *      - bc_bwrite:  broadcast block write
 *         - from PC 
 *         - from FPGA (priority = 4'hA)
 *   
 *   TX Mode
 *      FPGA mainly operates in passive mode, which means it does not initiate
 *      1394 transactions. The only exception is to broadcast self states as a 
 *      "response" to broadcast write from PC. The type of TX packets includes 
 *      the following list:
 *     
 *      List of TX types
 *        - ACK packet (e.g. ACK_DONE // ACK_PEND)
 *        - Quadlet Response
 *        - Block Response
 *           - Local info 
 *           - Hub info (with all FPGA nodes state)
 *        - Block Broadcast Write
 * 
 *    RX Mode
 *       List of RX types
 *         - QREAD: from PC 
 *         - BREAD: 
 *            - from PC for 1 board state
 *            - from PC for hub/prom/prom_qla data 
 *         - QWRITE: 
 *            - from PC: non-broadcast mode
 *            - from PC: broadcast mode
 *               - dest offset = 0xffff ffff xxxx indicates bc read request
 *               - otherwise, normal broadcast 
 *         - BWRITE:
 *            - from PC non-broadcast mode
 *            - from PC broadcast mode
 *            - from other FPGA broadcast mode (priority = 4'hA)
 *
 *  --------------------------------------------------------------------------------
 *  2014-01-24 NOTE for fake broadcast packet  Zihan Chen
 *   We noticed that some FireWire cards have issue with broadcast packets (can not 
 *   async read after sending broadcast packets). This leads us to use an asynchronous 
 *   write packet as fake broadcast packet on the PC software for better robustness. 
 *    
 *   Lists:
 *     - Query Packet:  dest_node_id = 0, dest_addr = 0xffffffff000f   (< Rev 7)
 *                      dest_node_id = 0, dest_addr = 0x1800           (FirewirePort, Rev 7+)
 *                      dest_node_id = 0x3f, dest_addr = 0x1800        (EthBasePort, Rev 7+)
 *     - Command Packet: dest_node_id = 0, dest_addr = 0xffffffff0000  (< Rev 7 and FirewirePort, Rev 7+)
 *                       dest_node_id = 0x3f, dest_addr = 0            (EthBasePort, Rev 7+)
 */
 

// -----------------------------------------------------------------
// IEEE-1394 64-bit Address Mapped 
// We only use last 16-bit, the rest bit number is 0 indexed
// 
//  addr[15:12] map (see Constants.v)
//     4'h0: board register + device memory
//     4'h1: hub caching space
//     4'h2: M25P16 prom space
//     4'h3: QLA 25AA128 prom space
//         
// In addition, the IEEE-1394 CSR Architecture specifies a register
// space starting at offset ffff f000 0000 (last 256 MB).
// Within this space, the first 2 KB is the Initial Node Space:
//   ffff f000 0000 -> ffff f000 01ff  -- CSR Architecture (512 bytes)
//   ffff f000 0200 -> ffff f000 03ff  -- Serial Bus (512 bytes)
//   ffff f000 0400 -> ffff f000 07ff  -- Configuration ROM
// The Configuration ROM follows ISO/IEC 13213:
//   The minimum ROM format requires the following 32-bit value to be
//   stored at address ffff f000 0400:  | 1 (8) | vendor_id (24) |
//   For JHU-LCSR, the 24-bit vendor_id is FA610E (see MIN_ROM_ENTRY)
// -----------------------------------------------------------------


// global constants, e.g. register & device addresses
`include "Constants.v"

// constants for receive speed codes
// See Book P237 Receiving Packets, D[0] is omitted here
`define RX_S100 3'b000            // 100 Mbps
`define RX_S200 3'b001            // 200 Mbps
`define RX_S400 3'b101            // 400 Mbps

// transmit mode ctl constants (llc driving)
`define CTL_IDLE 2'b00             // link asserts idle (done)
`define CTL_DATA 2'b01             // link is transmitting data
`define CTL_HOLD 2'b10             // link wants to hold the bus
`define CTL_UNUSED 2'b11           // link UNUSED

// transmit mode ctl constant (phy driving)
`define CTL_PHY_IDLE 2'b00         // phy driven ctrl status idle
`define CTL_PHY_RECV 2'b01         // phy driven ctrl status receive
`define CTL_PHY_STAT 2'b10         // phy driven ctrl status status
`define CTL_PHY_GRNT 2'b11         // phy driven ctrl status grand

// packet sizes
`define SZ_ACK 8                  // ack packet size
`define SZ_QREAD 16'd128          // quadlet read packet size
`define SZ_QWRITE 16'd160         // quadlet write packet size
`define SZ_QRESP 16'd160          // quadlet read response size
`define SZ_BWRITE 16'd192         // block write packet base size
`define SZ_BRESP 16'd192          // block read response base size
`define SZ_STAT  16'd4            // phy status transfer size (bits)
`define SZ_REG_STAT 16'd16        // phy register transfer size (bits)

// ack values
`define ACK_DONE 4'h1             // transaction complete, applies to writes
`define ACK_PEND 4'h2             // transaction pending, applies to reads
`define ACK_DATA 4'hD             // ack crc error, used as a general error

// types of transmissions
`define TX_TYPE_NULL  4'd0        // no transmission
`define TX_TYPE_DONE  4'd1        // ack complete (for write requests)
`define TX_TYPE_PEND  4'd2        // ack pending (for read requests)
`define TX_TYPE_DATA  4'd3        // ack data error, for crc or data length
`define TX_TYPE_QRESP 4'd4        // for quadlet read response
`define TX_TYPE_BRESP 4'd5        // for block read response
`define TX_TYPE_BBC   4'd6        // for block write broadcast
`ifdef HAS_ETHERNET
`define TX_TYPE_FWD   4'd7        // for 1394 pkt forward from eth port
`endif

// PHY status bit masks.
// Note that in the Firewire documentation, these are the 4 LSB, but we
// left shift them into the status buffer (st_buff) when reading.
`define ARB_RESET_GAP   2'd3
`define SUBACTION_GAP   2'd2
`define BUS_RESET_START 2'd1
`define PHY_INTERRUPT   2'd0

// other
`define CRC_INIT -32'd1           // initial value to start new crc calculation
`define INVALID_SIZE -16'd1       // packet size that we should never encounter

// FA610E is the 24-bit CID assigned to JHU-LCSR by IEEE
`define JHU_LCSR_CID   24'hFA610E

// Minimum Configuration ROM Entry:  | 01 (8) | FA610E (24) |
`define MIN_ROM_ENTRY  {4'h01, `JHU_LCSR_CID}

module PhyLinkInterface(
    // globals
    input wire sysclk,           // system clock
    input wire[3:0] board_id,    // global board id
    output reg[5:0] node_id,     // phy node id

    // phy-link interface bus
    inout[1:0] ctl_ext,          // control line
    inout[7:0] data_ext,         // data bus
    
    // act on received packets
    output reg reg_wen,          // register write signal
    output reg blk_wen,          // block write signal
    output reg blk_wstart,       // block write is starting
    
    // register access
    output reg[15:0] reg_raddr,   // read address to external register file
    output reg[15:0] reg_waddr,   // write address to external register file
    input wire[31:0] reg_rdata,   // read data from external register file
    output reg[31:0] reg_wdata,   // write data to external register file

`ifdef HAS_ETHERNET
    // eth/fw interface
    input wire eth_send_fw_req,   // request from ethernet to send fw pkt
    output reg eth_send_fw_ack,   // ack sent fw pkt
    output reg[8:0] eth_fwpkt_raddr,  // firewire pkt read addr
    input wire[31:0] eth_fwpkt_rdata, // firewire pkt read data
    input wire[15:0] eth_fwpkt_len,   // firewire pkt len in bytes
    input wire[15:0] eth_fw_addr,     // Host (PC) Firewire address (via Ethernet)

    output reg eth_send_req,         // request to send ethernet packet
    input wire eth_send_ack,         // ack from ethernet module
    input wire[8:0] eth_send_addr,   // packet address bus
    output wire[31:0] eth_send_data, // packet data bus
    output reg[15:0] eth_send_len,   // packet data len (bytes)
`endif

    output reg fw_bus_reset,         // 1 -> Firewire bus reset is in process

    // transmit parameters
    output reg lreq_trig,            // trigger signal for a phy request
    output reg[2:0] lreq_type,       // type of request to give to the phy

    // broadcast related fields
    input wire[15:0] rx_bc_sequence, // broadcast sequence num
    input wire[15:0] rx_bc_fpga,     // indicates whether a boards exists
    input wire rx_bc_bread,          // rx broadcast read request flag

    // Interface for real-time block write
    output reg       fw_rt_wen,
    output reg[2:0]  fw_rt_waddr,
    output reg[31:0] fw_rt_wdata,

    // Interface for sampling data (for block read)
    output reg sample_start,         // 1 -> start sampling for block read
    input wire sample_busy,          // Sampling in process
    output wire[4:0] sample_raddr,   // Read address for sampled data
    input wire[31:0] sample_rdata,   // Sampled data (for block read)
    output reg writeHub              // 1 -> write to Hub after sampling

    // debug
`ifdef USE_CHIPSCOPE
    ,
    inout[35:0] ila_control       // ila control module
`endif
);

    // -------------------------------------------------------------------------
    // registered outputs
    //
    
    // phy-link interface bus
    reg[7:0] data;                // data bus register
    reg[1:0] ctl;                 // control register

    initial begin
        // bidir phy-link lines normally driven by phy (we're the link)
        ctl = 2'bz;              // phy-link control lines
        data = 8'bz;             // phy-link data lines
    end

    // -------------------------------------------------------------------------
    // local wires and registers
    //

    // various
    reg tx_hold;                  // transmit hold flag
    reg rx_active;                // rx active flag

    reg[3:0] state, next;         // state register
    initial state = ST_IDLE;      // initialize state machine to idle state
    reg[2:0] rx_speed;            // received speed code
    reg[3:0] tx_type;             // encodes transmit type
    reg[9:0] bus_id;              // phy bus id (10 bits)
    initial bus_id = 10'h3ff;     // set default bus_id to 10'h3ff
    wire[15:0] local_id;          // full addr = bus_id + node_id

    // status-related buffers
    reg[15:0] st_buff;            // temp buffer for status
    reg[15:0] stcount;            // status bits counter

    // data buses
    wire[1:0] data2b;             // first two data bits
    wire[3:0] data4b;             // first four data bits
    wire[7:0] data8b;             // all eight data bits
    wire[7:0] txmsb8b;            // eight msb's of transmit buffer

    // packet data buffers and bit counters
    reg[31:0] buffer;             // buffer for receive/transmit bits
    reg[19:0] count;              // count received/transmitted bits
    reg[19:0] numbits;            // total number of bits for block packets

    // crc registers
    wire[7:0] crc_data;           // data into crc module to compute crc on
    reg[31:0] crc_comp;           // crc computed at each rx or tx data cycle
    reg[31:0] crc_in;             // input to crc module (starts at all ones)
    wire[31:0] crc_2b;            // current crc module output for data width 2
    wire[31:0] crc_4b;            // current crc module output for data width 4
    wire[31:0] crc_8b;            // current crc module output for data width 8
    wire[7:0] crc_8msb;           // shortcut to 8 msb's of crc_in register
    reg crc_tx;                   // flag to inidicate if in a transmit state

    // link request trigger and type
    reg crc_ini;                  // flag to reset the crc module
    wire phy_rw;                  // 0=phy reg read, 1=phy reg write

    // received packet fields
    reg[3:0]  rx_tcode;           // transaction code
    reg[15:0] rx_dest;            // destination ID field
    reg[5:0]  rx_tag;             // tag field
    reg[3:0]  rx_pri;             // priority code
    reg[15:0] rx_src;             // source ID field
    reg[15:0] reg_dlen;           // block data length
    reg[47:0] rx_addr_full;       // full 48-bit

    // real-time read stuff
    reg data_block;               // flag for block write data being received
    reg dac_local;                // Indicates that DAC entries in block write are for this board_id
    reg[2:0] RtCnt;               // Counter for real-time block quadlets

    // Read address for sampled data
    assign sample_raddr = reg_raddr[4:0];

    wire addrMainRead;
    wire addrMainWrite;
    assign addrMainRead  = (reg_raddr[15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;
    assign addrMainWrite = (reg_waddr[15:12] == `ADDR_MAIN) ? 1'd1 : 1'd0;

    // It is a ROM read when the upper 36 bits are ffff f0000.
    // This covers addresses from ffff f000 0000 to ffff f000 0fff, which includes
    // the CSR Architecture, Serial Bus, Configuration ROM and more.
    // Note that it is more convenient to use reg_raddr[11:0] instead of rx_addr_full[11:0].
    wire rom_read;          // Whether reading from Configuration ROM
    assign rom_read = (rx_addr_full[47:12] == 36'hfffff0000) ? 1'b1 : 1'b0;

    // Configuration ROM data
    reg[31:0] rom_data;

    wire[3:0] fpga_ver;       // FPGA version
`ifdef HAS_ETHERNET
    assign fpga_ver = 4'hE;   // Ethernet/Firwire (Rev 2.x)
`else
    assign fpga_ver = 4'hF;   // Firewire (Rev 1.x)
`endif

    // Configuration ROM:
    //   0400:  ROM Format (Minimal or General)
    // Bus_Info_Block:
    //   0404:  "1394"
    //   0408:  irmc, cmc, isc, bmc, pmc, reserved, cyc_clk_acc, max_rec, reserved, gen, rs, link_spd
    //   040c:  node_vendor_id (24) | chip_id_hi (4)
    //   0410:  chip_id_lo (32)
    //
    // We specify the Minimal ROM format (MIN_ROM_ENTRY), but it seems that drivers still expect
    // valid information in at least some of the Bus_Info_Block, especially to create the GUID.

    always @(*)
    begin
        if (reg_raddr[11:5] == {4'h4, 3'b000}) begin
            if (reg_raddr[4:0] == 5'b00000)      // 0400
                rom_data = `MIN_ROM_ENTRY;
            else if (reg_raddr[4:0] == 5'b00100) // 0404
                rom_data = "1394";
            else if (reg_raddr[4:0] == 5'b01000) // 0408
                rom_data = 32'h00ffa000;   // should be default values
            else if (reg_raddr[4:0] == 5'b01100) // 040C
                rom_data = {`JHU_LCSR_CID, board_id, fpga_ver};
            else if (reg_raddr[4:0] == 5'b10000) // 0410
                rom_data = `FW_VERSION;
            else
                rom_data = 32'd0;
        end
        else
            rom_data = 32'd0;
    end

    // state machine states
    parameter[3:0]
        ST_IDLE = 0,              // wait for phy event
        ST_STATUS = 1,            // receive status from phy
        ST_RX_D_ON = 2,           // rx state, data-on indication
        ST_RX_DATA = 3,           // rx state, receiving bits
        ST_TX = 4,                // tx state, phy gives phy-link bus to link
        ST_TX_DRIVE = 5,          // tx state, link drives phy-link bus
        ST_TX_ACK1 = 6,           // tx state, link transmits acknowledgement
        ST_TX_ACK2 = 7,           // tx state, link cleans up after ack
        ST_TX_QUAD = 8,           // tx state, link transmits quadlet response
        ST_TX_HEAD = 9,           // tx state, link transmits block read header
        ST_TX_HEAD_BC = 10,       // tx state, link transmits block read header for broadcast to PC
        ST_TX_DATA = 11,          // tx state, link transmits block data (including read from hub?)
        ST_TX_DATA_HUB = 12,      // tx state, link transmits hub block data (NOT USED?)
`ifdef HAS_ETHERNET
        ST_TX_FWD = 13,           // tx state, link transmits forward data from eth
`endif
        ST_TX_DONE1 = 14,         // tx state, link finalizes transmission
        ST_TX_DONE2 = 15;         // tx state, phy regains phy-link bus



    // real-time feedback broadcast packet size, in bits, including Firewire header/CRC
    //    32*[FW_header (4) + header_CRC (1) + seq (1) + data (N) + data_CRC (1)] = 32*(N+7)
    //    Rev 4-6: N=16 --> SZ_BBC = 16'd736  (should have been N=20, SZ_BBC = 16'd864)
    //    Rev 7:   N=28 --> SZ_BBC = 16'd1120
    //    `SZ_BWRITE includes FW_header + header_CRC + data_CRC
    localparam[15:0] SZ_BBC = (`SZ_BWRITE + 32*`NUM_BC_READ_QUADS);

    // maximum quadlet index for real-time feedback broadcast packet
    localparam[5:0] MAX_BBC_QUAD = (`NUM_BC_READ_QUADS-1);
    // real-time feedback broadcast packet size, in bytes, not include Firewire header/CRC
    localparam[15:0] SZ_BBC_BYTES = (4*`NUM_BC_READ_QUADS);

// -----------------------------------------------------------------------------
// hardware description
//

//
// continuous assignments and aliases for better readability (and writability!)
//

// full local_id
assign local_id = { bus_id[9:0], node_id[5:0] };   // full addr = bus_id + node_id

// hack for xilinx, compiler doesn't like inout ports as registers
assign data_ext = data;
assign ctl_ext = ctl;

// phy data lines, which are in reversed bit order
assign data2b = { data[0], data[1] };
assign data4b = { data[0], data[1], data[2], data[3] };
assign data8b = { data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7] };
assign txmsb8b = { buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31] };

// select data to compute crc on depending on if rx or tx
assign crc_data = crc_tx ? buffer[31:24] : data8b;

// hack to get high byte of transmit crc out to the data line because the crc
//   gets computed one cycle later than we'd like, based on our implementation
assign crc_8msb = { crc_in[24], crc_in[25], crc_in[26], crc_in[27], crc_in[28], crc_in[29], crc_in[30], crc_in[31] };

// this module computes crc continuously, so it's up to the state machine to
//   initialize, feed back, and latch crc values as necessary
crc32 mycrc(crc_data, crc_in, crc_2b, crc_4b, crc_8b);

// for phy requests, this bit distinguishes between register read and write
assign phy_rw = buffer[12];

`ifdef HAS_ETHERNET
// packet module (used to store FireWire packet that will be forwarded to Ethernet).
// This is 512 quadlets (512 x 32), which is the maximum possible Firewire packet size at 400 Mbits/sec
// (actually, could add a few quadlets because the 512 limit does not include header and CRC).
reg pkt_mem_wen;
reg [8:0] pkt_mem_waddr;
reg [31:0] pkt_mem_wdata;
hub_mem_gen pkt_mem(.clka(sysclk),
                    .wea(pkt_mem_wen),
                    .addra(pkt_mem_waddr),
                    .dina(pkt_mem_wdata),
                    .clkb(sysclk),
                    .addrb(eth_send_addr),
                    .doutb(eth_send_data)
                    );
`endif
   
// -------------------------------------------------------
// Broadcast Time Counter 
//   - Trigger:
//      - Special broadcast qwrite serves as bc read request
//   - Time offset
//      - 5 us is enough for 1 board to send data
//      - wait for lower numbered boards to send data first
//      - add 3 us for ACK
// -------------------------------------------------------
reg[31:0] write_counter;
wire[14:0] write_trig_count;    // 6 bits node_id + 8 bits (256 counts)
reg write_trig;                 // triggers broadcast board status
wire board_selected;            // flag: whether board is selected on PC side
wire [15:0] rx_bc_fpga_masked;  // indicate whether a board exist from board 0 to board_id

assign rx_bc_fpga_masked = ((16'b1 << board_id) - 16'b1) & rx_bc_fpga;
assign board_selected = rx_bc_fpga[board_id];

reg [15:0] d;
reg [5:0] write_trig_seq;   // counts how many boards before board_id
always @ (posedge sysclk) begin
   d <= rx_bc_fpga_masked;
   write_trig_seq <= (((d[ 0] + d[ 1] + d[ 2] + d[ 3]) + (d[ 4] + d[ 5] + d[ 6] + d[ 7]))
            +  ((d[ 8] + d[ 9] + d[10] + d[11]) + (d[12] + d[13] + d[14] + d[15])));
end

assign write_trig_count = {write_trig_seq, 8'd150};

always @(posedge(sysclk))
begin
    if (rx_bc_bread) begin               // if broadcast read request received
        write_counter <= 32'd0;          //    reset counter
        write_trig <= 1'b0;
    end
    else begin
        // First, wait (256*write_trig_seq+150) cycles, where each cycle is 20.345 ns.
        // write_trig_seq is equal to the number of boards in use that have a lower
        // number than the current board. 150 cycles is added for the ACK packet.
        // For example, if there is 1 board with a lower number, then the wait
        // will be for 256*1+150 = 406 cycles, or 8.26 microseconds.
        // In general, for N lower-numbered boards, wait 256*N+150 = 5.21*N+3.05 microseconds.
        // Next, if this board is selected, set write_trig, which will cause the
        // Firewire state machine to set lreq_type == `LREQ_TX_ISO.
        // Note that write_counter is not updated after write_trig is set, so it remains
        // at (write_trig_count+1) until the next broadcast read request.
        if (write_counter < write_trig_count) begin
            write_counter <= write_counter + 1'b1;
            write_trig <= 1'b0;
        end
        else if (write_counter == write_trig_count) begin
            write_counter <= write_counter + 1'b1;
            write_trig <= board_selected;
        end
        else if (lreq_type == `LREQ_TX_ISO) begin
            write_trig <= 1'b0;
        end
    end
end

//
// state machine clocked by sysclk; transitions depend on ctl and data
//
always @(posedge(sysclk))
begin

`ifdef HAS_ETHERNET
    // Clear eth_send_req when eth_send_ack asserted
    if (eth_send_req & eth_send_ack) begin
        eth_send_req <= 1'b0;
    end
`endif

    // Clear sample_start (and writeHub) when sample_busy asserted
    if (sample_start && sample_busy) begin
        sample_start <= 1'd0;
        writeHub <= 1'd0;
    end

    // phy-link state machine
    case (state)

        /***********************************************************************
         * idle state, waiting for phy to do something
         */

        ST_IDLE:
        begin
            blk_wstart <= 0;                       // block write not started
            reg_wen <= 1'b0;                       // no register write events
            blk_wen <= 0;                          // no block write events
            crc_tx <= 0;                           // not in a transmit state
            rx_active <= 0;                        // clear receive active     

            // To be safe, we stay in the idle state if the sampler still has control
            // over the read bus (reg_raddr), which should only be for a few cycles.
            if (~(sample_start|sample_busy)) begin
                // monitor ctl to select next state
                case (ctl)
                    `CTL_PHY_IDLE: begin
                        state <= ST_IDLE;           // stay in monitor state
                        if (write_trig) begin
                            lreq_trig <= 1;
                            lreq_type <= `LREQ_TX_ISO;
                            tx_type <= `TX_TYPE_BBC;
                        end
`ifdef HAS_ETHERNET
                        else if (eth_send_fw_req) begin
                            eth_send_fw_ack <= 1;
                            lreq_trig <= 1;
                            lreq_type <= `LREQ_TX_ISO;
                            tx_type <= `TX_TYPE_FWD;
                            eth_fwpkt_raddr <= 9'h00;
                            numbits <= (eth_fwpkt_len << 3);
                        end
`endif
                        else begin
                            lreq_trig <= 0;
                        end
                    end
                
                    `CTL_PHY_RECV: state <= ST_RX_D_ON;  // phy data from the bus
                    `CTL_PHY_GRNT: state <= ST_TX;       // phy grants tx request
                    `CTL_PHY_STAT: begin                 // phy status transfer
                        st_buff <= {14'b0, data2b};      // clock in status bits
                        state <= ST_STATUS;              // continue status loop
                        stcount <= 2;                    // start status bit count
                        end
                endcase
            end
        end


        /***********************************************************************
         * receiving status (i.e. register read or spontaneously) from phy
         */

        ST_STATUS:
        begin
            // do status transfer until complete or interrupted by data RX
            case (ctl)

                `CTL_PHY_RECV: state <= ST_RX_D_ON;  // interrupt by RX bus data
                `CTL_PHY_GRNT: state <= ST_IDLE;     // undefined, back to idle
                // -------------------------------------------------------------
                // normal status transfer
                //
                `CTL_PHY_STAT: begin
                    st_buff <= {st_buff[13:0], data2b};  // shift in 2 new bits
                    stcount <= stcount + 2'd2;     // count transferred bits
                    state <= ST_STATUS;            // loop in this state
                end
                // -------------------------------------------------------------
                // status transfer complete
                //
                `CTL_PHY_IDLE: begin

                    state <= ST_IDLE;              // go back to idle state

                    if (stcount == `SZ_STAT) begin
                        // update bus reset bit
                        fw_bus_reset <= st_buff[`BUS_RESET_START];
                    end
                    // save phy register into register file
                    else if (stcount == `SZ_REG_STAT) begin
                        reg_waddr <= { `ADDR_MAIN, 4'd0, 4'd0, `REG_PHYDATA };
                        reg_wdata <= { 16'd0, st_buff };
                        reg_wen <= 1;
                        // save node id if register zero
                        if (st_buff[11:8] == 0)
                            node_id <= st_buff[7:2];
                        // update bus reset bit
                        fw_bus_reset <= st_buff[12+`BUS_RESET_START];
                    end
                end

            endcase
        end


        /***********************************************************************
         * receiving data packet from phy, from the bus
         */

        // ---------------------------------------------------------------------
        // wait until data-on goes away, i.e. when phy provides speed code
        // Data: 00h FFh FFh FFh FFh Speed Data0 Data1 Data2 .... Datan 00h 00h
        // Ctrl: 00b 01b 01b 01b 01b   01b   01b   01b   01b ....   01b 00b 00b
        ST_RX_D_ON:
        begin
            // wait out data-on until data RX starts (or null packet indicated)
            // 01 --> CTL_PHY_RECV
            case ({data[0], ctl})
                3'b101: state <= ST_RX_D_ON;        // loop in data-on state
                3'b001: begin                       // receiving data packet
                    rx_speed <= data[3:1];          // latch 4-bit speed code
                    state <= ST_RX_DATA;            // go to receive data loop
                    count <= 0;                     // reset receive bit count
                    tx_type <= `TX_TYPE_NULL;       // to be set during receive
                    crc_in <= `CRC_INIT;            // start crc calculation
                    crc_ini <= 0;                   // clear the crc reset flag
                    data_block <= 0;                // clear block write flag
`ifdef HAS_ETHERNET
                    pkt_mem_waddr <= (9'd0 - 9'd2); // set pkt mem addr, dump 2
`endif
                end
                default: state <= ST_IDLE;          // null packet or error
            endcase
        end

        // ---------------------------------------------------------------------
        // receive packet data from serial bus via phy
        //
        ST_RX_DATA:
        begin
            // receive data from phy until phy indicates completion
            case (ctl)

                // -------------------------------------------------------------
                // normal receive loop
                //
                `CTL_PHY_RECV:
                begin
                    // loop in this state while ctl value tells us to
                    state <= ST_RX_DATA;

                    // ---------------------------------------------------------
                    // process block write data portion of incoming packet
                    //

`ifdef HAS_ETHERNET
                    // store packet
                    if (count[4:0] == 0) begin
                       pkt_mem_wen <= 1'b1;
                       pkt_mem_waddr <= pkt_mem_waddr + 9'd1;
                       pkt_mem_wdata <= buffer;
                    end
                    else begin
                       pkt_mem_wen <= 1'b0;
                    end
`endif

                    // now process data
                    if (data_block) begin

                        // latch data from data block on quadlet boundaries
                        if (count[4:0] == 0) begin
                            // Clear write started signal
                            blk_wstart <= 0;

                            // main address: special case
                            if (addrMainWrite) begin
                                // Real-time block write.
                                // Starting with Rev 7, the first 4 entries are the DAC (same as Rev 1-6),
                                // but that is followed by the status register (for power control).
                                // Note that for broadcast write, the packet will have data for all boards;
                                // thus, we check for consecutive DAC entries that match our board_id and
                                // assume that the next entry is the status register for this board.
                                fw_rt_waddr <= RtCnt;
                                fw_rt_wdata <= buffer;
                                if (RtCnt[2]) begin   // if (RtCnt == 3'd4)
                                    RtCnt <= 3'd0;
                                    dac_local <= 1;
                                    fw_rt_wen <= dac_local&rx_active;
                                end
                                else begin
                                    RtCnt <= RtCnt + 3'd1;
                                    // only respond to bit 27-24 == board_id (bc mode)
                                    if (buffer[27:24] == board_id) begin
                                        fw_rt_wen <= rx_active;
                                    end
                                    else begin
                                        fw_rt_wen <= 0;
                                        dac_local <= 0;
                                    end
                                end
                            end
                            // other space
                            else begin
                                // block write
                                //    1 - hub regs
                                //    2 - prom (M25P16)
                                //    3 - prom (25AA128)
                                reg_waddr[11:0] <= reg_waddr[11:0] + 1'b1;
                                reg_wdata <= buffer;    // latch data to regs
                                reg_wen <= rx_active;   // only save value's when device is targeted
                            end
                        end
                        else
                            reg_wen <= 0;

                        // save the computed crc of the block data
                        if (count == (numbits-16'd32))
                            crc_comp <= ~crc_in;
                    end // if (data_block)

                    // ---------------------------------------------------------
                    // on-the-fly packet processing at 32-bit boundaries
                    //
                    case (count)
                        // first quadlet received ------------------------------
                        32: begin
                            rx_dest <= buffer[31:16];     // destination addr
                            rx_tag <= buffer[15:10];      // transaction tag
                            rx_tcode <= buffer[7:4];      // transaction code
                            rx_pri <= buffer[3:0];        // priority

                            // trigger an ack if dest address matches us
                            if (buffer[21:16] == node_id) begin
                                rx_active <= 1;
                                case (buffer[7:4])
                                    // quadlet read
                                    `TC_QREAD: begin
                                        lreq_trig <= 1;
                                        lreq_type <= `LREQ_TX_IMM;
                                        tx_type <= `TX_TYPE_PEND;
                                    end
                                    // block read
                                    `TC_BREAD: begin
                                        lreq_trig <= 1;
                                        lreq_type <= `LREQ_TX_IMM;
                                        tx_type <= `TX_TYPE_PEND;
                                    end
                                    // quadlet write
                                    `TC_QWRITE: begin
                                        lreq_trig <= 1;
                                        lreq_type <= `LREQ_TX_IMM;
                                        tx_type <= `TX_TYPE_DONE;
                                    end
                                    // block write
                                    `TC_BWRITE: begin
                                        lreq_trig <= 1;
                                        lreq_type <= `LREQ_TX_IMM;
                                        tx_type <= `TX_TYPE_DONE;
                                    end
                                endcase
                            end

                            // process broadcast packets (NOTE: broadcast is write only)
                            else if (buffer[31:16] == 16'hffff) begin
                               // no response for bc packets
                               lreq_trig <= 0;
                               lreq_type <= `LREQ_RES;
                               tx_type <= `TX_TYPE_DATA; 

                                // set rx_active if has valid tcode
                                if ((buffer[7:4]==`TC_BWRITE) || (buffer[7:4]==`TC_QWRITE)) begin
                                    rx_active <= 1'b1;
                                end
                                else begin 
                                    rx_active <= 1'b0;  // ignore other packet e.g. cycle start
                                end
                            end
                            // unknown ignore
                            else begin
                                rx_active <= 0;
                                lreq_trig <= 0;
                                lreq_type <= `LREQ_RES;
                                tx_type <= `TX_TYPE_DATA;
                            end // nodeid
                        end
                        // second quadlet --------------------------------------
                        64: begin
                            rx_src <= buffer[31:16];     // source address
                            rx_addr_full[47:32] <= buffer[15:0];   // save high 16-bit of full addr
                        end
                        // third quadlet --------------------------------------
                        96: begin
                            rx_addr_full[31:0] <= buffer[31:0];  // save low 32-bit for full addr
                            reg_raddr <= buffer[15:0];      // register address
                            reg_waddr <= buffer[15:0];
                            crc_comp <= ~crc_in;          // computed crc for quadlet read

                            // broadcast read request    (trick: NOT standard !!!)
                            // rx_dest == 0 is an asynchronous quadlet write; it is sent to node 0, but processed
                            //              by all nodes.
                            // rx_dest == 3f is a broadcast command (no ack); was used for testing.
                            if ((rx_dest[5:0] == 6'd0 || rx_dest[5:0] == 6'h3f) && rx_tcode == `TC_QWRITE && 
                                (buffer[15:12] == `ADDR_HUB) && (buffer[11:0] == 12'h800)) begin
                                rx_active <= 1;
                                bus_id <= rx_src[15:6];    // latch bus_id
                            end
                            // broadcast write commands 
                            else if (rx_dest[5:0] == 6'd0 && rx_tcode == `TC_BWRITE && 
                                rx_addr_full[47:32] == 16'hffff && buffer[31:0] == 32'hffff0000) begin
                                rx_active <= 1;
                            end
                        end
                        // fourth quadlet --------------------------------------
                        128: begin
                            // quadlet read: 
                            //   crc quadlet, nothing

                            // quadlet write normal
                            reg_wdata <= buffer[31:0];    // reg write data

                            // block read/write
                            reg_dlen <= buffer[31:16];    // block data length
                            // total number of bits for block write packets
                            numbits <= { buffer[31:16], 3'd0 } + `SZ_BWRITE;

                            // computed crc for quadlet write, block read, and block write
                            if (rx_tcode != `TC_QREAD)
                                crc_comp <= ~crc_in;

                            // trigger phy register request if accessed.
                            // Support broadcast address because Ethernet initialization requires
                            // reading of PHY Register 0 so that this module obtains node_id.
                            if (((rx_dest[5:0] == node_id) || (rx_dest[5:0] == 6'h3f)) &&
                                (reg_waddr=={`ADDR_MAIN, 8'h0, `REG_PHYCTRL}) && (rx_tcode==`TC_QWRITE))
                            begin
                                // check the RW bit to determine access type
                                lreq_type <= (phy_rw ? `LREQ_REG_WR : `LREQ_REG_RD);
                                lreq_trig <= 1;
                            end
`ifdef HAS_ETHERNET
                            // trigger packet forward if packet is for pc
                            if ((rx_dest[15:0] == eth_fw_addr) && (rx_tcode == `TC_QRESP)) begin
                               eth_send_req <= 1;
                               eth_send_len <= 16'd20;
                            end
                            else if ((rx_dest[15:0] == eth_fw_addr) && (rx_tcode == `TC_BRESP)) begin
                               eth_send_req <= 1;
                               eth_send_len <= 16'd24 + buffer[31:16];
                            end
`endif
                        end
                        // quadlet 4.5 -----------------------------------------
                        144: crc_ini <= 1;     // reset crc for block data
                        // fifth quadlet: 
                        //   - block read request
                        //   - block write request
                        //   - start block starts
                        160: begin 
                            // flag to indicate the start of block data
                            data_block <= (rx_tcode==`TC_BWRITE) ? 1'b1 : 1'b0;

                            if (addrMainWrite) begin
                                // main is special, write to WriteRtData module
                                RtCnt <= 3'd0;
                                dac_local <= 1;
                            end
                            else begin
                                // block write to hub, prom, prom_qla
                                // NOTE: read addr (see 3rd quad)
                                //       write addr-1 to match timing
                                reg_waddr[11:0] <= reg_waddr[11:0] - 1'b1; 
                                blk_wstart <= (rx_tcode==`TC_BWRITE) ? 1'b1 : 1'b0;
                            end
                        end
                        // iffy implementation, works for now ------------------
                        default: begin
                            lreq_trig <= 0;    // keep lreq untriggered
                            crc_ini <= 0;      // start crc for block data
                        end
                    endcase

                    // ---------------------------------------------------------
                    // buffer and count data bits from the phy
                    //
                    case (rx_speed)
                        `RX_S100: begin
                            buffer <= buffer << 2;
                            buffer[1:0] <= data2b;
                            count <= count + 16'd2;
                            crc_in <= (crc_ini) ? `CRC_INIT : crc_2b;
                        end
                        `RX_S200: begin
                            buffer <= buffer << 4;
                            buffer[3:0] <= data4b;
                            count <= count + 16'd4;
                            crc_in <= (crc_ini) ? `CRC_INIT : crc_4b;
                        end
                        `RX_S400: begin
                            buffer <= buffer << 8;
                            buffer[7:0] <= data8b;
                            count <= count + 16'd8;
                            crc_in <= (crc_ini) ? `CRC_INIT : crc_8b;
                        end
                        default: begin
                            /* undefined speed code, do nothing */
                            // steps for each of the above cases:
                            // - shift over (2,4,8) previously read bits
                            // - clock in (2,4,8) new data bits
                            // - increment bit counter by (2,4,8)
                            // - feed back new crc for next iteration
                        end
                    endcase  // rx_speed
                end

                // -------------------------------------------------------------
                // receive complete, prepare for response actions (e.g. ack)
                //
                `CTL_PHY_IDLE:
                begin
                    // next state, go back to idle
                    state <= ST_IDLE;
                    
                    // makes the ack an error if there is a crc error
                    if (crc_comp != buffer)
                        tx_type <= `TX_TYPE_DATA;

                    // trigger a quadlet or block write event
                    // NOTE: 
                    //   & - bitwise AND
                    //   result is a 1-bit and assigned to reg_wen 
                    reg_wen <= (rx_active & (rx_tcode==`TC_QWRITE));
                    blk_wen <= (rx_active & ((rx_tcode==`TC_QWRITE) | ((rx_tcode==`TC_BWRITE) && !addrMainWrite)));

                    // Start sampling feedback data if a block read from ADDR_MAIN or
                    // a broadcast read request (quadlet write to ADDR_HUB). Note that sampler
                    // will enter its busy state (after the next cycle) and take control of reg_raddr
                    // for a few cycles. If writeHub is set, the sampler will also directly write
                    // this board's feedback to the Hub memory.
                    if (rx_active &&
                        ((addrMainRead && (rx_tcode==`TC_BREAD)) ||
                         ((reg_waddr[15:0] == {`ADDR_HUB, 12'h800}) && (rx_tcode==`TC_QWRITE)))) begin
                       sample_start <= 1;
                       writeHub <= (rx_tcode == `TC_QWRITE) ? 1'b1 : 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // undefined condition, go back to idle
                //
                default: state <= ST_IDLE;

            endcase
        end


        /***********************************************************************
         * transmitting data packet to phy, to the bus
         * assumes data is already ready in TX buffer
         */

        // ---------------------------------------------------------------------
        // an 'idle' state before phy lets link drive the interface
        //
        ST_TX:
        begin
            crc_in <= `CRC_INIT;         // start new crc calculation
            state <= ST_TX_DRIVE;        // the next state
            crc_ini <= 0;                // normal crc operation
            crc_tx <= 1;                 // selects tx data for crc
            count <= 0;                  // prepare the bit counter
            
            // prepare for the type of bus transmission
            case (tx_type)
            // transmit ack, to be followed by read response packet
            `TX_TYPE_PEND: begin
                buffer[31:24] <= { `ACK_PEND, ~`ACK_PEND };
                next <= ST_TX_ACK1;
            end
            // transmit ack, indicating write request was successful
            `TX_TYPE_DONE: begin
                buffer[31:24] <= { `ACK_DONE, ~`ACK_DONE };
                next <= ST_TX_ACK1;
            end
            // transmit ack, indicating an error in the received packet
            `TX_TYPE_DATA: begin
                buffer[31:24] <= { `ACK_DATA, ~`ACK_DATA };
                next <= ST_TX_ACK1;
            end
            // transmit quadlet read response packet
            `TX_TYPE_QRESP: begin
                buffer <= { rx_src, rx_tag, 2'd0, `TC_QRESP, 4'd0 };
                next <= ST_TX_QUAD;
            end
            // transmit block read response packet
            `TX_TYPE_BRESP: begin
                buffer <= { rx_src, rx_tag, 2'd0, `TC_BRESP, 4'd0 };
                next <= ST_TX_HEAD;
                numbits <= `SZ_BRESP + (reg_dlen<<3);
            end
            
            // transmit block write broadcast to pc
            //     broadcast requires no ack and response packet,
            //     which saves bus bandwidth
            //     dest_id = 0xffff (for broadcasting)
            //     priority (bits 3:0) 
            //        - are not used in cable environment
            //        - reuse it to indicate broadcast packet is from FPGA_QLA 
            //        - pri = 4'hA   A is a random picked value
            `TX_TYPE_BBC: begin
                buffer <= { 16'hffff, rx_tag, 2'd0, `TC_BWRITE, 4'hA };
                next <= ST_TX_HEAD_BC;
                numbits <= SZ_BBC;
            end

`ifdef HAS_ETHERNET
            // transmit packet from Ethernet
            `TX_TYPE_FWD: begin
                buffer <= eth_fwpkt_rdata;
                next <= ST_TX_FWD;
                numbits <= (eth_fwpkt_len << 3);  // len in bytes => in bits
                eth_fwpkt_raddr <= eth_fwpkt_raddr + 1'b1;
            end
`endif

            // for crc/unknown errors, send an error ack
            default: begin
                buffer[31:24] <= { `ACK_DATA, ~`ACK_DATA };
                next <= ST_TX_ACK1;
            end
            endcase
        end

        // ---------------------------------------------------------------------
        // another 'idle' state where link starts to drive the interface
        //
        ST_TX_DRIVE:
        begin
            ctl <= `CTL_HOLD;
            state <= next;
        end

        // ---------------------------------------------------------------------
        // link shifts ack bits out to the phy/bus
        //
        ST_TX_ACK1:
        begin
            ctl <= `CTL_DATA;
            data <= txmsb8b;
            state <= ST_TX_ACK2;
        end

        // ---------------------------------------------------------------------
        // clean up after sending ack bits
        //
        ST_TX_ACK2:
        begin
            // if response to be transmitted, hold data bus, else release it
            if (tx_type == `TX_TYPE_PEND)
                ctl <= `CTL_HOLD;
            else
                ctl <= `CTL_IDLE;

            // set tx type; this works because we do concatenated transactions
            // if rx_tcode != (TC_QREAD or TC_QWRITE), this is inconsequential
            if (rx_tcode == `TC_QREAD) begin
                tx_type <= `TX_TYPE_QRESP;
            end
            else if (rx_tcode == `TC_BREAD) begin
                tx_type <= `TX_TYPE_BRESP;
            end

            state <= ST_TX_DONE1;
        end

        // ---------------------------------------------------------------------
        // link shifts quadlet read response bits out to the phy/bus
        //
        ST_TX_QUAD:
        begin
            if (count == `SZ_QRESP) begin
                ctl <= `CTL_IDLE;
                state <= ST_TX_DONE1;
            end

            else begin
                ctl <= `CTL_DATA;

                // shift out transmit bit from buffer and update counter
                data <= txmsb8b;
                buffer <= buffer << 8;
                count <= count + 16'd8;
                crc_in <= crc_8b;

                // update transmit buffer at 32-bit boundaries
                case (count)
                     24: buffer <= { rx_dest, `RC_DONE, 12'd0 };
                     56: buffer <= 0;
                     88: buffer <= rom_read ? rom_data : reg_rdata;
                    128: begin
                        data <= ~crc_8msb;
                        buffer <= { ~crc_in[23:0], 8'd0 };
                    end
                endcase
            end
        end

        // ---------------------------------------------------------------------
        // link shifts block read header bits out to the phy/bus
        //
        
        ST_TX_HEAD:
        begin
            ctl <= `CTL_DATA;

            // shift out transmit bit from buffer and update counter
            data <= txmsb8b;
            buffer <= buffer << 8;
            count <= count + 16'd8;
            crc_in <= (crc_ini) ? `CRC_INIT : crc_8b;
            
            // update transmit buffer at quadlet boundaries
            case (count)
                 24: buffer <= { rx_dest, `RC_DONE, 12'd0 };  // quadlet 2
                 56: buffer <= 0;                             // quadlet 3
                 88: buffer <= { reg_dlen, 16'd0 };           // quadlet 4

                // latch header crc, reset crc in preparation for data crc
                128: begin
                    data <= ~crc_8msb;
                    buffer <= { ~crc_in[23:0], 8'd0 };
                    crc_ini <= 1;
                end

                // latch first data quadlet;
                // restart crc and goto ST_TX_DATA
                152: begin                                    // quadlet 6 
                    // ----- BRESP Continue -------
                    buffer <= rom_read ? rom_data :
                              addrMainRead ? sample_rdata : reg_rdata;
                    // Note that for rom_read, we increment by 4, otherwise by 1.
                    reg_raddr[11:0] <= reg_raddr[11:0] + {9'd0,rom_read,1'b0,~rom_read};
                    state <= ST_TX_DATA;
                    crc_ini <= 0;
                end
            endcase
        end // case: ST_TX_HEAD
        
        
        // ---------------------------------------------------------------------
        // link shifts block write header bits out to the phy/bus
        // HUB VERSION
        //   - Also needs to save data to HUB register

        ST_TX_HEAD_BC:
        begin
            ctl <= `CTL_DATA;

            // shift out transmit bit from buffer and update counter
            data <= txmsb8b;
            buffer <= buffer << 8;
            count <= count + 16'd8;
            crc_in <= (crc_ini) ? `CRC_INIT : crc_8b;
            
            // update transmit buffer at quadlet boundaries
            case (count)
                // NOTE: destination address
                // dest_addr = 0xffffff000(4'h01)(bid)0  
                //  - 4'h01 = `ADDR_HUB
                //  - bid is 4 bits board id
                24: buffer <= { local_id, 16'hffff };  // src_id, dest_offset
                56: buffer <= { 16'hff00, `ADDR_HUB, 3'd0, board_id[3:0], 5'd0 }; 

                //-------- Start broadcast back with sequence -------------
                // datalen = 4 x (1 + 4 + 4 + 4 + 4 + 4) = 84 bytes (Rev 1-6)
                //    Seq (1), BoardInfo (4), Pot/Cur (4), Enc (4), Enc Vel/DT (4), Enc Vel/DP/Q1 (4)
                // datalen = 4 x (1 + 4 + 4 + 4 + 4 + 4 + 4 + 4) = 116 bytes (Rev 7)
                //    above + Enc Accel Q5 (4), Enc Running (4)
                88: buffer <= { SZ_BBC_BYTES, 16'd0 };
                
                // latch header crc, reset crc in preparation for data crc
                128: begin
                    // crc
                    data <= ~crc_8msb;
                    buffer <= { ~crc_in[23:0], 8'd0 };
                    crc_ini <= 1;          // start crc
                end

                // latch bc_sequence and bc_fpga, send back to PC,  restart crc
                152: begin
                    buffer <= { rx_bc_sequence, rx_bc_fpga };
                    crc_ini <= 0;           // clear crc start bit
                    reg_raddr <= {`ADDR_MAIN, 12'd0 };  // Will actually read from SampleData
                    state <= ST_TX_DATA;    // goto ST_TX_DATA
                end

            endcase
        end  // ST_TX_HEAD_BC
        
        // ---------------------------------------------------------------------
        // link shifts block read/write data bits out to the phy/bus
        //
        ST_TX_DATA:
        begin
            if (count == numbits) begin
                ctl <= `CTL_IDLE;
                state <= ST_TX_DONE1;
            end

            else begin
                // shift out transmit bit from buffer and update counter
                ctl <= `CTL_DATA;
                data <= txmsb8b;
                buffer <= buffer << 8;
                count <= count + 16'd8;
                crc_in <= crc_8b;
                
                // latch data and update addresses on quadlet boundaries
                if (count[4:0] == 5'd24) begin
                    // send to FireWire bus
                    buffer <= rom_read ? rom_data :
                              addrMainRead ? sample_rdata : reg_rdata;
                    // 12-bit address increment, even though Firewire limited to 512 quadlets (9 bits)
                    // because this way we can support non-zero starting addresses.
                    // Note that for rom_read, we increment by 4, otherwise by 1.
                    reg_raddr[11:0] <= reg_raddr[11:0] + {9'd0,rom_read,1'b0,~rom_read};
                end

                if (count == (numbits-16'd32)) begin
                    data <= ~crc_8msb;
                    buffer <= { ~crc_in[23:0], 8'd0 };
                end
            end 
        end // case: ST_TX_DATA


`ifdef HAS_ETHERNET
        // ---------------------------------------------------------------------
        // link shifts packet from ethernet out to the phy/bus
        //
        ST_TX_FWD:
        begin
           if (count == numbits) begin
              // stop
              ctl <= `CTL_IDLE;
              state <= ST_TX_DONE1;
              eth_send_fw_ack <= 0;
           end
           else begin
              // shift out transmit bit from buffer
              ctl <= `CTL_DATA;
              data <= txmsb8b;
              buffer <= buffer << 8;
              count <= count + 16'd8;

              // latch data & update address
              if (count[4:0] == 5'd24) begin
                 eth_fwpkt_raddr <= eth_fwpkt_raddr + 1'b1;
                 buffer <= eth_fwpkt_rdata;
              end
           end
        end // case: ST_TX_FWD
`endif

        // ---------------------------------------------------------------------
        // drive one more cycle of idle
        //
        ST_TX_DONE1:
        begin
            ctl <= `CTL_IDLE;            // one cycle of idle
            state <= ST_TX_DONE2;        // phy regains bus in next state
        end

        // ---------------------------------------------------------------------
        // reliquish control of the bus to the phy and return to idle state
        //
        ST_TX_DONE2:
        begin
            ctl <= 2'bz;             // allow phy to drive ctl
            data <= 8'bz;            // allow phy to drive data
            state <= ST_IDLE;        // TX done, go to idle state
        end


        // ---------------------------------------------------------------------
        // just in case state machine reaches an illegal state
        //
        default: begin
            state <= ST_IDLE;
        end

    endcase
end


`ifdef USE_CHIPSCOPE
// // debug hub timing
// ila_fw_packet ila_hw(
//     .CONTROL(ila_control),
//     .CLK(sysclk),
//     .TRIG0({state, next}),
//     .TRIG1(eth_fwpkt_rdata),
//     .TRIG2({9'd0, eth_fwpkt_raddr}),
//     .TRIG3(ctl),
//     .TRIG4(data)
// );

ila_fw_packet ila_hw(
    .CONTROL(ila_control),
    .CLK(sysclk),
    .TRIG0({state, next}),
    .TRIG1(32'd0),
    .TRIG2(16'd0),
    .TRIG3(ctl),
    .TRIG4(data)
);
`endif

endmodule  // PhyLinkInterface


/*******************************************************************************
 * This module sends a request to the phy, via the lreq line, initiated by a
 * high level trigger signal.  The type of request, be it bus transfers or
 * register accesses, is encoded in type.
 */

// length of various request bitstreams
`define LEN_LREQ 24

module PhyRequest(
    input  wire     sysclk,     // global system clock
    output wire     lreq,       // lreq line to the phy
    
    input wire      trigger,    // initiates a link request
    input wire[2:0] rtype,      // encoded requested type
    input wire[11:0] data       // addr/data bits to send to phy
);

// local registers
reg[16:0] request;       // formatted request bit sequence


// -----------------------------------------------------------------------------
// hardware description
//

assign lreq = request[16];           // shift out msb of request string

// requests initiated by active low trigger and shifted out on sysclk
always @(posedge(sysclk))
begin
    // on trigger, construct request string
    if (trigger == 1) begin
        request[16:12] <= { 2'b01, rtype };
        case (rtype)
            `LREQ_REG_RD: request[11:8] <= data[3:0];
            `LREQ_REG_WR: request[11:0] <= data[11:0];
            `LREQ_TX_IMM: request[11:9] <= 3'b100;   // S400
            `LREQ_TX_ISO: request[11:9] <= 3'b100;   // S400
            `LREQ_TX_PRI: request[11:9] <= 3'b100;   // S400
        endcase
    end

    // shift out one bit per sysclk
    else
        request <= request << 1;
end

endmodule  // PhyRequest
