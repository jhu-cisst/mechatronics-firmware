/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023-2024 Johns Hopkins University
 *
 * This module contains code for the boot configuration check
 *
 * Revision history
 *      2/20/23    Peter Kazanzides    Initial version
 */

`include "Constants.v"

module BootConfig(
    // global clock
    input wire       sysclk,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,
    // 1 -> FPGA V3.0
    input wire isV30,

    // I/O between FPGA and QLA (connectors J1 and J2)
    // Includes extra I/O from FPGA V3.1
    inout[0:33]      IO1,
    inout[0:39]      IO2,

    // Read/Write bus
    input wire[15:0]  reg_raddr,
    input wire[15:0]  reg_waddr,
    output wire[31:0] reg_rdata,
    input wire[31:0]  reg_wdata,
    output wire reg_rwait,
    input wire reg_wen,
    input wire blk_wen,
    input wire blk_wstart,
    input wire blk_rt_rd,

    // Timestamp
    output reg[31:0] timestamp
);

//******************* I/O pin mappings ****************************
// For the BCFG firmware, channels 1-4 are used to control the FPGA
// I/O pins, IO1[0:33] and IO2[0:39]. This is intended to be used
// when the Manufacturing Test board is attached (isTEST), but we
// also allow it when no board is attached (isNONE).
//   Channel 1:  IO1[0:31]  (returned as IO1[31:0])
//   Channel 2:  IO1[32:33] (return as {30'd0, IO1[33:32]})
//   Channel 3:  IO2[0:31]  (returned as IO2[31:0])
//   Channel 4:  IO2[32:39] (return as {24'd0, IO2[39:32]})

// Following are the channel offsets
`define OFF_BCFG_IO_IN    4'd0     // I/O input values
`define OFF_BCFG_IO_DIR   4'd1     // I/O direction (0 -> input)
`define OFF_BCFG_IO_OUT   4'd2     // I/O output (if IO_DIR is 1)

// For feedback via quadlet read
wire[31:0] IO_In[1:4];

// I/O direction register (tristate):  0->input (default), 1->output
reg[33:0] IO1_Dir;
reg[39:0] IO2_Dir;

