/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022 Johns Hopkins University.
 *
 * Module: RTL8211F
 *
 * Purpose: Interface to RTL8211F Ethernet PHY
 *
 * MDC: Clock from FPGA to RTL8211F
 *      Low/high time must be at least 32 ns
 *      Period must be at least 80 ns
 * MDIO: Bidirectional data line, relative to rising MDC
 *      Setup/hold time must be at least 10 ns
 *      MDIO valid within 300 ns when driven by PHY
 *
 * Given the long MDIO valid time, use a clock period of
 * ~320 nsec (16 sysclks)
 *
 * Revision history
 *     04/30/22    Peter Kazanzides    Initial revision
 */

`include "Constants.v"

// Define following for debug data (DBG1)
`define HAS_DEBUG_DATA

module RTL8211F
    #(parameter[3:0] CHANNEL = 4'd1)
(
    input  wire clk,               // input clock

    input  wire[15:0] reg_raddr,   // read address
    input  wire[15:0] reg_waddr,   // write address
    output wire[31:0] reg_rdata,   // register read data
    input  wire[31:0] reg_wdata,   // register write data 
    input  wire reg_wen,           // reg write enable

    output wire RSTn,              // Reset to RTL8211F (active low)

    // MDIO signals
    // When connecting directly to PHY, only need MDIO (inout) and
    // MDC, but when using GMII to RGMII core, it is necessary to
    // use MDIO_I, MDIO_O and MDIO_T instead of MDIO.
    output wire MDC,               // Clock to RTL8211F
    input wire MDIO_I,             // Input from PHY
    output reg MDIO_O,             // Output to PHY
    output reg MDIO_T,             // Tristate control

    // GMII Interface
    input wire RxClk,              // Rx Clk
    input wire RxValid,            // Rx Valid
    input wire[7:0] RxD,           // Rx Data
    input wire RxErr,              // Rx Error

    input wire TxClk,              // Tx Clk
    output reg TxEn,               // Tx Enable
    output reg[7:0] TxD,           // Tx Data

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
    output reg recvReady,             // Indicates that recv_word is valid
    output wire[15:0] recv_word,      // Word received via Ethernet (`SDSwapped for KSZ8851)
    // Ethernet send
    output reg sendRequest,           // Request EthernetIO to start providing data to be sent
    input wire sendBusy,              // From EthernetIO
    output reg sendReady,             // Request EthernetIO to provide next send_word
    input wire[15:0] send_word,       // Word to send via Ethernet (SDRegDWR for KSZ8851)
    // Feedback bits
    input wire bw_active,             // Indicates that block write module is active
    output wire ethInternalError,     // Error summary bit to EthernetIO
    input wire useUDP                 // Whether EthernetIO is using UDP
);

assign RSTn = 1'b1;

initial MDIO_T = 1'b1;

// State machine
localparam[2:0]
    ST_MDIO_IDLE = 0,
    ST_MDIO_WRITE_PREAMBLE = 1,
    ST_MDIO_WRITE_DATA = 2,
    ST_MDIO_READ_TA = 3,
    ST_MDIO_READ_DATA = 4;

reg[2:0] mdioState;
initial  mdioState = ST_MDIO_IDLE;

reg[8:0] cnt;            // 9-bit counter
assign MDC = cnt[3];     // MDC toggles every 8 clocks (160 ns)

// Timing:
//    MDC period = 16 clocks (cnt[3:0])
//    Rising edges after cnt = 7, 23, 39, ... 7+16*N, where N=0,1,...
//    MDIO write setup at least 1 count before rising edge,
//        might as well make it 4 counts (cnt[3:0] == `WRITE_SETUP)
//    MDIO write hold at least 1 count after rising edge
//    MDIO read 15 clocks after rising edge (cnt[3:0] == `READ_READY)
//
// Packet length: 64  (cnt[9:4])
//    Preamble (32) + ST (2) + OP (2) + PHYAD (5) + REGAD (5) + TA (2) + DATA (16)
//
// We use a 9-bit counter, with the upper 5 bits counting output bits (0..31) and the
// lower 4 bits driving the waveforms (rising edge at 7, falling edge at 15).
//
// Because we are writing 64 bits, we run through the counter twice -- first for
// the 32-bit preamble and then for the remaining 32-bits.

`define WRITE_SETUP  3
`define READ_READY   6   // Wrap-around from 7 to 6 (15 counts)

