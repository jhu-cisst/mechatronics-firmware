/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 Johns Hopkins University.
 *
 * This module handles the PS EMIO bus interface.
 *
 * Basic operation is as follows:
 *
 *   Quadlet Read:
 *       1) Write 16-bit address (reg_addr)
 *       2) Assert req_bus
 *       3) Wait for op_done
 *       4) Read 32-bit data (reg_data)
 *       5) Deassert req_bus
 *
 *   Quadlet Write:
 *       1) Write address (reg_addr) and data (reg_data)
 *       2) Assert req_bus
 *       3) Wait for op_done
 *       4) Deassert req_bus
 *
 *   Block Read: (NOTE 1)
 *       1) Write 16-bit address (reg_addr)
 *       2) Assert req_bus and blk_start
 *       3) Wait for op_done
 *       4) Read data (reg_data)
 *       5) Repeat above until last quadlet (assert blk_end for last quadlet)
 *       6) Deassert req_bus
 *
 *   Block Write: (NOTE 2)
 *       1) Write address (reg_addr) and data (reg_data)
 *       2) Assert req_bus and blk_start
 *       3) Wait for op_done
 *       4) Repeat above until last quadlet (assert blk_end for last quadlet)
 *       5) Deassert req_bus
 *
 *   NOTES:
 *       1) For block read, PS must assert blk_start for all quadlets, except the last.
 *          For last quadlet, PS should deassert blk_start and/or assert blk_end.
 *       2) For block write, PS is only required to assert blk_start for first quadlet,
 *          but it can optionally be asserted for all remaining quadlets. PS must assert
 *          blk_end with last quadlet.
 *
 * Revision history
 *
 *     12/12/23     Peter Kazanzides    Initial revision
 */

module EmioBus
(
    input wire        sysclk,           // system clock
    input wire[3:0]   board_id,

    output wire[63:0] emio_ps_in,       // EMIO input to PS
    input  wire[63:0] emio_ps_out,      // EMIO output from PS
    input  wire[63:0] emio_ps_tri,      // EMIO tristate from PS (1 -> input to PS, 0 -> output from PS)

    output wire[15:0] reg_raddr,
    input  wire[31:0] reg_rdata,
    input  wire       reg_rvalid,       // reg_rdata should be valid
    output reg        req_read_bus,     // request read bus (sysclk domain)
    input  wire       grant_read_bus,   // read bus granted
    output wire[15:0] reg_waddr,
    output reg[31:0]  reg_wdata,
    output wire       reg_wen_out,
    output reg        blk_wen,
    output reg        blk_wstart,
    output reg        req_blk_rt_rd,    // request to start real-time block read
    output reg        blk_rt_rd,        // real-time block read
    output reg        blk_rt_wr,        // real-time block write
    output reg        req_write_bus,    // request write bus (sysclk domain)
    input  wire       grant_write_bus,  // write bus granted

    input wire[31:0]  timestamp         // external timestamp
);

// For local use
reg[15:0] reg_addr;         // Either the read or write address
reg reg_wen;
reg reg_rvalid_latched;

assign reg_raddr = reg_addr;

reg[31:0]  reg_rdata_latched;
wire[15:0] ps_reg_addr;
wire[31:0] ps_reg_wdata;
wire ps_req_bus;

// Following are not synchronized with sysclk, but should be stable
// since they are not used until the read or write bus is granted
// (some are synchronized with sysclk below).
assign ps_reg_wdata = emio_ps_out[31:0]; // emio[31:0]
assign ps_reg_addr = emio_ps_out[47:32]; // emio[47:32]
assign ps_req_bus = emio_ps_out[48];     // emio[48]
assign ps_reg_wen = emio_ps_out[50];     // emio[50] (not used)
assign ps_blk_start = emio_ps_out[51];   // emio[51]
assign ps_blk_end = emio_ps_out[52];     // emio[52]

// Following are synchronized with sysclk
reg[15:0] ps_reg_addr_latched;
reg ps_blk_start_latched;
reg ps_blk_end_latched;

wire ps_op_done;                         // emio[49]
wire ps_write;                           // emio[53]

reg  reg_op_done;

// There are three address registers:
//   ps_reg_addr          output from PS (not sync with sysclk)
//   ps_reg_addr_latched  latched version of ps_reg_addr
//   reg_addr             latched version of ps_reg_addr_latched, used externally
//
// Note that this module drives both the read and write address register (reg_raddr and
// reg_waddr), which is fine since reading and writing never occur at the same time.
//
// For block read or write, we need to detect when the address has incremented.
//
// When masking ps_op_done, we need all addresses to be equal (see addr_same below).

