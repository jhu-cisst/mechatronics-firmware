/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022-2023 Johns Hopkins University.
 *
 * Module: RTL8211F
 *
 * Purpose: Link layer interface to RTL8211F Ethernet PHY
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

module RTL8211F
    #(parameter[3:0] CHANNEL = 4'd1)
(
    input  wire clk,               // input clock
    input  wire[3:0] board_id,     // board id

    input  wire[15:0] reg_raddr,   // read address
    input  wire[15:0] reg_waddr,   // write address
    output wire[31:0] reg_rdata,   // register read data
    input  wire[31:0] reg_wdata,   // register write data 
    input  wire reg_wen,           // reg write enable
    input  wire reg_wen_ctrl,      // write enable to Ethernet control register

    output reg RSTn,               // Reset to RTL8211F (active low)
    input wire IRQn,               // Interrupt from RTL8211F (active low), FPGA V3.1+
    output reg resetActive,        // Indicates that reset is active

    // MDIO signals
    // When connecting directly to PHY, only need MDIO (inout) and
    // MDC, but when using GMII to RGMII core, it is necessary to
    // use MDIO_I, MDIO_O and MDIO_T instead of MDIO.
    output wire MDC,               // Clock to RTL8211F
    input wire MDIO_I,             // Input from PHY
    output reg MDIO_O,             // Output to PHY
    output reg MDIO_T,             // Tristate control
    output wire mdioBusy,          // 1 -> MDIO busy processing request

    // GMII Interface
    input wire RxClk,              // Rx Clk
    input wire RxValid,            // Rx Valid
    input wire[7:0] RxD,           // Rx Data
    input wire RxErr,              // Rx Error

    input wire TxClk,              // Tx Clk
    output reg TxEn,               // Tx Enable
    output reg[7:0] TxD,           // Tx Data
    output wire TxErr,             // Tx Error

    input wire[1:0] clock_speed,   // Detected clock speed (Rx)
    input wire[1:0] speed_mode,    // Speed mode (Tx)

    // Arbitration for Tx bus (PS may be using it)
    output reg tx_bus_req,         // Bus request
    input wire tx_bus_grant,       // Bus grant
    output reg ps_eth_enable,      // 1 -> Enable PS access to Ethernet

    // Feedback bits
    output wire ethInternalError,     // Error summary bit to EthernetIO
    output wire[7:0] eth_status,      // Ethernet status bits
    output reg hasIRQ,                // 1 -> PHY IRQn available (FPGA V3.1+)

    // Interface to EthSwitch
    output reg initOK,                // 1 -> Initialization successful

    output wire recv_fifo_empty,
    input wire recv_rd_en,
    output wire[15:0] recv_fifo_dout,
    output wire recv_info_fifo_empty,
    input wire recv_info_rd_en,
    output wire[31:0] recv_info_dout,
    input wire recv_fifo_error,       // Feedback from EthSwitchRt

    output wire send_fifo_full,
    input wire send_wr_en,
    input wire[15:0] send_fifo_din,
    output wire send_info_fifo_full,
    input wire send_info_wr_en,
    input wire[31:0] send_info_din,
    input wire send_fifo_overflow,    // Feedback from EthSwitchRt

    output reg clearErrors            // Clear error flags
);

initial RSTn = 1'b1;

initial MDIO_T = 1'b1;

initial ps_eth_enable = 1'b0;

assign TxErr = 1'b0;

// ----------------------------------------------------------------------------
// MDIO (management) interface

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

reg mdioRequest;         // 1 -> Request MDIO transaction (write_data was set)
assign mdioBusy = (mdioState == ST_MDIO_IDLE) ? 1'b0 : 1'b1;

