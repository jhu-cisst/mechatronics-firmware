/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 Johns Hopkins University.
 *
 * Module: EthSwitchRt
 *
 * Purpose: Ethernet switch for real-time interface (to FPGA)
 *
 * Revision history
 *     02/13/23    Peter Kazanzides    Initial revision (code from RTL8211F.v)
 */

`include "Constants.v"

// Define following for debug data (DBG2)
`define HAS_DEBUG_DATA

module EthSwitchRt
    #(parameter NUM = 2)              // Number of Ethernet ports (PHYs)
(
    input  wire clk,                  // input clock

    input  wire[15:0] reg_raddr,      // read address
    output wire[31:0] reg_rdata,      // register read data

    // Interface to RTL8211F
    input wire[(NUM-1):0] initOK,

    input wire[(NUM-1):0] recv_fifo_empty,
    output reg[(NUM-1):0] recv_rd_en,
    input wire[(16*NUM-1):0] recv_fifo_dout_vec,
    input wire[(NUM-1):0] recv_info_fifo_empty,
    output reg[(NUM-1):0] recv_info_rd_en,
    input wire[(32*NUM-1):0] recv_info_dout_vec,

    input wire[(NUM-1):0] send_fifo_full,
    output reg[(NUM-1):0] send_wr_en,
    output wire[15:0] send_fifo_din,
    input wire[(NUM-1):0] send_info_fifo_full,
    output reg[(NUM-1):0] send_info_wr_en,
    output wire[31:0] send_info_din,

    input wire[(NUM-1):0] eth_InternalError_rt,

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
    input wire useUDP,                // Whether EthernetIO is using UDP
    output wire eth_InternalError     // Internal error (from RTL8211F)
);

wire[15:0] recv_fifo_dout[0:(NUM-1)];
wire[31:0] recv_info_dout[0:(NUM-1)];

genvar i;
generate 
for (i = 1; i <= NUM; i = i + 1) begin : gen_loop
    assign recv_fifo_dout[i-1] = recv_fifo_dout_vec[(16*i-1):(16*(i-1))];
    assign recv_info_dout[i-1] = recv_info_dout_vec[(16*i-1):(16*(i-1))];
end 
endgenerate

// The following registers maintain the currently active recv and send ports.
// Note that this implementation only handles NUM==2 (i.e., ports 0 and 1).
// It is not yet clear whether it is necessary to have separate send and recv
// registers.
reg curPortRecv;
initial curPortRecv = 1'd0;
reg curPortSend;
initial curPortSend = 1'd0;

reg[11:0] last_sendCnt;
reg[11:0] last_responseBC;

reg[11:0] rxPktWords;  // Num of words in receive queue

reg[11:0] recvCnt;     // Counts number of received words
reg dataValid;
reg recvTransition;
reg recvWait;

reg curPacketValid;    // Whether current packet is valid (passed CRC check)
reg recv_fifo_error;   // First byte in recv_fifo not as expected

assign recv_word = recv_fifo_dout[curPortRecv];

reg[11:0] sendCnt;     // Counts number of sent bytes
reg send_ipv4;         // 1 -> IPv4 packet being sent

reg send_fifo_overflow;  // Overflow (send_fifo was full)

reg[7:0] send_first_byte_in;   // for error checking

wire send_fifo_flush;
assign send_fifo_flush = send_fifo_overflow;

assign send_fifo_din = {send_word[7:0], send_word[15:8]};

