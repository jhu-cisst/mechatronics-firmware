/*******************************************************************************
 *
 * Copyright(C) 2008-2015 ERC CISST, Johns Hopkins University.
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
 *     - Query Packet:  dest_node_id = 0, dest_addr = 0xffffffff000f
 *     - Command Packet: dest_node_id = 0, dest_addr = 0xffffffff0000
 *
 *
 *  2014-08-23 NOTE for Eth1394 packet  Zihan Chen
 *     - if eth1394 bit is set, nodes use rotary switch (board_id) as 
 *       FireWire node_id
 *     - This supports systems that do not have a proper FireWire master
 *       (e.g., when using a FireWire subnetwork consisting only of FPGA1394 boards,
 *       connected via a bridge such as the Ethernet/FireWire bridge).
 *   
 *
 */
 

// -------------------------------------------------------
// IEEE-1394 64-bit Address Mapped 
// We only use last 16-bit, the rest bit number is 0 indexed
// 
//  addr[15:12] map (see Constants.v)
//     4'h0: board register + device memory
//     4'h1: hub caching space
//     4'h2: M25P16 prom space
//     4'h3: QLA 25AA128 prom space
//         
// -------------------------------------------------------------


// global constant e.g. register & device address
`include "Constants.v"

// constants for receive speed codes
// See Book P237 Receving Packets, D[0] is omitted here
`define RX_S100 3'b000            // 100 Mbps
`define RX_S200 3'b001            // 200 Mbps
`define RX_S400 3'b101            // 400 Mbps

// phy request types (Ref: Book P230)
`define LREQ_TX_IMM 3'd0          // immediate transmit header
`define LREQ_TX_ISO 3'd1          // isochronous transmit header
`define LREQ_TX_PRI 3'd2          // priority transmit header
`define LREQ_TX_FAIR 3'd3         // fair transmit header
`define LREQ_REG_RD 3'd4          // register read header
`define LREQ_REG_WR 3'd5          // register write header
`define LREQ_ACCEL 3'd6           // async arbitration acceleration
`define LREQ_RES 3'd7             // reserved, presumably do nothing

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
`define SZ_STAT 16'd16            // phy register transfer size

//`define SZ_BBC  16'd576           // block write broadcast packet size
//                                  // (4 + 1 + 12 + 1) * 32 = 576
`define SZ_BBC  16'd736           // block write broadcast packet size
                                  // (4 + 1 + 1 + 16 + 1) * 32 = 736

// ack values
`define ACK_DONE 4'h1             // transaction complete, applies to writes
`define ACK_PEND 4'h2             // transaction pending, applies to reads
`define ACK_DATA 4'hD             // ack crc error, used as a general error

