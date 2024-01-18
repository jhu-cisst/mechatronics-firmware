/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023-2024 Johns Hopkins University.
 *
 * Module: EthSwitchRt
 *
 * Purpose: Ethernet switch for real-time interface (to FPGA)
 *
 * Revision history
 *     02/13/23    Peter Kazanzides    Initial revision (code from RTL8211F.v)
 */

`include "Constants.v"

module EthSwitchRt
(
    input  wire clk,                  // input clock
    input  wire[3:0] board_id,        // board id

    input  wire[15:0] reg_raddr,      // read address
    output wire[31:0] reg_rdata,      // register read data

    input wire resetActive,
    input wire clearErrors,           // Clear error flags

    output wire PortReady,         // 1 -> ready to receive input data

    // GMII Interface
    input wire RxClk,              // Rx Clk
    input wire RxValid,            // Rx Valid
    input wire[7:0] RxD,           // Rx Data
    input wire RxErr,              // Rx Error

    input wire TxClk,              // Tx Clk
    output reg TxEn,               // Tx Enable
    output reg[7:0] TxD,           // Tx Data
    output wire TxErr,             // Tx Error

    // Interface from Firewire (for sending packets via Ethernet)
    input wire sendReq,               // Send request from FireWire

    // Interface to EthernetIO
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
    output wire sendReady,            // Request EthernetIO to provide next send_word
    input wire[15:0] send_word,       // Word to send via Ethernet (SDRegDWR for KSZ8851)
    // Timing measurements (do not include times for Rx/Tx loops, which is consistent with KSZ8851)
    output reg[15:0] timeReceive,     // Time for receiving packet (not including Rx loop in RTL8211F)
    output reg[15:0] timeNow,         // Running time counting since receive started
    // Feedback bits
    input wire bw_active,             // Indicates that block write module is active
    output reg curPort,               // Currently active port (0->Eth1, 1->Eth2)
    output wire eth_InternalError     // Internal error (to EthernetIO)
);

initial curPort = 1'b0;   // TODO: No longer relevant

assign PortReady = 1'b1;  // TODO

//**************** TEMP ***********************

assign TxErr = 1'b0;

// Error bit provided to EthernetIO (reported back to PC in ExtraData)
assign ethInternalError = RxErr_1|recv_preamble_error_1;

wire recv_fifo_empty;
reg recv_rd_en;
wire[15:0] recv_fifo_dout;
wire recv_info_fifo_empty;
reg recv_info_rd_en;
wire[31:0] recv_info_dout;

wire send_fifo_full;
reg send_wr_en;
wire[15:0] send_fifo_din;
wire send_info_fifo_full;
reg send_info_wr_en;
wire[31:0] send_info_din;

`ifdef HAS_DEBUG_DATA
reg recv_fifo_reset_1;
reg recv_fifo_full_1;
reg tx_underflow_1;
reg send_fifo_empty_1;
reg send_fifo_error_1;
reg recv_ipv4_1;
reg recv_ipv4_err_1;
reg recv_udp_1;
reg isUnicast_1;
reg isMulticast_1;
reg isBroadcast_1;
reg txStateError_1;
reg rxStateError_1;
reg[2:0] txState_1;
reg[2:0] rxState_1;
reg[31:0] recv_crc_in_1;
reg[7:0] numRxDropped_1;
reg[7:0] send_first_byte_out_1;
reg[7:0] numTxSent_1;
reg[31:0] send_crc_in_1;
`endif

// ----------------------------------------------------------------------------
// Ethernet low-level interface

// ----------------------------------------------------------------------------
// Ethernet receive
//
// Receives bytes from the Ethernet PHY, via GMII interface. Since the RTL8211F
// uses a RGMII interface, the input is actually via a GMII-to-RGMII IP core.
//
// The receive loop caches the first 16 bytes, which includes the Ethernet frame
// header (first 14 bytes), so that MAC address filtering can be implemented.
// This helps with performance because the higher-level block takes longer to
// process the packets and therefore it is better to filter them out as early as
// possible. There are several reasons why a packet may be discarded at this level:
//
//   1) If the destination MAC address is not unicast (matching this board's MAC
//      address), or multicast, or broadcast.
//
//   2) If a CRC (Ethernet FCS) or IPv4 checksum error is detected. We currently
//      do not check the UDP checksum, but that could also be implemented.
//
//   3) If we could not store some of the bytes in the recv_fifo because it was full
//      (recv_fifo_overflow set).
//
// Note that once we detect that a packet should be discarded, we stop writing
// bytes to the recv_fifo.
//
// There are two ways to discard packets:
//
//   1) If the recv_fifo was empty when we started, we can just reset it.
//      This is the most efficient, but may not always be possible. The
//      numRxDropped counter indicates the number of packets discarded this way.
//
//   2) Set the ETH_RECV_FLUSH_BIT to indicate to the higher-level block that this
//      packet should be flushed from recv_fifo. The higher-level block sets the
//      numPacketFlushed counter to indicate the number of packets discarded this way.
//
// For packets that are not dropped, after the last byte is written to the recv_fifo,
// a single 32-bit status word is written to a second FIFO (recv_info_fifo).
// The status word indicates the number of received bytes. If the ETH_RECV_FLUSH_BIT is
// set, the higher-level loop should flush the packet. Otherwise, it should be processed.
// The status word contains other bits that can be used by the higher-level block,
// including a copy of the first byte in recv_fifo, which can be used to detect
// alignment problems.
//
// Note that recv_fifo takes 8-bit bytes as input and provides 16-bit words as
// output. The use of 16-bit words enables easier integration with the higher-level
// code in EthernetIO.v, which was initially implemented to interface to the
// 16-bit FIFO provided by the KSZ8851.
// ----------------------------------------------------------------------------

localparam
    ST_RX_IDLE     = 3'd0,
    ST_RX_PREAMBLE = 3'd1,
    ST_RX_RECV     = 3'd2,
    ST_RX_FINISH   = 3'd3,
    ST_RX_RESET    = 3'd4;

reg[2:0] rxState;
reg rxStateError;

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

reg[16:0] recv_ipv4_cksum;   // Used to verify IPv4 header checksum
reg recv_ipv4_err;           // 1 -> IPv4 checksum error

reg  recv_fifo_reset_req;    // Recv FIFO reset request via Ethernet control register
reg  recv_fifo_reset;

// Xilinx recommends asserting reset for at least 3 cycles of the slowest clock.
// In this implementation, the reset is asserted with respect to the write clock,
// which is either 2.5 MHz, 25 MHz, or 125 MHz depending on the Ethernet link speed.
// But, the read clock is 49.152 MHz (20.345 ns), so we need to assert reset for at least
// 8 clock cycles, in case the 125 MHz (8 ns) clock is active (20.345*3/8 = 7.63).
reg[2:0] recv_fifo_reset_cnt;

reg  recv_wr_en;
wire recv_fifo_full;
reg[7:0]   recv_byte;
wire[7:0]  recv_first_byte_in;

reg[2:0] recv_preamble_cnt;
reg      recv_preamble_error;

reg[11:0] recv_nbytes;    // Number of bytes received (not including preamble)
reg[11:0] recv_fifo_nb;   // Number of bytes in receive FIFO

// First 16 bytes of Ethernet frame
reg[7:0] frame_header[0:15];

assign recv_first_byte_in = frame_header[`ETH_Frame_Begin];

