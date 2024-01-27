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
 * It provides a GMII interface to the Ethernet switch, with a few extra signals,
 * such as PortReady and DataReady, to limit the data flow.
 *
 * The higher-level module (EthernetIO) does not handle the Ethernet preamble, so
 * this module discards the preamble on incoming (received) packets and adds it
 * to outgoing (sent) packets. It also computes and sends the Ethernet FCS (CRC).
 *
 * Revision history
 *     02/13/23    Peter Kazanzides    Initial revision (code from RTL8211F.v)
 *     01/18/24    Peter Kazanzides    Created from EthSwitchRt.v
 */

`include "Constants.v"

module EthRtInterface
(
    input  wire clk,                  // input clock

    input  wire[15:0] reg_raddr,      // read address
    output wire[31:0] reg_rdata,      // register read data

    input wire clearErrors,           // Clear error flags

    output reg PortReady,          // 1 -> ready to receive input data
    output reg DataReady,          // 1 -> TxD is valid (in addition to TxEn)

    // GMII Interface
    output wire RxClk,             // Rx Clk
    input wire RxValid,            // Rx Valid
    input wire[7:0] RxD,           // Rx Data
    input wire RxErr,              // Rx Error

    output wire TxClk,             // Tx Clk
    output reg TxEn,               // Tx Enable
    output reg[7:0] TxD,           // Tx Data
    output wire TxErr,             // Tx Error

    input wire[3:0] PacketInfo,    // Information about packet received from switch

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
    output reg[15:0] recv_word,       // Word received via Ethernet
    // Ethernet send
    output reg sendRequest,           // Request EthernetIO to start providing data to be sent
    input wire sendBusy,              // From EthernetIO
    output reg sendReady,             // Request EthernetIO to provide next send_word
    input wire[15:0] send_word,       // Word to send via Ethernet (SDRegDWR for KSZ8851)
    // Timing measurements (does not include times for Ethernet switch)
    input wire[31:0] timestamp,       // Free running timestamp
    output reg[15:0] timeReceive,     // Time for receiving packet (not including Rx loop in RTL8211F)
    output wire[15:0] timeNow,        // Running time counting since receive started
    // Feedback bits
    input wire bw_active,             // Indicates that block write module is active
    output wire eth_InternalError     // Internal error (to EthernetIO)
);

assign RxClk = clk;
assign TxClk = clk;

assign TxErr = 1'b0;

// ----------------------------------------------------------------------------
// Ethernet receive
//
// Receives bytes via GMII interface.
//
// ----------------------------------------------------------------------------

localparam
    ST_RX_IDLE          = 2'd0,
    ST_RX_FRAME         = 2'd1,
    ST_RX_WAIT_SEND     = 2'd2;

reg[1:0] rxState = ST_RX_IDLE;

reg[1:0] waitCnt;

reg[11:0] recv_nbytes;    // Number of bytes received (not including preamble)

wire curPacketValid;      // Whether current packet is valid
assign curPacketValid = 1'b1;  // TODO

reg sendResponse;         // 1 -> Request EthernetIO to send response packet

reg recvNotReady;         // 1 -> EthernetIO not ready (error)

reg[31:0] recvStartTime;  // timestamp when receive started

wire[31:0] timeNow32;
assign timeNow32 = timestamp - recvStartTime;
// Compute 16-bit time difference, with saturation if more than 16 bits
assign timeNow = (timeNow32 & 32'hffff0000) ? 16'hffff : timeNow32[15:0];

`ifdef HAS_DEBUG_DATA
reg[7:0] numRecv;
`endif

always @(posedge clk)
begin

    if (clearErrors) begin
        recvNotReady <= 1'b0;
    end

    // Following state machine similar to one in EthSwitch.v
    case (rxState)

    ST_RX_IDLE:
    begin
        PortReady <= ~sendBusy;
        recvReady <= 1'b0;
        sendResponse <= 1'b0;
        if (RxValid) begin
            recvRequest <= 1'b1;
            if (~recvRequest)
                recvStartTime <= timestamp;
            // Currently, no error checking on preamble
            if (RxD == 8'hd5) begin
                recv_nbytes <= 12'd0;
                if (~recvBusy) recvNotReady <= 1'b1;
                rxState <= ST_RX_FRAME;
                // Leave PortReady set so that first byte
                // is read on next clock
`ifdef HAS_DEBUG_DATA
                numRecv <= numRecv + 8'd1;
