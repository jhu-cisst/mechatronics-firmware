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
assign  data_struct_wen = reg_wen && reg_waddr[15:12] == `ADDR_DATA_BUF && reg_waddr[3:0] == `OFF_BUF_DATA_STRUCT;

/* Note:
 * 1. target_data_num    : number of signals to collect.
 * 2. target_data_type   : buffer data source, supports pot, cur, and encoder readings.
 * 3. target_data_channel: channel through which the data is coming from.
 * 4. target_data_format : number of bits allocated to store buffered data.
 */
reg     [3:0] target_data_num;
reg     [3:0] target_data_counter;
reg     [3:0] target_data_type    [15:0];
reg     [3:0] target_data_channel [15:0];
reg     [3:0] target_data_format  [15:0];

reg     data_struct_config_complete;

always @(posedge(clkbuffer)) begin
    if (data_struct_wen && reg_waddr[11:8] == `OFF_BUF_SIGNAL_NUM_MASK && !buf_busy) begin
        target_data_num <= reg_wdata[3:0];
        target_data_counter <= 4'b0;
    end
    if (data_struct_wen && reg_waddr[11:8] == `OFF_BUF_SIGNAL_SPEC_MASK && !buf_busy) begin
        target_data_type[target_data_counter]    <= reg_wdata[15:12];
        target_data_channel[target_data_counter] <= reg_wdata[7:4];
        target_data_format[target_data_counter]  <= reg_wdata[3:0];
        target_data_counter <= target_data_counter + 4'b1;
    end
    if (target_data_counter == target_data_num && target_data_num != 0) begin
        data_struct_config_complete <= 1'b1;
        target_data_counter <= 4'b0; 
    end
    if (buf_busy) begin
        data_struct_config_complete <= 0;
    end
end

// --------------------------------------------------------------
// configure buffer collection mode && start/stop collection
// --------------------------------------------------------------
wire    buf_collect_wen;
assign  buf_collect_wen = reg_wen && reg_waddr[15:12] == `ADDR_DATA_BUF && reg_waddr[3:0] == `OFF_BUF_STAT;

reg [3 :0]  buf_collect_mode;
reg [10:0]  buf_ram_counter;
reg [10:0]  buf_ram_samples;

