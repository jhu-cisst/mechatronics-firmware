/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * This module contains common code for the QLA and used with all FPGA versions
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
    input wire[3:0]  io_extra,

    // Read/Write bus
    input wire[15:0]  reg_raddr_non_sample,
    input wire[15:0]  reg_waddr,
    output wire[31:0] reg_rdata,
    input wire[31:0]  reg_wdata,
    input wire reg_wen,
    input wire blk_wen,
    input wire blk_wstart,

    // Block write support
    output wire bw_write_en,
    output wire[7:0] bw_reg_waddr,
    output wire[31:0] bw_reg_wdata,
    output wire bw_reg_wen,
    output wire bw_blk_wen,
    output wire bw_blk_wstart,

    // Real-time write support
    input wire  rt_wen,
    input wire[3:0]  rt_waddr,
    input wire[31:0] rt_wdata,

    // Sampling support
    input wire sample_start,        // Start sampling read data
    output wire sample_busy,        // 1 -> data sampler has control of bus
    output wire[3:0] sample_chan,   // Channel for sampling
    input wire[5:0] sample_raddr,   // Address in sample_data buffer
    output wire[31:0] sample_rdata, // Output from sample_data buffer
    input wire sample_read,
    output wire[31:0] timestamp,    // Timestamp used when sampling

    // Watchdog support
    input wire wdog_period_led,     // 1 -> external LED displays wdog_period_status
    input wire[2:0] wdog_period_status,
    input wire wdog_timeout,        // watchdog timeout status flag
    output wire wdog_clear          // clear watchdog timeout (e.g., on powerup)
);

// outputs
wire MV_EN;
wire EXTRA_IO;
wire FRONT_PANEL_LED;
wire ESPMV_EN;
wire RELAY_EN;
wire LVDS_TCLK;
wire LVDS_TDAT;
wire SCLK_ADC;
wire SDI_ADC;
wire CONV_ADC;
wire[1:10] PWM_P;
wire[1:10] PWM_N;
wire[1:10] RESETn;

// inputs
wire SAFETY_CHAIN_GOOD;
wire RELAY_GOODn;
wire ESPMV_GOODn;
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
assign IO1[5] = EXTRA_IO;
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
assign ESPMV_GOODn = IO1[30];
assign ADC_CUR_SDO[4] = IO1[31];
assign IO1[32] = RELAY_EN;



assign IO2[1] = LVDS_TCLK;
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
assign IO2[14] = SCLK_ADC;
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


// --------------------------------------------------------------------------
// rdata mux
// --------------------------------------------------------------------------

wire[15:0]  reg_raddr_sample;
wire[15:0]  reg_raddr = sample_read ? reg_raddr_sample : reg_raddr_non_sample;

wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire[31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_prom_qla; // reads from QLA prom
wire[31:0] reg_rdata_eth;      // for eth memory access
wire[31:0] reg_rdata_fw;       // for fw memory access
wire[31:0] reg_rdata_ds;       // for DS2505 memory access
wire[31:0] reg_rdata_chan0;    // 'channel 0' is a special axis that contains various board I/Os
wire[31:0] reg_rdata_motor_control;
wire[31:0] reg_rdata_debug;
reg[31:0] reg_rdata_main;
reg[31:0] reg_rdata_board_specific;
wire[31:0] reg_rdata_espm_debug;
wire[31:0] reg_rdata_databuf;
wire[31:0] reg_rtable = 'b0;


assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                  ((reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                  ((reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom_qla) :
                  ((reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth) :
                  ((reg_raddr[15:12]==`ADDR_FW) ? (reg_rdata_fw) :
                  ((reg_raddr[15:12]==`ADDR_DS) ? (reg_rdata_ds) :
                  ((reg_raddr[15:12]==`ADDR_DATA_BUF) ? (reg_rdata_databuf) :
                  ((reg_raddr[15:12]==`ADDR_WAVEFORM) ? (reg_rtable) :
                  ((reg_raddr[15:12]==`ADDR_MOTOR_CONTROL) ? (reg_rdata_motor_control) :
                  ((reg_raddr[15:12]==`ADDR_ESPM) ? (reg_rdata_espm_debug) :
                  ((reg_raddr[15:12]==`ADDR_BOARD_SPECIFIC) ? (reg_rdata_board_specific) :
                  ((reg_raddr[7:4]==4'd0) ? reg_rdata_chan0 : reg_rdata_main)))))))))));

// --------------------------------------------------------------------------
// ADC clock output
// --------------------------------------------------------------------------

wire sclk_adc_internal;
wire adc_sck_ce;

ODDR2 #(
    .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1"
    .INIT(1'b0),    // Sets initial state of the Q output to 1'b0 or 1'b1
    .SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
) clock_forward_adc (
    .Q(SCLK_ADC),     // 1-bit DDR output data
    .C0(sclk_adc_internal),  // 1-bit clock input
    .C1(~sclk_adc_internal), // 1-bit clock input
    .CE(1'b1),      // 1-bit clock enable input
    .D0(1'b1), // 1-bit data input (associated with C0)
    .D1(1'b0), // 1-bit data input (associated with C1)
    .R(1'b0),   // 1-bit reset input
    .S(1'b0)   // 1-bit set input
);

// --------------------------------------------------------------------------
// PWM timing
// --------------------------------------------------------------------------

wire[10:0] counter_unfolded;
wire pwm_cycle_start;
wire feedback_calculation_start;
wire adc_data_ready;

PwmAdcTiming PwmAdcTiming_instance
(
    .clk(pwmclk),
    .sysclk(sysclk),
    .adc_sck(sclk_adc_internal),
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

wire[15:0] cur_fb[1:10];
wire[15:0] cur_fb_filtered[1:10];
wire[31:0] reg_adc_data;
wire [15:0] pot_data;

wire[15:0] cur_cmd_fb[1:10];

wire [31:0] reg_rdata_motor_control_channel [1:10];
assign reg_rdata_motor_control = reg_rdata_motor_control_channel[1] | reg_rdata_motor_control_channel[2] | reg_rdata_motor_control_channel[3] | reg_rdata_motor_control_channel[4] | reg_rdata_motor_control_channel[5] | reg_rdata_motor_control_channel[6] | reg_rdata_motor_control_channel[7] | reg_rdata_motor_control_channel[8] | reg_rdata_motor_control_channel[9] | reg_rdata_motor_control_channel[10];

wire [31:0] motor_status [1:10];

reg [16:0] channel_to_motor_driver [1:10];
initial channel_to_motor_driver[8] = 1;
initial channel_to_motor_driver[9] = 1;
initial channel_to_motor_driver[10] = 2;
initial channel_to_motor_driver[1] = 2;
initial channel_to_motor_driver[5] = 3;
initial channel_to_motor_driver[2] = 3;
initial channel_to_motor_driver[6] = 4;
initial channel_to_motor_driver[3] = 4;
initial channel_to_motor_driver[7] = 5;
initial channel_to_motor_driver[4] = 5;

wire [1:10] motor_channel_fault;
wire [1:10] motor_channel_clear_fault;
wire [1:10] motor_channel_enable_requested;


genvar k;
generate
    for (k = 1; k < 11; k = k + 1) begin
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
            .adc_sck(sclk_adc_internal),
            .adc_sdo(ADC_CUR_SDO[k]),
            .adc_cnv(CONV_ADC),
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
wire reg_rdata_power_control;

wire espm_comm_good;
wire esii_escc_comm_good;
wire mv_good;
wire [3:0] interlocks =
    {esii_escc_comm_good, espm_comm_good, mv_good, ~wdog_timeout};
wire any_amp_enable_pending;

PowerControl #(.NUM_INTERLOCKS(4)) PowerControl_instance
(
    .sysclk(sysclk),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .reg_rdata(reg_rdata_power_control),
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

wire[31:0] reg_status;    // Status register
wire[31:0] reg_digin;     // Digital I/O register
wire[15:0] tempsense;     // Temperature sensor
wire[15:0] reg_databuf;   // Data collection status
wire is_ecm;
wire[11:0] reg_status12 = {10'b0, interlocks[3:2]};
BoardRegsDRAC chan0(
    .sysclk(sysclk),
    .pwr_enable(MV_EN),
    .relay_on(RELAY_EN),
    .relay(RELAY_GOODn),
    .mv_good(mv_good),
    .mv_amp_disable(mv_amp_disable),
    .safety_fb(SAFETY_CHAIN_GOOD),
    .board_id(board_id),
    .temp_sense({reg_databuf, tempsense}),
    .is_ecm(is_ecm),
    .reg_status12(reg_status12),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .reg_status(reg_status),
    .reg_digin(reg_digin),
    .wdog_timeout(wdog_timeout)
);

// --------------------------------------------------------------------------
// Sample data for block read
// --------------------------------------------------------------------------

reg [5:0] espm_bram_raddr;
wire [31:0] espm_bram_rdata;

SampleDataAddressTranslation sampler
(
    .clk(sysclk),
    .doSample(sample_start),
    .isBusy(sample_busy),
    .blk_addr(sample_raddr),
    .blk_data(sample_rdata),
    .reg_raddr(reg_raddr_sample),
    .reg_rdata(reg_rdata),
    .timestamp(timestamp)
);

// --------------------------------------------------------------------------
// Write data for real-time block
// --------------------------------------------------------------------------

WriteRtData #(.NUM_MOTORS(10)) rt_write
(
    .clk(sysclk),
    .rt_write_en(rt_wen),       // Write enable
    .rt_write_addr(rt_waddr),   // Write address
    .rt_write_data(rt_wdata),   // Write data
    .bw_write_en(bw_write_en),
    .bw_reg_wen(bw_reg_wen),
    .bw_block_wen(bw_blk_wen),
    .bw_block_wstart(bw_blk_wstart),
    .bw_reg_waddr(bw_reg_waddr),
    .bw_reg_wdata(bw_reg_wdata)
);

// --------------------------------------------------------------------------
// ESPM interface
// --------------------------------------------------------------------------

reg [31:0] rdata_pos [1:7];
reg [31:0] rdata_pot [1:7];
reg [31:0] rdata_misc[1:5];
assign esii_escc_comm_good = rdata_misc[2][1];
assign is_ecm = rdata_misc[2][0];
assign pot_data = reg_raddr[7:4] > 7 ? 16'hcccc : {4'b0, rdata_pot[reg_raddr[7:4]][17:6]};
assign reg_digin = rdata_misc[1];



// --------------------------------------------------------------------------
// TX to ESPM
// --------------------------------------------------------------------------

wire lvds_tx_clk = sysclk; // sysclk required
reg lvds_tx_clk_en = 'b1;
reg [31:0] lvds_tx_data;
reg [5:0] lvds_tx_data_count = 'b0;
reg lvds_tx_state = 'b0;
reg lvds_tdat_reg;
assign LVDS_TDAT = lvds_tdat_reg;

always @(posedge lvds_tx_clk) begin
    if (reg_waddr[15:12]==`ADDR_BOARD_SPECIFIC && reg_wen) begin
    case (reg_waddr[11:0])
        'h101: begin
        lvds_tx_state <= 'b1;
        lvds_tx_data <= reg_wdata;
        lvds_tx_data_count <= 'b0;
        end
    endcase
    end
    if (lvds_tx_state == 'd1) begin
        lvds_tx_clk_en <= 'b1;
        lvds_tdat_reg <= lvds_tx_data[lvds_tx_data_count];
        lvds_tx_data_count <= lvds_tx_data_count + 'b1;
        if (lvds_tx_data_count == 'd32) begin
            lvds_tx_state <= 'd0;
            lvds_tx_clk_en <= 'b0;
            lvds_tdat_reg <= 'b0;
        end
    end
end

ODDR2 #(
    .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1"
    .INIT(1'b1), // Sets initial state of the Q output to 1'b0 or 1'b1
    .SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
) ODDR2_inst (
    .Q(LVDS_TCLK), // 1-bit DDR output data
    .C0(lvds_tx_clk), // 1-bit clock input
    .C1(~lvds_tx_clk), // 1-bit clock input
    .CE(lvds_tx_clk_en), // 1-bit clock enable input
    .D0(1'b1), // 1-bit data input (associated with C0)
    .D1(1'b0), // 1-bit data input (associated with C1)
    .R(1'b0), // 1-bit reset input
    .S(1'b0) // 1-bit set input
);

// --------------------------------------------------------------------------
// RX from ESPM
// --------------------------------------------------------------------------
wire [31:0] rdata_espm;
wire  [5:0] rdata_sel_espm;
wire        load_rdata_espm;
wire [31:0] framed_espm;
wire        crc_good_espm;
wire  [31:0] crc_err_count;
wire  [31:0] crc_good_count;
reg  [9:0] crc_good_count_prev = 'b1;
wire [1:0] dvrk_rx_cfsm;
reg skip_crc = 0;


reg espm_comm_wdt_fault;
assign espm_comm_good = ~espm_comm_wdt_fault;
reg [18:0] espm_comm_wdt_clkdiv;
always @(posedge sysclk) begin
    espm_comm_wdt_clkdiv = espm_comm_wdt_clkdiv + 'd1;
    if (espm_comm_wdt_clkdiv == 'd0) begin // 10 ms
        crc_good_count_prev <= crc_good_count[9:0];
        espm_comm_wdt_fault <= crc_good_count[9:0] == crc_good_count_prev;
    end
end

DvrkRx rx(
    // Input
    .clock(LVDS_RCLK),            // received clock from ESPM
    .rdat(LVDS_RDAT),             // serial data in

    // Output
	.rdata(rdata_espm[31:0]),
   .load_rdata(load_rdata_espm),
	.rdata_sel(rdata_sel_espm),
	.framed(framed_espm),
	.crc_good(crc_good_espm),
   .crc_err(crc_err_count),
   .crc_good_count(crc_good_count),
   .cfsm(dvrk_rx_cfsm),
   .skip_crc(skip_crc)
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
        espm_bram_pre_crc_waddr <= rdata_sel_espm;
        espm_bram_pre_crc_we <= 'b1;
    end else begin
        espm_bram_pre_crc_we <= 'b0;
    end
end

reg [31:0] espm_bram [0:ESPM_BRAM_SIZE - 1];
reg [5:0] espm_bram_waddr;
wire [31:0] espm_bram_wdata;
assign espm_bram_wdata = espm_bram_pre_crc[espm_bram_waddr];
reg espm_bram_we;
wire crc_good_sysclk;
cdc_pulse crc_good_espm_cdc (LVDS_RCLK, crc_good_espm, sysclk, crc_good_sysclk);
reg copy_state;

assign espm_bram_rdata = espm_bram[espm_bram_raddr];
assign reg_rdata_espm_debug = espm_bram[reg_raddr];

always @(posedge sysclk) begin
    if (espm_bram_we) espm_bram[espm_bram_waddr] <= espm_bram_wdata;
    case (copy_state)
        0: begin
            if (crc_good_sysclk) begin
                copy_state <= 'b1;
                espm_bram_waddr <= 'b0;
                espm_bram_we <= 'b1;
            end
        end
        1: begin
            espm_bram_waddr <= espm_bram_waddr + 1;
            if (espm_bram_waddr == ESPM_BRAM_SIZE - 1) begin
                espm_bram_we <= 'b0;
                copy_state <= 'b0;
            end

            if (espm_bram_waddr[2:0] != 'b0) begin
                case (espm_bram_waddr[5:3])
                    `ESPM_POS_DATA: rdata_pos[espm_bram_waddr[2:0]] <= espm_bram_wdata;
                    `ESPM_POT_DATA: rdata_pot[espm_bram_waddr[2:0]] <= espm_bram_wdata;
                endcase
            end else begin
                case (espm_bram_waddr)
                    `ADDR_SWITCH: rdata_misc[1] <= espm_bram_wdata;  // switch
                    `ADDR_ESII: rdata_misc[2] <= espm_bram_wdata;  // esii status
                    `ADDR_MISC: rdata_misc[3] <= espm_bram_wdata;  // adc current {cannula_vmon,P5V_lcl_vmon}
                    `ADDR_INST_MODEL: rdata_misc[4] <= espm_bram_wdata;  // instrument ID
					`ADDR_INST_ID:    rdata_misc[5] <= espm_bram_wdata;  // instrument ID
                endcase
            end
        end
    endcase
end


// --------------------------------------------------------------------------
// Encoder preload
// --------------------------------------------------------------------------

reg [23:0] encoder_preload [1:7];
reg [23:0] encoder_preload_offset [1:7];

integer encoder_preload_i;
initial begin
    for (encoder_preload_i = 1; encoder_preload_i < 8; encoder_preload_i = encoder_preload_i + 1) begin
        encoder_preload[encoder_preload_i] = `ENC_MIDRANGE;
        encoder_preload_offset[encoder_preload_i] = `ENC_MIDRANGE;
    end
end

always @(posedge sysclk)
begin
    if (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_ENC_LOAD)) begin
        encoder_preload[reg_waddr[7:4]] <= reg_wdata[23:0];
        encoder_preload_offset[reg_waddr[7:4]] <= reg_wdata[23:0] - rdata_pos[reg_waddr[7:4]];
    end
end

// --------------------------------------------------------------------------
// MV
// --------------------------------------------------------------------------

wire [31:0] mv_adc_out;
reg[15:0] mv;
integer mv_max = 36570 + 3657; // 48V + 4.8V
integer mv_min = 36570 - 3657; // 48V - 4.8V
assign mv_good = (mv < mv_max) && (mv > mv_min);
AD4008 mv_adc
(
    .sck(sclk_adc_internal),
    .sdo(ADC_MV_SDO),
    .data_ready(adc_data_ready),
    .out(mv_adc_out)
);
always @(posedge pwmclk) begin
    if (adc_data_ready) begin
        mv <= mv_adc_out[15:0];
    end
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
        'h002: reg_rdata_board_specific = mv;
        'h003: reg_rdata_board_specific = {is_ecm, esii_escc_comm_good, espm_comm_good, SAFETY_CHAIN_GOOD, ESPMV_GOODn};
        'h010: reg_rdata_board_specific = rdata_misc[2]; // esii status
        'h011: reg_rdata_board_specific = rdata_misc[3]; // adc current {cannula_vmon,P5V_lcl_vmon}
        'h012: reg_rdata_board_specific = rdata_misc[4]; // instrument model
        'h013: reg_rdata_board_specific = rdata_misc[5]; // instrument version
        'h020: reg_rdata_board_specific = {reg_databuf, tempsense};
        'h021: reg_rdata_board_specific = reg_digin;
        // 'h021: reg_rdata_board_specific = 'hffffffff;
        'hfff: reg_rdata_board_specific = 'h04400000; // development build number
        default: reg_rdata_board_specific = 'hcccc;
    endcase
end

// --------------------------------------------------------------------------
// Main registers
// --------------------------------------------------------------------------

always @(*) begin
    case (reg_raddr[3:0])
        `OFF_ADC_DATA: reg_rdata_main = {pot_data, cur_fb_filtered[reg_raddr[7:4]]};
        `OFF_DAC_CTRL: reg_rdata_main = {16'h0000, cur_cmd_fb[reg_raddr[7:4]]};
        `OFF_ENC_LOAD: reg_rdata_main = encoder_preload[reg_raddr[7:4]];
        `OFF_ENC_DATA: reg_rdata_main = rdata_pos[reg_raddr[7:4]][23:0] + encoder_preload_offset[reg_raddr[7:4]];
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

reg extra_io_reg = 'b1;
assign EXTRA_IO = extra_io_reg;
always @(posedge sysclk) begin
    if (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == 4'd0) & (reg_waddr[3:0] == `REG_DIGIOUT)) begin
        if (reg_wdata[8]) extra_io_reg <= reg_wdata[0];
    end
end


// --------------------------------------------------------------------------
// Front panel LEDs
// --------------------------------------------------------------------------


reg blink_0_5hz;
reg [25:0] blink_counter;
reg blink_ovf;
always @(posedge sysclk) begin
    blink_counter <= blink_counter + 'd1;
    blink_ovf <= blink_counter == 'd49_152_000 - 'd1;
    if (blink_ovf) begin
        blink_counter <= 'd0;
        blink_0_5hz <= ~blink_0_5hz;
    end
end

reg [7:0] led_red;
reg [7:0] led_green;
reg [7:0] led_blue;
wire [3:0] led_address;

always @(posedge sysclk) begin
    case (led_address)
        'd1: begin // 48v
            if (MV_EN && !SAFETY_CHAIN_GOOD) begin
                led_red <= 'd60;
                led_green <= 'd0;
                led_blue <= 'd0;
            end
            else if (MV_EN && !mv_good) begin
                led_red <= blink_0_5hz ? 'd60 : 'd0;
                led_green <= 'd0;
                led_blue <= 'd0;
            end
            else begin
                led_red <= 'd0;
                led_green <= MV_EN? 'd50 : 'd0;
                led_blue <= 'd0;
            end
        end
        'd3: begin // ESPM comm
            if (espm_comm_good) begin
                led_red <= 'd40;
                led_green <= 'd0;
                led_blue <= esii_escc_comm_good ? 'd40 : 'd0;
            end else begin
                led_red <= 'd0;
                led_green <= 'd0;
                led_blue <= 'd0;
            end
        end
        'd4: begin // eth/fw
            led_red <= 'd0;
            led_green <= 'd0;
            led_blue <= 'd0;
        end
        'd2: begin // motor driver
            if (|motor_channel_fault) begin
                led_red <= 'd60;
                led_green <= 'd0;
                led_blue <= 'd0;
            end else if (|(motor_channel_enable_requested ^ RESETn)) begin
                led_red <= blink_0_5hz ? 'd60 : 'd0;
                led_green <= 'd0;
                led_blue <= 'd0;
            end else if (|RESETn) begin
                led_red <= 'd0;
                led_green <= 'd50;
                led_blue <= 'd0;
            end else begin
                led_red <= 'd0;
                led_green <= 'd0;
                led_blue <= 'd0;
            end
        end
        'd0: begin // fpga prog ok
            led_red <= 'd0;
            led_green <= blink_0_5hz ? 'd15 : 'd8;
            led_blue <= 'd0;
        end
        default: begin // unused
            led_red <= 'd0;
            led_green <= 'd0;
            led_blue <= is_ecm ? 'd60 : 'd0;
        end
    endcase
end

ws2811 #(.NUM_LEDS(6),.SYSTEM_CLOCK(49_152_000)) ws2811_instance (
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

    // spi interface
    .prom_mosi(qla_prom_mosi),
    .prom_miso(IO1[1]),
    .prom_sclk(qla_prom_sclk),
    .prom_cs(IO1[4]),
    .other_busy('b0),
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
