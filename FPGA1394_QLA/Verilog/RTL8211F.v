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
    input wire RxErr               // Rx Error
);

assign RSTn = 1'b1;

// State machine
localparam [2:0]
    ST_IDLE = 0,
    ST_WRITE_PREAMBLE = 1,
    ST_WRITE_DATA = 2,
    ST_READ_TA = 3,
    ST_READ_DATA = 4;

reg[2:0] state;
initial  state = ST_IDLE;

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
// handled in separate states (ST_READ_TA and ST_READ_DATA).
reg[31:0] write_data;

// Following is the 16-bits of data read from the RTL8211F (read commands only)
reg[15:0] read_data;
// Register address for read
reg[4:0] read_reg_addr;

wire[31:0] reg_rdata_mem;   // Receive data
wire[31:0] recv_info_dout;
wire recv_info_fifo_empty;
reg[31:0] recv_crc_comp[0:3]; // computed crc of received frame
reg[31:0] recv_crc_frame;     // crc in received frame

// Following data is accessible via block read from address `ADDR_ETH (0x4000)
//    4x00 - 4x7f (128 quadlets) Received packet (first 128 quadlets only)
//    4x80                       MDIO feedback (data read from management interface)
//    4x81                       Receive info (if available)
// where x is the Ethernet channel (1 or 2)

assign reg_rdata = (reg_raddr[7] == 1'b0) ? reg_rdata_mem :
                   (reg_raddr[7:0] == 8'h80) ? { 5'd0, state, 3'd0, read_reg_addr, read_data} :
                   ((reg_raddr[7:0] == 8'h81) && (~recv_info_fifo_empty)) ? recv_info_dout :
                   (reg_raddr[7:0] == 8'h82) ? recv_crc_comp[0] :
                   (reg_raddr[7:0] == 8'h83) ? recv_crc_frame : 32'd0;

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

    if (state != ST_IDLE)
        cnt <= cnt + 9'd1;

    case (state)

    ST_IDLE:
        begin
            MDIO_T <= 1'b1;
            cnt <= 9'd0;
            if (reg_wen && (reg_waddr[6:0] == 7'd0)) begin
                write_data <= reg_wdata;
                MDIO_T <= 1'b0;
                MDIO_O <= 1'b1;
                state <= ST_WRITE_PREAMBLE;
            end
        end

    ST_WRITE_PREAMBLE:
        begin
            if (cnt == {5'd31, 4'hf})
                state <= ST_WRITE_DATA;
            // cnt == 9'd0 when moving to ST_WRITE_DATA
        end

    ST_WRITE_DATA:
        begin
            if (cnt[3:0] == `WRITE_SETUP) begin
                MDIO_O <= write_data[~cnt[8:4]];
            end
            if (isRead && (cnt == {5'd13, 4'hf}))
                state <= ST_READ_TA;
            else if (cnt == {5'd31, 4'hf})
                state <= ST_IDLE;
        end

    ST_READ_TA:
        begin
            if (cnt[3:0] == `WRITE_SETUP) begin
                MDIO_T <= 1'b1;
            end
            if (cnt == {5'd15, 4'hf}) begin
                read_reg_addr <= regAddr;
                state <= ST_READ_DATA;
            end
        end

    ST_READ_DATA:
        begin
            if (cnt[3:0] == `READ_READY)
                read_data <= {read_data[14:0], MDIO_I};
            if (cnt == {5'd31, 4'hf})
                state <= ST_IDLE;
        end

    default:
        // Could note this as an error
        state <= ST_IDLE;

    endcase // case (state)
end

// -----------------------------------------
// Ethernet receive
// ------------------------------------------

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
reg[15:0]  recv_fifo_latched;

reg[2:0]   preamble_cnt;
reg  preamble_done;
reg  preamble_error;

reg[15:0] recv_nbytes;  // Number of bytes received (not including preamble)

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

wire recv_crc_error;
assign recv_crc_error = (recv_crc_comp[0] == recv_crc_frame) ? 1'b0 : 1'b1;

assign recv_info_din = { 5'd0, recv_crc_error, RxErr, preamble_error, recv_first_byte, recv_nbytes };

assign reg_rdata_mem = { 3'd0, RxErr, preamble_error, recv_fifo_reset, recv_fifo_full, recv_fifo_empty,
                         8'd0, recv_fifo_latched };

always @(posedge RxClk)
begin
    recv_wr_en <= 1'b0;
    recv_info_wr_en <= 1'b0;
    if (RxValid) begin
        recv_byte <= RxD;
        if (~preamble_done) begin
            if (RxD == 8'h55) begin
                preamble_cnt <= preamble_cnt + 3'd1;
            end
            else begin
                preamble_done <= 1'b1;
                preamble_cnt <= 3'd0;
                recv_crc_in <= 32'hffffffff;    // Initialize CRC
                if ((RxD != 8'hd5) ||
                    (preamble_cnt != 3'd7)) begin
                    preamble_error <= 1'b1;
                end
            end
        end
        else begin
            if (recv_nbytes == 16'd0)
                recv_first_byte <= RxD;
            recv_nbytes <= recv_nbytes + 16'd1;
            recv_wr_en <= ~recv_fifo_full;
            recv_crc_in <= recv_crc_8b;
            // Frame CRC is last 32-bits (FCS)
            recv_crc_frame <= { recv_crc_frame[23:0], RxD };
            // The CRC should be computed on all bytes except the
            // CRC (last 4 bytes); thus we use recv_crc_comp[0].
            // Note that this code already skips last byte.
            recv_crc_comp[0] <= recv_crc_comp[1];
            recv_crc_comp[1] <= recv_crc_comp[2];
            recv_crc_comp[2] <= recv_crc_comp[3];
            recv_crc_comp[3] <= ~recv_crc_in;
        end
    end
    else begin
        preamble_done <= 1'b0;
        preamble_cnt <= 3'd0;
        if (recv_nbytes != 16'd0) begin
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
                recv_nbytes <= 16'd0;
                preamble_error <= 1'b0;
            end
        end
    end
end

reg[6:0] last_reg_raddr;
initial last_reg_raddr = 7'h3f;

always @(posedge(clk))
begin
    // Reset the FIFO by writing to 4x81, where x is channel number
    if (reg_wen && (reg_waddr[6:0] == 7'd1)) begin
       recv_fifo_reset <= 1'b1;
    end
    else begin
       recv_fifo_reset <= 1'b0;
    end

    // Assumes first word fall-through (FWFT) FIFO
    recv_rd_en <= 1'b0;
    if (reg_raddr[15:7] == {`ADDR_ETH, CHANNEL, 1'b0}) begin
        last_reg_raddr <= reg_raddr[6:0];
        if (last_reg_raddr != reg_raddr[6:0]) begin
            recv_rd_en <= ~recv_fifo_empty;
            recv_fifo_latched <= recv_fifo_empty ? 16'd0 : recv_fifo_dout;
        end
    end
end

endmodule