// For MDIO requests from PC
reg mdioRequest_pending;
reg[31:0] write_data_pending;
reg[31:0] mdio_result;

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
            if (mdioRequest) begin
                // write_data already set by caller
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
        tx_bus_req <= 1'b0;
        TxEn <= 1'b0;
        if (resetActive) begin
            txStateError <= 1'b0;
        end
        else if (~send_info_fifo_empty) begin
            // If the MSB is set, we flush the packet, so we don't
            // need to request the bus
            tx_bus_req <= ~send_info_dout[31];
            tx_underflow <= 1'b0;
            send_nbytes <= send_info_dout[15:0];
            send_first_byte_out <= send_info_dout[23:16];
            if (tx_bus_grant|send_info_dout[31]) begin
                // Could clear tx_bus_req if desired
                send_info_rd_en <= 1'b1;
                txState <= ST_TX_PREAMBLE;
                // If the MSB is set, we flush the packet (TxEn=0)
                TxEn <= ~send_info_dout[31];
            end
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

// ----------------------------------------------------------------------------
// MDIO state machine
// ----------------------------------------------------------------------------

localparam[3:0]
    ST_IDLE = 4'd0,
    ST_RESET_ASSERT = 4'd1,         // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 4'd2,           // wait after bringing reset high -- at least 50 msec
    ST_RUN_PROGRAM_EXECUTE = 4'd3,
    ST_WAIT_MDIO_RESULT = 4'd4,
    ST_INIT_CHECK_CHIPID1 = 4'd5,
    ST_INIT_CHECK_CHIPID2 = 4'd6,
    ST_GET_PHYSR_DATA = 4'd7,
    ST_SET_GMII_SPEED = 4'd8;

reg[3:0] state = ST_RESET_ASSERT;

localparam[4:0]
        ADDR_BMCR = 5'd0,       // Basic Mode Control Register, page 0
        ADDR_PHYID1 = 5'd2,     // PHY Identifier Register 1, page 0
        ADDR_PHYID2 = 5'd3,     // PHY Identifier Register 2, page 0
        ADDR_INER = 5'd18,      // Interrupt Enable Register, page 0xa42
        ADDR_PHYSR = 5'd26,     // PHY Specific Status Register, page 0xa43
        ADDR_INSR = 5'd29,      // Interrupt Status Register, page 0xa43
        ADDR_PAGSR = 5'd31;     // Page Select Register, 0xa43

// Speed bits in BMCR (and GMII control register)
`define SPEED_LSB 13
`define SPEED_MSB  6

//***************************************************************************************
// Microcode for RTL8211F register access
//
// A simple microcode is defined to streamline access to the RTL8211F registers.
//
// The instruction length is 27 bits, defined as follows:
// | R/W (1) | Phy (5) | Reg (5) | Data (16) |
// |    26   |  25:21  |  20:16  |   15:0    |
//
// Bit 26      Write (0) or Read (1)
// Bits 25:21  PHY address (00001 for RTL8211F, 01000 for RGMII-to-GMII)
// Bits 20:16  Address of register to read or write
// Bits 15:0   Data to write to register; for Read commands, the 4 LSB indicate
//             the next state

`define READ_BIT 26
`define PHY_BITS 25:21
`define REG_BITS 20:16
`define PHY_REG_BITS 25:16
`define DATA_BITS 15:0
`define NEXT_BITS 3:0

localparam CMD_WRITE = 1'b0,        // Write to register
           CMD_READ  = 1'b1;        // Read from register

localparam[4:0] PHY_RTL  = 5'd1,    // PHY address for RTL8211F
                PHY_GMII = 5'd8;    // PHY address for GMII core

// Program for initialization (0-10) and IRQ handler (4-10)
reg[26:0] RunProgram[0:10];
reg[3:0] runPC;    // Program counter for RunProgram

localparam[3:0] PC_RESET_BEGIN = 4'd0,   // Program counter for starting reset handler
                PC_IRQ_BEGIN = 4'd4,     // Program counter for starting IRQ handler
                PC_END = 4'd10;          // End (also used for MDIO requests from PC)

