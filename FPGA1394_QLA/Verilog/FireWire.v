/*******************************************************************************
 *
 * Copyright(C) 2008-2011 ERC CISST, Johns Hopkins University.
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
 *                                     Fixed mixed blocking/non-blocking issues
 */

// constants for receive speed codes
`define RX_S100 3'b000            // 100 Mbps
`define RX_S200 3'b001            // 200 Mbps
`define RX_S400 3'b101            // 400 Mbps

// phy request types
`define LREQ_TX_IMM 3'd0          // immediate transmit header
`define LREQ_TX_ISO 3'd1          // isochronous transmit header
`define LREQ_TX_PRI 3'd2          // priority transmit header
`define LREQ_TX_FAIR 3'd3         // fair transmit header
`define LREQ_REG_RD 3'd4          // register read header
`define LREQ_REG_WR 3'd5          // register write header
`define LREQ_ACCEL 3'd6           // async arbitration acceleration
`define LREQ_RES 3'd7             // reserved, presumably do nothing

// transmit mode ctl constants
`define CTL_IDLE 2'd0             // link asserts idle (done)
`define CTL_DATA 2'd1             // link is transmitting data
`define CTL_HOLD 2'd2             // link wants to hold the bus

// packet sizes
`define SZ_ACK 8                  // ack packet size
`define SZ_QREAD 16'd128          // quadlet read packet size
`define SZ_QWRITE 16'd160         // quadlet write packet size
`define SZ_QRESP 16'd160          // quadlet read response size
`define SZ_BWRITE 16'd192         // block write packet base size
`define SZ_BRESP 16'd192          // block read response base size
`define SZ_STAT 16'd16            // phy register transfer size

// transaction and response codes
`define TC_QWRITE 4'd0            // quadlet write
`define TC_BWRITE 4'd1            // block write
`define TC_QREAD 4'd4             // quadlet read
`define TC_BREAD 4'd5             // block read
`define TC_QRESP 4'd6             // quadlet read response
`define TC_BRESP 4'd7             // block read response
`define RC_DONE 4'd0              // complete response code

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

// other
`define CRC_INIT -32'd1           // initial value to start new crc calculation
`define REG_PHYCTRL 4'd1          // phy request bitstream (to request reg r/w)
`define REG_PHYDATA 4'd2          // holder for phy register read contents
`define INVALID_SIZE -16'd1       // packet size that we should never encounter

module PhyLinkInterface(
    sysclk, reset, board_id,
    ctl_ext, data_ext,
    reg_wen, blk_wen, blk_wstart,
    reg_addr, reg_rdata, reg_wdata,
    lreq_trig, lreq_type
);

    // -------------------------------------------------------------------------
    // define I/Os
    //

    // globals
    input sysclk;                 // system clock
    input reset;                  // global reset
    input[3:0] board_id;          // global board id

    // phy-link interface bus
    inout[1:0] ctl_ext;           // control line
    inout[7:0] data_ext;          // data bus

    // act on received packets
    output reg_wen;               // register write signal
    output blk_wen;               // block write signal
    output blk_wstart;            // block write is starting

    // register access
    output[7:0] reg_addr;         // read address to external register file
    input[31:0] reg_rdata;        // read data from external register file
    output[31:0] reg_wdata;       // write data to external register file

    // transmit parameters
    output lreq_trig;             // trigger signal for a phy request
    output[2:0] lreq_type;        // type of request to give to the phy

    // -------------------------------------------------------------------------
    // registered outputs
    //

    reg[7:0] data;                // data bus register
    reg[1:0] ctl;                 // control register
    reg blk_wstart;               // start of a block write
    reg reg_wen;                  // register write signal
    reg blk_wen;                  // block write signal

    // -------------------------------------------------------------------------
    // local wires and registers
    //

    // various
    reg tx_hold;                  // transmit hold flag
    reg rx_active;                // rx active flag
    reg[3:0] state, next;         // state register
    reg[2:0] rx_speed;            // received speed code
    reg[3:0] tx_type;             // encodes transmit type
    reg[5:0] node_id;             // phy node id register

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
    reg[2:0] lreq_type;           // encoded phy request type
    reg lreq_trig;                // phy request trigger
    reg crc_ini;                  // flag to reset the crc module
    wire phy_rw;                  // 0=phy reg read, 1=phy reg write

    // received packet fields
    reg[3:0] rx_tcode;            // transaction code
    reg[15:0] rx_dest;            // destination ID field
    reg[5:0] rx_tag;              // tag field
    reg[15:0] rx_src;             // source ID field
    reg[7:0] reg_addr;            // register address
    reg[15:0] reg_dlen;           // block data length
    reg[31:0] reg_wdata;          // register write data

    // real-time read stuff
    // an array of 4 4-bits device address
    // adc enc_pos enc_period enc_freq
    wire[3:0] dev_addr[0:3];      // order of device addresses for block read
    reg[2:0] dev_index;           // selects device address from map
    reg[31:0] timestamp;          // timestamp counter register
    reg ts_reset;                 // timestamp counter reset signal
    reg data_block;               // flag for block write data being received

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
        ST_TX_DATA = 10,          // tx state, link transmits block data
        ST_TX_DONE1 = 11,         // tx state, link finalizes transmission
        ST_TX_DONE2 = 12;         // tx state, phy regains phy-link bus


