/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023-2024 Johns Hopkins University.
 *
 * Module: EthRtInterface
 *
 * Purpose: Interface to real-time Ethernet implementation on FPGA
 *
 * This module lies between the 4-port Ethernet switch (EthSwitch.v) and the
 * high-level Ethernet interface (EthernetIO.v) for FPGA V3.
 *
 * Revision history
 *     02/13/23    Peter Kazanzides    Initial revision (code from RTL8211F.v)
 *     01/18/24    Peter Kazanzides    Created from EthSwitchRt.v
 */

`include "Constants.v"

module EthRtInterface
(
    input  wire clk,                  // input clock
    input  wire[3:0] board_id,        // board id

    input  wire[15:0] reg_raddr,      // read address
    output wire[31:0] reg_rdata,      // register read data

    input wire resetActive,
    input wire clearErrors,           // Clear error flags

    output wire PortReady,         // 1 -> ready to receive input data

    // GMII Interface
    output wire RxClk,             // Rx Clk
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
    output wire recvReady,            // Indicates that recv_word is valid
    output reg[15:0] recv_word,       // Word received via Ethernet (`SDSwapped for KSZ8851)
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

//**************** TEMP ***********************

assign TxErr = 1'b0;

// Error bit provided to EthernetIO (reported back to PC in ExtraData)
assign ethInternalError = 1'b0;

// ----------------------------------------------------------------------------
// Ethernet low-level interface

// ----------------------------------------------------------------------------
// Ethernet receive
//
// Receives bytes via GMII interface.
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
// Note that recv_fifo takes 8-bit bytes as input and provides 16-bit words as
// output. The use of 16-bit words enables easier integration with the higher-level
// code in EthernetIO.v, which was initially implemented to interface to the
// 16-bit FIFO provided by the KSZ8851.
// ----------------------------------------------------------------------------

localparam
    ST_RX_IDLE          = 1'd0,
    ST_RX_FRAME         = 1'd1;

reg rxState;

reg[11:0] recv_nbytes;    // Number of bytes received (not including preamble)

// First 16 bytes of Ethernet frame
reg[7:0] frame_header[0:15];

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

`ifdef HAS_DEBUG_DATA
reg[7:0] numRxDropped;   // Number of irrelevant or erroneous packets dropped by Rx loop
`endif

assign RxClk = ~clk;

reg rxDone;

// For now, very slow
reg[4:0] rxCtrl = 5'b00001;
assign PortReady = rxCtrl[0];
assign recvReady = (rxState == ST_RX_FRAME) ? rxCtrl[1] : 1'b0;
wire recvTransition;
assign recvTransition = rxCtrl[4];

always @(posedge clk)
begin

    // Following state machine similar to one in EthSwitch.v
    case (rxState)

    ST_RX_IDLE:
    begin
        rxDone <= 1'b0;
        rxCtrl <= 5'b00001;
        if (RxValid) begin
            recvRequest <= 1'b1;
            // Currently, no error checking on preamble
            recv_nbytes <= 12'd0;
            if (RxD == 8'hd5) begin
                rxCtrl <= 5'b00010;
                rxState <= ST_RX_FRAME;
            end
        end
    end

    ST_RX_FRAME:
    begin
        recvRequest <= 1'b0;
        rxCtrl <= { rxCtrl[3:0], rxCtrl[4] };
        if (recvReady) begin
            if (RxValid) begin
                if (recv_nbytes[0])
                    recv_word[7:0] <= RxD;
                else
                    recv_word[15:8] <= RxD;

                if (recv_nbytes[11:4] == 8'd0) begin
                    // Save first 16 bytes (Ethernet header is 14 bytes)
                    frame_header[recv_nbytes[3:0]] <= RxD;
                end
            end
            else begin
                // End of packet
                // If an odd number of bytes, pad with 0
                if (recv_nbytes[0]) begin
                    recv_word[7:0] <= 8'd0;
                end
                rxDone <= 1'b1;
            end
        end

        if (recvTransition) begin
            recv_nbytes <= recv_nbytes + 12'd1;
            if (rxDone)
                rxState <= ST_RX_IDLE;
        end
    end

    endcase

end

// ----------------------------------------------------------------------------
// Ethernet send
//
// Receive words from EthernetIO and send bytes via GMII interface.
//
// Note that this module is responsible for computing and sending the CRC.
//
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

// Reverse bits for computing CRC
// TODO: Can we use TxD below?
wire[7:0] TxRev = { TxD[0], TxD[1], TxD[2], TxD[3],
                    TxD[4], TxD[5], TxD[6], TxD[7] };

assign send_crc_data = (txState == ST_TX_SEND) ? TxRev : 8'd0;

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
        TxEn <= 1'b0;
        if (resetActive) begin
            txStateError <= 1'b0;
        end
        // TODO:  txState <= ST_TX_PREAMBLE;
    end

    ST_TX_PREAMBLE:
    begin
        if (tx_cnt == 3'd7) begin
            txState <= ST_TX_SEND;
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
        TxD <= 8'd0;  // TODO
        send_crc_in <= send_crc_8b;
        if (send_cnt == (send_nbytes-16'd1)) begin
            tx_cnt <= 3'd0;
            txState <= (padding_cnt == 6'd0) ? ST_TX_CRC : ST_TX_PADDING;
        end
        else begin
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

`ifdef IGNORE // HAS_DEBUG_DATA
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

`ifdef IGNORE // HAS_DEBUG_DATA
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

`ifdef 0 // HAS_DEBUG_DATA
assign reg_rdata = (reg_raddr[7:3] == {4'h9, 1'b1}) ? DebugData[reg_raddr[2:0]] :
                   (reg_raddr[7:3] == {4'h9, 1'b0}) ? DebugDataRTL[reg_raddr[2:0]] : 32'd0;
`else
assign reg_rdata = 32'd0;
`endif

endmodule