initial begin
    // Read Chip ID1 (should be 001c)
    RunProgram[0] = {CMD_READ,  PHY_RTL, ADDR_PHYID1, 12'd0, ST_INIT_CHECK_CHIPID1};
    // Read Chip ID2 (should be c916)
    RunProgram[1] = {CMD_READ,  PHY_RTL, ADDR_PHYID2, 12'd0, ST_INIT_CHECK_CHIPID2};
    // Change page to 0xa42 to access INER
    RunProgram[2] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'h0a42};
    // Enable link change interrupt
    RunProgram[3] = {CMD_WRITE, PHY_RTL, ADDR_INER, 16'h0010};
    // Change page to 0xa43 to access INSR
    RunProgram[4] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'h0a43};
    // Read interrupt status register (clears interrupt)
    RunProgram[5] = {CMD_READ,  PHY_RTL, ADDR_INSR, 12'd0, ST_RUN_PROGRAM_EXECUTE};
    // Read PHYSR to get link status
    RunProgram[6] = {CMD_READ,  PHY_RTL, ADDR_PHYSR, 12'd0, ST_GET_PHYSR_DATA};
    // Change page to 0 to access BMCR (might not be necessary)
    RunProgram[7] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'd0};
    // Read BMCR to get speed bits, which are used to update RunProgram[9]
    // Note that speed bits are also available in PHYSR.
    RunProgram[8] = {CMD_READ,  PHY_RTL, ADDR_BMCR, 12'd0, ST_SET_GMII_SPEED};
    // Write speed bits to GMII core register 16 (ST_SET_GMII_SPEED updates the data field)
    RunProgram[9] = {CMD_WRITE, PHY_GMII, 5'd16, 16'd0};
    // Change page to 0xa42 since that is the default page (probably not necessary)
    RunProgram[10] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'h0a42};
end

`ifdef HAS_DEBUG_DATA
reg[15:0] debug_PhyId1;
reg[15:0] debug_PhyId2;
reg[23:0] debug_initCount;
`endif

reg[23:0] initCount;
reg resetRequest;            // 1 -> Request PHY reset
reg[7:0] numReset;           // Number of times reset called
reg[7:0] numIRQ;             // Number of times IRQ handler called

reg IRQn_latched;            // 1 -> IRQn synchronized with sysclk
reg IRQn_disable;            // 1 -> disable handling of IRQn
reg IRQ_sw;                  // 1 -> software-generated IRQ (active high)
reg IRQ_cs;                  // 1 -> IRQ generated by change in Rx clock_speed

// Following is to generate an interrupt (IRQ_cs) for FPGA V3.0,
// which does not have the hardware IRQn.
reg[1:0] clock_speed_latch1;
reg[1:0] clock_speed_latch2;

reg linkOK;                  // 1 -> link on
reg[1:0] linkSpeed;          // 00 -> 10Mbps, 01 -> 100 Mbps, 10 -> 1000 Mbps

// validChannel is used when the implementation only supports 2 channels
wire validChannel;
assign validChannel = ((CHANNEL == 4'd1) || (CHANNEL == 4'd2)) ? 1'b1 : 1'b0;

// Bit offset within status register (0 for Eth1, 8 for Eth2)
localparam BIT_OFFSET = 8*(CHANNEL-1);

always @(posedge(clk))
begin

    // Synchronize IRQn with clk
    IRQn_latched <= IRQn;

    // Generate IRQ_cs for boards without IRQ (~hasIRQ)
    clock_speed_latch1 <= clock_speed;
    clock_speed_latch2 <= clock_speed_latch1;
    if (clock_speed_latch1 != clock_speed_latch2) begin
        IRQ_cs <= initOK&(~hasIRQ);
    end

    // Write to Ethernet status register
    if (reg_wen_ctrl) begin
        // Ignore reset request if already in reset
        resetRequest <= validChannel&reg_wdata[26]&reg_wdata[BIT_OFFSET+7]&RSTn;
        IRQn_disable <= validChannel&reg_wdata[27]&reg_wdata[BIT_OFFSET+6];
        IRQ_sw <= validChannel&reg_wdata[28]&reg_wdata[BIT_OFFSET+5];
        clearErrors <= validChannel&reg_wdata[28]&reg_wdata[BIT_OFFSET+4];
        recv_fifo_reset_req <= validChannel&reg_wdata[28]&reg_wdata[BIT_OFFSET+2];
        send_fifo_reset <= validChannel&reg_wdata[28]&reg_wdata[BIT_OFFSET+1];
        ps_eth_enable <= validChannel&reg_wdata[25]&reg_wdata[BIT_OFFSET];
    end
    else begin
        clearErrors <= 0;
        recv_fifo_reset_req <= 0;
        send_fifo_reset <= 0;
    end

    // Request write to RTL8211F register via MDIO, address = 4xa0,
    // where x is channel number.
    // Store it as pending and handle it when in IDLE state.
    if (reg_wen && (reg_waddr[3:0] == 4'd0)) begin
        write_data_pending <= reg_wdata;
        mdioRequest_pending <= 1;
    end

    case (state)

    ST_IDLE:
    begin
        initCount <= 24'd0;
        if (resetRequest) begin
            state <= ST_RESET_ASSERT;
        end
        else if (mdioRequest_pending) begin
            // Allow MDIO write even if initOK is false (could be useful for debugging)
            write_data <= write_data_pending;
            mdioRequest <= 1'b1;
            state <= ST_WAIT_MDIO_RESULT;
            runPC <= PC_END;
        end
        else if (initOK) begin
            if (((~IRQn_latched)&(~IRQn_disable)) | IRQ_sw | IRQ_cs) begin
                // Link change interrupt: clear interrupt,then read speed bits from
                // RTL8211F BMCR register and write them to GMII control register.
                state <= ST_RUN_PROGRAM_EXECUTE;
                runPC <= PC_IRQ_BEGIN;
                numIRQ <= numIRQ + 8'd1;
            end
        end
    end

    //******************* RESET STATES ***********************
    ST_RESET_ASSERT:
    begin
        if (initCount == 24'd491520) begin  // 10 ms (49.152 MHz sysclk)
            state <= ST_RESET_WAIT;
            RSTn <= 1;   // Remove the reset
            resetRequest <= 1'b0;
            numReset <= numReset + 8'd1;
        end
        else begin
            RSTn <= 0;
            initOK <= 0;
            resetActive <= 1;
            initCount <= initCount + 24'd1;
        end
    end

    ST_RESET_WAIT:
    begin
        // Wait until IRQn is asserted (low). Experimentally, this
        // seems to take about 160 ms, so we have a timeout at
        // 0xFFFFFF (340 msec).
        if ((initCount == 24'hFFFFFF) || (~IRQn_latched)) begin
            hasIRQ <= ~IRQn_latched;
`ifdef HAS_DEBUG_DATA
            debug_initCount <= initCount;
`endif
            resetActive <= 0;
            state <= ST_RUN_PROGRAM_EXECUTE;
            runPC <= PC_RESET_BEGIN;
        end
        else begin
            initCount <= initCount + 21'd1;
        end
    end

    ST_RUN_PROGRAM_EXECUTE:
    begin
        write_data <= { 2'b01, RunProgram[runPC][`READ_BIT], ~RunProgram[runPC][`READ_BIT],
                        RunProgram[runPC][`PHY_REG_BITS], 2'b10,
                        RunProgram[runPC][`DATA_BITS] };
        mdioRequest <= 1'b1;
        state <= ST_WAIT_MDIO_RESULT;
    end

    ST_WAIT_MDIO_RESULT:
    begin
        if (mdioRequest&mdioBusy) begin
            mdioRequest <= 1'b0;
        end
        else if (~(mdioRequest|mdioBusy)) begin
            if (runPC == PC_END) begin
                state <= ST_IDLE;
                if (mdioRequest_pending) begin
                    mdio_result <= { 5'd0, mdioState, 3'd0, read_reg_addr, read_data};
                end
                mdioRequest_pending <= 1'b0;
                IRQ_sw <= 1'b0;
                IRQ_cs <= 1'b0;
            end
            else begin
                state <= RunProgram[runPC][`READ_BIT] ? RunProgram[runPC][`NEXT_BITS]
                         : ST_RUN_PROGRAM_EXECUTE;
                runPC <= runPC + 4'd1;
            end
        end
    end

    ST_INIT_CHECK_CHIPID1:
    begin
        // ChipID1 should be 001c; if not, go to IDLE
        state <= (read_data == 16'h001c) ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
`ifdef HAS_DEBUG_DATA
        debug_PhyId1 <= read_data;
`endif
    end

    ST_INIT_CHECK_CHIPID2:
    begin
        // ChipID2 should be c916; if not, go to IDLE
        state <= (read_data == 16'hc916) ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
        initOK <= (read_data == 16'hc916) ? 1'b1 : 1'b0;
`ifdef HAS_DEBUG_DATA
        debug_PhyId2 <= read_data;
`endif
    end

    ST_GET_PHYSR_DATA:
    begin
        linkOK <= read_data[2];
        linkSpeed <= read_data[5:4];
        state <= ST_RUN_PROGRAM_EXECUTE;
    end

    ST_SET_GMII_SPEED:
    begin
        RunProgram[runPC][`SPEED_LSB] <= read_data[`SPEED_LSB];
        RunProgram[runPC][`SPEED_MSB] <= read_data[`SPEED_MSB];
        state <= ST_RUN_PROGRAM_EXECUTE;
    end

    default:
    begin
        // Could note this as an error
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

// Error bit provided to EthernetIO (reported back to PC in ExtraData)
assign ethInternalError = RxErr_1|recv_preamble_error_1;

// Ethernet status bits for this port
assign eth_status = { initOK, hasIRQ, linkOK, linkSpeed, recv_fifo_error, send_fifo_overflow, ps_eth_enable };

// -----------------------------------------------
// Debug data
// -----------------------------------------------

`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:7];
assign DebugData[0] = "2GBD";  // DBG2 byte-swapped
assign DebugData[1] = { RxErr_1, recv_preamble_error_1, recv_fifo_reset_1, recv_fifo_full_1,   // 31:28
                        recv_fifo_empty, recv_info_fifo_empty, 2'd0,                      // 27:24
                        1'd0, tx_underflow_1, send_fifo_full, send_fifo_empty_1,          // 23:20
                        ~IRQn_latched, 1'd0, send_fifo_error_1, recv_ipv4_1,              // 19:16
                        recv_ipv4_err_1, recv_udp_1, 1'd0, hasIRQ,                        // 15:12
                        isUnicast_1, isMulticast_1, isBroadcast_1, initOK,                // 11:8
                        txStateError_1, rxStateError_1, 6'd0 };
assign DebugData[2] = {  speed_mode, clock_speed, state, 1'b0, txState_1, 1'b0, rxState_1, numIRQ, numReset };
                      //      2,          2,         4            3,            3
assign DebugData[3] = recv_crc_in_1;
assign DebugData[4] = { numRxDropped_1, 8'd0, send_first_byte_out_1, numTxSent_1 };
assign DebugData[5] = send_crc_in_1;
assign DebugData[6] = { debug_PhyId2, debug_PhyId1 };
assign DebugData[7] = { 8'd0, debug_initCount };
`endif

// Following data is accessible via block read from address `ADDR_ETH (0x4000),
// where x is the Ethernet channel (1 or 2).
// Note that some data is provided by this module (RTL8211F) whereas most is provided
// by other modules (EthernetIO and EthSwitchRt).
//    4x00 - 4x7f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4080 - 408f (16 quadlets)  EthernetIO Debug data
//    4090 - 4097 (8 quadlets)   Low-level (e.g., RTL8211F) Debug data
//    4098 - 409f (8 quadlets)   Low-level (e.g., EthSwitchRt) Debug data
//    4xa0        (1 quadlet)    MDIO feedback (data read from management interface)
//    4xa1 - 4xbf (31 quadlets)  Unused
//    4xc0 - 4xdf (32 quadlets)  PacketBuffer/ReplyBuffer (64 words)
//    4xe0 - 4xff (32 quadlets)  ReplyIndex (64 words)

assign reg_rdata = (reg_raddr[7:3] == {4'h9, 1'b0}) ?
`ifdef HAS_DEBUG_DATA
                                               DebugData[reg_raddr[2:0]] :
`else
                                               "0GBD" :
`endif
                   (reg_raddr[7:0] == 8'ha0) ? mdio_result : 32'd0;

endmodule