// Following is the 32-bits of data written to the RTL8211F after the preamble.
// Note that for a read command, the last 18 bits (TA + DATA) are ignored and
// handled in separate states (ST_MDIO_READ_TA and ST_MDIO_READ_DATA).
reg[31:0] write_data;

// Following is the 16-bits of data read from the RTL8211F (read commands only)
reg[15:0] read_data;
// Register address for read
reg[4:0] read_reg_addr;

// Whether a read command
wire isRead;
assign isRead = (write_data[29:28] == 2'b10) ? 1'b1 : 1'b0;

// PHY address
wire[4:0] phyAddr;
assign phyAddr = write_data[27:23];

// Register address
wire[4:0] regAddr;
assign regAddr = write_data[22:18];

// -----------------------------------------
// command processing
// ------------------------------------------
always @(posedge(clk))
begin

    if (mdioState != ST_MDIO_IDLE)
        cnt <= cnt + 9'd1;

    case (mdioState)

    ST_MDIO_IDLE:
        begin
            MDIO_T <= 1'b1;
            cnt <= 9'd0;
            if (reg_wen && (reg_waddr[6:0] == 7'd0)) begin
                write_data <= reg_wdata;
                MDIO_T <= 1'b0;
                MDIO_O <= 1'b1;
                mdioState <= ST_MDIO_WRITE_PREAMBLE;
            end
        end

    ST_MDIO_WRITE_PREAMBLE:
        begin
            if (cnt == {5'd31, 4'hf})
                mdioState <= ST_MDIO_WRITE_DATA;
            // cnt == 9'd0 when moving to ST_MDIO_WRITE_DATA
        end

    ST_MDIO_WRITE_DATA:
        begin
            if (cnt[3:0] == `WRITE_SETUP) begin
                MDIO_O <= write_data[~cnt[8:4]];
            end
            if (isRead && (cnt == {5'd13, 4'hf}))
                mdioState <= ST_MDIO_READ_TA;
            else if (cnt == {5'd31, 4'hf})
                mdioState <= ST_MDIO_IDLE;
        end

    ST_MDIO_READ_TA:
        begin
            if (cnt[3:0] == `WRITE_SETUP) begin
                MDIO_T <= 1'b1;
            end
            if (cnt == {5'd15, 4'hf}) begin
                read_reg_addr <= regAddr;
                mdioState <= ST_MDIO_READ_DATA;
            end
        end

    ST_MDIO_READ_DATA:
        begin
            if (cnt[3:0] == `READ_READY)
                read_data <= {read_data[14:0], MDIO_I};
            if (cnt == {5'd31, 4'hf})
                mdioState <= ST_MDIO_IDLE;
        end

    default:
        // Could note this as an error
        mdioState <= ST_MDIO_IDLE;

    endcase // case (mdioState)
end

// ----------------------------------------------------------------------------
// Ethernet receive
//
// Receives bytes from the Ethernet PHY, via GMII interface. Since the RTL8211F
// uses a RGMII interface, the input is actually via a GMII-to-RGMII IP core.
// The received bytes are written to a FIFO (recv_fifo). Once all bytes are
// received, the CRC is computed and a single 32-bit status word is written
// to a second FIFO (recv_info_fifo). The status word indicates the number of
// received bytes, as well as whether or not the CRC is correct. If the CRC
// is not correct, the next module should flush the bytes from the recv_fifo.
//
// Note that recv_fifo takes 8-bit bytes as input and provides 16-bit words as
// output. The use of 16-bit words enables easier integration with the higher-level
// code in EthernetIO.v, which was initially implemented to interface to the
// 16-bit FIFO provided by the KSZ8851.
// ----------------------------------------------------------------------------

// crc registers
wire[7:0] recv_crc_data;    // data into crc module to compute crc on
reg[31:0] recv_crc_in;      // input to crc module (starts at all ones)
wire[31:0] recv_crc_2b;     // current crc module output for data width 2 (not used)
wire[31:0] recv_crc_4b;     // current crc module output for data width 4 (not used)
wire[31:0] recv_crc_8b;     // current crc module output for data width 8

// Reverse bits when computing CRC
assign recv_crc_data = { RxD[0], RxD[1], RxD[2], RxD[3], RxD[4], RxD[5], RxD[6], RxD[7] };

// This module computes crc continuously, so it is up to the state machine to
// initialize, feed back, and latch crc values as necessary
crc32 recv_crc(recv_crc_data, recv_crc_in, recv_crc_2b, recv_crc_4b, recv_crc_8b);

reg  recv_fifo_reset;
reg  recv_wr_en;
reg  recv_rd_en;
wire recv_fifo_full;
wire recv_fifo_empty;
reg[7:0]   recv_byte;
reg[7:0]   recv_first_byte;
wire[15:0] recv_fifo_dout;

reg[2:0]   recv_preamble_cnt;
reg  recv_preamble_done;
reg  recv_preamble_error;

reg[11:0] recv_nbytes;  // Number of bytes received (not including preamble)

// Receive FIFO: 8 KByte (for now)
// KSZ8851 has 12 KByte receive FIFO and 6 KByte transmit FIFO
fifo_8x8192_16 recv_fifo(
    .rst(recv_fifo_reset),
    .wr_clk(RxClk),
    .rd_clk(clk),
    .din(recv_byte),
    .wr_en(recv_wr_en),
    .rd_en(recv_rd_en),
    .dout(recv_fifo_dout),
    .full(recv_fifo_full),
    .empty(recv_fifo_empty)
);

wire[31:0] recv_info_din;
reg recv_info_wr_en;
reg recv_info_rd_en;
wire recv_info_fifo_full;
wire recv_info_fifo_empty;
wire[31:0] recv_info_dout;

fifo_32x32 recv_info_fifo(
    .rst(recv_fifo_reset),
    .wr_clk(RxClk),
    .rd_clk(clk),
    .din(recv_info_din),
    .wr_en(recv_info_wr_en),
    .rd_en(recv_info_rd_en),
    .dout(recv_info_dout),
    .full(recv_info_fifo_full),
    .empty(recv_info_fifo_empty)
);

// The CRC of the packet, including the FCS (CRC) field should equal 32'hc704dd7b.
// Due to byte swapping, we check against 32'h7bdd04c7
wire recv_crc_error;
assign recv_crc_error = (recv_crc_in != 32'h7bdd04c7) ? 1'b0 : 1'b1;

// Bit index in recv_info_din and recv_info_dout
`define RECV_CRC_ERROR_BIT 26

assign recv_info_din = { 5'd0, recv_crc_error, RxErr, recv_preamble_error, recv_first_byte, 4'd0, recv_nbytes };

always @(posedge RxClk)
begin
    recv_wr_en <= 1'b0;
    recv_info_wr_en <= 1'b0;
    if (RxValid) begin
        recv_byte <= RxD;
        if (~recv_preamble_done) begin
            if (RxD == 8'h55) begin
                recv_preamble_cnt <= recv_preamble_cnt + 3'd1;
            end
            else begin
                recv_preamble_done <= 1'b1;
                recv_preamble_cnt <= 3'd0;
                recv_crc_in <= 32'hffffffff;    // Initialize CRC
                if ((RxD != 8'hd5) ||
                    (recv_preamble_cnt != 3'd7)) begin
                    recv_preamble_error <= 1'b1;
                end
            end
        end
        else begin
            if (recv_nbytes == 12'd0)
                recv_first_byte <= RxD;
            recv_nbytes <= recv_nbytes + 12'd1;
            recv_wr_en <= ~recv_fifo_full;
            recv_crc_in <= recv_crc_8b;
        end
    end
    else begin
        recv_preamble_done <= 1'b0;
        recv_preamble_cnt <= 3'd0;
        if (recv_nbytes != 12'd0) begin
            if (recv_info_wr_en == 1'b0) begin
                // First time through
                // If an odd number of bytes, pad with 0
                if (recv_nbytes[0]) begin
                    recv_byte <= 8'd0;
                    recv_wr_en <= ~recv_fifo_full;
                end
                // TODO: better handling of full FIFO
                // Write to recv_info FIFO (on next RxClk)
                recv_info_wr_en <= ~recv_info_fifo_full;
            end
            else begin
                recv_nbytes <= 12'd0;
                recv_preamble_error <= 1'b0;
            end
        end
    end
end

// ----------------------------------------------------------------------------
// Ethernet send
//
// Sends bytes to the Ethernet PHY, via GMII interface. Since the RTL8211F
// uses a RGMII interface, the output is actually via a GMII-to-RGMII IP core.
//
// The input is via two FIFOs, one that contains the bytes to send (send_fifo)
// and another that contains a single 32-bit status word (send_info_fifo).
// In particular, the status word specifies the number of bytes to send.
//
// Note that send_fifo does not include the CRC, so this module is responsible
// for computing and sending the CRC.
//
// Note that send_fifo takes 16-bit words as input and provides 8-bit bytes as
// output (used by this module). The use of 16-bit words enables easier
// integration with the higher-level code in EthernetIO.v, which was initially
// implemented to interface to the 16-bit FIFO provided by the KSZ8851.
// ----------------------------------------------------------------------------

localparam[1:0]
    ST_TX_IDLE = 2'd0,
    ST_TX_PREAMBLE = 2'd1,
    ST_TX_SEND = 2'd2,
    ST_TX_CRC = 2'd3;

reg[1:0] txState;

// crc registers
wire[7:0] send_crc_data;    // data into crc module to compute crc on
reg[31:0] send_crc_in;      // input to crc module (starts at all ones)
wire[31:0] send_crc_2b;     // current crc module output for data width 2 (not used)
wire[31:0] send_crc_4b;     // current crc module output for data width 4 (not used)
wire[31:0] send_crc_8b;     // current crc module output for data width 8

// Reverse bits when computing CRC
assign send_crc_data = { TxD[0], TxD[1], TxD[2], TxD[3], TxD[4], TxD[5], TxD[6], TxD[7] };

// This module computes crc continuously, so it is up to the state machine to
// initialize, feed back, and latch crc values as necessary
crc32 send_crc(send_crc_data, send_crc_in, send_crc_2b, send_crc_4b, send_crc_8b);

reg[15:0] send_nbytes;  // Number of bytes to send (not including preamble or CRC), from send_info_fifo
reg[15:0] send_cnt;     // Counts number of bytes sent (not including preamble or CRC)
reg[2:0]  tx_cnt;       // Counter used for preamble and crc

reg tx_underflow;       // Attempt to read send_fifo when empty

reg  send_fifo_reset;
reg  send_wr_en;
reg  send_rd_en;
wire send_fifo_full;
wire send_fifo_empty;
wire[15:0] send_fifo_din;
wire[7:0] send_fifo_dout;

assign send_fifo_din = {send_word[7:0], send_word[15:8]};

// Send FIFO: 4 KByte (for now)
// KSZ8851 has 6 KByte transmit FIFO
fifo_16x2048_8 send_fifo(
    .rst(send_fifo_reset),
    .wr_clk(clk),
    .rd_clk(TxClk),
    .din(send_fifo_din),
    .wr_en(send_wr_en),
    .rd_en(send_rd_en),
    .dout(send_fifo_dout),
    .full(send_fifo_full),
    .empty(send_fifo_empty)
);

wire[31:0] send_info_din;
reg send_info_wr_en;
reg send_info_rd_en;
wire send_info_fifo_full;
wire[31:0] send_info_dout;

assign send_info_din = { 16'd0, responseByteCount };

fifo_32x32 send_info_fifo(
    .rst(send_fifo_reset),
    .wr_clk(clk),
    .rd_clk(TxClk),
    .din(send_info_din),
    .wr_en(send_info_wr_en),
    .rd_en(send_info_rd_en),
    .dout(send_info_dout),
    .full(send_info_fifo_full),
    .empty(send_info_fifo_empty)
);

always @(posedge TxClk)
begin
    // TODO: Send CRC -- maybe from higher level instead
    // TODO: maybe also use a send info queue, so that we do not have to
    //       worry about running out of data in the FIFO
    case (txState)

    ST_TX_IDLE:
    begin
        send_cnt <= 16'd0;
        tx_cnt <= 3'd0;
        send_rd_en <= 1'b0;
        TxEn <= 1'b0;
        if (~send_info_fifo_empty) begin
            send_info_rd_en <= 1'b1;
            send_nbytes <= send_info_dout[15:0];
            txState <= ST_TX_PREAMBLE;
        end
    end

    ST_TX_PREAMBLE:
    begin
        send_info_rd_en <= 1'b0;
        TxEn <= 1'b1;
        if (tx_cnt == 3'd7) begin
            txState <= ST_TX_SEND;
            send_crc_in <= 32'hffffffff;    // Initialize CRC
            TxD <= 8'hd5;
        end
        else begin
            tx_cnt <= tx_cnt + 3'd1;
            TxD <= 8'h55;
        end
    end

    ST_TX_SEND:
    begin
        send_rd_en <= 1'b1;
        if (send_fifo_empty) begin
            tx_underflow <= 1'b1;
            TxD <= 8'd0;
        end          
        else begin
            TxD <= send_fifo_dout;
        end
        send_crc_in <= send_crc_8b;
        if (send_cnt == send_nbytes) begin
            tx_cnt <= 3'd0;
            txState <= ST_TX_CRC;
        end
        else begin
            send_cnt <= send_cnt + 16'd1;
        end
    end

    ST_TX_CRC:
    begin
        send_rd_en <= 1'b0;
        TxD <= send_crc_in[31:24];
        if (tx_cnt == 3'd3) begin
            txState <= ST_TX_IDLE;
        end
        else begin
            send_crc_in <= {send_crc_in[23:0], 8'd0};
            tx_cnt <= tx_cnt + 3'd1;
        end
   end

   endcase
end

// ----------------------------------------------------------------------------
// Ethernet state machine
//
// This is a simple state machine that does not take advantage of the fact that
// we can send and receive at the same time. In practice, this is not an issue
// due to the use of a request-response communication protocol.
//
// This module lies between the low-level send and receive modules above, and
// the high-level module in EthernetIO.v. The interface to the lower-level
// modules is via FIFOs (recv_fifo, recv_info_fifo, send_fifo, send_info_fifo).
// The interface to EthernetIO.v is via signals. Specifically, the receive or
// send process is initiated by asserting recvRequest or sendRequest, respectively.
// Each 16-bit word is received or sent by asserting recvReady or sendReady,
// respectively. The 16-bit interface between this module and EthernetIO is a
// legacy from the KSZ8851 interface used for FPGA V2.
// ----------------------------------------------------------------------------

localparam[1:0]
    ST_IDLE = 2'd0,
    ST_RECEIVE = 2'd1,
    ST_SEND = 2'd2;

reg[1:0] state;

`ifdef HAS_DEBUG_DATA
reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[7:0]  numPacketInvalid;  // Number of invalid Ethernet frames received
reg[7:0]  numPacketSent;     // Number of packets sent to host PC
`endif

reg[11:0] rxPktWords;  // Num of words in receive queue

reg[5:0] recvCnt;      // Counts number of received words
reg dataValid;
reg recvTransition;

assign recv_word = { recv_fifo_dout[7:0], recv_fifo_dout[15:8] };  // Byte swap?

reg[11:0] sendCnt;     // Counts number of sent bytes

always @(posedge(clk))
begin

    case (state)

    ST_IDLE:
    begin
        recvCnt <= 6'd0;
        sendCnt <= 12'd0;
        isForward <= 0;
        sendReady <= 1'b0;
        send_wr_en <= 1'b0;
        send_info_wr_en <= 1'b0;
        if (sendReq & (~send_fifo_full)) begin
            // forward packet from FireWire
            isForward <= 1;
            sendRequest <= 1;
            state <= ST_SEND;
        end
        else if (~recv_info_fifo_empty) begin
            rxPktWords <= ((recv_info_dout[11:0]+12'd3)>>1)&12'hffe;
            recv_info_rd_en <= 1'b1;
            // Request EthernetIO to receive if CRC valid (flush if not valid)
            recvRequest <= ~recv_info_dout[`RECV_CRC_ERROR_BIT];
            recvReady <= 1'b1;
            state <= ST_RECEIVE;
`ifdef HAS_DEBUG_DATA
            if (recv_info_dout[`RECV_CRC_ERROR_BIT])
                numPacketInvalid <= numPacketInvalid + 8'd1;
            else
                numPacketValid <= numPacketValid + 16'd1;
`endif
        end
    end

    ST_RECEIVE:
    begin
        if (recvBusy)
            recvRequest <= 1'b0;
        if (recvReady) begin
            recvReady <= 1'b0;
            dataValid <= 1'b1;
        end
        else if (dataValid) begin
           dataValid <= 1'b0;
           recvTransition <= 1'b1;
           recv_rd_en <= 1'b1;
        end
        else begin  // recvTransition
           recvTransition <= 1'b0;
           recvReady <= 1'b1;
           recv_info_rd_en <= 1'b0;
           recv_rd_en <= 1'b0;
           if (recvCnt == rxPktWords) begin
               sendRequest <= responseRequired;
               state <= responseRequired ? ST_SEND : ST_IDLE;
           end
           else begin
               recvCnt <= recvCnt + 6'd1;
           end
        end
    end

    ST_SEND:
    begin
        if (sendBusy) begin
            sendCnt <= sendCnt + 12'd1;  // Essentially counts number of bytes
            sendRequest <= 1'b0;
            sendReady <= ~sendReady;
            send_wr_en <= sendReady;
        end
        else begin
            // All done
            // Compare sendCnt to responseByteCount
            send_wr_en <= 1'b0;
            send_info_wr_en <= 1'b1;
`ifdef HAS_DEBUG_DATA
            numPacketSent <= numPacketSent + 8'd1;
`endif
            state <= ST_IDLE;
        end

    end

    endcase
end

// Error bit provided to EthernetIO (reported back to PC in ExtraData)
assign ethInternalError = RxErr|recv_preamble_error;

// -----------------------------------------------
// Debug data
// -----------------------------------------------
`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:15];
assign DebugData[0]  = "1GBD";  // DBG1 byte-swapped
assign DebugData[1]  = 32'd0;
assign DebugData[2]  = { 8'd0, 1'b0, sendRequest, 6'd0, 16'd0};
assign DebugData[3]  = { 16'd0, 8'd0, isForward, 7'd0};
assign DebugData[4]  = 32'd0;
assign DebugData[5]  = { 16'd0, 8'd0, numPacketSent};
assign DebugData[6]  = 32'd0;
assign DebugData[7]  = { 16'd0, 4'd0, rxPktWords };
//assign DebugData[8]  = { timeSend, timeReceive };
assign DebugData[8]  = 32'd0;
assign DebugData[9]  = { 8'd0, numPacketInvalid, numPacketValid };
assign DebugData[10] = 32'd0;
assign DebugData[11] = 32'd0;
assign DebugData[12] = 32'd0;
assign DebugData[13] = 32'd0;
assign DebugData[14] = 32'd0;
assign DebugData[15] = 32'd0;
`endif

// TODO: move reg_rdata_dbg into DebugData
wire[31:0] reg_rdata_dbg;   // Debug data
assign reg_rdata_dbg = { 2'd0, tx_underflow, RxErr, recv_preamble_error, recv_fifo_reset, recv_fifo_full, recv_fifo_empty,
                         8'd0, 16'd0 };

// Following data is accessible via block read from address `ADDR_ETH (0x4000),
// where x is the Ethernet channel (1 or 2).
// Note that some data (addresses 90-93) is provided by this module (RTL8211F) whereas everything
// else is provided by the high-level interface (EthernetIO).
//    4x00 - 4x7f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4x80 - 4x8f (16 quadlets)  Debug data
// PK TODO: Change PC software to read following from 90-93 instead of 80-83
//    4x90                       MDIO feedback (data read from management interface)
//    4x91                       Receive info (if available)
//    4x92                       Computed CRC
//    4x93                       Debug data (reg_rdata_dbg)
//    4x94 - 4x9f (12 quadlets) Unused
//    4xa0 - 4xbf (32 quadlets) Unused
//    4xc0 - 4xdf (32 quadlets) PacketBuffer/ReplyBuffer (64 words)
//    4xe0 - 4xff (32 quadlets) ReplyIndex (64 words)

`ifdef HAS_DEBUG_DATA
assign reg_rdata = (reg_raddr[7:4] == 4'h8) ? DebugData[reg_raddr[3:0]] :
`else
assign reg_rdata = (reg_raddr[7:4] == 4'h8) ? "0GBD" :
`endif
                   (reg_raddr[7:0] == 8'h90) ? { 5'd0, state, 3'd0, read_reg_addr, read_data} :
                   ((reg_raddr[7:0] == 8'h91) && (~recv_info_fifo_empty)) ? recv_info_dout :
                   (reg_raddr[7:0] == 8'h92) ? recv_crc_in :
                   (reg_raddr[7:0] == 8'h93) ? reg_rdata_dbg : 32'd0;

// For debugging
always @(posedge(clk))
begin
    // Reset the FIFOs by writing to 4x81, where x is channel number
    if (reg_wen && (reg_waddr[6:0] == 7'd1)) begin
       recv_fifo_reset <= 1'b1;
       send_fifo_reset <= 1'b1;
    end
    else begin
       recv_fifo_reset <= 1'b0;
       send_fifo_reset <= 1'b0;
    end
end

endmodule