// First 44 bits of FPGA MAC address (last 4 bits is board_id)
localparam[43:0] fpgaMAC44 = 44'hFA610E13940;

// FPGA multicast MAC address
localparam[47:0] fpgaMulticastMAC = 48'hFB610E1394FF;

// FPGA broadcast MAC address
localparam[47:0] fpgaBroadcastMAC = 48'hFFFFFFFFFFFF;

// Destination MAC address
wire[47:0] destMac;
assign destMac = { frame_header[`ETH_Dest_MAC],   frame_header[`ETH_Dest_MAC+1],
                   frame_header[`ETH_Dest_MAC+2], frame_header[`ETH_Dest_MAC+3],
                   frame_header[`ETH_Dest_MAC+4], frame_header[`ETH_Dest_MAC+5] };

wire isUnicast;
assign isUnicast = (destMac == {fpgaMAC44, board_id}) ? 1'b1 : 1'b0;
wire isMulticast;
assign isMulticast = (destMac == fpgaMulticastMAC) ? 1'b1 : 1'b0;
wire isBroadcast;
assign isBroadcast = (destMac == fpgaBroadcastMAC) ? 1'b1 : 1'b0;

// Whether Ethernet frame should be handled by this board
wire isForThis;
assign isForThis = isUnicast|isMulticast|isBroadcast;

// For sampling recv_fifo_empty, which is synchronized with the read clock
reg[3:0] recv_fifo_was_empty;

reg recv_fifo_overflow;

