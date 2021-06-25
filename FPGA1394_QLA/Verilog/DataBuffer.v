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
    input                clkbuffer,
    input  wire [31:0]   ts,               // Timestamp
    input  wire          data_fb_wen,      // channel 1~4 data ready
    input  wire [15:0]   input_data1,      // channel 1 data
    input  wire [15:0]   input_data2,      // channel 2 data
    input  wire [15:0]   input_data3,      // channel 3 data
    input  wire [15:0]   input_data4,      // channel 4 data
    input  wire [15:0]   reg_waddr,
    input  wire [31:0]   reg_wdata,
    input  wire          reg_wen,
    input  wire [15:0]   reg_raddr,
    output wire [31:0]   reg_rdata,
    output wire [15:0]   databuf_status
);

// local wires
reg         collecting;
// RAM specific
reg         buf_wen;
reg [9 :0]  buf_waddr [4:1];
reg [31:0]  buf_wdata [4:1];
// Synchronization specific 
reg         data_fb_wen_last;
reg         data_fb_pending;
wire        data_fb_trigger;

integer ii;
initial     begin
    for (ii = 1; ii < `NUM_CHANNELS+1; ii = ii + 1) buf_waddr[ii] = 0;
end

assign      data_fb_trigger = (data_fb_wen == 1) && (data_fb_wen_last == 0) ? 1'b1 : 1'b0;
assign      databuf_status = { collecting, 1'b0, reg_raddr[10], buf_waddr[reg_raddr[10]] };

// Indicate whether timestamp has more than 14 bits
wire        ts_over14;
assign      ts_over14 = (ts[31:14] == 18'd0) ? 1'b0 : 1'b1;

// Note that the data collection bit (30) is used to start/stop data collection.
// Write the command signal to the buffer when:
//   1) Collection bit set (reg_wdata[30]), but not already collecting
//   2) Collection in process and writing signal to the correct channel
// Write enable for commanded signal
wire        data_cmd_wen;    
assign      data_cmd_wen = reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_DAC_CTRL);

// Read data:
//   7000-73ff  memory
//   7400-77ff  memory (wrapping for circular buffer)
//   7800       status register
// all other addresses return 0

// 12th bit of reg_raddr dedicated to channel selection
wire[31:0]  mem_read [4:1];
assign      reg_rdata = (reg_raddr[11] == 1'b0) ? ((reg_raddr[10] == `OFF_RAM_CHAN1) ? mem_read[1] : (reg_raddr[10] == `OFF_RAM_CHAN2) ? mem_read[2] :
                                                   (reg_raddr[10] == `OFF_RAM_CHAN3) ? mem_read[3] : (reg_raddr[10] == `OFF_RAM_CHAN4) ? mem_read[4] : 32'b0): 
                                                  (reg_raddr[11:0] == 12'h800) ? { 16'd0, databuf_status } : 32'd0;

// --------------------------------------------
// buffer write address and data gen
// --------------------------------------------

always @(posedge clkbuffer)
begin
    // if new cmd values which fit criteria
    if (data_cmd_wen) begin
        // if collection hasn't started and PC commanded collection
        // reset all buffer address to 0 with channel offsets
        if (!collecting && reg_wdata[30]) begin
            // reset channel 1~4 buffer write address
            for (ii = 1; ii < `NUM_CHANNELS+1; ii = ii + 1) buf_waddr[ii] <= 10'd0;
            collecting <= 1;
        end
        else begin
            for (ii = 1; ii < `NUM_CHANNELS+1; ii = ii + 1) buf_waddr[ii] <= buf_waddr[ii] + reg_wdata[30];
            collecting <= reg_wdata[30];
        end
        buf_wen <= reg_wdata[30];
        // write commanded signal
        for (ii = 1; ii < `NUM_CHANNELS+1; ii = ii + 1) buf_wdata[ii] <= {1'b0, ts_over14, ts[13:0], reg_wdata[15:0]};
        // prepare to save pending ADC reading (collected when writing commanded signal) 
        if (reg_wdata[30] & data_fb_trigger)
            data_fb_pending <= 1;
    end
    else if ((collecting & data_fb_trigger) | data_fb_pending) begin
        // enable buffer write
        buf_wen <= 1;
        // write ADC readings
        buf_wdata[1] <= {1'b1, ts_over14, ts[13:0], input_data1};
        buf_wdata[2] <= {1'b1, ts_over14, ts[13:0], input_data2};
        buf_wdata[3] <= {1'b1, ts_over14, ts[13:0], input_data3};
        buf_wdata[4] <= {1'b1, ts_over14, ts[13:0], input_data4};
        // increment buffer write address for new ADC value
        for (ii = 1; ii < `NUM_CHANNELS+1; ii = ii + 1) buf_waddr[ii] <= buf_waddr[ii] + 1;
        // reset pending state 
        data_fb_pending <= 0;
    end
    else begin
        buf_wen <= 0;
    end
    // update ADC edge detection flag for next cycle
    data_fb_wen_last <= data_fb_wen; 
end

Dual_port_RAM_32X1024 Dual_port_RAM_32X1024_chan1(
    .clka(clkbuffer),
    .ena(1'b1),
    .wea(buf_wen),
    .addra(buf_waddr[1]),
    .dina(buf_wdata[1]),
    .clkb(clkbuffer),
    .enb(1'b1),
    .addrb(reg_raddr[9:0]),
    .doutb(mem_read[1])
);

Dual_port_RAM_32X1024 Dual_port_RAM_32X1024_chan2(
    .clka(clkbuffer),
    .ena(1'b1),
    .wea(buf_wen),
    .addra(buf_waddr[2]),
    .dina(buf_wdata[2]),
    .clkb(clkbuffer),
    .enb(1'b1),
    .addrb(reg_raddr[9:0]),
    .doutb(mem_read[2])
);

Dual_port_RAM_32X1024 Dual_port_RAM_32X1024_chan3(
    .clka(clkbuffer),
    .ena(1'b1),
    .wea(buf_wen),
    .addra(buf_waddr[3]),
    .dina(buf_wdata[3]),
    .clkb(clkbuffer),
    .enb(1'b1),
    .addrb(reg_raddr[9:0]),
    .doutb(mem_read[3])
);

Dual_port_RAM_32X1024 Dual_port_RAM_32X1024_chan4(
    .clka(clkbuffer),
    .ena(1'b1),
    .wea(buf_wen),
    .addra(buf_waddr[4]),
    .dina(buf_wdata[4]),
    .clkb(clkbuffer),
    .enb(1'b1),
    .addrb(reg_raddr[9:0]),
    .doutb(mem_read[4])
);

endmodule