`endif
            end
        end
    end

    ST_RX_FRAME:
    begin
        if (RxValid) begin
            recvRequest <= 1'b0;
            // If PortReady is 0, setting it to 1 will cause RxValid to be
            // asserted 2 clocks later (1 clock for PortReady to be set,
            // and 1 clock for FIFO to generate RxValid).
            // Note that EthernetIO sets recvBusy when it is processing the
            // packet, so if recvBusy is 0, it means we can flush the rest
            // of the packet.
            recv_nbytes <= recv_nbytes + 12'd1;
            if (~recv_nbytes[0]) begin   // even byte
                recv_word[15:8] <= RxD;
                PortReady <= ~recvBusy;
            end
            else begin                   // odd byte
                recv_word[7:0] <= RxD;
                waitCnt <= recvBusy ? 2'd3 : 2'd0;
                recvReady <= recvBusy;
            end
        end
        else begin
            recvReady <= 1'b0;
            waitCnt <= waitCnt - 2'd1;
            if (waitCnt == 2'd2)
                PortReady <= 1'b1;
            else if (waitCnt == 2'd0) begin
                // If we get here, it means that the packet is finished
                // (i.e., RxValid was not asserted 2 clocks after PortReady).
                // If an odd number of bytes, pad with 0 and set recvReady
                // so that EthernetIO processes last byte.
                // We do not have to worry about the next packet starting
                // right away due to the 12-byte interpacket gap (IPG).
                if (recv_nbytes[0]) begin
                    recv_word[7:0] <= 8'd0;
                    recvReady <= recvBusy;
                end
                if (curPacketValid & responseRequired) begin
                    timeReceive <= timeNow;
                    // Don't accept new packets until send completed
                    PortReady <= 1'b0;
                    sendResponse <= ~sendBusy;
                    rxState <= ST_RX_WAIT_SEND;
                end
                else begin
                    rxState <= ST_RX_IDLE;
                end
            end
        end
    end

    ST_RX_WAIT_SEND:
    begin
        // This state is entered with either sendResponse=1 or sendBusy=1.
        // In the first case, it waits until sendBusy is set.
        // In the second case, it waits until sendBusy is cleared, then
        // sets sendResponse and waits for sendBusy to be set again.
        // Note that sendResponse is cleared in ST_RX_IDLE.
        if (sendResponse) begin
            if (sendBusy)
                rxState <= ST_RX_IDLE;
        end
        else if (~sendBusy) begin
            sendResponse <= 1'b1;
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

reg[2:0] txState = ST_TX_IDLE;

reg[7:0] send_word_msb;

// crc registers
wire[7:0] send_crc_data;    // data into crc module to compute crc on
reg[31:0] send_crc_in;      // input to crc module (starts at all ones)
wire[31:0] send_crc_2b;     // current crc module output for data width 2 (not used)
wire[31:0] send_crc_4b;     // current crc module output for data width 4 (not used)
wire[31:0] send_crc_8b;     // current crc module output for data width 8

// This module computes crc continuously, so it is up to the state machine to
// initialize, feed back, and latch crc values as necessary
crc32 send_crc(send_crc_data, send_crc_in, send_crc_2b, send_crc_4b, send_crc_8b);

reg[15:0] send_cnt;     // Counts number of bytes sent (not including preamble or CRC)
reg[5:0]  padding_cnt;  // Counter used to ensure minimum Ethernet frame size (64)
reg[2:0]  tx_cnt;       // Counter used for preamble and crc

reg txStateError;       // Invalid state

// Reverse bits for computing CRC
wire[7:0] TxMsbRev = { send_word_msb[0], send_word_msb[1], send_word_msb[2], send_word_msb[3],
                       send_word_msb[4], send_word_msb[5], send_word_msb[6], send_word_msb[7] };
wire[7:0] TxLsbRev = { send_word[0], send_word[1], send_word[2], send_word[3],
                       send_word[4], send_word[5], send_word[6], send_word[7] };

assign send_crc_data = (txState != ST_TX_SEND) ? 8'd0 :
                       (~send_cnt[0]) ? TxLsbRev : TxMsbRev;

`ifdef HAS_DEBUG_DATA
reg[15:0] timeSend;          // Time when send portion finished
reg[7:0]  numSent;           // Number of packets sent to host PC
`endif

always @(posedge TxClk)
begin

    case (txState)

    ST_TX_IDLE:
    begin
        send_cnt <= 16'd0;
        tx_cnt <= 3'd0;
        TxEn <= 1'b0;
        sendReady <= 1'b0;
        DataReady <= 1'b1;
        if (clearErrors) begin
            txStateError <= 1'b0;
        end
        if (sendReq) begin
            // Request to send from Firewire
            isForward <= 1;
            sendRequest <= 1'b1;
            txState <= ST_TX_PREAMBLE;
        end
        else if (sendResponse) begin
            // Request to send response packet
            isForward <= 0;
            sendRequest <= 1'b1;
            txState <= ST_TX_PREAMBLE;
        end
    end

    ST_TX_PREAMBLE:
    begin
        TxEn <= 1'b1;
        if (tx_cnt == 3'd7) begin
            // Assume that sendBusy is set by now, so clear sendRequest
            sendRequest <= 1'b0;
            sendReady <= 1'b0;
            txState <= ST_TX_SEND;
            send_crc_in <= 32'hffffffff;    // Initialize CRC
            padding_cnt <= 6'd59;           // Minimum frame size is 64 (-4 for CRC)
            TxD <= 8'hd5;
        end
        else begin
            if (tx_cnt == 3'd6)
                sendReady <= 1'b1;
            tx_cnt <= tx_cnt + 3'd1;
            TxD <= 8'h55;
        end
    end

    ST_TX_SEND:
    begin
        if (~send_cnt[0]) begin
            send_word_msb <= send_word[15:8];
            TxD <= send_word[7:0];    // even byte
        end
        else begin
            TxD <= send_word_msb;      // odd byte
        end
        send_crc_in <= send_crc_8b;
        sendReady <= ~send_cnt[0];
        send_cnt <= send_cnt + 16'd1;
        if (padding_cnt != 6'd0)
            padding_cnt <= padding_cnt - 6'd1;
        if (send_cnt == responseByteCount-16'd1) begin
            tx_cnt <= 3'd0;
            txState <= (padding_cnt == 6'd0) ? ST_TX_CRC : ST_TX_PADDING;
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
            timeSend <= timeNow;
            txState <= ST_TX_IDLE;
`ifdef HAS_DEBUG_DATA
            numSent <= numSent + 8'd1;
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

// Error bit provided to EthernetIO (reported back to PC in ExtraData)
assign eth_InternalError = recvNotReady | txStateError;

`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:3];
assign DebugData[0] = "3GBD";   // DBG3 byte-swapped
assign DebugData[1] = { sendBusy, sendRequest, rxState,                // 31:28
                        1'd0, recvNotReady, recvReady, PortReady,      // 27:24
                        numRecv, 4'd0, recv_nbytes};
assign DebugData[2] = { responseByteCount, 3'd0, txStateError, responseRequired, txState, numSent };
assign DebugData[3] = { timeSend, timeReceive };

assign reg_rdata = (reg_raddr[7:4] == 4'ha) ? DebugData[reg_raddr[1:0]] : 32'd0;
`else
assign reg_rdata = 32'd0;
`endif

endmodule