// Whether to write to FIFO -- always write first 16 bytes, unless FIFO is full
// or has overflowed.
wire writeToRecvFifo;
assign writeToRecvFifo = ((recv_nbytes[11:4] == 8'd0) || isForThis) ?
                         ~(recv_fifo_full|recv_fifo_overflow) : 1'b0;

// Ethernet frame length/type and IPv4 protocol are used to compute checksums.
// This duplicates some code from EthernetIO.v, but the advantage is that we
// can detect checksum errors before the packet is processed in EthernetIO.v.
wire[15:0] recv_length;   // Ethernet frame length/type (0x0800 is IPv4)
assign recv_length = {frame_header[`ETH_Frame_Length], frame_header[`ETH_Frame_Length+1]};
wire recv_ipv4;
assign recv_ipv4 = (recv_length == 16'h0800) ? 1'b1 : 1'b0;
reg  recv_udp;           // Indicates UDP protocol

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
wire recv_info_fifo_full;

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

// Whether to flush packet
wire recv_flush;
assign recv_flush = recv_fifo_overflow|(~isForThis)|recv_ipv4_err|recv_crc_error;

assign recv_info_din = { recv_flush, 1'b0, recv_fifo_overflow, ~isForThis,            // [31:28]
                         recv_ipv4_err, recv_crc_error, RxErr, recv_preamble_error,   // [27:24]
                         recv_first_byte_in,                                          // [23:16]
                         1'b0, isUnicast, isMulticast, isBroadcast,                   // [15:12]
                         recv_fifo_nb };                                              // [11:0]

`ifdef HAS_DEBUG_DATA
reg[7:0] numRxDropped;   // Number of irrelevant or erroneous packets dropped by Rx loop
`endif

always @(posedge RxClk)
begin

    if (clearErrors) begin
        rxStateError <= 1'b0;
    end

    case (rxState)

    ST_RX_IDLE:
    begin
        recv_nbytes <= 12'd0;
        recv_fifo_nb <= 12'd0;
        recv_wr_en <= 1'b0;
        recv_info_wr_en <= 1'b0;
        recv_preamble_error <= 1'b0;
        recv_fifo_reset <= 1'b0;
        recv_fifo_reset_cnt <= 3'd0;
        recv_fifo_was_empty <= 4'd0;
        if (RxValid) begin
            recv_preamble_cnt <= (RxD == 8'h55) ? 3'd1 : 3'd0;
            rxState <= ST_RX_PREAMBLE;
        end
        else if (recv_fifo_reset_req) begin
            recv_fifo_reset <= 1'b1;
            rxState <= ST_RX_RESET;
        end
    end

    ST_RX_PREAMBLE:
    begin
        if (RxValid) begin
            recv_fifo_was_empty <= { recv_fifo_was_empty[2:0], recv_fifo_empty };
            if (RxD == 8'h55) begin
                recv_preamble_cnt <= recv_preamble_cnt + 3'd1;
            end
            else begin
                rxState <= ST_RX_RECV;
                recv_crc_in <= 32'hffffffff;    // Initialize CRC
                recv_fifo_overflow <= 1'b0;
                if ((RxD != 8'hd5) ||
                    (recv_preamble_cnt != 3'd7)) begin
                    recv_preamble_error <= 1'b1;
                end
            end
        end
        else begin
            // Here, the preamble was terminated prematurely;
            // This is not a significant problem.
            rxState <= ST_RX_IDLE;
        end
    end

    ST_RX_RECV:
    begin
        if (RxValid) begin
            recv_byte <= RxD;
            if (recv_nbytes[11:4] == 8'd0) begin
                // Save first 16 bytes (Ethernet header is 14 bytes)
                frame_header[recv_nbytes[3:0]] <= RxD;
            end
            recv_wr_en <= writeToRecvFifo;
            if (writeToRecvFifo) begin
                recv_fifo_nb <= recv_fifo_nb + 12'd1;
            end
            if (recv_fifo_full) begin
                recv_fifo_overflow <= 1'b1;
            end

            if (recv_nbytes == `ETH_IPv4_Protocol)
                recv_udp <= (recv_ipv4 && (RxD == 8'd17)) ? 1'd1 : 1'd0;

            // IPv4 header checksum. Note that the carry bit is added to the sum.
            if (recv_nbytes == `ETH_IPv4_Begin)
                recv_ipv4_cksum <= {1'b0, RxD, 8'd0};
            else if (recv_nbytes == `ETH_IPv4_End)
                recv_ipv4_err <= ((recv_ipv4_cksum == 17'h0ffff) || (recv_ipv4_cksum == 17'h1fffe)) ? 1'b0 : recv_ipv4;
            else if (~recv_nbytes[0])
                recv_ipv4_cksum <= {1'b0, recv_ipv4_cksum[15:0]} + {RxD, 7'd0, recv_ipv4_cksum[16]};
            else
                recv_ipv4_cksum <= recv_ipv4_cksum + { 9'd0, RxD };

            recv_nbytes <= recv_nbytes + 12'd1;
            recv_crc_in <= recv_crc_8b;
        end
        else begin
            // If an odd number of bytes in FIFO, pad with 0; not necessary to
            // check for FIFO full (overflow) in this case because FIFO has
            // an even number of bytes.
            recv_byte <= 8'd0;
            recv_wr_en <= recv_nbytes[0]&writeToRecvFifo;
            if (recv_fifo_nb[0]&writeToRecvFifo)
                recv_fifo_nb <= recv_fifo_nb + 12'd1;

            // As long as bytes were received, go to ST_RX_FINISH
            rxState <= (recv_nbytes == 12'd0) ? ST_RX_IDLE : ST_RX_FINISH;
        end
    end

    ST_RX_FINISH:
    begin
        // This state is entered when a receive has just ended
        // RxValid should still be 0

        if (recv_flush && (recv_fifo_was_empty != 4'd0)) begin
            // If we need to flush the packet and can just reset the recv_fifo.
            // Here, we assume the fifo was empty if any of the last 4 values
            // (sampled during preamble) are non-zero.
            recv_fifo_reset <= 1'b1;
            rxState <= ST_RX_RESET;
`ifdef HAS_DEBUG_DATA
            numRxDropped <= numRxDropped + 8'd1;
`endif
        end
        else begin
            // Write to recv_info FIFO (on next RxClk)
            recv_info_wr_en <= ~recv_info_fifo_full;
            rxState <= ST_RX_IDLE;
        end
    end

    ST_RX_RESET:
    begin
        // Enforce fifo reset pulse timing. Note that reset can only be asserted when RxValid is 0,
        // but we do not worry about RxValid becoming 1 during the fifo reset pulse because we do not
        // need to access the recv_fifo while processing the preamble.
        recv_fifo_reset_cnt <= recv_fifo_reset_cnt + 3'd1;
        if (recv_fifo_reset_cnt == 3'd7)
            rxState <= ST_RX_IDLE;
    end

    default:
    begin
        rxStateError <= 1'b1;
        rxState <= ST_RX_IDLE;
    end

    endcase

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

localparam[2:0]
    ST_TX_IDLE = 3'd0,
    ST_TX_PREAMBLE = 3'd1,
    ST_TX_SEND = 3'd2,
    ST_TX_PADDING = 3'd3,
    ST_TX_CRC = 3'd4;

reg[2:0] txState;

// crc registers
wire[7:0] send_crc_data;    // data into crc module to compute crc on
reg[31:0] send_crc_in;      // input to crc module (starts at all ones)
wire[31:0] send_crc_2b;     // current crc module output for data width 2 (not used)
wire[31:0] send_crc_4b;     // current crc module output for data width 4 (not used)
wire[31:0] send_crc_8b;     // current crc module output for data width 8

// This module computes crc continuously, so it is up to the state machine to
// initialize, feed back, and latch crc values as necessary
crc32 send_crc(send_crc_data, send_crc_in, send_crc_2b, send_crc_4b, send_crc_8b);

reg[15:0] send_nbytes;  // Number of bytes to send (not including preamble or CRC), from send_info_fifo
reg[15:0] send_cnt;     // Counts number of bytes sent (not including preamble or CRC)
reg[5:0]  padding_cnt;  // Counter used to ensure minimum Ethernet frame size (64)
reg[2:0]  tx_cnt;       // Counter used for preamble and crc

reg txStateError;       // Invalid state
reg tx_underflow;       // Attempt to read send_fifo when empty

reg  send_fifo_reset;
reg  send_rd_en;
wire send_fifo_empty;
reg  send_fifo_error;     // First byte in send_fifo not as expected

wire[7:0] send_fifo_dout;

// Reverse bits for computing CRC
wire[7:0] TxRev = { send_fifo_dout[0], send_fifo_dout[1], send_fifo_dout[2], send_fifo_dout[3],
                    send_fifo_dout[4], send_fifo_dout[5], send_fifo_dout[6], send_fifo_dout[7] };

assign send_crc_data = (txState == ST_TX_SEND) ? TxRev : 8'd0;

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

reg send_info_rd_en;
wire[31:0] send_info_dout;
reg[7:0]   send_first_byte_out;  // for error checking

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

`ifdef HAS_DEBUG_DATA
reg[7:0]  numTxSent;         // Number of packets sent to host PC
`endif

always @(posedge TxClk)
begin
    case (txState)

    ST_TX_IDLE:
    begin
        send_cnt <= 16'd0;
        tx_cnt <= 3'd0;
        send_rd_en <= 1'b0;
        TxEn <= 1'b0;
        if (resetActive) begin
            txStateError <= 1'b0;
        end
        else if (~send_info_fifo_empty) begin
            // If the MSB is set, we flush the packet, so we don't
            // need to request the bus
            tx_underflow <= 1'b0;
            send_nbytes <= send_info_dout[15:0];
            send_first_byte_out <= send_info_dout[23:16];
            send_info_rd_en <= 1'b1;
            txState <= ST_TX_PREAMBLE;
            // If the MSB is set, we flush the packet (TxEn=0)
            TxEn <= ~send_info_dout[31];
        end
    end

    ST_TX_PREAMBLE:
    begin
        send_info_rd_en <= 1'b0;
        if (tx_cnt == 3'd7) begin
            txState <= ST_TX_SEND;
            send_rd_en <= ~send_fifo_empty;
            send_crc_in <= 32'hffffffff;    // Initialize CRC
            padding_cnt <= 6'd59;           // Minimum frame size is 64 (-4 for CRC)
            TxD <= 8'hd5;
        end
        else begin
            tx_cnt <= tx_cnt + 3'd1;
            TxD <= 8'h55;
        end
    end

    ST_TX_SEND:
    begin
        if (send_fifo_empty) begin
            tx_underflow <= 1'b1;
            TxD <= 8'd0;
        end
        else begin
            TxD <= send_fifo_dout;
            if (send_cnt == 16'd0) begin
                send_fifo_error <= (send_first_byte_out == send_fifo_dout) ? 1'b0 : 1'b1;
                // May not be easy to handle an error if it occurs
            end
            send_crc_in <= send_crc_8b;
        end
        if (send_cnt == (send_nbytes-16'd1)) begin
            send_rd_en <= 1'b0;
            tx_cnt <= 3'd0;
            txState <= (padding_cnt == 6'd0) ? ST_TX_CRC : ST_TX_PADDING;
        end
        else begin
            send_rd_en <= ~send_fifo_empty;
            send_cnt <= send_cnt + 16'd1;
        end
        if (padding_cnt != 6'd0) begin
            padding_cnt <= padding_cnt - 6'd1;
        end
    end

    ST_TX_PADDING:
    begin
        TxD <= 8'd0;
        send_crc_in <= send_crc_8b;
        padding_cnt <= padding_cnt - 6'd1;
        if (padding_cnt == 6'd0)
            txState <= ST_TX_CRC;
    end

    ST_TX_CRC:
    begin
        if (tx_cnt == 3'd0) begin
            // If the number of bytes is odd, we need to pop the last
            // byte from the FIFO because the producer provides words.
            send_rd_en <= send_nbytes[0];
        end
        else begin
            send_rd_en <= 1'b0;
        end
        // Need to bit-reverse CRC when sending
        TxD <= ~{send_crc_in[24], send_crc_in[25], send_crc_in[26], send_crc_in[27],
                 send_crc_in[28], send_crc_in[29], send_crc_in[30], send_crc_in[31]};
        send_crc_in <= {send_crc_in[23:0], send_crc_in[31:24]};
        if (tx_cnt == 3'd3) begin
            txState <= ST_TX_IDLE;
`ifdef HAS_DEBUG_DATA
            numTxSent <= numTxSent + 8'd1;
`endif
        end
        else begin
            tx_cnt <= tx_cnt + 3'd1;
        end
    end

    default:
    begin
        txStateError <= 1'b1;
        txState <= ST_TX_IDLE;
    end

   endcase
end

//********************** END TEMP ***********************************************

reg[11:0] last_sendCnt;
reg[11:0] last_responseBC;

`ifdef HAS_DEBUG_DATA
reg[9:0] bw_wait;      // Time waiting for block write to finish
`endif

reg[11:0] rxPktWords;  // Num of words in receive queue

reg[11:0] recvCnt;     // Counts number of received words
reg dataValid;
reg recvTransition;
reg recvWait;

reg curPacketValid;    // Whether current packet is valid (passed CRC check)

assign recv_word = recv_fifo_dout;

reg[11:0] sendCnt;     // Counts number of sent bytes
reg send_ipv4;         // 1 -> IPv4 packet being sent

reg[7:0] send_first_byte_in;   // for error checking

reg send_fifo_flush;   // 1 -> flush packet due to fifo overflow

reg[15:0] send_word_latched;
assign send_fifo_din = {send_word_latched[7:0], send_word_latched[15:8]};

assign send_info_din = { send_fifo_flush, 7'd0, send_first_byte_in, responseByteCount };

// Internal error (from RTL8211F) is sent back to host via ExtraData in EthernetIO.v
// Note that this includes recv_fifo_error and send_fifo_overflow because this module
// provides them to RTL8211F.
// Error bit provided to EthernetIO (reported back to PC in ExtraData)
assign ethInternalError = RxErr_1|recv_preamble_error_1;

`ifdef HAS_DEBUG_DATA
reg[15:0] timeSend;          // Time when send portion finished
reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[7:0]  numPacketFlushed;  // Number of received Ethernet frames flushed
reg[7:0]  numPacketSent;     // Number of packets sent to host PC
reg[7:0]  recvFlushCnt;      // Number of words flushed
`endif

// sendCtrl==100 when sending not active
reg[2:0] sendCtrl = 3'b100;
assign sendReady = sendCtrl[0];
wire sendValid;
assign sendValid = sendCtrl[1];
wire sendIncr;
assign sendIncr = sendCtrl[2];

reg recv_fifo_error;       // First byte in recv_fifo not as expected
reg send_fifo_overflow;    // Overflow (send_fifo was full)

reg[7:0] recv_first_byte_out;
`ifdef HAS_DEBUG_DATA
reg[7:0] recv_first_byte;
reg[7:0] recv_fifo_error_cnt;
`endif

// ----------------------------------------------------------------------------
// Ethernet state machine
//
// This is a simple state machine that does not take advantage of the fact that
// we can send and receive at the same time. In practice, this is not an issue
// due to the use of a request-response communication protocol.
//
// This module lies between the low-level send and receive modules in RTL8211F
// and the high-level module in EthernetIO.v. The interface to the lower-level
// modules is via FIFOs (recv_fifo, recv_info_fifo, send_fifo, send_info_fifo).
// The interface to EthernetIO.v is via signals. Specifically, the receive or
// send process is initiated by asserting recvRequest or sendRequest, respectively.
// Each 16-bit word is received or sent by asserting recvReady or sendReady,
// respectively. The 16-bit interface between this module and EthernetIO is a
// legacy from the KSZ8851 interface used for FPGA V2.
// ----------------------------------------------------------------------------

localparam[2:0]
    ST_IDLE = 3'd0,
    ST_RECEIVE_WAIT = 3'd1,
    ST_RECEIVE = 3'd2,
    ST_SEND_WAIT = 3'd3,
    ST_SEND = 3'd4;

reg[2:0] state = ST_IDLE;

always @(posedge(clk))
begin

    // Clear recv_fifo_error and send_fifo_overflow for any ports that are in reset or for
    // which clearErrors is set.
    recv_fifo_error <= recv_fifo_error&(~(resetActive|clearErrors));
    send_fifo_overflow <= send_fifo_overflow&(~(resetActive|clearErrors));

`ifdef HAS_DEBUG_DATA
    if (clearErrors) begin
        recv_fifo_error_cnt <= 8'd0;
    end
`endif

    case (state)

    ST_IDLE:
    begin
        timeNow <= 16'd0;
        recvCnt <= 12'd0;
        sendCnt <= 12'd0;
        isForward <= 0;
        send_info_wr_en <= 1'b0;
        recv_rd_en <= 1'b0;
        if (bw_active) begin
`ifdef HAS_DEBUG_DATA
            bw_wait <= bw_wait + 10'd1;
`endif
        end
        else if (sendReq & (~send_fifo_full)) begin
            // forward packet from FireWire
            // Note: This will forward it via the currently active port.
            // To support simultaneous use of ports 0 and 1, it would be best
            // to encode the port number in the outgoing Firewire packet, as
            // long as it is reflected in the incoming response packet.
            // For example, one bit in the Firewire TL field could be used.
            isForward <= 1;
            sendRequest <= 1;
            state <= ST_SEND_WAIT;
        end
        else if (~recv_info_fifo_empty) begin
            // Number of words; following will also work for an odd number of bytes,
            // even though number of bytes should always be even.
            rxPktWords <= (recv_info_dout[11:0]+12'd1)>>1;
            recv_first_byte_out <= recv_info_dout[23:16];
            recv_info_rd_en <= 1'b1;
            recv_rd_en <= 1'b1;   // Get first word from FIFO
            curPacketValid <= ~recv_info_dout[`ETH_RECV_FLUSH_BIT];
            // Request EthernetIO to receive if packet valid (flush if not valid).
            recvRequest <= ~recv_info_dout[`ETH_RECV_FLUSH_BIT];
            recvReady <= 1'b0;
            dataValid <= 1'b0;
            recvTransition <= 1'b0;
            recvWait <= 1'b0;
            state <= recv_info_dout[`ETH_RECV_FLUSH_BIT] ? ST_RECEIVE : ST_RECEIVE_WAIT;
`ifdef HAS_DEBUG_DATA
            recvFlushCnt <= 8'd0;
            if (recv_info_dout[`ETH_RECV_FLUSH_BIT])
                numPacketFlushed <= numPacketFlushed + 8'd1;
            else
                numPacketValid <= numPacketValid + 16'd1;
`endif
        end
	end

    //******************* RECEIVE STATES ***********************

    ST_RECEIVE_WAIT:
    begin
        // Wait for recvRequest to be acknowledged
        timeNow <= timeNow + 16'd1;
        recv_rd_en <= 1'b0;
        if (recvBusy) begin
            recvRequest <= 1'b0;
            recvReady <= 1'b1;
            state <= ST_RECEIVE;
        end
    end

    ST_RECEIVE:
    begin
        timeNow <= timeNow + 16'd1;
        recv_info_rd_en <= 1'b0;
        // Normal packet processing occurs when recvBusy is 1, in which case we
        // cycle through 4 states: recvReady, dataValid, recvTransition and recvWait.
        // Note that only recvReady is sent to EthernetIO.
        // If recvBusy is 0, we just flush the data. In this case, recvRead is 0,
        // and dataValid and recvTransition are both 1.
        // Note that EthernetIO clears recvBusy in idle state, which it can enter one
        // clock cycle after recvTransition. This will happen for packets shorter
        // than the Ethernet minimum (64 bytes), which are padded to 64 bytes.
        recvReady <= recvBusy & recvWait;
        dataValid <= ~recvBusy | recvReady;        // 1 clock after recvReady
        recvTransition <= ~recvBusy | dataValid;   // 1 clock after dataValid
        recvWait <= recvTransition;
`ifdef HAS_DEBUG_DATA
        // Following counts number of words flushed in a valid packet
        if (~recvBusy & curPacketValid)
            recvFlushCnt <= recvFlushCnt + 8'd1;
`endif
        // Prepare to read next word from FIFO (when dataValid is 1)
        recv_rd_en <= (recvCnt == (rxPktWords-12'd1)) ? 1'b0 : dataValid;

        if (dataValid && (recvCnt == 12'd0)) begin
            recv_fifo_error <= (recv_word[15:8] == recv_first_byte_out) ? 1'b0 : 1'b1;
            // May not be easy to handle an error if it occurs
`ifdef HAS_DEBUG_DATA
            recv_first_byte <= recv_word[15:8];
            if (recv_word[15:8] != recv_first_byte_out)
                recv_fifo_error_cnt <= recv_fifo_error_cnt + 8'd1;
`endif
        end
        // Check for end of packet.
        if (recvTransition) begin
            if (recvCnt == (rxPktWords-12'd1)) begin
                sendRequest <= curPacketValid&responseRequired;
                timeReceive <= timeNow;
`ifdef HAS_DEBUG_DATA
                if (bw_active) bw_wait <= 10'd0;
`endif
                state <= (curPacketValid&responseRequired) ? ST_SEND_WAIT : ST_IDLE;
            end
            else begin
                recvCnt <= recvCnt + 12'd1;
            end
        end
    end

    //******************* SEND STATES ***********************

    ST_SEND_WAIT:
    begin
        // Wait for sendRequest to be acknowledged
        timeNow <= timeNow + 16'd1;
        if (sendBusy) begin
            sendRequest <= 1'b0;
            send_fifo_flush <= 1'b0;
            sendCtrl <= 3'b001;
            state <= ST_SEND;
        end
    end

    ST_SEND:
    begin
        timeNow <= timeNow + 16'd1;
        if (sendBusy) begin
            sendCtrl <= {sendCtrl[1:0], sendCtrl[2] };
            if (sendValid) begin
                send_wr_en <= ~(send_fifo_full|send_fifo_flush);
                send_word_latched <= send_word;
                if (send_fifo_full) begin
                    send_fifo_flush <= 1'b1;
                    send_fifo_overflow <= 1'b1;
                end
                if (sendCnt == `ETH_Frame_Begin)
                    send_first_byte_in <= send_word[7:0];
                else if (sendCnt == `ETH_Frame_Length)
                    send_ipv4 <= (send_word == 16'h0008) ? 1'b1 : 1'b0;
            end
            else begin
                send_wr_en <= 1'b0;
                if (sendIncr)
                    sendCnt <= sendCnt + 12'd2;  // Bytes
            end
        end
        else begin
            // All done
            // Compare sendCnt to responseByteCount
            sendCtrl <= 3'b100;
            send_wr_en <= 1'b0;
            last_sendCnt <= sendCnt;    // for debugging
            last_responseBC <= responseByteCount;  // for debugging
            send_info_wr_en <= 1'b1;
`ifdef HAS_DEBUG_DATA
            numPacketSent <= numPacketSent + 8'd1;
            timeSend <= timeNow;
`endif
            state <= ST_IDLE;
        end
    end

    default:
    begin
        // Could set an error flag
        state <= ST_IDLE;
    end

    endcase
end

// Registers for clk domain to synchronize signals from RxClk and TxClk
// domains (i.e., clock domain crossing). Note that the recommended practice
// is to use two consecutive flip-flops, but we use just one here because
// the other occurs when reg_rdata is latched.

reg RxErr_1;
reg recv_preamble_error_1;

// Synchronize signals with clk
always @(posedge clk)
begin
    RxErr_1 <= RxErr;
    recv_preamble_error_1 <= recv_preamble_error;

`ifdef HAS_DEBUG_DATA
    recv_fifo_reset_1 <= recv_fifo_reset;
    recv_fifo_full_1 <= recv_fifo_full;
    tx_underflow_1 <= tx_underflow;
    send_fifo_empty_1 <= send_fifo_empty;
    send_fifo_error_1 <= send_fifo_error;
    recv_ipv4_1 <= recv_ipv4;
    recv_ipv4_err_1 <= recv_ipv4_err;
    recv_udp_1 <= recv_udp;
    isUnicast_1 <= isUnicast;
    isMulticast_1 <= isMulticast;
    isBroadcast_1 <= isBroadcast;
    txStateError_1 <= txStateError;
    rxStateError_1 <= rxStateError;
    txState_1 <= txState;
    rxState_1 <= rxState;
    recv_crc_in_1 <= recv_crc_in;
    numRxDropped_1 <= numRxDropped;
    send_first_byte_out_1 <= send_first_byte_out;
    numTxSent_1 <= numTxSent;
    send_crc_in_1 <= send_crc_in;
`endif
end

`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:7];
assign DebugData[0] = "2GBD";  // DBG2 byte-swapped
assign DebugData[1] = { curPort, curPacketValid, sendRequest, send_ipv4,    // 31:28
                        send_fifo_overflow, 1'b0, recv_fifo_error, 1'b0,    // 27:24
                        24'd0 };
assign DebugData[2] = { recv_first_byte, recv_first_byte_out, 4'd0, rxPktWords };   // 8, 8, 12
assign DebugData[3] = { numPacketSent, numPacketFlushed, numPacketValid };  // 8, 8, 16
assign DebugData[4] = { 6'd0, bw_wait, 4'd0, last_responseBC };
assign DebugData[5] = { timeSend, timeReceive };
assign DebugData[6] = { recv_fifo_error_cnt, recvFlushCnt, 4'd0, last_sendCnt };
assign DebugData[7] = 32'd0;
`endif

// -----------------------------------------------
// Debug data
// -----------------------------------------------

`ifdef HAS_DEBUG_DATA
wire[31:0] DebugDataRTL[0:7];
assign DebugDataRTL[0] = "2GBD";  // DBG2 byte-swapped
assign DebugDataRTL[1] = { RxErr_1, recv_preamble_error_1, recv_fifo_reset_1, recv_fifo_full_1,   // 31:28
                        recv_fifo_empty, recv_info_fifo_empty, 2'd0,                      // 27:24
                        1'd0, tx_underflow_1, send_fifo_full, send_fifo_empty_1,          // 23:20
                        send_info_fifo_empty, 1'd0, send_fifo_error_1, recv_ipv4_1,       // 19:16
                        recv_ipv4_err_1, recv_udp_1, 1'd0, 1'd0,                          // 15:12
                        isUnicast_1, isMulticast_1, isBroadcast_1, 1'b1,                  // 11:8
                        txStateError_1, rxStateError_1, 6'd0 };
assign DebugDataRTL[2] = {   2'd0,       2'd0, 1'b0, state, 1'b0, txState_1, 1'b0, rxState_1, 8'd0, 8'd0 };
                        //      2,          2,               3            3,                3
assign DebugDataRTL[3] = recv_crc_in_1;
assign DebugDataRTL[4] = { numRxDropped_1, 8'd0, send_first_byte_out_1, numTxSent_1 };
assign DebugDataRTL[5] = send_crc_in_1;
assign DebugDataRTL[6] = 32'd0;
assign DebugDataRTL[7] = 32'd0;
`endif

// Following data is accessible via block read from address `ADDR_ETH (0x4000),
// where x is the Ethernet channel (1 or 2).
// Note that some data is provided by this module (EthSwitchRt) whereas most is provided
// by other modules (EthernetIO).
//    4x00 - 4x7f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4080 - 408f (16 quadlets)  EthernetIO Debug data
//    4090 - 4097 (8 quadlets)   Low-level (e.g., RTL8211F) Debug data
//    4098 - 409f (8 quadlets)   Low-level (e.g., EthSwitchRt) Debug data
//    4xa0        (1 quadlet)    MDIO feedback (data read from management interface)
//    4xa1 - 4xbf (31 quadlets)  Unused
//    4xc0 - 4xdf (32 quadlets)  PacketBuffer/ReplyBuffer (64 words)
//    4xe0 - 4xff (32 quadlets)  ReplyIndex (64 words)

`ifdef HAS_DEBUG_DATA
assign reg_rdata = (reg_raddr[7:3] == {4'h9, 1'b1}) ? DebugData[reg_raddr[2:0]] :
                   (reg_raddr[7:3] == {4'h9, 1'b0}) ? DebugDataRTL[reg_raddr[2:0]] : 32'd0;
`else
assign reg_rdata = 32'd0;
`endif

endmodule