// -----------------------------------------------------------------------------
// hardware description
//

//
// continuous assignments and aliases for better readability (and writability!)
//

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

// timestamp counts number of clocks between block reads
always @(posedge(sysclk) or posedge(ts_reset) or negedge(reset))
begin
    if (reset==0 || ts_reset)
        timestamp <= 0;
    else
        timestamp <= timestamp + 1'b1;
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
        blk_wstart <= 0;          // clear the block write started flag
        reg_wen <= 0;             // keep register writes inactive by default
        blk_wen <= 0;             // keep block writes inactive by default
        lreq_trig <= 0;           // clear the phy request trigger
        lreq_type <= 0;           // set phy request type to known value
        node_id <= 0;             // hope phy updates this during self-id
        reg_addr <= 0;            // set reg address to known value
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
            reg_wen <= 0;                          // no register write events
            blk_wen <= 0;                          // no block write events
            crc_tx <= 0;                           // not in a transmit state

            // monitor ctl to select next state
            case (ctl)
                2'b00: state <= ST_IDLE;           // stay in monitor state
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
                        reg_addr <= { 4'd0, `REG_PHYDATA };
                        reg_wdata <= { 16'd0, st_buff };
                        reg_wen <= 1;
                        // save node id if register zero
                        if (st_buff[11:8] == 0)
                            node_id <= st_buff[7:2];
                    end
                end

            endcase
        end


        /***********************************************************************
         * receiving data packet from phy, from the bus
         */

        // ---------------------------------------------------------------------
        // wait until data-on goes away, i.e. when phy provides speed code
        //
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
                    if (data_block) begin
                        // latch data from data block on quadlet boundaries
                        if (count[4:0] == 0) begin
                            blk_wstart <= 0;   // Clear write started signal
                            if (reg_addr[7:6] == 2'b11) begin  // block write to PROM (M25P16)
                                if (reg_addr[5:0] == 6'h3f)
                                    reg_addr[5:0] <= 6'd0;
                                else
                                    reg_addr[5:0] <= reg_addr[5:0] + 1'b1;
                                reg_wdata <= buffer;   // data to program
                                reg_wen <= rx_active;
                            end
                            else begin                      // DAC data
                                // channel address circularly increments from 1 to num_channels
                                // (chan addr and dev offset are previously set)
                                if (reg_addr[7:4] == num_channels)
                                    reg_addr[7:4] <= 4'd1;
                                else
                                    reg_addr[7:4] <= reg_addr[7:4] + 1'b1;
                                reg_wdata <= buffer[30:0];               // data to write
                                reg_wen <= (buffer[31] & rx_active);     // check valid bit
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
                            else begin
                                rx_active <= 0;
                                lreq_trig <= 0;
                                lreq_type <= `LREQ_RES;
                                tx_type <= `TX_TYPE_DATA;
                            end
                        end
                        // second quadlet --------------------------------------
                        64: begin
                            rx_src <= buffer[31:16];      // source address
                        end
                        // third quadlet --------------------------------------
                        96: begin
                            reg_addr <= buffer[7:0];      // register address
                            crc_comp <= ~crc_in;          // computed crc for quadlet read
                        end
                        // fourth quadlet --------------------------------------
                        128: begin
                            reg_dlen <= buffer[31:16];    // block data length
                            reg_wdata <= buffer[31:0];    // reg write data

                            // total number of bits for block write packets
                            numbits <= { buffer[31:16], 3'd0 } + `SZ_BWRITE;

                            // computed crc for quadlet write, block read, and block write
                            if (rx_tcode != `TC_QREAD)
                                crc_comp <= ~crc_in;

                            // trigger phy register request if accessed
                            if ((rx_dest[5:0] == node_id) && (reg_addr == `REG_PHYCTRL) && (rx_tcode == `TC_QWRITE))
                            begin
                                // check the RW bit to determine access type
                                lreq_type <= (phy_rw ? `LREQ_REG_WR : `LREQ_REG_RD);
                                lreq_trig <= 1;
                            end
                        end
                        // quadlet 4.5 -----------------------------------------
                        144: crc_ini <= 1;     // reset crc for block data
                        // for block write packets, data block starts ----------
                        160: begin
                            // flag to indicate the start of block data
                            data_block <= (rx_tcode==`TC_BWRITE) ? 1'b1 : 1'b0;
                            blk_wstart <= (rx_tcode==`TC_BWRITE) ? 1'b1 : 1'b0;
                            if (reg_addr[7:6] == 2'b11) begin
                                if (rx_tcode==`TC_BWRITE)
                                    reg_addr[5:0] <= 6'h3f;  // block write to PROM (M25P16)
                                else
                                    reg_addr[5:0] <= 6'd0;   // block read from PROM (M25P16)
                            end
                            else begin
                                reg_addr[7:4] <= 0;    // init channel address
                                reg_addr[3:0] <= 1;    // set dac device address
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
                    endcase
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
                    reg_wen <= (rx_active & (rx_tcode==`TC_QWRITE));
                    blk_wen <= (rx_active & (rx_tcode==`TC_QWRITE) | (rx_tcode==`TC_BWRITE));
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
            if (rx_tcode == `TC_QREAD)
                tx_type <= `TX_TYPE_QRESP;
            else
                tx_type <= `TX_TYPE_BRESP;

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
                 24: buffer <= { rx_dest, `RC_DONE, 12'd0 };
                 56: buffer <= 0;
                 88: buffer <= { reg_dlen, 16'd0 };

                // latch header crc, reset crc in preparation for data crc
                128: begin
                    data <= ~crc_8msb;
                    buffer <= { ~crc_in[23:0], 8'd0 };
                    crc_ini <= 1;
                end

                // latch timestamp, setup address for status, restart crc
                152: begin
                    if (reg_addr[7:6] == 2'b11) begin  // block read from PROM (M25P16)
                        buffer <= reg_rdata;
                        reg_addr[5:0] <= 6'd1;
                    end
                    else begin                         // block read of real-time feedback
                        buffer <= timestamp;
                        reg_addr <= 0;                 // 0: status
                        ts_reset <= 1;
                    end
                    crc_ini <= 0;
                end

                // latch status data, setup address for digital inputs
                184: begin
                    buffer <= reg_rdata;
                    if (reg_addr[7:6] == 2'b11) begin  // block read from PROM (M25P16)
                        reg_addr[5:0] <= 6'd2;
                    end
                    else begin                         // block read of real-time feedback
                        reg_addr <= 8'd10;             // 10: digital inputs
                        ts_reset <= 0;
                    end
                end

                // latch digital inputs, setup address for temperature sensors
                216: begin
                    buffer <= reg_rdata;
                    if (reg_addr[7:6] == 2'b11) begin  // block read from PROM (M25P16)
                        reg_addr[5:0] <= 6'd3;
                    end
                    else begin                         // block read of real-time feedback
                        reg_addr <= 8'h5;              // 5: temperature sensors
                    end
                end

                // latch temperature sensors, go to block data state
                248: begin
                    buffer <= reg_rdata;
                    if (reg_addr[7:6] == 2'b11) begin  // block read from PROM (M25P16)
                        reg_addr[5:0] <= 6'd4;
                    end
                    else begin                         // block read of real-time feedback
                        reg_addr <= 8'h10;             // start cycling through channels
                        dev_index <= 1;
                    end
                    state <= ST_TX_DATA;
                end

            endcase
        end

        // ---------------------------------------------------------------------
        // link shifts block read data bits out to the phy/bus
        //
        ST_TX_DATA:
        begin
            if (count == numbits) begin
                ctl <= `CTL_IDLE;
                state <= ST_TX_DONE1;
            end

            else begin
                // shift out transmit bit from buffer and update counter
                data <= txmsb8b;
                buffer <= buffer << 8;
                count <= count + 16'd8;
                crc_in <= crc_8b;

                // latch data and update addresses on quadlet boundaries
                if (count[4:0] == 5'd24) begin
                    buffer <= reg_rdata;
                    if (reg_addr[7:6] == 2'b11) begin   // block read from PROM (M25P16)
                        if (reg_addr[5:0] == 6'h3f)
                            reg_addr[5:0] <= 6'd0;
                        else
                            reg_addr[5:0] <= reg_addr[5:0] + 1'b1;
                    end
                    else begin   // block read of real-time sensor data
                        // channel address circularly increments from 1 to num_channels
                        if (reg_addr[7:4] == num_channels) begin
                            reg_addr[7:4] <= 1;
                            reg_addr[3:0] <= dev_addr[dev_index];
                            dev_index <= (dev_index<3) ? (dev_index+1'b1) : 3'd0;
                        end
                        else
                            reg_addr[7:4] <= reg_addr[7:4] + 1'b1;
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

endmodule


/*******************************************************************************
 * This module sends a request to the phy, via the lreq line, initiated by a
 * high level trigger signal.  The type of request, be it bus transfers or
 * register accesses, is encoded in type.
 */

// length of various request bitstreams
`define LEN_LREQ 24

module PhyRequest(sysclk, reset, lreq, trigger, rtype, data);

    // define I/Os
    input sysclk;            // global system clock
    input reset;             // global reset signal
    input trigger;           // initiates a link request
    input[2:0] rtype;        // encoded request type
    input[11:0] data;        // addr/data bits to send to phy
    output lreq;             // lreq line to the phy

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
            `LREQ_TX_IMM: request[11:9] <= 3'b100;
        endcase
    end

    // shift out one bit per sysclk
    else
        request <= request << 1;
end

endmodule