always @(posedge(clkbuffer)) begin
    if (buf_collect_wen && reg_waddr[11:8] == `OFF_BUF_MODE_SAMPLE && !buf_busy) begin
        /*<collection stops when requested amount of data frames have been collected>*/
        /*<PC writes requested data frame number>*/
        buf_ram_samples <= reg_wdata[10:0];
        buf_collect_mode <= `OFF_BUF_MODE_SAMPLE;
    end else if (buf_collect_wen && reg_waddr[11:8] == `OFF_BUF_MODE_CONTINUOUS && !buf_busy) begin
        /*<buffer continuously capture data until a stop collection command is sent>*/
        buf_ram_samples <= 0;
        buf_collect_mode <= `OFF_BUF_MODE_CONTINUOUS;
    end
end

/*<buffer start/stop collection command>*/
reg     buf_collect_ctrl;
always @(posedge(clkbuffer)) begin
    if (buf_collect_wen && reg_waddr[7:4] == `OFF_BUF_START_COLLECT) begin
        buf_collect_ctrl <= 1;
    end else if (buf_collect_wen && reg_waddr[7:4] == `OFF_BUF_STOP_COLLECT) begin
        buf_collect_ctrl <= 0;
    end
end

// --------------------------------------------
// buffer write & buffer state machine
// --------------------------------------------

/*<local wires>*/
reg         buf_wen;
reg         buf_busy;
reg [9 :0]  buf_waddr;
reg [9 :0]  buf_waddr_align;
reg [31:0]  buf_wdata;
reg [3 :0]  buf_counter;

/*<Indicate whether timestamp has more than 14 bits>*/
wire        ts_over14;
assign      ts_over14 = (ts[31:14] == 18'd0) ? 1'b0 : 1'b1;

/*<find type, channel, format according to assigned data structure>*/
assign data_type    = target_data_type[buf_counter];
assign data_channel = target_data_channel[buf_counter];
assign data_format  = target_data_format[buf_counter];

/*<data valid signal trigger>*/
reg  data_fb_wen_sync;
reg  data_fb_wen_prev;
wire data_fb_wen_trigger;

always @(posedge(clkbuffer)) begin
    data_fb_wen_sync <= data_fb_wen;
    data_fb_wen_prev <= data_fb_wen_sync;
end
assign data_fb_wen_trigger = (!data_fb_wen_prev) && data_fb_wen_sync;

/*<state machine>*/
reg [3:0] state;
parameter
    ST_IDLE            = 4'd0,  // wait for collect start command or configuration command
    ST_WAIT_CONFIG     = 4'd1,  // wait for new configuration when PC requested or board rebooted
    ST_MODE_SAMPLE     = 4'd2,  // wait for new data valid signal, stop collection on stop command or enough samples 
    ST_MODE_CONTINUOUS = 4'd3,  // wait for new data valid signal, stop collection on stop command
    ST_TIME_STAMP      = 4'd4,  // save time stamps
    ST_LOOP_MAIN       = 4'd5;  // save data frames

initial state = ST_WAIT_CONFIG;

always @(posedge(clkbuffer)) begin
    case (state)

        ST_IDLE: begin
            /*<data structure configuration requested, go to configuration state>*/
            if (data_struct_wen) begin
                state <= ST_WAIT_CONFIG;
            end else if (buf_collect_ctrl) begin 
                /*<collect command received, use old data structure configuration>*/
                buf_busy <= 1;
                state <= (buf_collect_mode == `OFF_BUF_MODE_SAMPLE) ? ST_MODE_SAMPLE : 
                         ((buf_collect_mode == `OFF_BUF_MODE_CONTINUOUS) ? ST_MODE_CONTINUOUS : 0);
            end else begin
                state <= ST_IDLE;
            end
        end

        ST_WAIT_CONFIG: begin
            /*<new data structure configuration complete, ready to buffer data>*/
            if (data_struct_config_complete) begin
                buf_wen <= 0;
                buf_busy <= 1;
                buf_waddr <= 0;
                buf_ram_counter <= 0;
                state <= (buf_collect_mode == `OFF_BUF_MODE_SAMPLE) ? ST_MODE_SAMPLE : 
                         ((buf_collect_mode == `OFF_BUF_MODE_CONTINUOUS) ? ST_MODE_CONTINUOUS : 0);
            end else begin
                /*<waiting for new data structure>*/
                state <= ST_WAIT_CONFIG;
            end
        end

        ST_MODE_SAMPLE: begin
            /*<data valid signal received, start buffering loop>*/
            if (data_fb_wen_trigger && (buf_ram_counter != buf_ram_samples) && buf_collect_ctrl) begin
                buf_counter <= 0;
                buf_ram_counter <= buf_ram_counter + 10'b1;
                state <= ST_TIME_STAMP;
            end else if ((buf_ram_counter == buf_ram_samples) && buf_collect_ctrl) begin
                /*<enough data samples have been captured, quit collect loop>*/
                buf_wen <= 0;
                buf_busy <= 0;
                buf_ram_counter <= 0;
                state <= ST_IDLE;
            end else if (~buf_collect_ctrl) begin
                /*<stop command received, quit collect loop>*/
                buf_wen <= 0;
                buf_busy <= 0;
                state <= ST_IDLE;
            end else begin
                /*<wait for data valid signal to start>*/
                state <= ST_MODE_SAMPLE;
            end
        end

        ST_MODE_CONTINUOUS: begin
            if (data_fb_wen_trigger && buf_collect_ctrl) begin
                buf_counter <= 0;
                state <= ST_TIME_STAMP;
            end else if (~buf_collect_ctrl) begin
                /*<stop command received, quit collect loop>*/
                buf_wen <= 0;
                buf_busy <= 0;
                state <= ST_IDLE;
            end else begin
                /*<wait for data valid signal to start>*/
                state <= ST_MODE_CONTINUOUS;
            end
        end

        ST_TIME_STAMP: begin
            /*<save time stamp>*/
            buf_wen <= 1'b1;
            buf_waddr <= buf_waddr + 9'b1;
            buf_wdata <= {1'b1, ts_over14, ts[13:0]};
            state <= ST_LOOP_MAIN;
        end

        ST_LOOP_MAIN: begin
            if (buf_counter == target_data_num) begin
                /*<one sample buffering complete, update frame-aligned write address>*/
                /*<go to ready state for another valid signal>*/
                buf_wen <= 0;
                buf_waddr_align <= buf_waddr;
                state <= (buf_collect_mode == `OFF_BUF_MODE_SAMPLE) ? ST_MODE_SAMPLE : 
                         ((buf_collect_mode == `OFF_BUF_MODE_CONTINUOUS) ? ST_MODE_CONTINUOUS : 0);
            end else begin
                /*<buffer data according to data structure>*/
                buf_wen <= 1;
                buf_waddr <= buf_waddr + 9'b1;
                buf_wdata <= input_data;
                buf_counter <= buf_counter + 3'b1;
                state <= ST_LOOP_MAIN;
            end
        end

    endcase
end

// --------------------------------------------
// buffer read && maintain last read address
// --------------------------------------------

// Read data:
//   7000-73ff  memory
//   7400-77ff  memory (wrapping for circular buffer)
//   7800       status register
//   all other addresses return 0

wire [31:0]  buf_rdata;

/*<buffer write/read status>*/
assign       buf_status = {buf_busy, 1'b0, target_data_num, buf_waddr_align};

/*<feedback last read address and buffer status>*/
assign       reg_rdata  = (reg_raddr[11] == 1'b0) ? buf_rdata : (reg_raddr[11:0] == 12'h800) ? { buf_last_raddr, buf_status } : 32'd0;

/*<track PC reading>*/
wire   master_read;
assign master_read = (reg_raddr[15:12] == `ADDR_DATA_BUF) && (~reg_raddr[11]);

/*<local register pointing to last valid read address>*/
/*<keeps updating last read address when PC is reading>*/
reg  [9 :0]  buf_last_raddr;

always @(posedge(clkbuffer)) begin
    if (master_read) begin
        buf_last_raddr <= reg_raddr[9:0];
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
    .addrb(reg_raddr[9:0]),
    .doutb(buf_rdata)
);

endmodule