wire ps_addr_equal;
wire reg_addr_equal;
wire reg_addr_incr;
assign ps_addr_equal = (ps_reg_addr == ps_reg_addr_latched) ? 1'b1 : 1'b0;
assign reg_addr_equal = (ps_reg_addr_latched == reg_addr) ? 1'b1 : 1'b0;
assign reg_addr_incr = (ps_reg_addr_latched == (reg_addr+16'd1)) ? 1'b1 : 1'b0;

wire addr_next;
// Could also check ps_addr_equal, but not necessary
assign addr_next = reg_addr_incr;

wire addr_same;
assign addr_same =  reg_addr_equal & ps_addr_equal;

assign ps_op_done = reg_op_done & addr_same;

// It is a write when no data lines are tristate; otherwise, we assume a read
assign ps_write = (emio_ps_tri[31:0] == 32'd0) ? 1'b1 : 1'b0;

assign emio_ps_in = {4'd1,                                            // Version 1
                     5'd0,                                            // Unused
                     (ps_write ? grant_write_bus : grant_read_bus),   // [54]
                     ps_write,                                        // [53]
                     ps_blk_end, ps_blk_start, ps_reg_wen,            // [52:50]
                     ps_op_done,                                      // [49]
                     ps_req_bus, ps_reg_addr,                         // [48] [47:32]
                     (ps_write ? ps_reg_wdata : reg_rdata_latched) }; // [31:0]

//*********************** Write Address Translation *******************************
//
// Write bus address translation (to support real-time block write).

wire board_equal;
assign board_equal = (reg_wdata[11:8] == board_id) ? 1'b1 : 1'b0;

WriteAddressTranslation PsWriteAddr
(
    .sysclk(sysclk),
    .reg_waddr_in(reg_addr[7:0]),
    .reg_wen_in(reg_wen),
    .reg_waddr_out(reg_waddr[7:0]),
    .reg_wen_out(reg_wen_out),
    .blk_rt_wr(blk_rt_wr),
    .reg_wdata_lsb(reg_wdata[7:0]),
    .board_equal(board_equal)
);

assign reg_waddr[15:8] = reg_addr[15:8];

//*************************** PS EMIO Read/Write ************************************

localparam[2:0]
   ST_IDLE = 3'd0,
   ST_READ = 3'd1,
   ST_WRITE_QUAD = 3'd2,
   ST_WRITE_BLOCK_START = 3'd3,
   ST_WRITE_BLOCK_DATA = 3'd4,
   ST_WRITE_FINISH = 3'd5;

reg[2:0] state;
initial state = ST_IDLE;

// For synchronizing ps_req_bus with sysclk and generating triggers
// on the rising and falling edges.
reg ps_req_bus_1;
reg ps_req_bus_2;

reg req_read_bus_next;
reg reg_wen_next;
reg reg_op_done_next;

reg[1:0] blk_cnt;         // for block write timing
reg first_quad;           // first quadlet

wire addrMain;
assign addrMain = (ps_reg_addr_latched[15:12] == `ADDR_MAIN) ? 1'b1 : 1'b0;

wire addrHubReg;
assign addrHubReg = (ps_reg_addr_latched == {`ADDR_HUB, 12'h800 }) ? 1'b1 : 1'b0;

wire timestamp_rd;
assign timestamp_rd = (blk_rt_rd && (reg_addr[7:0] == 8'd0)) ? 1'd1 : 1'd0;

// For reading the timestamp
reg[31:0] timestamp_latched;
reg[31:0] timestamp_prev;

always @(posedge sysclk)
begin
    // Synchronize ps_req_bus with sysclk
    ps_req_bus_1 <= ps_req_bus;
    ps_req_bus_2 <= ps_req_bus_1;

    // Synchronize read/write address with sysclk
    ps_reg_addr_latched <= ps_reg_addr;
    // Synchronize blk_start with sysclk
    ps_blk_start_latched <= ps_blk_start;
    // Synchronize blk_end with sysclk
    ps_blk_end_latched <= ps_blk_end;

    reg_rvalid_latched <= reg_rvalid;

    // req_blk_rt_rd is asserted for just one sysclk
    req_blk_rt_rd <= 1'b0;

    if ((~ps_req_bus_1) & ps_req_bus_2) begin
        // Falling edge of ps_req_bus causes system to transition to ST_IDLE,
        // which provides a way for the PS to abort a bus transfer.
        // Note that ST_READ and ST_WRITE_FINISH also rely on this state transition.
        state <= ST_IDLE;
    end

    case (state)

    ST_IDLE:
    begin
        reg_op_done <= 1'b0;
        reg_wen <= 1'b0;
        blk_wen <= 1'b0;
        blk_wstart <= 1'b0;
        blk_cnt <= 2'd0;
        // Wait for rising edge of ps_req_bus
        if (ps_req_bus_1 & (~ps_req_bus_2)) begin
            first_quad <= 1'b1;
            if ((~ps_write & ps_blk_start_latched & addrMain) ||
                (ps_write & addrHubReg)) begin
                // Set req_blk_rt_rd if real-time block read or
                // if write to Hub register 800
                req_blk_rt_rd <= 1'b1;
                timestamp_latched <= (timestamp-timestamp_prev)-32'd1;
                timestamp_prev <= timestamp;
            end
            if (~ps_write) begin
                // Request read bus on rising edge of ps_req_bus
                req_read_bus <= 1'b1;
                req_read_bus_next <= ps_blk_start_latched & (~ps_blk_end_latched);
                reg_addr <= ps_reg_addr_latched;
                blk_rt_rd <= ps_blk_start_latched & addrMain;
                state <= ST_READ;
            end
            else begin
                // Request write bus on rising edge of ps_req_bus
                req_write_bus <= 1'b1;
                reg_addr <= ps_reg_addr_latched;
                reg_wdata <= ps_reg_wdata;
                blk_rt_wr <= ps_blk_start_latched & addrMain;
                state <= ps_blk_start_latched ? ST_WRITE_BLOCK_START : ST_WRITE_QUAD;
            end
        end
        else begin
            // Relinquish control of any busses
            req_read_bus <= 1'b0;
            req_write_bus <= 1'b0;
        end
    end

    ST_READ:
    begin
        // Latch reg_rdata when we get the bus and data is valid
        if (req_read_bus & grant_read_bus) begin
            if (addr_next) begin
                // Latch next address (for block read)
                reg_addr <= ps_reg_addr_latched;
                reg_op_done <= 1'b0;
                req_read_bus_next <= ps_blk_start_latched & (~ps_blk_end_latched);
            end
            else if (reg_rvalid & reg_rvalid_latched) begin
                reg_rdata_latched <= timestamp_rd ? timestamp_latched : reg_rdata;
                reg_op_done <= 1'b1;
                req_read_bus <= req_read_bus_next;
            end
        end
        // Will stay in this state until falling edge of ps_req_bus
        // causes transition to ST_IDLE.
    end

    ST_WRITE_QUAD:
    begin
        if (req_write_bus & grant_write_bus) begin
            // reg_waddr (reg_addr) and reg_wdata already set
            reg_wen <= 1'b1;
            blk_wen <= 1'b1;
            state <= ST_WRITE_FINISH;
        end
    end

    ST_WRITE_BLOCK_START:
    begin
        if (req_write_bus & grant_write_bus) begin
            blk_wstart <= 1'b1;
            blk_cnt <= blk_cnt + 2'd1;
            // blk_cnt will be 2'd0 when this state exits
            if (blk_cnt == 2'd3)
                state <= ST_WRITE_BLOCK_DATA;
        end
        else begin
            // Reset block counter in case block write was interrupted
            // (i.e., by losing bus access)
            blk_cnt <= 3'd0;
        end
    end

    ST_WRITE_BLOCK_DATA:
    begin
        if (req_write_bus & grant_write_bus) begin
            blk_wstart <= 1'b0;
            if (first_quad) begin
                first_quad <= 1'b0;
                reg_wen <= 1'b1;
                reg_wen_next <= 1'b0;
                reg_op_done_next <= ~ps_blk_end_latched;
                blk_cnt <= 2'd1;
            end
            else if (addr_next) begin
                // New data available
                reg_addr <= ps_reg_addr_latched;
                reg_wdata <= ps_reg_wdata;
                reg_wen <= 1'b0;
                reg_wen_next <= 1'b1;
                reg_op_done <= 1'b0;
                reg_op_done_next <= ~ps_blk_end_latched;
                blk_cnt <= 2'd0;
            end
            else begin
                reg_wen <= reg_wen_next;
                reg_wen_next <= 1'b0;
                reg_op_done <= reg_op_done_next & (~reg_wen_next);
                blk_cnt <= blk_cnt + 2'd1;
                if ((blk_cnt == 2'd3) && ~reg_op_done_next) begin
                    blk_wen <= 1'b1;
                    state <= ST_WRITE_FINISH;
                end
            end
        end
        else begin
            // Reset block counter in case block write was interrupted
            // (i.e., by losing bus access)
            blk_cnt <= 3'd0;
        end
    end

    ST_WRITE_FINISH:
    begin
        reg_wen <= 1'b0;
        blk_wen <= 1'b0;
        req_write_bus <= 1'b0;
        reg_op_done <= 1'b1;
        // Will stay in this state until falling edge of ps_req_bus
        // causes transition to ST_IDLE.
    end

    endcase

end

endmodule
