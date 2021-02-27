/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2020-2021 Johns Hopkins University.
 *
 * This module implements a data collection buffer.
 *
 * Revision history
 *      3/9/20      Shi Xin Sun         Initial Revision
 *     3/16/20      Peter Kazanzides    Adapted for QLA
 *     5/28/20      Stefan Kohlgrueber  Corrections for operation for all channels
 */

`include "Constants.v"

module DataBuffer(
    input             clk,
    // write interface
    input  wire       cur_fb_wen,   // motor current feedback data ready
    input  wire[15:0] cur_fb,       // motor current feedback
    output reg[3:0]   chan,         // selected data channel
    // CPU interface
    input  wire[15:0] reg_waddr,    // register write address
    input  wire[31:0] reg_wdata,    // register write
    input  wire       reg_wen,      // register write enable
    input  wire[15:0] reg_raddr,    // register read address
    output wire[31:0] reg_rdata     // read data
);

initial chan = 4'd1;

reg       collecting;
reg       buf_wr;
reg[9:0]  buf_wr_addr;
reg[31:0] buf_wr_data;
reg       cur_fb_wen_last;
reg       cur_fb_pending;

wire      cur_fb_trigger;
assign    cur_fb_trigger = (cur_fb_wen == 1) && (cur_fb_wen_last == 0) ? 1'b1 : 1'b0;

// Note that the data collection bit (30) is used to start/stop data collection.
wire cur_cmd_wen;    // Write enable for commanded current
// Write the command current to the buffer when:
//   1) Collection bit set (reg_wdata[30]), but not already collecting
//   2) Collection in process and writing current to the correct channel
assign cur_cmd_wen = reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_DAC_CTRL);

wire[31:0] mem_read;
// Read data: flags (2 bits), current write address (10 bits), channel (4 bits), data (16 bits)
assign reg_rdata = {mem_read[31:30], buf_wr_addr, mem_read[19:0]};

Dual_port_RAM_32X1024 Dual_port_RAM_32X1024(
    .clka(clk),
    .ena(1'b1),
    .wea(buf_wr),
    .addra(buf_wr_addr),
    .dina(buf_wr_data),
    .clkb(clk),
    .enb(1'b1),
    .addrb(reg_raddr),
    .doutb(mem_read)
);

// --------------------------------------------
// buffer write address and data gen
// --------------------------------------------

always @(posedge clk)
begin
    if (cur_cmd_wen) begin     // if new cmd values which fit criteria
        if (!collecting && reg_wdata[30]) begin  // rising edge collecting
            chan <= reg_waddr[7:4];   // update channel
            buf_wr_addr <= 10'd0;     // reset address
            collecting <= 1;
        end
        else if (reg_waddr[7:4] == chan) begin
            buf_wr_addr <= buf_wr_addr+1;
            collecting <= reg_wdata[30];
        end
        buf_wr <= reg_wdata[30];
        buf_wr_data <= {2'd0, 10'd0, reg_waddr[7:4], reg_wdata[15:0]};
        if (reg_wdata[30]&cur_fb_trigger)
            cur_fb_pending <= 1;
    end
    else if ((collecting&cur_fb_trigger)|cur_fb_pending) begin
        buf_wr_data <= {2'd1, 10'd0, chan, cur_fb};
        buf_wr <= 1;
        buf_wr_addr <= buf_wr_addr+1;
        cur_fb_pending <= 0;
    end
    else begin
        buf_wr <= 0;
    end
    cur_fb_wen_last <= cur_fb_wen; //update ADC edge detection flag for next cycle
end

endmodule
