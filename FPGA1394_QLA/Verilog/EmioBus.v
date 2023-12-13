/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 Johns Hopkins University.
 *
 * This module handles the PS EMIO bus interface.
 *
 * Revision history
 *
 *     12/12/23     Peter Kazanzides    Initial revision
 */

module EmioBus
(
    input wire        sysclk,           // system clock

    output wire[63:0] emio_ps_in,       // EMIO input to PS
    input  wire[63:0] emio_ps_out,      // EMIO output from PS
    input  wire[63:0] emio_ps_tri,      // EMIO tristate from PS (1 -> input to PS, 0 -> output from PS)

    output wire[15:0] reg_raddr,
    input  wire[31:0] reg_rdata,
    input  wire       reg_rvalid,       // reg_rdata should be valid
    output reg        req_read_bus,     // request read bus (sysclk domain)
    input  wire       grant_read_bus,   // read bus granted
    output wire[15:0] reg_waddr,
    output wire[31:0] reg_wdata,
    output wire       reg_wen,
    output wire       blk_wen,
    output wire       blk_wstart,
    output wire       req_blk_rt_rd,    // request to start real-time block read
    output wire       blk_rt_rd,        // real-time block read
    output reg        req_write_bus,    // request write bus (sysclk domain)
    input  wire       grant_write_bus   // write bus granted
);

reg[31:0] ps_reg_rdata;                 // emio[31:0]
wire[15:0] ps_reg_addr;
   
// Following are not synchronized with sysclk, but should be stable
// since they are not used until the read or write bus is granted.
assign ps_reg_addr = emio_ps_out[47:32]; // emio[47:32]
assign reg_raddr = ps_reg_addr;
assign reg_waddr = ps_reg_addr;
assign reg_wdata = emio_ps_out[31:0];    // emio[31:0]
assign reg_wen = emio_ps_out[50];        // emio[50]
assign blk_wstart = emio_ps_out[51];     // emio[51]
assign blk_wen = emio_ps_out[52];        // emio[52]

assign req_blk_rt_rd = 1'b0;    // TEMP
assign blk_rt_rd = 1'b0;        // TEMP

wire ps_req_bus;
assign ps_req_bus = emio_ps_out[48];     // emio[48]

reg  ps_read_done;                       // emio[49]
reg  ps_write_done;                      // emio[49]
wire ps_write;                           // emio[53]

wire ps_req_read_bus;
wire ps_req_write_bus;

// It is a write when no data lines are tristate; otherwise, we assume a read
assign ps_write = (emio_ps_tri[31:0] == 32'd0) ? 1'b1 : 1'b0;

assign ps_req_read_bus = ps_req_bus & (~ps_write);
assign ps_req_write_bus = ps_req_bus & ps_write;

assign emio_ps_in = {9'd0,
                     (ps_write ? grant_write_bus : grant_read_bus),   // [54]
                     ps_write,                                        // [53]
                     blk_wen, blk_wstart, reg_wen,                    // [52:50]
                     (ps_write ? ps_write_done : ps_read_done),       // [49]
                     ps_req_bus, ps_reg_addr,                         // [48] [47:32]
                     (ps_write ? reg_wdata : ps_reg_rdata) };         // [31:0]

//**************************** PS EMIO Read *************************************

// For synchronizing ps_req_read_bus with sysclk and generating triggers
// on the rising and falling edges.
reg ps_req_read_bus_1;
reg ps_req_read_bus_2;

always @(posedge sysclk)
begin
    // Synchronize req_read_bus with sysclk
    ps_req_read_bus_1 <= ps_req_read_bus;
    ps_req_read_bus_2 <= ps_req_read_bus_1;

    if (ps_req_read_bus_1 & (~ps_req_read_bus_2)) begin
        // Request read bus on rising edge of ps_req_read_bus
        req_read_bus <= 1'b1;
    end
    // Latch reg_rdata when we get the bus and data is valid
    if (req_read_bus & grant_read_bus & reg_rvalid) begin
        ps_reg_rdata <= reg_rdata;
        ps_read_done <= 1'b1;
        req_read_bus <= 1'b0;
    end
    if ((~ps_req_read_bus_1) & ps_req_read_bus_2) begin
        // Clear ps_read_done on falling edge of ps_req_write_bus
        ps_read_done <= 1'b0;
        req_read_bus <= 1'b0;
    end
end

//**************************** PS EMIO Write ***********************************

// For synchronizing ps_req_write_bus with sysclk and generating triggers
// on the rising and falling edges.
reg ps_req_write_bus_1;
reg ps_req_write_bus_2;
reg reg_wen_latched;
reg is_block;             // indicates block write

always @(posedge sysclk)
begin
    // Synchronize req_write_bus with sysclk
    ps_req_write_bus_1 <= ps_req_write_bus;
    ps_req_write_bus_2 <= ps_req_write_bus_1;
    reg_wen_latched <= reg_wen;

    if (ps_req_write_bus_1 & (~ps_req_write_bus_2)) begin
        // Request write bus on rising edge of ps_req_write_bus
        req_write_bus <= 1'b1;
        is_block <= blk_wstart;
    end   
    // Write is done when we get the bus
    if (grant_write_bus) begin
        ps_write_done <= reg_wen_latched;
        // Keep write bus if a block write
        req_write_bus <= is_block;
    end
    if ((~ps_req_write_bus_1) & ps_req_write_bus_2) begin
        // Clear ps_write_done on falling edge of ps_req_write_bus
        ps_write_done <= 1'b0;
        // Clear req_write_bus (for block write)
        req_write_bus <= 1'b0;
    end
end

endmodule
