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
 *     7/22/21      Jintan Zhang        Revised Implementation
 */

`include "Constants.v"

module DataBuffer(
    input                clkbuffer,
    input  wire [31:0]   ts,

    input  wire          data_fb_wen,
    input  wire [31:0]   input_data,      
    output wire [3 :0]   data_type,
    output wire [3 :0]   data_channel,
    output wire [3 :0]   data_format,

    input  wire [15:0]   reg_waddr,
    input  wire [31:0]   reg_wdata,
    input  wire          reg_wen,
    input  wire [15:0]   reg_raddr,
    output wire [31:0]   reg_rdata,
    output wire [15:0]   buf_status
);

// --------------------------------------------
// receive & update target data struct
// --------------------------------------------
wire    data_struct_wen;
assign  data_struct_wen = reg_wen && reg_waddr[15:12] == `ADDR_DATA_BUF && reg_waddr[3:0] == `OFF_DATA_STRUCT;

/* Note:
 * 1. target_data_num    : number of signals to collect.
 * 1. target_data_type   : buffer data source, supports pot, cur, and encoder readings.
 * 2. target_data_channel: channel through which the data is coming from.
 * 3. target_data_format : number of bits allocated to store buffered data.
 */
reg     [3:0] target_data_num;
reg     [3:0] target_data_counter;
reg     [3:0] target_data_type    [15:0];
reg     [3:0] target_data_channel [15:0];
reg     [3:0] target_data_format  [15:0];

integer i;
initial begin
    target_data_num        = 0;
    target_data_counter    = 0;
    for(i = 1; i <= `NUM_CHANNELS; i = i + 1) begin
        target_data_type[i]    = 0;
        target_data_channel[i] = 0;
        target_data_format[i]  = 0;
    end
end

reg     data_struct_config_complete;
initial data_struct_config_complete = 0;

always @(posedge(clkbuffer)) begin
    if (data_struct_wen && reg_waddr[11:8] == `OFF_BUF_SIGNAL_NUM_MASK) begin
        target_data_num <= reg_wdata[3:0];
    end
    if (data_struct_wen && reg_waddr[11:8] == `OFF_BUF_SIGNAL_SPEC_MASK) begin
        target_data_type[target_data_counter]    <= reg_wdata[15:12];
        target_data_channel[target_data_counter] <= reg_wdata[7:4];
        target_data_format[target_data_counter]  <= reg_wdata[3:0];
        target_data_counter <= target_data_counter + 4'b1;
    end
    if (target_data_counter == target_data_num && target_data_num != 0) begin
        data_struct_config_complete <= 1'b1;
        target_data_counter <= 4'b0;
    end
end

// --------------------------------------------
// buffer write
// --------------------------------------------

// Note that the data collection bit (30) is used to start/stop data collection.
// Write the command signal to the buffer when:
//   1) Collection bit set (reg_wdata[30]), but not already collecting
//   2) Collection in process and writing signal to the correct channel

// local wires
reg         collecting;
reg         buf_wen;
reg [9 :0]  buf_waddr;
reg [31:0]  buf_wdata;
reg [3 :0]  buffer_counter;

initial begin
    collecting     = 0;
    buf_wen        = 0;
    buf_waddr      = 0;
    buf_wdata      = 0;
    buffer_counter = 0;
end

// Indicate whether timestamp has more than 14 bits
wire        ts_over14;
assign      ts_over14 = (ts[31:14] == 18'd0) ? 1'b0 : 1'b1;

// find type, channel, format according to assigned data structure
assign data_type    = target_data_type[buffer_counter];
assign data_channel = target_data_channel[buffer_counter];
assign data_format  = target_data_format[buffer_counter];

always @(posedge(clkbuffer)) begin
    if (~collecting) begin
        buf_wen <= 0;
    end else if (data_struct_config_complete) begin
        // reset write address pointer, set counter to waiting state
        buf_wen <= 0;
        buf_waddr <= 0;
        buffer_counter <= target_data_num;
        data_struct_config_complete <= 0;
    end else if (buffer_counter == 0) begin
        // store time stamps
        buf_wen <= 1'b1;
        buf_wdata <= {1'b1, ts_over14, ts[13:0]};
        buffer_counter <= buffer_counter + 3'b1;
    end else if (buffer_counter < target_data_num) begin
        // store target data
        buf_wen <= 1;
        buf_waddr <= buf_waddr + 9'b1;
        buf_wdata <= input_data;
        buffer_counter <= buffer_counter + 3'b1;
    end else if (buffer_counter == target_data_num && data_fb_wen) begin
        // buffer waiting state, reset counter to 0 when new samples are ready
        buffer_counter <= 0;
    end
end

// --------------------------------------------
// buffer read
// --------------------------------------------

// Read data:
//   7000-73ff  memory
//   7400-77ff  memory (wrapping for circular buffer)
//   7800       status register
//   all other addresses return 0

wire [31:0]  buf_rdata;

assign       buf_status = {collecting, 1'b0, reg_raddr[10], buf_waddr[reg_raddr[10]]};
assign       reg_rdata  = (reg_raddr[11] == 1'b0) ? buf_rdata : (reg_raddr[11:0] == 12'h800) ? { 16'd0, buf_status } : 32'd0;

// local register pointing to last valid read address
reg  [9 :0]  buf_last_raddr;
reg  [9 :0]  buf_raddr;

initial begin
    buf_last_raddr = 0;
    buf_raddr = 0;
end

always @(posedge(clkbuffer)) begin
    if(~reg_raddr[11]) begin
        buf_last_raddr <= reg_raddr[9:0];
    end
end

// set buffer read address to last valid read address when program restarts
wire prog_restart;

always @(posedge(clkbuffer)) begin
    if(prog_restart) begin
        buf_raddr <= buf_last_raddr;
    end else begin
        buf_raddr <= reg_raddr[9:0];
    end
end

// --------------------------------------------
// RAM unit
// --------------------------------------------
Dual_port_RAM_32X1024 Dual_port_RAM_32X1024(
    .clka(clkbuffer),
    .ena(1'b1),
    .wea(buf_wen),
    .addra(buf_waddr),
    .dina(buf_wdata),
    .clkb(clkbuffer),
    .enb(1'b1),
    .addrb(buf_raddr),
    .doutb(buf_rdata)
);

endmodule
