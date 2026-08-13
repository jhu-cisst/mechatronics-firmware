/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2026 Johns Hopkins University.
 *
 * This module contains common code for the DRAC
 *
 * Revision history
 *     1/1/23    Keshuai Xu   Initial version adapted from QLA.v
 */

`include "Constants.v"

module DRAC(
    // global clock
    input wire       sysclk,

    // sysclk * 3 clock for PWM generation and PI loop
    input wire       pwmclk,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,

    // I/O between FPGA and QLA (connectors J1 and J2)
    inout[1:32]      IO1,
    inout[1:38]      IO2,
    inout wire[3:0]  io_extra,

    // Number of real-time block read quadlets
    output wire[6:0] num_rt_read_quads,

    // Read/Write bus
    input wire[15:0]  host_reg_raddr,
    input wire[15:0]  reg_waddr,
    output reg[31:0]  reg_rdata,
    input wire[31:0]  reg_wdata,
    output reg reg_rwait,
    input wire reg_wen,
    input wire blk_wen,
    input wire blk_wstart,
    input wire req_blk_rt_rd,
    input wire blk_rt_rd,

    // Timestamp
    output wire[31:0] timestamp,

    // Watchdog support
    input wire wdog_period_led,     // 1 -> external LED displays wdog_period_status
    input wire[2:0] wdog_period_status,
    input wire wdog_timeout,        // watchdog timeout status flag
    output wire wdog_clear,          // clear watchdog timeout (e.g., on powerup)

    output wire lvds_tx_clk,        // TX clk to ESPM, to be output by ODDR
    output wire adc_sck             // SCK to ADC, to be output by ODDR
);

// outputs
wire MV_EN;
wire suj_brake_release_n;
wire dsib_si_uart_tx;
wire FRONT_PANEL_LED;
wire ESPMV_EN;
wire RELAY_EN;
wire LVDS_TDAT;
// wire SCLK_ADC;
wire SDI_ADC;
wire CONV_ADC;
wire[1:10] PWM_P;
wire[1:10] PWM_N;
wire[1:10] RESETn;

// inputs
wire SAFETY_CHAIN_GOOD;
wire RELAY_GOODn;
wire ESPMV_GOOD;
wire LVDS_RCLK;
wire LVDS_RDAT;
wire ADC_MV_SDO;
wire[1:5] FAULTn;
wire[1:5] OTWn;
wire[1:10] ADC_CUR_SDO;

// wire MISO_EEPROM = IO1[1];
// wire MOSI_EEPROM = IO1[2];
// wire SCLK_EEPROM = IO1[3];
// wire CS_EEPROM = IO1[4];
assign IO1[5] = 1'bz; // spare IO on P6
assign IO1[6] = FRONT_PANEL_LED;
assign ADC_CUR_SDO[6] = IO1[7];
assign IO1[8] = PWM_P[6];
assign IO1[9] = RESETn[6];
assign IO1[10] = PWM_N[6];
assign IO1[11] = PWM_P[3];
assign IO1[12] = RESETn[3];
assign IO1[13] = PWM_N[3];
assign FAULTn[4] = IO1[14];
assign OTWn[4] = IO1[15];
assign ADC_CUR_SDO[3] = IO1[16];
assign ADC_CUR_SDO[7] = IO1[17];
assign IO1[18] = PWM_P[7];
assign IO1[19] = RESETn[7];
assign IO1[20] = PWM_N[7];
assign IO1[21] = MV_EN;
assign IO1[22] = PWM_P[4];
assign IO1[23] = RESETn[4];
assign SAFETY_CHAIN_GOOD = IO1[24];
assign IO1[25] = PWM_N[4];
assign RELAY_GOODn = IO1[26];
assign FAULTn[5] = IO1[27];
assign IO1[28] = ESPMV_EN;
assign OTWn[5] = IO1[29];
assign ESPMV_GOOD = IO1[30];
assign ADC_CUR_SDO[4] = IO1[31];
assign IO1[32] = RELAY_EN;



// assign IO2[1] = LVDS_TCLK;
assign ADC_CUR_SDO[2] = IO2[2];
assign IO2[3] = LVDS_TDAT;
assign OTWn[3] = IO2[4];
assign FAULTn[3] = IO2[5];
assign LVDS_RCLK = IO2[6];
assign LVDS_RDAT = IO2[7];
assign IO2[8] = PWM_N[2];
assign IO2[9] = CONV_ADC;
assign IO2[10] = RESETn[2];
assign ADC_MV_SDO = IO2[11];
assign IO2[12] = PWM_P[2];
assign IO2[13] = PWM_N[5];
// assign IO2[14] = SCLK_ADC;
assign IO2[15] = RESETn[5];
assign IO2[16] = SDI_ADC;
assign IO2[17] = PWM_P[5];
assign ADC_CUR_SDO[8] = IO2[18];
assign ADC_CUR_SDO[5] = IO2[19];
assign IO2[20] = PWM_P[8];
assign ADC_CUR_SDO[1] = IO2[21];
assign IO2[22] = RESETn[8];
assign OTWn[2] = IO2[23];
assign IO2[24] = PWM_N[8];
assign FAULTn[2] = IO2[25];
assign IO2[26] = PWM_N[1];
assign IO2[27] = PWM_P[9];
assign IO2[28] = RESETn[1];
assign IO2[29] = RESETn[9];
assign IO2[30] = PWM_P[1];
assign IO2[31] = PWM_N[9];
assign IO2[32] = PWM_N[10];
assign FAULTn[1] = IO2[33];
assign IO2[34] = RESETn[10];
assign OTWn[1] = IO2[35];
assign IO2[36] = PWM_P[10];
assign ADC_CUR_SDO[9] = IO2[37];
assign ADC_CUR_SDO[10] = IO2[38];

assign IO1[7] = 1'bz;
assign IO1[14] = 1'bz;
assign IO1[15] = 1'bz;
assign IO1[16] = 1'bz;
assign IO1[17] = 1'bz;
assign IO1[24] = 1'bz;
assign IO1[26] = 1'bz;
assign IO1[27] = 1'bz;
assign IO1[29] = 1'bz;
assign IO1[30] = 1'bz;
assign IO1[31] = 1'bz;
assign IO2[2] = 1'bz;
assign IO2[4] = 1'bz;
assign IO2[5] = 1'bz;
assign IO2[6] = 1'bz;
assign IO2[7] = 1'bz;
assign IO2[11] = 1'bz;
assign IO2[18] = 1'bz;
assign IO2[19] = 1'bz;
assign IO2[21] = 1'bz;
assign IO2[23] = 1'bz;
assign IO2[25] = 1'bz;
assign IO2[33] = 1'bz;
assign IO2[35] = 1'bz;
assign IO2[37] = 1'bz;
assign IO2[38] = 1'bz;
assign io_extra[0] = 1'bz; // safety chain S sense
assign io_extra[1] = dsib_si_uart_tx; // dSIB-Si UART TX
assign io_extra[2] = 1'bz; // dSIB-Si UART RX
assign io_extra[3] = suj_brake_release_n;

// Number of motors and encoders
localparam NUM_MOTORS = 10;
localparam NUM_ENCODERS = 7;
localparam[6:0] NUM_EXTRA = 5;

localparam[6:0] NUM_RT_READ_QUADS = 4 + 2*NUM_MOTORS + 5*NUM_ENCODERS;

assign num_rt_read_quads = has_suj_pots ? (NUM_RT_READ_QUADS + NUM_EXTRA) : NUM_RT_READ_QUADS;

//*********************** Read Address Translation *******************************
//
// Read bus address translation (to support real-time block read).

wire[15:0] reg_raddr;

ReadAddressTranslation
    #(.NUM_MOTORS(NUM_MOTORS), .NUM_ENCODERS(NUM_ENCODERS), .NUM_EXTRA(NUM_EXTRA))
ReadAddr(
    .reg_raddr_in(host_reg_raddr),
    .reg_raddr_out(reg_raddr),
    .blk_rt_rd(blk_rt_rd)
);

// --------------------------------------------------------------------------
// dSIB-Si UART
// --------------------------------------------------------------------------

wire dsib_si_uart_rx = io_extra[2];
wire[7:0] dsib_si_uart_rx_data;
wire dsib_si_uart_rx_valid;
wire dsib_si_uart_rx_ready = 1'b1;
wire dsib_si_uart_tx_ready;

dsib_si_uart dsib_si_uart_inst
(
    .clk(sysclk),
    .rx_pin(dsib_si_uart_rx),
    .rx_data(dsib_si_uart_rx_data),
    .rx_data_valid(dsib_si_uart_rx_valid),
    .rx_data_ready(dsib_si_uart_rx_ready),
    .tx_data(8'd0),
    .tx_data_valid(1'b0),
    .tx_data_ready(dsib_si_uart_tx_ready),
    .tx_pin(dsib_si_uart_tx)
);

reg dsib_si_present = 1'b0;
wire[3:0] suj_z_id;
wire dsib_z_si_present;
wire[11:0] suj_z_pot1;
wire[11:0] suj_z_pot2;
wire dsib_packet_accept;

dsib_si_parser dsib_si_parser_inst
(
    .clk(sysclk),
    .rx_data(dsib_si_uart_rx_data),
    .rx_data_valid(dsib_si_uart_rx_valid),
    .packet_valid(dsib_packet_accept),
    .suj_z_id(suj_z_id),
    .dsib_z_si_present(dsib_z_si_present),
    .suj_z_pot1(suj_z_pot1),
    .suj_z_pot2(suj_z_pot2)
);

// dsib_si_present is detected by at least one valid dSIB-Si RX packet received in a 100 ms window.
localparam[22:0] DSIB_PRESENT_WINDOW_LAST = 23'd4915199; // 100 ms at 49.152 MHz

reg[22:0] dsib_present_window_count = 23'd0;
reg[15:0] dsib_present_packet_count = 16'd0;

always @(posedge sysclk) begin
    if (dsib_present_window_count == DSIB_PRESENT_WINDOW_LAST) begin
        dsib_present_window_count <= 23'd0;
        dsib_si_present <= (dsib_present_packet_count != 16'd0) || dsib_packet_accept;
        dsib_present_packet_count <= 16'd0;
    end else begin
        dsib_present_window_count <= dsib_present_window_count + 23'd1;
        if (dsib_packet_accept && (dsib_present_packet_count != 16'hffff)) begin
            dsib_present_packet_count <= dsib_present_packet_count + 16'd1;
        end
    end
end

// --------------------------------------------------------------------------
// rdata mux
// --------------------------------------------------------------------------

wire[31:0] reg_rdata_prom_qla; // reads from QLA prom
wire[31:0] reg_rdata_chan0;    // 'channel 0' is a special axis that contains various board I/Os
wire reg_rwait_chan0;
wire[31:0] reg_rdata_motor_control;
reg[31:0] reg_rdata_main;
reg[31:0] reg_rdata_board_specific;
wire[31:0] reg_rdata_databuf;
wire reg_rwait_databuf;
reg [31:0] reg_espm_bram;

always @(*) begin
    case (reg_raddr[15:12])
        `ADDR_PROM_QLA: {reg_rdata, reg_rwait} = {reg_rdata_prom_qla, 1'b0};
        `ADDR_DATA_BUF: {reg_rdata, reg_rwait} = {reg_rdata_databuf, reg_rwait_databuf};
        `ADDR_MOTOR_CONTROL: {reg_rdata, reg_rwait} = {reg_rdata_motor_control, 1'b0};
        `ADDR_ESPM: {reg_rdata, reg_rwait} = {reg_espm_bram, 1'b0};
        `ADDR_BOARD_SPECIFIC: {reg_rdata, reg_rwait} = {reg_rdata_board_specific, 1'b0};
        `ADDR_MAIN: {reg_rdata, reg_rwait} = (reg_raddr[7:4]==4'd0) ? {reg_rdata_chan0, reg_rwait_chan0} : {reg_rdata_main, 1'b0};
        default: {reg_rdata, reg_rwait} = {32'b0, 1'b0};
    endcase
end


// --------------------------------------------------------------------------
// PWM timing
// --------------------------------------------------------------------------

wire[10:0] counter_unfolded; // 0..2048. The on-time is symmetrical around 1024.
wire pwm_cycle_start; // Assert for one pwmclk at beginning of a PWM cycle.
// Assert for one pwmclk to start feedback calculation. The calucation takes
// <10 pwmclk cycles. It has to finish before the next PWM cycle starts.
wire feedback_calculation_start;
wire adc_data_ready; // Latch the ADC shift registers when this is asserted.

PwmAdcTiming PwmAdcTiming_instance
(
    .clk(pwmclk),
    .sysclk(sysclk),
    .adc_sck(adc_sck),
    .adc_cnv(CONV_ADC),
    .adc_data_ready(adc_data_ready),
    .pwm_cycle_start(pwm_cycle_start),
    .feedback_calculation_start(feedback_calculation_start),
    .counter_unfolded(counter_unfolded),
    .adc_sdi(SDI_ADC),
    .reg_waddr(reg_waddr),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen)
);

// --------------------------------------------------------------------------
// Motor channels
// --------------------------------------------------------------------------

// Both current-feedback variants are staged into sysclk in MotorChannelDRAC
// before reaching the register mux. The PWM-local raw sample remains private to
// the motor-control loop.
wire[15:0] cur_fb[1:10];
wire[15:0] cur_fb_filtered[1:10];
wire cur_fb_raw;         // 1 -> send cur_fb (instead of cur_fb_filtered) to PC
wire [15:0] pot_data;

wire[15:0] cur_cmd_fb[1:10]; // current setpoint
wire[3:0] ctrl_mode[1:10];   // Control mode per channel

// reg_rdata_motor_control_channel[i] for each channel are driven as zeros when the channel is not selected. So you can or them together.
wire [31:0] reg_rdata_motor_control_channel [1:10];
assign reg_rdata_motor_control = reg_rdata_motor_control_channel[1] | reg_rdata_motor_control_channel[2] | reg_rdata_motor_control_channel[3] | reg_rdata_motor_control_channel[4] | reg_rdata_motor_control_channel[5] | reg_rdata_motor_control_channel[6] | reg_rdata_motor_control_channel[7] | reg_rdata_motor_control_channel[8] | reg_rdata_motor_control_channel[9] | reg_rdata_motor_control_channel[10];

wire [31:0] motor_status [1:10];

// mapping from channel number to hardware channel number.
// each DRV8432 chip has two channels, so there are 5 DRV8432 chips.
wire [2:0] channel_to_motor_driver [1:10];
assign channel_to_motor_driver[8] = 1;
assign channel_to_motor_driver[9] = 1;
assign channel_to_motor_driver[10] = 2;
assign channel_to_motor_driver[1] = 2;
assign channel_to_motor_driver[5] = 3;
assign channel_to_motor_driver[2] = 3;
assign channel_to_motor_driver[6] = 4;
assign channel_to_motor_driver[3] = 4;
assign channel_to_motor_driver[7] = 5;
assign channel_to_motor_driver[4] = 5;

wire [1:10] motor_channel_fault; // 1 if any fault is asserted.
wire [1:10] motor_channel_clear_fault; // 1 to clear fault state.
wire [1:10] motor_channel_enable_requested; // PC requested to enable channel.


genvar k;
generate
    for (k = 1; k < 11; k = k + 1) begin : mchan_loop
        MotorChannelDRAC #(.CHANNEL(k)) MotorChannel_instance
        (
            .sysclk(sysclk),
            .pwmclk(pwmclk),
            .reg_raddr(reg_raddr),
            .reg_waddr(reg_waddr),
            .reg_wdata(reg_wdata),
            .reg_wen(reg_wen),
            .reg_rdata(reg_rdata_motor_control_channel[k]),
            .cur_fb(cur_fb[k]),
            .cur_fb_filtered(cur_fb_filtered[k]),
            .cur_cmd_fb(cur_cmd_fb[k]),
            .control_mode(ctrl_mode[k]),
            .adc_sck(adc_sck),
            .adc_sdo(ADC_CUR_SDO[k]),
            .adc_data_ready(adc_data_ready),
            .feedback_calculation_start(feedback_calculation_start),
            .otw_n(OTWn[channel_to_motor_driver[k]]),
            .fault_n(FAULTn[channel_to_motor_driver[k]]),
            .counter_unfolded(counter_unfolded),
            .pwm_cycle_start(pwm_cycle_start),
            .pwm_p(PWM_P[k]),
            .pwm_n(PWM_N[k]),
            .clear_disable(motor_channel_clear_fault[k]),
            .safety_amp_disable(motor_channel_fault[k]),
            .motor_status(motor_status[k]),
            .enable_pin(RESETn[k]),
            .enable_requested(motor_channel_enable_requested[k])
        );
    end
endgenerate


// --------------------------------------------------------------------------
// Power control
// --------------------------------------------------------------------------

wire espm_comm_good; // RX from ESPM is good
wire esii_escc_comm_good; // ESII/ESCC -> ESPM is good. Invalid when espm_comm_good is 0.
reg preload_good; // Encoder preload is valid.
wire mv_good; // 48V is within +-10% of nominal.
// All interlocks must be 1 to enable any motor channel.
wire [4:0] interlocks =
    {preload_good, esii_escc_comm_good, espm_comm_good, mv_good, ~wdog_timeout};
wire any_amp_enable_pending; // 1 if PC requested to enable any motor channel but it is not enabled yet because of interlocks.

PowerControl #(.NUM_INTERLOCKS(5)) PowerControl_instance
(
    .sysclk(sysclk),
    .reg_waddr(reg_waddr),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .interlocks(interlocks),
    .motor_channel_fault(motor_channel_fault),
    .motor_channel_clear_fault(motor_channel_clear_fault),
    .motor_channel_enable_pin(RESETn),
    .motor_channel_enable_requested(motor_channel_enable_requested),
    .pwr_enable(MV_EN),
    .wdog_clear(wdog_clear)
);

// --------------------------------------------------------------------------
// BoardRegs
// --------------------------------------------------------------------------

wire mv_amp_disable;

wire[31:0] reg_digin;     // Digital I/O register
// This board has no temperature-sensor source. XST previously tied the
// undriven net low; make that implemented behavior explicit.
wire[15:0] tempsense = 16'd0;
wire[15:0] reg_databuf;   // Data collection status
wire is_ecm;
wire has_suj_pots;

wire[3:0] reg_status4 = {preload_good, ESPMV_GOOD, esii_escc_comm_good, espm_comm_good};
BoardRegsDRAC chan0(
    .sysclk(sysclk),
    .pwr_enable(MV_EN),
    .relay_on(RELAY_EN),
    .relay(RELAY_GOODn),
    .mv_good(mv_good),
    .mv_amp_disable(mv_amp_disable),
    .safety_fb(SAFETY_CHAIN_GOOD),
    .board_id(board_id),
    .temp_sense({(blk_rt_rd ? reg_databuf : 16'd0), tempsense}),
    .is_ecm(is_ecm),
    .has_suj_pots(has_suj_pots),
    .dsib_si_present(dsib_si_present),
    .dsib_z_si_present(dsib_z_si_present),
    .essj_present(suj_essj_status[0]),
    .cur_fb_raw(cur_fb_raw),
    .reg_status4(reg_status4),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_rwait(reg_rwait_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .reg_digin(reg_digin),
    .wdog_timeout(wdog_timeout)
);

// --------------------------------------------------------------------------
// Sample data for block read
// --------------------------------------------------------------------------

reg [5:0] espm_bram_raddr;
reg [31:0] espm_bram_rdata;
wire crc_good_espm_sysclk;
reg [31:0] timestamp_espmcomm;
reg [31:0] timestamp_espmcomm_counter;
reg espm_bram_update_inhibit;
reg blk_rt_rd_delay;
wire blk_rt_rd_falling_edge = blk_rt_rd_delay & ~blk_rt_rd;

always @(posedge sysclk) begin
    timestamp_espmcomm_counter <= timestamp_espmcomm_counter + 'b1;
    blk_rt_rd_delay <= blk_rt_rd;
    if (req_blk_rt_rd) espm_bram_update_inhibit <= 'b1;
    if (blk_rt_rd_falling_edge) espm_bram_update_inhibit <= 'b0;
end

assign timestamp = timestamp_espmcomm;

// --------------------------------------------------------------------------
// Data Buffer
// --------------------------------------------------------------------------
reg pwm_cycle_start_toggle_pwmclk;
always @ (posedge pwmclk) pwm_cycle_start_toggle_pwmclk <= pwm_cycle_start_toggle_pwmclk ^ pwm_cycle_start;
reg [2:0] pwm_cycle_start_sync_sysclk;
always @ (posedge sysclk) pwm_cycle_start_sync_sysclk <= {pwm_cycle_start_sync_sysclk[1:0], pwm_cycle_start_toggle_pwmclk};
wire pwm_cycle_start_sysclk = pwm_cycle_start_sync_sysclk[2] ^ pwm_cycle_start_sync_sysclk[1];

wire[3:0] data_channel;

DataBuffer data_buffer(
    .clk(sysclk),
    // data collection interface
    .cur_fb_wen(pwm_cycle_start_sysclk),
    .cur_fb(cur_fb[data_channel]),
    .chan(data_channel),
    // cpu interface
    .reg_waddr(reg_waddr),          // write address
    .collect_bit(reg_wdata[30]),    // collect bit
    .reg_wdata(reg_wdata[15:0]),    // write data
    .reg_wen(reg_wen),              // write enable
    .reg_raddr(reg_raddr),          // read address
    .reg_rdata(reg_rdata_databuf),  // read data
    .reg_rwait(reg_rwait_databuf),  // read wait state
    // status and timestamp
    .databuf_status(reg_databuf),   // status for real-time block read
    .ts(timestamp)                  // timestamp
);

// --------------------------------------------------------------------------
// ESPM interface
// --------------------------------------------------------------------------

reg [31:0] rdata_pos [1:7]; // encoder position
reg [31:0] rdata_pot [1:7]; // pot
reg [31:0] rdata_misc[1:5];
assign esii_escc_comm_good = rdata_misc[2][1];
assign is_ecm = rdata_misc[2][0]; // 1 if ECM, 0 if PSM
assign pot_data = reg_raddr[7:4] > 7 ? 16'hcccc : {4'b0, rdata_pot[reg_raddr[7:4]][17:6]};
assign reg_digin = rdata_misc[1]; // buttons



// --------------------------------------------------------------------------
// TX to ESPM
// --------------------------------------------------------------------------

// Sends the content of espm_tx_ram to the ESPM all the time.
// Except quadlet 'h10, which is for detecting loss of encoder preload due to ESPM reset.

(* KEEP = "TRUE", EQUIVALENT_REGISTER_REMOVAL = "NO" *)
reg sysclk_div2 = 1'b0;
assign lvds_tx_clk = sysclk_div2;
wire [9:0] espm_tx_tdata_sel;
reg [31:0] espm_tx_tdata;
wire espm_tx_pkt_start;
reg preload_set_espm_tx_pulse;

always @(posedge sysclk) begin
    sysclk_div2 <= ~sysclk_div2;
end

ESPMTX espm_tx (
    .clock(lvds_tx_clk),
    .tdata(espm_tx_tdata),
    .page(16'b0),
    .length(10'd64),
    .tdata_sel(espm_tx_tdata_sel),
    .pkt_start(espm_tx_pkt_start),
    .tdat(LVDS_TDAT)
);

reg [31:0] espm_tx_ram [0:63];

initial espm_tx_ram[1] = 'h3c0b3c0b; // arm LED color

always @(posedge sysclk) begin
    if (reg_wen && reg_waddr[15:12] == `ADDR_ESPM) begin
        espm_tx_ram[reg_waddr[5:0]] <= reg_wdata;
    end
end

always @(posedge lvds_tx_clk) begin
    if (espm_tx_pkt_start) begin
        preload_count_prev <= preload_count;
        preload_set_espm_tx_pulse <= preload_count != preload_count_prev;
    end

    case (espm_tx_tdata_sel[5:0])
        'h10: espm_tx_tdata <= {31'b0, preload_set_espm_tx_pulse};
        default: espm_tx_tdata <= espm_tx_ram[espm_tx_tdata_sel[5:0]];
    endcase
end

// --------------------------------------------------------------------------
// RX from ESPM
// --------------------------------------------------------------------------

// Pre-CRC data are dumped into espm_bram_pre_crc. Once CRC is checked, data
// are copied to espm_bram and espm_bram2. espm_bram is read by the sampler
// and espm_bram2 is used for debugging.

wire [31:0] rdata_espm;
wire  [9:0] rdata_sel_espm;
wire        load_rdata_espm;
wire        crc_good_espm;
wire        eof_espm;
reg  [31:0] crc_err_count = 32'd0;
reg  [31:0] crc_good_count = 32'd0;
reg  [9:0] crc_good_count_prev = 'b1;
wire crc_err_espm = eof_espm && !crc_good_espm;
wire crc_err_espm_sysclk;


reg espm_comm_wdt_fault;
assign espm_comm_good = ~espm_comm_wdt_fault;
reg [18:0] espm_comm_wdt_clkdiv;
always @(posedge sysclk) begin
    espm_comm_wdt_clkdiv = espm_comm_wdt_clkdiv + 19'd1;
    if (crc_good_espm_sysclk) crc_good_count <= crc_good_count + 32'd1;
    if (crc_err_espm_sysclk) crc_err_count <= crc_err_count + 32'd1;
    if (espm_comm_wdt_clkdiv == 'd0) begin // 10 ms
        crc_good_count_prev <= crc_good_count[9:0];
        espm_comm_wdt_fault <= crc_good_count[9:0] == crc_good_count_prev;
    end
end

ESPMRX espm_rx(
    // Input
    .clock(LVDS_RCLK),            // received clock from ESPM
    .rdat(LVDS_RDAT),             // serial data in

    // Output
    .rdata(rdata_espm),
    .load_rdata(load_rdata_espm),
    .rdata_sel(rdata_sel_espm),
    .crc_good(crc_good_espm),
    .eof(eof_espm)
);

localparam ESPM_BRAM_SIZE = 'd64;
reg [31:0] espm_bram_pre_crc [0:ESPM_BRAM_SIZE - 1];
reg [31:0] espm_bram_pre_crc_wdata;
reg [5:0] espm_bram_pre_crc_waddr;
reg espm_bram_pre_crc_we;

always @(posedge LVDS_RCLK) begin
    if (espm_bram_pre_crc_we) espm_bram_pre_crc[espm_bram_pre_crc_waddr] <= espm_bram_pre_crc_wdata;
    if (load_rdata_espm) begin
        espm_bram_pre_crc_wdata <= rdata_espm;
        espm_bram_pre_crc_waddr <= rdata_sel_espm[5:0];
        espm_bram_pre_crc_we <= 1'b1;
    end else begin
        espm_bram_pre_crc_we <= 1'b0;
    end
end

reg [31:0] espm_bram [0:ESPM_BRAM_SIZE - 1];
reg [31:0] espm_bram2 [0:ESPM_BRAM_SIZE - 1];
reg [5:0] espm_bram_waddr;
reg [31:0] espm_bram_wdata;
reg [5:0] espm_bram_pre_crc_raddr;
reg espm_bram_we;
reg [95:0] suj_essj_adc;
reg [1:0] suj_essj_status;
cdc_pulse crc_good_espm_cdc (LVDS_RCLK, crc_good_espm, sysclk, crc_good_espm_sysclk);
cdc_pulse crc_err_espm_cdc (LVDS_RCLK, crc_err_espm, sysclk, crc_err_espm_sysclk);
reg copy_state;

always @(posedge sysclk) begin
    if (espm_bram_we) begin
        espm_bram[espm_bram_waddr] <= espm_bram_wdata;
        espm_bram2[espm_bram_waddr] <= espm_bram_wdata;
    end
    espm_bram_wdata <= espm_bram_pre_crc[espm_bram_pre_crc_raddr];
    espm_bram_rdata <= espm_bram[espm_bram_raddr];
    reg_espm_bram <= espm_bram2[reg_raddr[5:0]];
    espm_bram_waddr <= espm_bram_pre_crc_raddr;
    case (copy_state)
        0: begin
            if (crc_good_espm_sysclk && (~espm_bram_update_inhibit)) begin
                copy_state <= 'b1;
                espm_bram_we <= 'b1;
                timestamp_espmcomm <= timestamp_espmcomm_counter;
            end
        end
        1: begin
            espm_bram_pre_crc_raddr <= espm_bram_pre_crc_raddr + 6'b1;
            if (espm_bram_waddr == ESPM_BRAM_SIZE - 'b1) begin
                espm_bram_we <= 'b0;
                copy_state <= 'b0;
                espm_bram_pre_crc_raddr <= 6'b0;
            end

            if (espm_bram_waddr[2:0] != 'b0) begin
                case (espm_bram_waddr[5:3])
                    `ESPM_POS_DATA: rdata_pos[espm_bram_waddr[2:0]] <= espm_bram_wdata;
                    `ESPM_POT_DATA: rdata_pot[espm_bram_waddr[2:0]] <= espm_bram_wdata;
                endcase
            end
            case (espm_bram_waddr)
                `ADDR_SWITCH: rdata_misc[1] <= espm_bram_wdata;  // switch
                `ADDR_ESII: rdata_misc[2] <= espm_bram_wdata;  // esii status
                `ADDR_INST_MODEL: rdata_misc[4] <= espm_bram_wdata;  // instrument ID
                `ADDR_INST_ID:    rdata_misc[5] <= espm_bram_wdata;  // instrument ID
                `ADDR_ESPM_PRELOAD_VALID: preload_good <= espm_bram_wdata[0];
                `ADDR_SUJ_ADC0: suj_essj_adc[31:0] <= espm_bram_wdata;
                `ADDR_SUJ_ADC1: suj_essj_adc[63:32] <= espm_bram_wdata;
                `ADDR_SUJ_ADC2: suj_essj_adc[95:64] <= espm_bram_wdata;
                `ADDR_SUJ_STATUS: suj_essj_status <= espm_bram_wdata[1:0];
            endcase
        end
    endcase
end


// --------------------------------------------------------------------------
// Encoder preload
// --------------------------------------------------------------------------

// ESPM has a constant preload of midrange. When power cycled, the encoder
// count resets. We maintain the preload here. Therefore, we must know when
// ESPM is reset, so we can invalidate the preload. We do this by setting a
// register in ESPM to 1 when we preload the encoder here. When ESPM is reset,
// it will clear this register. We use this register as an interlock, which
// will turn off the motor axes and prevent them from turning on until the
// preload is valid.

reg [23:0] encoder_preload [1:7];
reg [23:0] encoder_preload_offset [1:7];
reg [1:7] encoder_overflow;

integer encoder_preload_i;
initial begin
    for (encoder_preload_i = 1; encoder_preload_i < 8; encoder_preload_i = encoder_preload_i + 1) begin
        encoder_preload[encoder_preload_i] = `ENC_MIDRANGE;
        encoder_preload_offset[encoder_preload_i] = 'b0;
    end
end

reg [4:0] preload_count;
reg [4:0] preload_count_prev;
wire [23:0] pos_plus_preload [1:7];
genvar pos_i;
generate
for (pos_i = 1; pos_i < 8; pos_i = pos_i+1) begin : plus_loop
    assign pos_plus_preload[pos_i] = rdata_pos[pos_i][23:0] + encoder_preload_offset[pos_i];
end
endgenerate

integer encoder_overflow_i;
always @(posedge sysclk)
begin
    if (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_ENC_LOAD)) begin
        encoder_preload[reg_waddr[7:4]] <= reg_wdata[23:0];
        encoder_preload_offset[reg_waddr[7:4]] <= reg_wdata[23:0] - rdata_pos[reg_waddr[7:4]][23:0];
        preload_count <= preload_count + 5'b1;
        encoder_overflow[reg_waddr[7:4]] <= 'b0;
    end else begin
        for (encoder_overflow_i = 1; encoder_overflow_i < 8; encoder_overflow_i = encoder_overflow_i + 1) begin
            if ((pos_plus_preload[encoder_overflow_i][23:12] == 'h0) ||
                (pos_plus_preload[encoder_overflow_i][23:12] == 'hfff)) begin
                encoder_overflow[encoder_overflow_i] <= 'b1;
            end
        end
    end
end

// --------------------------------------------------------------------------
// MV
// --------------------------------------------------------------------------

wire [15:0] mv_adc_out;
reg[15:0] mv;
reg[15:0] mv_sysclk;
reg mv_good_pwm;
localparam [15:0] MV_MAX = 16'd40227; // 48V + 4.8V
localparam [15:0] MV_MIN = 16'd32913; // 48V - 4.8V
assign mv_good = mv_good_pwm;
AD4008 mv_adc
(
    .sck(adc_sck),
    .sdo(ADC_MV_SDO),
    .out(mv_adc_out)
);
always @(posedge pwmclk) begin
    if (adc_data_ready) begin
        mv <= mv_adc_out[15:0];
        // Evaluate the same sample captured into mv so the power-interlock
        // response is unchanged; only the diagnostic word crosses to sysclk.
        mv_good_pwm <= (mv_adc_out[15:0] < MV_MAX) &&
                       (mv_adc_out[15:0] > MV_MIN);
    end
end
always @(posedge sysclk) begin
    mv_sysclk <= mv;
end

// --------------------------------------------------------------------------
// ADDR_BOARD_SPECIFIC registers
// --------------------------------------------------------------------------
always @(*)
begin
    case (reg_raddr[11:0])
        // ADDR_BOARD_SPECIFIC 4'hB
        'h000: reg_rdata_board_specific = crc_err_count;
        'h001: reg_rdata_board_specific = crc_good_count;
        'h002: reg_rdata_board_specific = mv_sysclk;
        'h004: reg_rdata_board_specific = {22'b0, OTWn, FAULTn};
        'h010: reg_rdata_board_specific = rdata_misc[2]; // esii status
        'h012: reg_rdata_board_specific = rdata_misc[4]; // instrument model
        'h013: reg_rdata_board_specific = rdata_misc[5]; // instrument version
        'h020: reg_rdata_board_specific = {reg_databuf, tempsense};      // TODO: Is this still needed?
        'h021: reg_rdata_board_specific = reg_digin;                     // TODO: Is this still needed?
        'h030: reg_rdata_board_specific = {suj_z_id, suj_z_pot2, 2'b0, dsib_z_si_present, dsib_si_present, suj_z_pot1};
        'hfff: reg_rdata_board_specific = 'h100; // development build number
        default: reg_rdata_board_specific = 'hcccc;
    endcase
end

// --------------------------------------------------------------------------
// Main registers
// --------------------------------------------------------------------------

// SUJ real-time register map:
// suj_pots[1]: [31] z_valid [30] dsib_z_si_present [29] dsib_si_present [28] reserved (0),
//              [27:16] z_pot2,
//              [15:12] suj_z_id,
//              [ 11:0] z_pot1
// suj_pots[N]: [31] r_valid [30] adc_valid [29] essj_present [28] reserved (0)
// (N=2..5)     [27:16] rotN_pot2,
//              [15:12] reserved (0000),
//              [ 11:0] rotN_pot1

wire suj_z_valid;   // SUJ Z axis pot data valid (from dSIB-Z-Si to dSIB-Si to FPGA via UART)
wire suj_r_valid;   // SUJ rotary axis pot data valid (from ESSJ to FPGA via LVDS)
assign suj_z_valid = dsib_si_present & dsib_z_si_present;
assign suj_r_valid = suj_essj_status[0] & suj_essj_status[1];

wire[31:0] suj_pots[1:NUM_EXTRA];
assign suj_pots[1] = {suj_z_valid, dsib_z_si_present, dsib_si_present, 1'b0, suj_z_pot2,
                      suj_z_id, suj_z_pot1};
assign suj_pots[2] = {suj_r_valid, suj_essj_status, 1'b0, suj_essj_adc[59:48],
                      4'b0, suj_essj_adc[11:0]};
assign suj_pots[3] = {suj_r_valid, suj_essj_status, 1'b0, suj_essj_adc[71:60],
                      4'b0, suj_essj_adc[23:12]};
assign suj_pots[4] = {suj_r_valid, suj_essj_status, 1'b0, suj_essj_adc[83:72],
                      4'b0, suj_essj_adc[35:24]};
assign suj_pots[5] = {suj_r_valid, suj_essj_status, 1'b0, suj_essj_adc[95:84],
                      4'b0, suj_essj_adc[47:36]};

always @(*) begin
    case (reg_raddr[3:0])
        `OFF_ADC_DATA: reg_rdata_main = {pot_data, cur_fb_raw ? cur_fb[reg_raddr[7:4]] : cur_fb_filtered[reg_raddr[7:4]]};
        `OFF_MOTOR_CTRL: reg_rdata_main = {4'd0, ctrl_mode[reg_raddr[7:4]], 8'd0, cur_cmd_fb[reg_raddr[7:4]]};
        `OFF_EXTRA_DATA: reg_rdata_main = suj_pots[reg_raddr[7:4]];
        `OFF_ENC_LOAD: reg_rdata_main = encoder_preload[reg_raddr[7:4]];
        `OFF_ENC_DATA: reg_rdata_main = {7'b0, encoder_overflow[reg_raddr[7:4]], rdata_pos[reg_raddr[7:4]][23:0] + encoder_preload_offset[reg_raddr[7:4]]};
        `OFF_PER_DATA: reg_rdata_main = espm_bram_rdata;
        `OFF_QTR1_DATA: reg_rdata_main = espm_bram_rdata;
        `OFF_QTR5_DATA: reg_rdata_main = espm_bram_rdata;
        `OFF_RUN_DATA: reg_rdata_main = espm_bram_rdata;
        `OFF_MOTOR_STATUS: reg_rdata_main = motor_status[reg_raddr[7:4]];
        default: reg_rdata_main = 'hcccc;
    endcase
end

always @(*) begin
    case (reg_raddr[7:0])
        `include "case_main_addr_to_espm_addr.v"
    endcase
end

reg suj_brake_release_n_reg = 1'bz;
assign suj_brake_release_n = suj_brake_release_n_reg;
always @(posedge sysclk) begin
    if (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == 4'd0) & (reg_waddr[3:0] == `REG_DIGIOUT)) begin
        if (reg_wdata[8]) suj_brake_release_n_reg <= reg_wdata[0] ? 1'bz : 1'b0;
    end
end


// --------------------------------------------------------------------------
// Front panel LEDs
// --------------------------------------------------------------------------


reg blink_0_5hz;
reg [25:0] blink_counter;
reg blink_ovf;
always @(posedge sysclk) begin
    blink_counter <= blink_counter + 26'd1;
    blink_ovf <= blink_counter == 26'd49_152_000 - 26'd1;
    if (blink_ovf) begin
        blink_counter <= 'd0;
        blink_0_5hz <= ~blink_0_5hz;
    end
end

reg [7:0] led_red;
reg [7:0] led_green;
reg [7:0] led_blue;
wire [2:0] led_address;

always @(posedge sysclk) begin
    case (led_address)
        'd1: begin // fpga prog ok
            led_red <= 8'd0;
            led_green <= blink_0_5hz ? 8'd50 : 8'd8;
            led_blue <= 8'd0;
        end
        'd3: begin // ESPM comm
            if (espm_comm_good) begin
                led_red <= esii_escc_comm_good ? 8'd0 : 8'd90;
                led_green <= 8'd50;
                led_blue <= 8'd0;
            end else begin
                led_red <= 8'd0;
                led_green <= 8'd0;
                led_blue <= 8'd0;
            end
        end
        'd4: begin // eth/fw
            led_red <= 8'd0;
            led_green <= 8'd0;
            led_blue <= 8'd0;
        end
        'd5: begin // 48v
            if (MV_EN && !SAFETY_CHAIN_GOOD) begin
                led_red <= 8'd60;
                led_green <= 8'd0;
                led_blue <= 8'd0;
            end
            else if (MV_EN && !mv_good) begin
                led_red <= blink_0_5hz ? 8'd60 : 8'd0;
                led_green <= 8'd0;
                led_blue <= 8'd0;
            end
            else begin
                led_red <= 8'd0;
                led_green <= MV_EN ? 8'd50 : 8'd0;
                led_blue <= 8'd0;
            end
        end
        'd6: begin // motor driver
            if (|motor_channel_fault) begin
                led_red <= 8'd60;
                led_green <= 8'd0;
                led_blue <= 8'd0;
            end else if (|(motor_channel_enable_requested ^ RESETn)) begin
                led_red <= blink_0_5hz ? 8'd60 : 8'd0;
                led_green <= 8'd0;
                led_blue <= 8'd0;
            end else if (|RESETn) begin
                led_red <= 8'd0;
                led_green <= 8'd100;
                led_blue <= 8'd20;
            end else begin
                led_red <= 8'd0;
                led_green <= 8'd0;
                led_blue <= 8'd0;
            end
        end
        default: begin // 0, 2, unused
            led_red <= 8'd0;
            led_green <= 8'd0;
            led_blue <= 8'd0;
        end
    endcase
end

ws2811 #(.NUM_LEDS(7),.SYSTEM_CLOCK(49_152_000)) ws2811_instance (
    .clk(sysclk),
    .address(led_address),
    .red_in(led_red),
    .blue_in(led_blue),
    .green_in(led_green),
    .DO(FRONT_PANEL_LED)
);

// --------------------------------------------------------------------------
// QLA prom 25AA128
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

wire qla_prom_mosi;
wire qla_prom_sclk;
assign IO1[2] = qla_prom_mosi;
assign IO1[3] = qla_prom_sclk;
wire qla_prom_busy;

QLA25AA128 prom_qla(
    .clk(sysclk),

    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom_qla),
    .reg_wdata(reg_wdata),

    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),

    .cs_wait(1'b0),          // no additional wait

    // spi interface
    .prom_mosi(qla_prom_mosi),
    .prom_miso(IO1[1]),
    .prom_sclk(qla_prom_sclk),
    .prom_cs(IO1[4]),
    .other_busy(1'b0),
    .this_busy(qla_prom_busy)
);

// --------------------------------------------------------------------------
// ESPM 6V power control
// --------------------------------------------------------------------------

reg espmv_en_reg = 'b1;
assign ESPMV_EN = espmv_en_reg;

always @(posedge sysclk)
begin
    if (reg_waddr[15:12]==`ADDR_BOARD_SPECIFIC && reg_wen) begin
        case (reg_waddr[11:0])
            'h102: espmv_en_reg <= reg_wdata[0];
        endcase
    end
end


endmodule