// types of transmissions
`define TX_TYPE_NULL 4'd0         // no transmission
`define TX_TYPE_DONE 4'd1         // ack complete (for write requests)
`define TX_TYPE_PEND 4'd2         // ack pending (for read requests)
`define TX_TYPE_DATA 4'd3         // ack data error, for crc or data length
`define TX_TYPE_QRESP 4'd4        // for quadlet read response
`define TX_TYPE_BRESP 4'd5        // for block read response
`define TX_TYPE_BBC   4'd6        // for block write broadcast


// other
`define CRC_INIT -32'd1           // initial value to start new crc calculation
`define INVALID_SIZE -16'd1       // packet size that we should never encounter

module PhyLinkInterface(
    // globals
    input wire sysclk,           // system clock
    input wire reset,            // global reset
    input wire eth1394,          // global eth1394
    input wire[3:0] board_id,    // global board id
    
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
    input wire[31:0] reg_rdata,  // read data from external register file
    output reg[31:0] reg_wdata,  // write data to external register file
    
    // transmit parameters
    output reg lreq_trig,        // trigger signal for a phy request
    output reg[2:0] lreq_type    // type of request to give to the phy    
);


    // -------------------------------------------------------------------------
    // registered outputs
    //
    
    // phy-link interface bus
    reg[7:0] data;                // data bus register
    reg[1:0] ctl;                 // control register

    // -------------------------------------------------------------------------
    // local wires and registers
    //

    // various
    reg tx_hold;                  // transmit hold flag
    reg rx_active;                // rx active flag

    reg[3:0] state, next;         // state register
    reg[2:0] rx_speed;            // received speed code
    reg[3:0] tx_type;             // encodes transmit type
    reg[9:0] bus_id;              // phy bus id (10 bits)
    wire[5:0] node_id;            // phy node id 
    reg[5:0] fw_node_id;          // phy node id firewire (6 bits)
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

    // broadcast related fields
    reg[15:0] rx_bc_sequence;     // broadcast sequence num
    reg[15:0] rx_bc_fpga;         // indicates whether a boards exists
    reg rx_bc_bread;              // rx broadcast read request flag

    // real-time read stuff
    // an array of 4 4-bits device address
    // adc enc_pos enc_period enc_freq
    wire[3:0] dev_addr[0:3];      // order of device addresses for block read
    reg[2:0] dev_index;           // selects device address from map
    reg[31:0] timestamp;          // timestamp counter register
    reg ts_reset;                 // timestamp counter reset signal
    reg data_block;               // flag for block write data being received
    
    // ----- hub -------
    
    parameter num_channels = 4;

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
        ST_TX_HEAD = 9,           // tx state, link transmits block header
        ST_TX_HEAD_BC = 10,       // tx state, link transmits block write broadcast to PC
        ST_TX_DATA = 11,          // tx state, link transmits block data
        ST_TX_DATA_HUB = 12,      // tx state, link transmits hub block data
        ST_TX_DONE1 = 13,         // tx state, link finalizes transmission
        ST_TX_DONE2 = 14;         // tx state, phy regains phy-link bus



// -----------------------------------------------------------------------------
// hardware description
//

//
// continuous assignments and aliases for better readability (and writability!)
//

// node_id based on eth1394 mode
assign node_id = eth1394 ? {2'b00, board_id} : fw_node_id;
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

// map of device address in order of appearance in block read
assign dev_addr[0] = 4'd0;        // adc device address
assign dev_addr[1] = 4'd5;        // enc position address
assign dev_addr[2] = 4'd6;        // enc period address
assign dev_addr[3] = 4'd7;        // enc frequency address

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
// Broadcast Time Counter 
//   - Trigger: 2 different triggers
//      - 1: broadcast write command
//      - 2: special broadcast qwrite serves as bc read request 
//   - Time offset
//      - 5 us is enough for 1 board to send data
//      - offset can be based on nodeid or boardid (rotary switch)
// -------------------------------------------------------
// counter for initiate block write to controller PC
reg[31:0] write_counter;
wire[14:0] write_trig_count;  // 6 bits node_id + 8 bits (256 counts)
reg write_trig;

assign write_trig_count = eth1394 ? {count[5:0], 8'd0} : {node_id[5:0], 8'd0};

always @(posedge(sysclk) or negedge(reset))
begin
    if (reset == 0 || rx_bc_bread) begin
        write_counter <= 32'd0;
        write_trig <= 1'b0;
    end
    else begin
        if (write_counter < (write_trig_count + 150)) begin  // 150 cycle for ACK packet
            write_counter <= write_counter + 1'b1;
            write_trig <= 1'b0;
        end
        else if ( write_counter == (write_trig_count + 150)) begin
            write_counter <= write_counter + 1'b1;
            write_trig <= 1'b1;
        end
        else if (lreq_type == `LREQ_TX_ISO) begin
            write_trig <= 1'b0;
        end
    end
end