// Feedback via quadlet read
wire[31:0] IO_Dir[1:4];
assign IO_Dir[1] = IO1_Dir[31:0];
assign IO_Dir[2] = {30'd0, IO1_Dir[33:32]};
assign IO_Dir[3] = IO2_Dir[31:0];
assign IO_Dir[4] = {24'd0, IO2_Dir[39:32]};

wire isInputAll;
assign isInputAll = ((IO1_Dir == 34'd0) && (IO2_Dir == 40'd0)) ? 1'b1 : 1'b0;

// I/O output register
reg[33:0] IO1_Out;
reg[39:0] IO2_Out;

// Feedback via quadlet read
wire[31:0] IO_Out[1:4];
assign IO_Out[1] = IO1_Out[31:0];
assign IO_Out[2] = {30'd0, IO1_Out[33:32]};
assign IO_Out[3] = IO2_Out[31:0];
assign IO_Out[4] = {24'd0, IO2_Out[39:32]};

// Board EEPROM
// Assume that all boards define IO1[1]-IO1[4] the same (EEPROM interface)
wire prom_sclk;
wire prom_miso;
wire prom_mosi;
wire prom_CSn;
assign IO1[3] = prom_CSn ? 1'bz : prom_sclk;
assign IO1[2] = prom_CSn ? 1'bz : prom_mosi;
assign prom_miso = IO1[1];
assign IO1[4] = prom_CSn;

//***********************************************************************************

// For DRAC, use IO1[6] for front panel LED
wire drac_front_panel_led;

assign IO1[0] = IO1_Dir[0] ? IO1_Out[0] : 1'bz;
assign IO1[5] = IO1_Dir[5] ? IO1_Out[5] : 1'bz;
assign IO1[6] = isDRAC ? drac_front_panel_led :
                IO1_Dir[6] ? IO1_Out[6] : 1'bz;

genvar i;
generate
    for (i = 7; i <= 33; i = i + 1) begin : io1_loop
       assign IO1[i] = IO1_Dir[i] ? IO1_Out[i] : 1'bz;
    end
    for (i = 0; i <= 39; i = i + 1) begin : io2_loop
       assign IO2[i] = IO2_Dir[i] ? IO2_Out[i] : 1'bz;
    end
    for (i = 0; i <= 31; i = i + 1) begin : in1_loop
       assign IO_In[1][i] = IO1[i];
       assign IO_In[2][i] = (i <= 1) ? IO1[32+i] : 1'b0;
       assign IO_In[3][i] = IO2[i];
       assign IO_In[4][i] = (i <= 7) ? IO2[32+i] : 1'b0;
    end
endgenerate

//------------------------------------------------------------------------------
// hardware description
//

wire[31:0] reg_rdata_prom;       // reads from prom
wire[31:0] reg_rdata_chan0;      // 'channel 0' is a special axis that contains various board I/Os

wire isAddrMain;
assign isAddrMain = (reg_raddr[15:8] == {`ADDR_MAIN, 4'd0}) ? 1'b1 : 1'b0;
wire isAddrPromQla;
assign isAddrPromQla = (reg_raddr[15:12] == `ADDR_PROM_QLA) ? 1'b1 : 1'b0;

// Mux routing read data based on read address
//   See Constants.v for details
assign reg_rdata = isAddrPromQla ? reg_rdata_prom :
                   (isAddrMain && (reg_raddr[7:4] == 4'd0)) ? reg_rdata_chan0 :
                   (isAddrMain && (reg_raddr[3:0] == `OFF_BCFG_IO_IN))  ? IO_In[reg_raddr[7:4]] :
                   (isAddrMain && (reg_raddr[3:0] == `OFF_BCFG_IO_DIR)) ? IO_Dir[reg_raddr[7:4]] :
                   (isAddrMain && (reg_raddr[3:0] == `OFF_BCFG_IO_OUT)) ? IO_Out[reg_raddr[7:4]] : 32'd0;

// No wait-states for reg_rdata
assign reg_rwait = 1'b0;

// --------------------------------------------------------------------------
// I/O control
// --------------------------------------------------------------------------

wire reg_wen_io_dir;
assign reg_wen_io_dir = ((reg_waddr[15:12] == `ADDR_MAIN) && (reg_waddr[3:0] == `OFF_BCFG_IO_DIR)) ?
                        reg_wen : 1'b0;

wire reg_wen_io_out;
assign reg_wen_io_out = ((reg_waddr[15:12] == `ADDR_MAIN) && (reg_waddr[3:0] == `OFF_BCFG_IO_OUT)) ?
                        reg_wen : 1'b0;

// Controls whether we can write to IO_DIR or IO_OUT
wire io_write_en;

// See above for definition channel numbers 1-4
always @(posedge sysclk)
begin
    if (io_write_en) begin
        if (reg_wen_io_dir) begin
            case (reg_waddr[7:4])
                4'd1: IO1_Dir[31:0]  <= reg_wdata;
                4'd2: IO1_Dir[33:32] <= reg_wdata[1:0];
                4'd3: IO2_Dir[31:0]  <= reg_wdata;
                4'd4: IO2_Dir[39:32] <= reg_wdata[7:0];
            endcase
        end
        if (reg_wen_io_out) begin
            case (reg_waddr[7:4])
                4'd1: IO1_Out[31:0]  <= reg_wdata;
                4'd2: IO1_Out[33:32] <= reg_wdata[1:0];
                4'd3: IO2_Out[31:0]  <= reg_wdata;
                4'd4: IO2_Out[39:32] <= reg_wdata[7:0];
            endcase
        end
    end
end

// --------------------------------------------------------------------------
// Prom 25AA128
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

wire reg_wen_prom;
assign reg_wen_prom = ((reg_waddr[15:12] == `ADDR_PROM_QLA) && (reg_waddr[7:4] == 4'd0)) ?
                       reg_wen : 1'b0;

QLA25AA128 prom(
    .clk(sysclk),

    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom),
    .reg_wdata(reg_wdata),

    .reg_wen(reg_wen_prom),
    .blk_wen(blk_wen),       // not used
    .blk_wstart(blk_wstart), // not used

    // spi interface
    .prom_mosi(prom_mosi),
    .prom_miso(prom_miso),
    .prom_sclk(prom_sclk),
    .prom_cs(prom_CSn),
    .other_busy(1'b0)
);

//---------------------------------------------------------------------------------
//
// Board detection logic
//
// The following logic distinguishes between the known boards (and NONE, which
// means no board attached) by looking at the power-up values of the IO lines.
// It assumes that all IO lines are configured with pull-up resistors
// (see BootConfig.ucf).
//
// Note that, except for NONE, we do not check all IOs, but rather only check
// when there is at least one expected difference.
//
// If desired, it would also be possible to read the PROM attached to IO1[1]-IO1[4],
// or to look for square waves on the temperature feedback lines on QLA/DQLA.
//
//---------------------------------------------------------------------------------

// NONE: all IO have pull-ups
reg isNONE;

// TEST: manufacturing test board (loopbacks on I/O)
wire TESTzeros;
wire TESTones;
reg isTEST;
// IO1[31]=1 for DQLA, IO2[32]=IO2[36]=1 for DRAC, all IOs are 1 for NONE
assign TESTzeros = ~(IO1[30]|IO1[31]|IO2[32]|IO2[36]);
// IO1[0]=0 for QLA, DQLA, IO1[9]=IO1[12]=0 for DRAC, IO1[32]=IO2[34]=0 for QLA, DRAC
assign TESTones = IO1[0]&IO1[9]&IO1[12]&IO1[32]&IO2[34];

// QLA: it is sufficient to check the 0 values because IO1[31]=1 for DQLA
//      and there are many that are 1 for DRAC and NONE
wire QLAzeros;
reg isQLA;
assign QLAzeros = ~(IO1[0]|IO1[31]|IO1[32]|IO2[1]|IO2[3]|IO2[5]|IO2[7]|IO2[11]|
                    IO2[31]|IO2[32]|IO2[33]|IO2[34]|IO2[35]|IO2[36]|IO2[37]|IO2[38]);

// DQLA
wire DQLAzeros;
wire DQLAones;
reg isDQLA;
// IO1[0]=1 for TEST, NONE
assign DQLAzeros = ~IO1[0];
// IO1[12]=0 for DRAC and IO1[31]=0 for QLA, TEST
assign DQLAones = IO1[12]&IO1[31];

// DRAC
wire DRACzeros;
wire DRACones;
reg isDRAC;
// IO1[12]=1 for DQLA, TEST; all IOs are 1 for NONE
assign DRACzeros = ~(IO1[9]|IO1[12]|IO1[19]|IO1[21]|IO1[23]|IO1[32]|
                     IO2[10]|IO2[15]|IO2[22]|IO2[28]|IO2[29]|IO2[34]);
// IO2[32]=IO2[36]=0 for TEST, QLA; many IOs are 0 for QLA
assign DRACones = IO2[1]&IO2[3]&IO2[31]&IO2[32]&IO2[36];

// Latch the following values when all I/O are inputs
always @(posedge sysclk)
begin
    if (isInputAll) begin
       isNONE <= ((IO1[0:33] == {34{1'b1}}) && (IO2[0:39] == {40{1'b1}})) ? 1'b1 : 1'b0;
       isTEST <= TESTzeros & TESTones;
       isQLA <= QLAzeros;
       isDQLA <= DQLAzeros & DQLAones;
       isDRAC <= DRACzeros & DRACones;
    end
end

// Only allow IO_DIR and IO_OUT to be written when Manufacturing Test board attached
// (isTEST) or no board attached (isNONE).
assign io_write_en = isNONE | isTEST;

// --------------------------------------------------------------------------
// miscellaneous board I/Os
//
// Following could be moved to BoardRegs-BCFG.v, but since there is not
// much code, we keep it here.
//
// --------------------------------------------------------------------------

wire[31:0] reg_status;
assign reg_status = {4'd0, board_id,                                    // 31:24
                     isNONE, isQLA, isDQLA, isDRAC,                     // 23:20
                     isV30, QLAzeros, DQLAzeros, DQLAones,              // 19:16
                     DRACzeros, DRACones, isTEST, TESTzeros,            // 15:12
                     TESTones, isInputAll, 2'd0,                        // 11:8
                     8'd0 };                                            // 7:0
wire[31:0] reg_version;   // Hardware version
assign reg_version = 32'h42434647;   // "BCFG"

// Repurpose REG_DIGIN and REG_TEMPSNS for additional feedback; also, note that lower 10 bits of REG_STATUS
// are used for real-time block read.
assign reg_rdata_chan0 = (reg_raddr[3:0] == `REG_STATUS)  ? { reg_status[31:10], (blk_rt_rd ? IO1[0:9] : 10'd0) } :
                         (reg_raddr[3:0] == `REG_DIGIN)   ? { IO1[10:33], IO2[0:7] } :
                         (reg_raddr[3:0] == `REG_TEMPSNS) ? IO2[8:39] :
                         (reg_raddr[3:0] == `REG_VERSION) ? reg_version :
                         32'd0;

// -------------------------------------------------------------------------
// Timestamp: just a free-running counter
// -------------------------------------------------------------------------

always @(posedge sysclk)
begin
    timestamp <= timestamp + 1'b1;
end

// --------------------------------------------------------------------------
// dRAC LED
// --------------------------------------------------------------------------
reg [25:0] blink_counter;
reg blink_ovf;
reg [3:0] on_led = 4'd1;
reg [7:0] led_red;
reg [7:0] led_green;
reg [7:0] led_blue;
wire [3:0] led_address;
always @(posedge sysclk) begin
    blink_counter <= blink_counter + 26'd1;
    blink_ovf <= blink_counter == 'd12_288_000 - 'd1;
    led_green <= led_address == on_led ? 'd50 : 'd0;
    if (blink_ovf) begin
        blink_counter <= 26'd0;
        on_led <= on_led + 4'd1;
        if (on_led == 4'd6) begin
            on_led <= 4'd1;
        end
    end
end

ws2811 #(.NUM_LEDS(7),.SYSTEM_CLOCK(49_152_000)) ws2811_instance (
    .clk(sysclk),
    .address(led_address),
    .red_in(led_red),
    .blue_in(led_blue),
    .green_in(led_green),
    .DO(drac_front_panel_led)
);

endmodule