assign send_info_din = { send_fifo_flush, 7'd0, send_first_byte_in, responseByteCount };

// Internal error (from RTL8211F) is sent back to host via ExtraData in EthernetIO.v
assign eth_InternalError = eth_InternalError_rt[curPortSend];

`ifdef HAS_DEBUG_DATA
reg[15:0] timeSend;          // Time when send portion finished
reg[15:0] numPacketValid;    // Number of valid Ethernet frames received
reg[7:0]  numPacketFlushed;  // Number of received Ethernet frames flushed
reg[7:0]  numPacketSent;     // Number of packets sent to host PC
`endif

// sendCtrl==100 when sending not active
reg[2:0] sendCtrl = 3'b100;
assign sendReady = sendCtrl[0];
wire sendValid;
assign sendValid = sendCtrl[1];
wire sendIncr;
assign sendIncr = sendCtrl[2];

reg[7:0] recv_first_byte_out;

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

    timeNow <= timeNow + 16'd1;

    case (state)

    ST_IDLE:
    begin
        recvCnt <= 12'd0;
        sendCnt <= 12'd0;
        isForward <= 0;
        send_info_wr_en <= 2'b00;
        if (initOK[curPortSend] & sendReq & (~send_fifo_full[curPortSend])) begin
            // forward packet from FireWire
            isForward <= 1;
            sendRequest <= 1;
            timeSend <= 16'd0;
            state <= ST_SEND_WAIT;
        end
        else if (initOK[curPortRecv] & (~recv_info_fifo_empty[curPortRecv])) begin
            rxPktWords <= ((recv_info_dout[curPortRecv][11:0]+12'd3)>>1)&12'hffe;
            recv_first_byte_out <= recv_info_dout[curPortRecv][23:16];
            recv_info_rd_en[curPortRecv] <= 1'b1;
            curPacketValid <= ~recv_info_dout[curPortRecv][`ETH_RECV_FLUSH_BIT];
            // Request EthernetIO to receive if packet valid (flush if not valid).
            recvRequest <= ~recv_info_dout[curPortRecv][`ETH_RECV_FLUSH_BIT];
            recvReady <= 1'b0;
            dataValid <= 1'b0;
            // If flushing packet, just stay in recvTransition state
            recvTransition <= recv_info_dout[curPortRecv][`ETH_RECV_FLUSH_BIT];
            recvWait <= 1'b0;
            timeNow <= 16'd0;
            state <= recv_info_dout[curPortRecv][`ETH_RECV_FLUSH_BIT] ? ST_RECEIVE : ST_RECEIVE_WAIT;
`ifdef HAS_DEBUG_DATA
            if (recv_info_dout[curPortRecv][`ETH_RECV_FLUSH_BIT])
                numPacketFlushed <= numPacketFlushed + 8'd1;
            else
                numPacketValid <= numPacketValid + 16'd1;
`endif
        end
        else if (initOK[~curPortRecv] & (~recv_info_fifo_empty[~curPortRecv])) begin
            // If the other port has data, we switch curPortRecv.
            // Note that this implementation only works for NUM==2.
            curPortRecv <= ~curPortRecv;
            curPortSend <= ~curPortRecv;   // TODO: remove this?
        end
	end

    //******************* RECEIVE STATES ***********************

    ST_RECEIVE_WAIT:
    begin
        // Wait for recvRequest to be acknowledged
        if (recvBusy) begin
            recvRequest <= 1'b0;
            recvReady <= 1'b1;
            state <= ST_RECEIVE;
        end
    end

    ST_RECEIVE:
    begin
        recv_info_rd_en <= 2'b00;
        if (curPacketValid) begin
            recvReady <= recvWait;
            dataValid <= recvReady;           // 1 clock after recvReady
            recvTransition <= dataValid;      // 1 clock after dataValid
            recvWait <= recvTransition;
        end
        recv_rd_en[curPortRecv] <= (dataValid|(~curPacketValid));
        if (dataValid && (recvCnt == 12'd0)) begin
            recv_fifo_error <= (recv_fifo_dout[curPortRecv][15:8] == recv_first_byte_out) ? 1'b0 : 1'b1;
            // May not be easy to handle an error if it occurs
        end
        if (recvTransition) begin
            if (recvCnt == rxPktWords) begin
                sendRequest <= curPacketValid&responseRequired;
                timeReceive <= timeNow;
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
        // curPortSend <= curPortRecv;   // TODO: restore this?
        if (sendBusy) begin
            sendRequest <= 1'b0;
            send_fifo_overflow <= 1'b0;
            sendCtrl <= 3'b001;
            state <= ST_SEND;
        end
    end

    ST_SEND:
    begin
        if (sendBusy) begin
            sendCtrl <= {sendCtrl[1:0], sendCtrl[2] };
            if (sendValid) begin
                send_wr_en[curPortSend] <= ~(send_fifo_full[curPortSend]|send_fifo_overflow);
                if (send_fifo_full[curPortSend])
                    send_fifo_overflow <= 1'b1;
                if (sendCnt == ETH_Frame_Begin)
                    send_first_byte_in <= send_word[7:0];
                else if (sendCnt == ETH_Frame_Length)
                    send_ipv4 <= (send_word == 16'h0008) ? 1'b1 : 1'b0;
            end
            else begin
                send_wr_en <= 2'b00;
                if (sendIncr)
                    sendCnt <= sendCnt + 12'd2;  // Bytes
            end
        end
        else begin
            // All done
            // Compare sendCnt to responseByteCount
            sendCtrl <= 3'b100;
            send_wr_en <= 2'b00;
            last_sendCnt <= sendCnt;    // for debugging
            last_responseBC <= responseByteCount;  // for debugging
            send_info_wr_en[curPortSend] <= 1'b1;
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

`ifdef HAS_DEBUG_DATA
wire[31:0] DebugData[0:7];
assign DebugData[0] = "2GBD";  // DBG2 byte-swapped
assign DebugData[1] = { curPortRecv, curPortSend, curPacketValid, sendRequest,    // 31:28
                        send_ipv4, send_fifo_overflow, recv_fifo_error, 1'd0,     // 27:24
                        24'd0 };
assign DebugData[2] = { 8'd0, recv_first_byte_out, 4'd0, rxPktWords };      // 8, 12
assign DebugData[3] = { numPacketSent, numPacketFlushed, numPacketValid };  // 8, 8, 16
assign DebugData[4] = { 4'd0, last_sendCnt, 4'd0, last_responseBC };
assign DebugData[5] = { timeSend, timeReceive };
assign DebugData[6] = 32'd0;
assign DebugData[7] = 32'd0;
`endif

// Following data is accessible via block read from address `ADDR_ETH (0x4000),
// where x is the Ethernet channel (1 or 2).
// Note that some data is provided by this module (EthSwitchRt) whereas most is provided
// by other modules (EthernetIO and RTL8211F).
//    4x00 - 4x7f (128 quadlets) FireWire packet (first 128 quadlets only)
//    4080 - 408f (16 quadlets)  EthernetIO Debug data
//    4090 - 4097 (8 quadlets)   Low-level (e.g., RTL8211F) Debug data
//    4098 - 409f (8 quadlets)   Low-level (e.g., EthSwitchRt) Debug data
//    4xa0        (1 quadlet)    MDIO feedback (data read from management interface)
//    4xa1 - 4xbf (31 quadlets)  Unused
//    4xc0 - 4xdf (32 quadlets)  PacketBuffer/ReplyBuffer (64 words)
//    4xe0 - 4xff (32 quadlets)  ReplyIndex (64 words)

`ifdef HAS_DEBUG_DATA
assign reg_rdata = (reg_raddr[7:3] == {4'h9, 1'b1}) ? DebugData[reg_raddr[2:0]] : 32'd0;
`else
assign reg_rdata = 32'd0;
`endif

endmodule
