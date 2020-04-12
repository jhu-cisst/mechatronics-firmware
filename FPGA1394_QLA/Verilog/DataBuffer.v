/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2020 Johns Hopkins University.
 *
 * This module implements a data collection buffer.
 *
 * Revision history
 *      3/9/20      Shi Xin Sun       Initial Revision
 *     3/16/20      Peter Kazanzides  Adapted for QLA     
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

reg       collecting = 0;
reg       buf_wr = 0;
reg[9:0]  buf_wr_addr = 10'h000;
reg[31:0] buf_wr_data;

// Note that the data collection bit (30) is used to start/stop data collection.
wire cur_cmd_wen;    // Write enable for commanded current
// Write the command current to the buffer when:
//   1) Collection bit set (reg_wdata[30]), but not already collecting
//   2) Collection in process and writing current to the correct channel
assign cur_cmd_wen = reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_DAC_CTRL) &&
                     ((!collecting && reg_wdata[30])) || (collecting && (reg_waddr[7:4] == chan));

// Following used in case cur_cmd_wen and cur_fb_wen happen at same time
reg       cur_cmd_wen_dly = 0;
reg[15:0] cur_cmd_dly = 16'd0;

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
    cur_cmd_wen_dly <= cur_cmd_wen;
    if (cur_cmd_wen) begin
        collecting <= reg_wdata[30];
        if (!collecting && reg_wdata[30]) begin
           // If data collection just started, set channel and reset buffer address
           chan <= reg_waddr[7:4];
           buf_wr_addr <= 10'd0;
        end
        cur_cmd_dly <= reg_wdata[15:0];
    end
    else if (collecting) begin
        buf_wr_addr <= buf_wr ? buf_wr_addr+1 : buf_wr_addr;
    end
end

always @(*)
begin
    if (collecting) begin     
        case ({cur_fb_wen, cur_cmd_wen, cur_cmd_wen_dly})
          3'b100,
          3'b110  : begin
                    buf_wr <= cur_fb_wen;
                    buf_wr_data <= {2'd3, 10'd0, chan, cur_fb};
                    end
          3'b010  : begin
                    buf_wr <= cur_cmd_wen;
                    buf_wr_data <= {2'd1, 10'd0, reg_waddr[7:4], reg_wdata[15:0]};
                    end
          3'b001  : begin
                    buf_wr <= cur_cmd_wen_dly;
                    buf_wr_data <= {2'd2, 10'd0, chan, cur_cmd_dly};
                    end
          default : begin
                    buf_wr <= 0;
                    buf_wr_data <= 32'h00000000;
                    end
        endcase
    end
end

endmodule
