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

    inout  MDIO,                   // Bidirectional I/O to RTL8211F
    output wire MDC,               // Clock to RTL8211F
    output wire RSTn,              // Reset to RTL8211F (active low)

    input wire RxClk,              // Rx Clk
    input wire RxValid,            // Rx Valid
    input wire[3:0] RxD            // Rx Data
);

assign RSTn = 1'b1;

reg MDIOreg;
assign MDIO = MDIOreg;

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

// Following data is accessible via block read from address `ADDR_ETH (0x4000)
//    4x00 - 4x7f (128 quadlets) Received packet (first 128 quadlets only)
//    4x80                       MDIO feedback (data read from management interface)
// where x is the Ethernet channel (1 or 2)

assign reg_rdata = (reg_raddr[7] == 1'b1) ? { 5'd0, state, 3'd0, read_reg_addr, read_data}
                                          : reg_rdata_mem;

// Whether a read command
wire isRead;
assign isRead = (write_data[29:28] == 2'b10) ? 1'b1 : 1'b0;

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
            MDIOreg <= 1'bz;
            cnt <= 9'd0;
            if (reg_wen && (reg_waddr[6:0] == 7'd0)) begin
                write_data <= reg_wdata;
                MDIOreg <= 1'b1;
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
                MDIOreg <= write_data[~cnt[8:4]];
            end
            if (isRead && (cnt == {5'd13, 4'hf}))
                state <= ST_READ_TA;
            else if (cnt == {5'd31, 4'hf})
                state <= ST_IDLE;
        end

    ST_READ_TA:
        begin
            if (cnt[3:0] == `WRITE_SETUP)
                MDIOreg <= 1'bz;
            if (cnt == {5'd15, 4'hf}) begin
                read_reg_addr <= write_data[22:18];
                state <= ST_READ_DATA;
            end
        end

    ST_READ_DATA:
        begin
            if (cnt[3:0] == `READ_READY)
                read_data <= {read_data[14:0], MDIO};
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

reg  recv_fifo_reset;
reg  recv_wr_en;
reg  recv_rd_en;
wire recv_fifo_full;
wire recv_fifo_empty;
reg[7:0] recv_byte;
wire[15:0] fifo_dout;
reg[15:0] fifo_latched;

fifo_8x1024_16 recv_fifo(
    .rst(recv_fifo_reset),
    .wr_clk(RxClk),
    .rd_clk(clk),
    .din(recv_byte),
    .wr_en(recv_wr_en),
    .rd_en(recv_rd_en),
    .dout(fifo_dout),
    .full(recv_fifo_full),
    .empty(recv_fifo_empty)
);

assign reg_rdata_mem = { 5'd0, recv_fifo_reset, recv_fifo_full, recv_fifo_empty, recv_byte, fifo_latched };

always @(posedge RxClk)
begin
    if (RxValid) begin
        recv_byte[3:0] <= RxD;
    end
end

always @(negedge RxClk)
begin
    recv_wr_en <= 1'b0;
    if (RxValid) begin
        recv_byte[7:4] <= RxD;
        recv_wr_en <= ~recv_fifo_full;
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
            recv_rd_en <= 1'b1;
            fifo_latched <= fifo_dout;
        end
    end
end

endmodule