//
// state machine clocked by sysclk; transitions depend on ctl and data
//
always @(posedge(sysclk) or negedge(reset))
begin

    // reset sends everything to default states and values
    if (reset == 0)
    begin
        // bidir phy-link lines normally driven by phy (we're the link)
        ctl <= 2'bz;              // phy-link control lines
        data <= 8'bz;             // phy-link data lines

        // initialize internal buffers, registers, and counters
        state <= ST_IDLE;         // initialize state machine to idle state
        st_buff <= 0;             // status value receive buffer
        stcount <= 0;             // received status bits counter
        rx_speed <= 0;            // clear the received speed code
        rx_active <= 0;           // clear the receive flag 
        blk_wstart <= 0;          // clear the block write started flag
        reg_wen <= 0;             // keep register writes inactive by default
        blk_wen <= 0;             // keep block writes inactive by default
        lreq_trig <= 0;           // clear the phy request trigger
        lreq_type <= 0;           // set phy request type to known value
        fw_node_id <= 0;             // hope phy updates this during self-id
        bus_id <= 10'h3ff;        // set default bus_id to 10'h3ff
        reg_raddr <= 0;           // set reg address to known value
        reg_waddr <= 0;           // set reg address to known value
        reg_wdata <= 0;           // set reg write data to known value
        crc_ini <= 0;             // initialize crc start flag
        crc_tx <= 0;              // flag for crc; 0=non-transmit state
        ts_reset <= 0;            // clear the timestamp reset signal
        data_block <= 0;          // indicates data portion of block writes
    end

    // phy-link state machine
    else begin
        case (state)

        /***********************************************************************
         * idle state, waiting for phy to do something
         */

        ST_IDLE:
        begin
            blk_wstart <= 0;                       // block write not started
            reg_wen <= 1'b0;                          // no register write events
            blk_wen <= 0;                          // no block write events
            crc_tx <= 0;                           // not in a transmit state
            rx_active <= 0;                        // clear receive active     
            rx_bc_bread <= 1'b0;                   // clear broadcast reqd request flag       
            
            // monitor ctl to select next state
            case (ctl)
                2'b00: begin 
                    state <= ST_IDLE;           // stay in monitor state
                    if (write_trig) begin
                        lreq_trig <= 1;
                        lreq_type <= `LREQ_TX_ISO;
                        tx_type <= `TX_TYPE_BBC;
                    end
                    else begin
                        lreq_trig <= 0;
                    end
                end
                
                2'b01: state <= ST_RX_D_ON;        // phy data from the bus
                2'b11: state <= ST_TX;             // phy grants tx request                
                2'b10: begin                       // phy status transfer
                    st_buff <= {16'b0, data2b};    // clock in status bits
                    state <= ST_STATUS;            // continue status loop
                    stcount <= 2;                  // start status bit count
                end
            endcase
        end


        /***********************************************************************
         * receiving status (i.e. register read or spontaneously) from phy
         */

        ST_STATUS:
        begin
            // do status transfer until complete or interrupted by data RX
            case (ctl)

                2'b01: state <= ST_RX_D_ON;        // interrupt by RX bus data
                2'b11: state <= ST_IDLE;           // undefined, back to idle
                // -------------------------------------------------------------
                // normal status transfer
                //
                2'b10: begin
                    st_buff <= st_buff << 2;       // shift over previous bits
                    st_buff[1:0] <= data2b;        // clock in 2 new bits
                    stcount <= stcount + 2'd2;     // count transferred bits
                    state <= ST_STATUS;            // loop in this state
                end
                // -------------------------------------------------------------
                // status transfer complete
                //
                2'b00: begin

                    state <= ST_IDLE;              // go back to idle state

                    // save phy register into register file
                    if (stcount == `SZ_STAT) begin
                        reg_waddr <= { `ADDR_MAIN, 4'd0, 4'd0, `REG_PHYDATA };
                        reg_wdata <= { 16'd0, st_buff };
                        reg_wen <= 1;
                        // save node id if register zero
                        if (st_buff[11:8] == 0)
                            fw_node_id <= st_buff[7:2];
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
                2'b01:
                begin
                    // loop in this state while ctl value tells us to
                    state <= ST_RX_DATA;

                    // ---------------------------------------------------------
                    // process block write data portion of incoming packet
                    //
                    
                    // now process data
                    if (data_block) begin

                        // latch data from data block on quadlet boundaries
                        if (count[4:0] == 0) begin
                            // Clear write started signal
                            blk_wstart <= 0;  

                            // main address: special case
                            if (reg_waddr[15:12]==`ADDR_MAIN) begin
                                // Block write to dac data
                                // channel address circularly increments from 1 to num_channels
                                // (chan addr and dev offset are previously set)
                                if (reg_waddr[7:4] == num_channels)
                                    reg_waddr[7:4] <= 4'd1;
                                else
                                    reg_waddr[7:4] <= reg_waddr[7:4] + 1'b1;

                                // only respond to bit 27-24 == board_id (bc mode)
                                if (buffer[27:24] == board_id) begin
                                    reg_wdata <= buffer[30:0];               // data to write
                                    reg_wen <= (buffer[31] & rx_active);     // check valid bit
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
                            if (rx_dest[5:0] == 6'd0 && rx_tcode == `TC_QWRITE && 
                                rx_addr_full[47:32] == 16'hffff && buffer[31:0] == 32'hffff000f) begin
                                rx_bc_bread <= 1;          // set rx_bc_bread 
                                bus_id <= rx_src[15:6];    // latch bus_id
                            end
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

                            // quadlet write bc read start
                            if (rx_bc_bread) begin
                                rx_bc_sequence <= buffer[31:16];    // sequence number
                                rx_bc_fpga <= buffer[15:0];         // fpga board exist    
                            end

                            // block read/write
                            reg_dlen <= buffer[31:16];    // block data length
                            // total number of bits for block write packets
                            numbits <= { buffer[31:16], 3'd0 } + `SZ_BWRITE;

                            // computed crc for quadlet write, block read, and block write
                            if (rx_tcode != `TC_QREAD)
                                crc_comp <= ~crc_in;

                            // trigger phy register request if accessed
                            if ((rx_dest[5:0]==node_id) && (reg_waddr=={`ADDR_MAIN, 8'h0, `REG_PHYCTRL}) && (rx_tcode==`TC_QWRITE))
                            begin
                                // check the RW bit to determine access type
                                lreq_type <= (phy_rw ? `LREQ_REG_WR : `LREQ_REG_RD);
                                lreq_trig <= 1;
                            end
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
                            blk_wstart <= (rx_tcode==`TC_BWRITE) ? 1'b1 : 1'b0;

                            if (reg_waddr[15:12]==`ADDR_MAIN) begin
                                // main is special, ignore address in 1394 packet
                                reg_waddr[7:4] <= 0;    // init channel address
                                reg_waddr[3:0] <= 1;    // set dac device address
                            end
                            else begin
                                // block write to hub, prom, prom_qla
                                // NOTE: read addr (see 3rd quad)
                                //       write addr-1 to match timing
                                reg_waddr[11:0] <= reg_waddr[11:0] - 1'b1; 
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
                2'b00:
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
                    //   NO quadlet write event for bc read request
                    reg_wen <= (rx_active & (rx_tcode==`TC_QWRITE) & (rx_bc_bread == 1'b0));  // ??? SHOULD WE 
                    // reg_wen <= (rx_active & (rx_tcode==`TC_QWRITE)); 
                    blk_wen <= (rx_active & ((rx_tcode==`TC_QWRITE) | (rx_tcode==`TC_BWRITE))); 
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
            // ZC: broadcast requires no ack and response packet,
            //     which saves bus bandwidth
            //     dest_id = 0xffff (for broadcasting)
            //     priority (bits 3:0) 
            //        - are not used in cable environment
            //        - reuse it to indicate broadcast packet is from FPGA_QLA 
            //        - pri = 4'hA   A is a random picked value
            `TX_TYPE_BBC: begin
                buffer <= { 16'hffff, rx_tag, 2'd0, `TC_BWRITE, 4'hA };
                next <= ST_TX_HEAD_BC;
                numbits <= `SZ_BBC;
            end          
            
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
                     88: buffer <= reg_rdata;
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

                // latch Board 0, data 0 from hub register, 
                // restart crc and goto ST_TX_DATA
                152: begin                                    // quadlet 6 
                    // ----- BRESP Continue -------
                    if (reg_raddr[15:12]==`ADDR_MAIN) begin
                        // main keep going special case
                        buffer <= timestamp;         // latch timestamp
                        reg_raddr[7:0] <= 8'h00;     // address for status data
                        ts_reset <= 1'b1;            // set timestamp reset 
                    end
                    else begin
                        // block read from hub, prom, prom_qla
                        buffer <= reg_rdata;
                        reg_raddr[7:0] <= reg_raddr[7:0] + 1'b1;

                        // end header for hub, prom, prom_qla
                        state <= ST_TX_DATA;
                    end
                    crc_ini <= 0;
                end

                // latch status data, setup address for digital inputs
                184: begin
                    buffer <= reg_rdata;             
                    reg_raddr[7:0] <= 8'h0a;      // 8'h0a: digital inputs
                    ts_reset <= 1'b0;             // clear timestamp reset
                end

                // latch digital inputs, setup address for temperature sensors
                216: begin
                    buffer <= reg_rdata;             
                    reg_raddr[7:0] <= 8'h05;      // 8'h05: temperature sensors
                end

                // latch temperature sensors, go to block data state
                248: begin
                    buffer <= reg_rdata;
                    // start cycling through channels
                    reg_raddr[7:4] <= 4'h1;        // start from channel 1
                    reg_raddr[3:0] <= dev_addr[0]; // 1st device address
                    dev_index <= 1;                // set next dev_index 

                    // end main header
                    state <= ST_TX_DATA;
                end

            endcase
        end
        
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
                // datalen = 4 x (1 + 4 + 4 + 4 + 4) = 68 bytes
                88: buffer <= { 16'd68, 16'd0 };
                
                // latch header crc, reset crc in preparation for data crc
                128: begin
                    // for hub register
                    reg_waddr[15:0] <= { `ADDR_HUB, 3'd0, board_id[3:0], 5'd0 };
                    reg_wen <= 1'b1;

                    // crc
                    data <= ~crc_8msb;
                    buffer <= { ~crc_in[23:0], 8'd0 };
                    crc_ini <= 1;          // start crc
                end

                // latch bc_sequence and bc_fpga, send back to PC,  restart crc
                152: begin
                    reg_waddr[4:0] <= 4'd0;  // hubreg 
                    reg_wdata <= { rx_bc_sequence[15:0], rx_bc_fpga[15:0] };
                    buffer <= { rx_bc_sequence[15:0], rx_bc_fpga[15:0] };
                    crc_ini <= 0;           // clear crc start bit                    
                end

                // latch timestamp, setup address for status
                184: begin
                    reg_waddr[4:0] <= 4'd1;  // hubreg 
                    reg_wdata <= timestamp;
                    buffer <= timestamp;    // latch timestamp
                    reg_raddr[15:0] <= { `ADDR_MAIN, 4'h0, 8'h00 };      // 0: status (See BoardRegs)
                    ts_reset <= 1;          // reset timestamp counter
                end

                // latch status data, setup address for digital inputs
                216: begin
                    reg_waddr[4:0] <= 4'd2;  // hubreg
                    reg_wdata <= reg_rdata;
                    buffer <= reg_rdata;    // latch status
                    reg_raddr[7:0] <= 8'h0a;      // 8'h0a: digital inputs (See BoardRegs)
                    ts_reset <= 0;          // clear timestamp reset
                end

                // latch digital inputs, setup address for temperature sensors
                248: begin
                    reg_waddr[4:0] <= 4'd3;  // hubreg
                    reg_wdata <= reg_rdata;
                    buffer <= reg_rdata;    // latch digital inputs
                    reg_raddr[7:0] <= 8'h05;      // 5: temperature sensors (See BoardRegs)
                end

                // latch temperature sensors, go to block data state
                280: begin
                    reg_waddr[4:0] <= 4'd4;   // hubreg
                    reg_wdata <= reg_rdata;
                    buffer <= reg_rdata;      // latch temperature
                    reg_raddr[7:4] <= 4'h1;        // start from channel 1
                    reg_raddr[3:0] <= dev_addr[0]; // 1st device address
                    dev_index <= 1;           // start from device 1
                    state <= ST_TX_DATA;      // goto ST_TX_DATA
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
                
                    // cache to hubreg, only saves to hub when block broadcast packets
                    reg_waddr[4:0] <= reg_waddr[4:0] + 1'b1;
                    reg_wdata <= reg_rdata;
                    
                    // send to FireWire bus
                    buffer <= reg_rdata;

                    if (reg_raddr[15:12] == `ADDR_MAIN) begin
                        // channel address circularly increments from 1 to num_channels
                        if (reg_raddr[7:4] == num_channels) begin
                            reg_raddr[7:4] <= 4'h1;
                            reg_raddr[3:0] <= dev_addr[dev_index];
                            dev_index <= (dev_index<3) ? (dev_index+1'b1) : 3'd0;
                        end
                        else
                            reg_raddr[7:4] <= reg_raddr[7:4] + 1'b1;
                    end
                    else if (reg_raddr[15:12] == `ADDR_HUB) begin
                        // 1 boards = 17 quadlets
                        if (reg_raddr[4:0] == 5'd16) begin
                            reg_raddr[8:5] <= reg_raddr[8:5] + 1'b1;
                            reg_raddr[4:0] <= 5'd0;
                        end
                        else begin
                            reg_raddr[4:0] <= reg_raddr[4:0] + 1'b1;
                        end
                    end
                    else begin   // PROM & PROM_QLA
                        reg_raddr[5:0] <= reg_raddr[5:0] + 1'b1;
                    end
                end

                if (count == (numbits-16'd32)) begin
                    data <= ~crc_8msb;
                    buffer <= { ~crc_in[23:0], 8'd0 };
                end
            end 
        end

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
end

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
    input  wire     reset,      // global reset signal
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
always @(posedge(sysclk) or negedge(reset))
begin
    // reset signal actions
    if (reset == 0)
        request <= 0;

    // on trigger, construct request string
    else if (trigger == 1) begin
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