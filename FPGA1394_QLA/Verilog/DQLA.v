/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2024 ERC CISST, Johns Hopkins University.
 *
 * This module contains code for the DQLA (dual QLA) interface
 *
 * Revision history
 *     12/12/22    Peter Kazanzides    Created from QLA.v
 */

`include "Constants.v"

module DQLA(
    // global clock
    input wire       sysclk,

    // 400k clock for temperature sensors
    input wire       clk400k,

    // ~12MHz clock for SPI to ADCs
    input wire       clkadc,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,

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

    // Timestamp
    output reg[31:0] timestamp,

    // Watchdog support
    input wire wdog_period_led,     // 1 -> external LED displays wdog_period_status
    input wire[2:0] wdog_period_status,
    input wire wdog_timeout,        // watchdog timeout status flag
    output wire wdog_clear          // clear watchdog timeout (e.g., on powerup)
);

    //******************* I/O pin mappings **************************

    // QLA EEPROM / IO-EXP
    // Assume that all boards define IO1[1]-IO1[4] the same (EEPROM interface)
    wire sclk1;
    wire miso1;
    wire mosi1;
    wire Q1_prom_CSn;
    wire Q2_prom_CSn;
    wire Q1_ioexp_CSn;
    wire Q2_ioexp_CSn;
    assign IO1[3] = sclk1;
    assign IO1[2] = mosi1;
    assign miso1 = IO1[1];
    assign IO1[28] = Q1_prom_CSn;
    assign IO1[4] = Q2_prom_CSn;
    assign IO1[31] = Q1_ioexp_CSn;
    assign IO1[15] = Q2_ioexp_CSn;

    // Incremental encoders
    wire[1:4] Q1_enc_a;
    wire[1:4] Q2_enc_a;
    wire[1:4] Q1_enc_b;
    wire[1:4] Q2_enc_b;
    assign Q1_enc_a = { IO2[22], IO2[24], IO2[26], IO2[28] };
    assign Q2_enc_a = { IO2[25], IO2[27], IO2[29], IO2[31] };
    assign Q1_enc_b = { IO2[30], IO2[32], IO2[34], IO2[36] };
    assign Q2_enc_b = { IO2[33], IO2[35], IO2[37], IO2[38] };
   
    // Potentiometer ADC
    wire sclk_pot;
    wire conv_pot;
    wire[3:0] Q1_miso_pot;
    wire[3:0] Q2_miso_pot;
    assign IO1[19] = sclk_pot;
    assign IO1[21] = conv_pot;
    assign Q1_miso_pot = { IO1[29], IO1[30], IO1[26], IO1[27] };
    assign Q2_miso_pot = { IO2[11], IO2[12], IO2[9], IO2[10] };

    // Motor current ADC
    wire sclk_cur;
    wire conv_cur;
    wire[3:0] Q1_miso_cur;
    wire[3:0] Q2_miso_cur;
    assign IO1[20] = sclk_cur;
    assign IO1[23] = conv_cur;
    assign Q1_miso_cur = { IO2[5], IO2[6], IO2[1], IO2[3] };
    assign Q2_miso_cur = { IO2[15], IO2[18], IO2[17], IO2[16] };

    // Motor DAC
    wire dac_sclk;      // SCLK in schematic
    wire Q1_dac_mosi;   // Q1-MOSI in schematic
    wire Q2_dac_mosi;   // Q2-MOSI in schematic
    wire Q1_dac_mosi_fb;
    wire Q2_dac_mosi_fb;
    wire Q1_dac_CSn;
    wire Q2_dac_CSn;
    assign IO1[22] = dac_sclk;
    assign IO1[25] = Q1_dac_mosi;
    assign IO1[13] = Q2_dac_mosi;
    assign Q1_dac_mosi_fb = IO1[25];
    assign Q2_dac_mosi_fb = IO1[13];
    assign IO1[24] = Q1_dac_CSn;
    assign IO1[9]  = Q2_dac_CSn;
   
    // DQLA I/O expander
    wire exp_sclk;      // labeled Q1_exp_sclk on schematic
    wire exp_mosi;      // labeled Q1_exp_mosi on schematic
    wire exp_miso;
    wire Q1_exp_CSn;
    wire Q2_exp_CSn;
    assign IO1[18] = exp_sclk;
    assign IO1[16] = exp_mosi;
    assign exp_miso = IO1[14];
    assign IO1[10] = Q1_exp_CSn;
    assign IO1[12] = Q2_exp_CSn;
    
    // Safety relay
    wire relay_on;
    assign IO1[0] = relay_on;
   
    // Digital outputs and direction control
    wire[1:4] Q1_out;
    wire[1:4] Q2_out;
    wire Q1_dir12;
    wire Q2_dir12;
    wire Q1_dir34;
    wire Q2_dir34;
    wire Q1_dir12_fb;
    wire Q2_dir12_fb;
    wire Q1_dir34_fb;
    wire Q2_dir34_fb;
    assign { IO1[6], IO1[5], IO1[8], IO1[7] } = Q1_out;
    assign { IO2[2], IO2[0], IO2[39], IO2[4] } = Q2_out;
    assign IO1[33] = Q1_dir12;
    assign IO1[17] = Q2_dir12;
    assign IO1[32] = Q1_dir34;
    assign IO1[11] = Q2_dir34;
    assign Q1_dir12_fb = IO1[33];
    assign Q2_dir12_fb = IO1[17];
    assign Q1_dir34_fb = IO1[32];
    assign Q2_dir34_fb = IO1[11];

    // Digital inputs (directly connected)
    wire[1:4] Q1_poslim;
    wire[1:4] Q2_poslim;
    // Q1_poslim[1:2] via DQLA I/O expander
    assign Q1_poslim[3:4] = { IO2[14], IO2[13] };
    // Q2_poslim[1:2] via DQLA I/O expander
    assign Q2_poslim[3:4] = { IO2[23], IO2[21] };

    // Temperature sensors
    wire Q1_temp[1:2];
    wire Q2_temp[1:2];
    assign Q1_temp[1] = IO2[7];
    assign Q1_temp[2] = IO2[8];
    assign Q2_temp[1] = IO2[20];
    assign Q2_temp[2] = IO2[19];
    
    //********************** I/O Expander Signals (MAX7301 on DQLA) *********************
    wire Q1_DQLA_exp_ok;     // 1 -> I/O expander (MAX7301) detected
    wire Q2_DQLA_exp_ok;     // 1 -> I/O expander (MAX7301) detected

    wire[31:4] Q1_IOP;
    wire[16:12] Q1_IOP_Error;

    wire Q1_led1_grn;
    wire Q1_led1_red;
    wire Q1_led2_grn;
    wire Q1_led2_red;
    wire Q1_mv_good;
    wire[1:4] Q1_home;
    wire[1:4] Q1_neglim;
    // Q1_poslim defined above (direct connect)
    wire Q1_pwr_en;
    wire Q1_pwr_en_error;        // Error detected in I/O expander output
    wire[1:4] Q1_disable;
    wire[1:4] Q1_amp_fault;      // Fault signal from op amp, active low (1 -> amplifier on, 0 -> fault)
    wire[1:4] Q1_enc_i;

    assign Q1_IOP[31:28] = { Q1_led1_grn, Q1_led1_red, Q1_led2_grn, Q1_led2_red };
    assign Q1_mv_good = Q1_IOP[27];
    assign Q1_home[1:4] = Q1_IOP[26:23];
    assign Q1_neglim[1:4] = { Q1_IOP[22], Q1_IOP[20], Q1_IOP[21], Q1_IOP[19] };
    assign Q1_poslim[1:2] = Q1_IOP[18:17];
    assign Q1_IOP[16] = Q1_pwr_en;
    assign Q1_pwr_en_error = Q1_IOP_Error[16];
    assign Q1_IOP[15:12] = Q1_disable[1:4];
    assign Q1_amp_fault[1:4] = Q1_IOP[11:8];
    assign Q1_enc_i[1:4] = Q1_IOP[7:4];

    wire[31:4] Q2_IOP;
    wire[16:12] Q2_IOP_Error;

    wire Q2_led1_grn;
    wire Q2_led1_red;
    wire Q2_led2_grn;
    wire Q2_led2_red;
    wire Q2_mv_good;
    wire[1:4] Q2_home;
    wire[1:4] Q2_neglim;
    // Q2_poslim defined above (direct connect)
    wire Q2_pwr_en;
    wire Q2_pwr_en_error;        // Error detected in I/O expander output
    wire[1:4] Q2_disable;
    wire[1:4] Q2_amp_fault;      // Fault signal from op amp, active low (1 -> amplifier on, 0 -> fault)
    wire[1:4] Q2_enc_i;

    assign Q2_IOP[31:28] = { Q2_led1_grn, Q2_led1_red, Q2_led2_grn, Q2_led2_red };
    assign Q2_mv_good = Q2_IOP[27];
    assign Q2_home[1:4] = Q2_IOP[26:23];
    assign Q2_neglim[1:4] = { Q2_IOP[22], Q2_IOP[20], Q2_IOP[21], Q2_IOP[19] };
    assign Q2_poslim[1:2] = Q2_IOP[18:17];
    assign Q2_IOP[16] = Q2_pwr_en;
    assign Q2_pwr_en_error = Q2_IOP_Error[16];
    assign Q2_IOP[15:12] = Q2_disable[1:4];
    assign Q2_amp_fault[1:4] = Q2_IOP[11:8];
    assign Q2_enc_i[1:4] = Q2_IOP[7:4];

    //***********************************************************************************

    // SPI interface to QLA PROM and I/O Expander
    wire Q1_prom_mosi;
    wire Q1_ioexp_mosi;
    wire Q1_prom_sclk;
    wire Q1_ioexp_sclk;
    wire Q1_prom_busy;         // 1 -> QLA PROM using SPI
    wire Q1_ioexp_busy;        // 1 -> I/O Expander using SPI

    wire Q2_prom_mosi;
    wire Q2_ioexp_mosi;
    wire Q2_prom_sclk;
    wire Q2_ioexp_sclk;
    wire Q2_prom_busy;         // 1 -> QLA PROM using SPI
    wire Q2_ioexp_busy;        // 1 -> I/O Expander using SPI

    // Multiplex MOSI (output from FPGA) and SCLK (SPI clock)
    assign mosi1 = Q1_prom_busy ? Q1_prom_mosi :
                   Q1_ioexp_busy ? Q1_ioexp_mosi :
                   Q2_prom_busy ? Q2_prom_mosi :
                   Q2_ioexp_busy ? Q2_ioexp_mosi : 1'bz;
    assign sclk1 = Q1_prom_busy ? Q1_prom_sclk :
                   Q1_ioexp_busy ? Q1_ioexp_sclk :
                   Q2_prom_busy ? Q2_prom_sclk :
                   Q2_ioexp_busy ? Q2_ioexp_sclk : 1'bz;

    wire[31:0] reg_rd[0:15];

//------------------------------------------------------------------------------
// hardware description
//

wire[31:0] reg_rdata_prom_qla;   // reads from QLA prom
wire[31:0] reg_rdata_prom_qla1;  // reads from QLA 1 prom
wire[31:0] reg_rdata_prom_qla2;  // reads from QLA 2 prom
wire[31:0] reg_rdata_ds;         // for DS2505 memory access
wire[31:0] reg_rdata_chan0;      // 'channel 0' is a special axis that contains various board I/Os
wire       reg_rwait_chan0;      // 'channel 0' read wait state
reg[31:0]  reg_rdata_ioexp;      // reads from MAX7317 I/O expander (QLA 1.5+)
wire[31:0] reg_rdata_ioexp_1;    // reads from MAX7317 I/O expander (QLA 1.5+)
wire[31:0] reg_rdata_ioexp_2;    // reads from MAX7317 I/O expander (QLA 1.5+)
wire[31:0] reg_rdata_ioexp_3;    // reads from MAX7301 I/O expander (DQLA)

assign reg_rdata_prom_qla = (reg_raddr[7:4] == 4'd1) ? reg_rdata_prom_qla1 :
                            (reg_raddr[7:4] == 4'd2) ? reg_rdata_prom_qla2 :
                            32'd0;

// Only one I/O expander should be providing data to the host PC
always @(*)
begin
    case ({reg_rdata_ioexp_3[30], reg_rdata_ioexp_2[30], reg_rdata_ioexp_1[30]})
      3'b000:  reg_rdata_ioexp = 32'd0;
      3'b001:  reg_rdata_ioexp = reg_rdata_ioexp_1;
      3'b010:  reg_rdata_ioexp = reg_rdata_ioexp_2;
      3'b100:  reg_rdata_ioexp = reg_rdata_ioexp_3;
      default:  reg_rdata_ioexp = 32'h80000000;
    endcase
end          

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | waveform
// reg_rwait indicates when reg_rdata is valid
//   0 --> same sysclk as reg_raddr (e.g., register read)
//   1 --> one sysclk after reg_raddr set (e.g., reading from memory)
// reg_rdata_ds is latched, so rwait=1
assign {reg_rdata, reg_rwait} =
                   (reg_raddr[15:12]==`ADDR_PROM_QLA) ? {reg_rdata_prom_qla, 1'b0} :
                   (reg_raddr[15:12]==`ADDR_DS) ? {reg_rdata_ds, 1'b1} :
                   (reg_raddr[15:12]==`ADDR_WAVEFORM) ? {reg_rtable, 1'b1} :
                   ((reg_raddr[15:12]==`ADDR_MAIN) && (reg_raddr[7:4]!=4'd0)) ? {reg_rd[reg_raddr[3:0]], 1'b0} :
                   ((reg_raddr[15:12]==`ADDR_MAIN) && (reg_raddr[3:0]==`REG_IO_EXP)) ? {reg_rdata_ioexp, 1'b0} :
                   (reg_raddr[15:12]==`ADDR_MAIN) ? {reg_rdata_chan0, reg_rwait_chan0} :
                   {32'd0, 1'b0};

// Unused channel offsets
assign reg_rd[`OFF_UNUSED_02] = 32'd0;
assign reg_rd[`OFF_UNUSED_03] = 32'd0;
assign reg_rd[`OFF_UNUSED_13] = 32'd0;
assign reg_rd[`OFF_UNUSED_14] = 32'd0;
assign reg_rd[`OFF_UNUSED_15] = 32'd0;

// -------------------------------------------------------------------------
// Timestamp: just a free-running counter
// -------------------------------------------------------------------------
always @(posedge sysclk)
begin
   timestamp <= timestamp + 32'd1;
end

// --------------------------------------------------------------------------
// adcs: pot + current 
// --------------------------------------------------------------------------

// local wire for cur_fb(1-8)
wire[15:0] cur_fb[1:8];
wire       cur_fb_wen;

// local wire for pot_fb(1-8)
wire[15:0] pot_fb[1:8];
wire       pot_fb_wen;

// pot feedback

wire pot_latch_bit;
wire pot_latch_word;

Ltc1864SPI spi_pot(
    .clk(clkadc),
    .sclk(sclk_pot),
    .conv(conv_pot),
    .OutReady(pot_fb_wen),
    .latch_bit(pot_latch_bit),
    .latch_word(pot_latch_word)
);

Ltc1864x4 Q1_adc_pot(
    .clk(clkadc),
    .Out1(pot_fb[1]),
    .Out2(pot_fb[2]),
    .Out3(pot_fb[3]),
    .Out4(pot_fb[4]),
    .latch_bit(pot_latch_bit),
    .latch_word(pot_latch_word),
    .miso(Q1_miso_pot)
);

Ltc1864x4 Q2_adc_pot(
    .clk(clkadc),
    .Out1(pot_fb[5]),
    .Out2(pot_fb[6]),
    .Out3(pot_fb[7]),
    .Out4(pot_fb[8]),
    .latch_bit(pot_latch_bit),
    .latch_word(pot_latch_word),
    .miso(Q2_miso_pot)
);

// motor current feedback

wire cur_latch_bit;
wire cur_latch_word;

Ltc1864SPI spi_cur(
    .clk(clkadc),
    .sclk(sclk_cur),
    .conv(conv_cur),
    .OutReady(cur_fb_wen),
    .latch_bit(cur_latch_bit),
    .latch_word(cur_latch_word)
);

Ltc1864x4 Q1_adc_cur(
    .clk(clkadc),
    .Out1(cur_fb[1]),
    .Out2(cur_fb[2]),
    .Out3(cur_fb[3]),
    .Out4(cur_fb[4]),
    .latch_bit(cur_latch_bit),
    .latch_word(cur_latch_word),
    .miso(Q1_miso_cur)
);

Ltc1864x4 Q2_adc_cur(
    .clk(clkadc),
    .Out1(cur_fb[5]),
    .Out2(cur_fb[6]),
    .Out3(cur_fb[7]),
    .Out4(cur_fb[8]),
    .latch_bit(cur_latch_bit),
    .latch_word(cur_latch_word),
    .miso(Q2_miso_cur)
);

assign reg_rd[`OFF_ADC_DATA] = {pot_fb[reg_raddr[7:4]], cur_fb[reg_raddr[7:4]]};

// ----------------------------------------------------------------------------
// Read/Write of commanded current (cur_cmd) and amplifier enable
//
// This is now done in MotorChannelQLA (rather than CtrlDac) to support digital
// control implementations.
// ----------------------------------------------------------------------------

wire ioexp_cfg_reset;          // 1 -> Check if I/O expander (MAX7317) present
wire Q1_ioexp_cfg_present;     // 1 -> I/O expander (MAX7317) detected
wire Q2_ioexp_cfg_present;     // 1 -> I/O expander (MAX7317) detected

// Delay between mv_good and amp enable (from BoardRegsDQLA)
wire Q1_mv_amp_disable;
wire Q2_mv_amp_disable;

// amp_disable_pin is output from MotorChannelQLA and is output via FPGA
wire[1:8] amp_disable_pin;

// amp_disable_f is output from MotorChannelQLA and is provided to the
// follower op amp via the Max7317 I/O expander (QLA Rev 1.5+)
wire[1:8] amp_disable_f;

// Fault signal from op amp, active low (1 -> amplifier on, 0 -> fault)
wire[1:8] amp_fault;
assign amp_fault = { Q1_amp_fault, Q2_amp_fault };

wire[1:8] cur_ctrl_error;    // 1 -> output error in Max7317 I/O expander
wire[1:8] disable_f_error;   // 1 -> output error in Max7317 I/O expander

wire[1:8] amp_disable_error; // 1 -> output error in Max7301 I/O expander
assign amp_disable_error = { Q1_IOP_Error[15:12], Q2_IOP_Error[15:12] };

wire[15:0] cur_cmd[1:8];     // Commanded current per channel
wire[3:0] ctrl_mode[1:8];    // Control mode per channel
wire[1:8] cur_ctrl;          // 1 -> current control, 0 -> voltage control

// Motor status feedback
wire[31:0] motor_status[1:8];

// Motor configuration
wire[31:0] motor_config[1:8];

// pwr_enable_cmd (from BoardRegsDQLA) and amp_enable_cmd (from MotorChannelQLA) are
// used to clear safety_amp_disable (in MotorChannelQLA) and wdog_timeout (wdog_clear to FPGA)
wire pwr_enable_cmd;
wire[1:8] amp_enable_cmd;

// wdog_clear is true if the host is attempting to enable board power or any amplifier.
// This is used to clear the watchdog status flag (wdog_timeout).
assign wdog_clear = (pwr_enable_cmd || (amp_enable_cmd != 8'd0)) ? 1'b1 : 1'b0;

// Delay clock, used to delay the amplifier enable.
// 49.152 MHz / 2**10 ==> 48 kHz (1 cnt = 20.83 us)
wire clkdiv32, clk_delay;
ClkDiv div32clk(sysclk, clkdiv32);
defparam div32clk.width = 10;
BUFG delayclk(.I(clkdiv32), .O(clk_delay));

genvar k;
generate
    for (k = 1; k <= 8; k = k + 1) begin : mchan_loop
        MotorChannelQLA #(.CHANNEL(k)) Motor_instance(
            .clk(sysclk),
            .delay_clk(clk_delay),

            .reg_waddr(reg_waddr),
            .reg_wdata(reg_wdata),
            .reg_wen(reg_wen),
            .motor_status(motor_status[k]),
            .motor_config(motor_config[k]),

            .ioexp_present((k <= 4) ? Q1_ioexp_cfg_present : Q2_ioexp_cfg_present),

            .pwr_enable((k <= 4) ? Q1_pwr_en : Q2_pwr_en),
            .pwr_enable_cmd(pwr_enable_cmd),
            .amp_enable_cmd(amp_enable_cmd[k]),
            .mv_amp_disable((k <= 4) ? Q1_mv_amp_disable : Q2_mv_amp_disable),
            .wdog_timeout(wdog_timeout),
            .amp_fault(amp_fault[k]),
            .amp_disable_error(amp_disable_error[k]),
            .cur_ctrl_error(cur_ctrl_error[k]),
            .disable_f_error(disable_f_error[k]),
            .amp_disable_pin(amp_disable_pin[k]),
            .amp_disable_f(amp_disable_f[k]),

            .cur_cmd(cur_cmd[k]),
            .ctrl_mode(ctrl_mode[k]),
            .cur_ctrl(cur_ctrl[k]),

            .cur_fb(cur_fb[k])
        );
    end
endgenerate

assign Q1_disable[1] = amp_disable_pin[1];
assign Q1_disable[2] = amp_disable_pin[2];
assign Q1_disable[3] = amp_disable_pin[3];
assign Q1_disable[4] = amp_disable_pin[4];

assign Q2_disable[1] = amp_disable_pin[5];
assign Q2_disable[2] = amp_disable_pin[6];
assign Q2_disable[3] = amp_disable_pin[7];
assign Q2_disable[4] = amp_disable_pin[8];

// Write to global status register
wire reg_waddr_status;
assign reg_waddr_status = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == 4'd0) &&
                           (reg_waddr[3:0]==`REG_STATUS)) ? 1'd1 : 1'd0;

// Check for non-zero channel number (reg_waddr[7:4]) to ignore write to global register.
// It would be even better to check that channel number is 1-4.
wire reg_waddr_dac;
assign reg_waddr_dac = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] != 4'd0) &&
                        (reg_waddr[3:0]==`OFF_DAC_CTRL)) ? 1'd1 : 1'd0;

// Following indicates whether at least one DAC has been updated (via a block write)
// since the last write.
reg dac_update;

// Following indicates whether DAC value is valid (bit 31 set), assuming
// reg_waddr_dac is 1. This will work for either a block write or a single quadlet
// write because in both cases reg_wen is set.
wire dac_valid;
assign dac_valid = reg_wen & reg_wdata[31];

wire dac_busy;
reg  cur_cmd_req;
reg  cur_cmd_updated;

always @(posedge(sysclk))
begin
    // We check both reg_waddr_dac and reg_waddr_status because in a block write, the last
    // write is to the status/control register.
    if (reg_waddr_dac | reg_waddr_status) begin
        // For block write, dac_update will be set if any DAC was valid prior to blk_wen
        // For quadlet write, need to check (dac_valid&reg_waddr_dac) because blk_wen and
        // reg_wen occur at the same time
        if (blk_wen) begin
            dac_update <= 1'b0;
            if (dac_update|(dac_valid&reg_waddr_dac)) begin
                cur_cmd_req <= dac_busy;
                cur_cmd_updated <= ~dac_busy;
            end
        end
        else if (dac_valid) begin
            // This condition is only possible for block write
            dac_update <= 1'b1;
        end
    end
    if (cur_cmd_req&(~dac_busy)) begin
        cur_cmd_req <= 0;
        cur_cmd_updated <= 1;
    end
    else if (cur_cmd_updated&dac_busy) begin
        cur_cmd_updated <= 1'b0;
    end
end

assign reg_rd[`OFF_DAC_CTRL] = cur_cmd[reg_raddr[7:4]];

assign reg_rd[`OFF_MOTOR_STATUS] = motor_status[reg_raddr[7:4]];
assign reg_rd[`OFF_MOTOR_CONFIG] = motor_config[reg_raddr[7:4]];

// --------------------------------------------------------------------------
// dacs
//
// Note that there are two DAC chains, but they are both driven by the same
// SCLK and cur_cmd_updated, so should remain synchronized.
// --------------------------------------------------------------------------

wire Q1_is_quad_dac;      // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
wire Q2_is_quad_dac;      // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
wire dac_test_reset;      // reset (repeat) detection of DAC type

CtrlDac #(.NUM_CS(2)) dac(
    .sysclk(sysclk),
    .sclk(dac_sclk),
    .mosi({Q2_dac_mosi, Q1_dac_mosi}),
    .csel({Q2_dac_CSn, Q1_dac_CSn}),
    .dac1({cur_cmd[5], cur_cmd[1]}),
    .dac2({cur_cmd[6], cur_cmd[2]}),
    .dac3({cur_cmd[7], cur_cmd[3]}),
    .dac4({cur_cmd[8], cur_cmd[4]}),
    .busy(dac_busy),
    .data_ready(cur_cmd_updated),
    .mosi_read({Q2_dac_mosi_fb, Q1_dac_mosi_fb}),
    .isQuadDac({Q2_is_quad_dac, Q1_is_quad_dac}),
    .dac_test_reset(dac_test_reset)
);

// --------------------------------------------------------------------------
// encoders
// --------------------------------------------------------------------------

wire[31:0] reg_preload;
wire[31:0] reg_quad_data;
wire[31:0] reg_perd_data;
wire[31:0] reg_qtr1_data;
wire[31:0] reg_qtr5_data;
wire[31:0] reg_run_data;

// encoder controller: the thing that manages encoder reads and preloads
CtrlEnc #(.NUM_ENC(8)) enc(
    .sysclk(sysclk),
    .enc_a({Q1_enc_a, Q2_enc_a}),
    .enc_b({Q1_enc_b, Q2_enc_b}),
    .enc_i({Q1_enc_i, Q2_enc_i}),
    .reg_raddr_chan(reg_raddr[7:4]),
    .reg_waddr(reg_waddr),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .reg_preload(reg_preload),
    .reg_quad_data(reg_quad_data),
    .reg_perd_data(reg_perd_data),
    .reg_qtr1_data(reg_qtr1_data),
    .reg_qtr5_data(reg_qtr5_data),
    .reg_run_data(reg_run_data)
);

assign reg_rd[`OFF_ENC_LOAD] = reg_preload;      // preload
assign reg_rd[`OFF_ENC_DATA] = reg_quad_data;    // quadrature
assign reg_rd[`OFF_PER_DATA] = reg_perd_data;    // period
assign reg_rd[`OFF_QTR1_DATA] = reg_qtr1_data;   // last quarter cycle 
assign reg_rd[`OFF_QTR5_DATA] = reg_qtr5_data;   // quarter cycle 5 edges ago
assign reg_rd[`OFF_RUN_DATA] = reg_run_data;     // running counter

// --------------------------------------------------------------------------
// digital output (DOUT) control
// --------------------------------------------------------------------------

wire[31:0] reg_rdout;
assign reg_rd[`OFF_DOUT_CTRL] = reg_rdout;
wire[31:0] reg_rtable;

// DOUT hardware configuration
wire dout_config_valid;
wire dout_config_bidir;
wire dout_config_reset;
wire[31:0] dout;
wire Q1_dir12_cd;
wire Q1_dir34_cd;
wire Q2_dir12_cd;
wire Q2_dir34_cd;

// Overrides from DS2505 module. When interfacing to the Dallas DS2505
// via 1-wire interface, the DS2505 module sets ds_enable and takes over
// control of DOUT3 and DIR34 on QLA 2.
wire ds_enable;
wire dout3_ds;
wire dir34_ds;

// If dout_config_dir==1, then invert logic; note that this is accomplished using the XOR operator.
// Note that old version QLA IOs are not bi-directional, thus dout_config_bidir==0. In that case, dout3_ds logic needs to be inverted via XNOR.
// Meanwhile, new version QLA does have bi-dir driver for IOs, therefore dout3_ds doesn't need to be inverted, which is still achieved by XNOR.
assign Q1_out[4] = Q1_dout_config_bidir ^ dout[3];
assign Q1_out[3] = Q1_dout_config_bidir ^ dout[2];
assign Q1_out[2] = Q1_dout_config_bidir ^ dout[1];
assign Q1_out[1] = Q1_dout_config_bidir ^ dout[0];

assign Q2_out[4] = Q2_dout_config_bidir ^ dout[7];
assign Q2_out[3] = ds_enable ? (dir34_ds ?  (dout3_ds ^~ Q2_dout_config_bidir) : 1'bz) : (Q2_dout_config_bidir ^ dout[6]);
assign Q2_out[2] = Q2_dout_config_bidir ^ dout[5];
assign Q2_out[1] = Q2_dout_config_bidir ^ dout[4];


assign Q1_dir12 = (Q1_dout_config_valid && Q1_dout_config_bidir) ? Q1_dir12_cd : 1'bz;
assign Q1_dir34 = (Q1_dout_config_valid && Q1_dout_config_bidir) ? Q1_dir34_cd : 1'bz;

assign Q2_dir12 = (Q2_dout_config_valid && Q2_dout_config_bidir) ? Q2_dir12_cd : 1'bz;
assign Q2_dir34 = (Q2_dout_config_valid && Q2_dout_config_bidir) ? (ds_enable ? dir34_ds : Q2_dir34_cd) : 1'bz;

DoutCfgCheck Q1_dconf(
    .sysclk(sysclk),
    .dir12_read(Q1_dir12_fb),
    .dir34_read(Q1_dir34_fb),
    .dir12_reg(Q1_dir12_cd),
    .dir34_reg(Q1_dir34_cd),
    .dout_cfg_valid(Q1_dout_config_valid),
    .dout_cfg_bidir(Q1_dout_config_bidir),
    .dout_cfg_reset(dout_config_reset)
);

DoutCfgCheck Q2_dconf(
    .sysclk(sysclk),
    .dir12_read(Q2_dir12_fb),
    .dir34_read(Q2_dir34_fb),
    .dir12_reg(Q2_dir12_cd),
    .dir34_reg(Q2_dir34_cd),
    .dout_cfg_valid(Q2_dout_config_valid),
    .dout_cfg_bidir(Q2_dout_config_bidir),
    .dout_cfg_reset(dout_config_reset)
);

CtrlDout #(.NUM_DOUT(8)) cdout(
    .sysclk(sysclk),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdout),
    .table_rdata(reg_rtable),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .dout(dout),
    .io_extra(4'd0)
);

// --------------------------------------------------------------------------
// temperature sensors 
// --------------------------------------------------------------------------

// tempsense module instantiations
Max6576 Q1_T1(
    .clk400k(clk400k), 
    .In(Q1_temp[1]), 
    .Out(Q1_tempsense[15:8])
);

Max6576 Q1_T2(
    .clk400k(clk400k), 
    .In(Q1_temp[2]), 
    .Out(Q1_tempsense[7:0])
);


// tempsense module instantiations
Max6576 Q2_T1(
    .clk400k(clk400k), 
    .In(Q2_temp[1]), 
    .Out(Q2_tempsense[15:8])
);

Max6576 Q2_T2(
    .clk400k(clk400k), 
    .In(Q2_temp[2]), 
    .Out(Q2_tempsense[7:0])
);


//---------------------------------------------------------------------------
// Simple mechanism to avoid contention of SPI bus between QLA PROMs
// and Max7317 I/O expanders.
//---------------------------------------------------------------------------

reg[3:0] spi_token;
initial spi_token = 4'b0001;

always @(posedge sysclk)
begin
    spi_token <= {spi_token[2:0], spi_token[3]};
end

// --------------------------------------------------------------------------
// QLA prom 25AA128
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

wire reg_wen_prom_qla1;
assign reg_wen_prom_qla1 = ((reg_waddr[15:12] == `ADDR_PROM_QLA) && (reg_waddr[7:4] == 4'd1)) ?
                           reg_wen : 1'b0;

QLA25AA128 Q1_prom_qla(
    .clk(sysclk),
    
    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom_qla1),
    .reg_wdata(reg_wdata),
        
    .reg_wen(reg_wen_prom_qla1),
    .blk_wen(blk_wen),       // not used
    .blk_wstart(blk_wstart), // not used

    // spi interface
    .prom_mosi(Q1_prom_mosi),
    .prom_miso(miso1),
    .prom_sclk(Q1_prom_sclk),
    .prom_cs(Q1_prom_CSn),
    .other_busy(Q1_ioexp_busy|Q2_prom_busy|Q2_ioexp_busy|(~spi_token[0])),
    .this_busy(Q1_prom_busy)
);

wire reg_wen_prom_qla2;
assign reg_wen_prom_qla2 = ((reg_waddr[15:12] == `ADDR_PROM_QLA) && (reg_waddr[7:4] == 4'd2)) ?
                           reg_wen : 1'b0;

QLA25AA128 Q2_prom_qla(
    .clk(sysclk),
    
    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom_qla2),
    .reg_wdata(reg_wdata),
        
    .reg_wen(reg_wen_prom_qla2),
    .blk_wen(blk_wen),       // not used
    .blk_wstart(blk_wstart), // not used

    // spi interface
    .prom_mosi(Q2_prom_mosi),
    .prom_miso(miso1),
    .prom_sclk(Q2_prom_sclk),
    .prom_cs(Q2_prom_CSn),
    .other_busy(Q1_prom_busy|Q1_ioexp_busy|Q2_ioexp_busy|(~spi_token[1])),
    .this_busy(Q2_prom_busy)
);

// --------------------------------------------------------------------------
// MAX7317: I/O Expander
// --------------------------------------------------------------------------

wire Q1_safety_fb_n;         // 0 -> voltage present on safety line
wire Q1_mv_fb;               // Feedback from comparator between DAC4 and motor supply

Max7317
    #(.IOEXP_ID(1), .CLKBIT(1))
Q1_IO_Exp(
    .clk(sysclk),

    // address & wen
    //.reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_ioexp_1),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),

    // Configuration
    .ioexp_cfg_reset(ioexp_cfg_reset),
    .ioexp_cfg_present(Q1_ioexp_cfg_present),

    // spi interface
    .mosi(Q1_ioexp_mosi),
    .miso(miso1),
    .sclk(Q1_ioexp_sclk),
    .CSn(Q1_ioexp_CSn),
    .other_busy(Q1_prom_busy|Q2_prom_busy|Q2_ioexp_busy|(~spi_token[2])),
    .this_busy(Q1_ioexp_busy),

    // Signals
    .P30(cur_ctrl[1:4]),
    .P74(amp_disable_f[1:4]),
    .P98({Q1_mv_fb, Q1_safety_fb_n}),

    .P30_error(cur_ctrl_error[1:4]),
    .P74_error(disable_f_error[1:4])
);

wire Q2_safety_fb_n;         // 0 -> voltage present on safety line
wire Q2_mv_fb;               // Feedback from comparator between DAC4 and motor supply

Max7317
    #(.IOEXP_ID(2), .CLKBIT(1))
Q2_IO_Exp(
    .clk(sysclk),

    // address & wen
    //.reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_ioexp_2),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),

    // Configuration
    .ioexp_cfg_reset(ioexp_cfg_reset),
    .ioexp_cfg_present(Q2_ioexp_cfg_present),

    // spi interface
    .mosi(Q2_ioexp_mosi),
    .miso(miso1),
    .sclk(Q2_ioexp_sclk),
    .CSn(Q2_ioexp_CSn),
    .other_busy(Q1_prom_busy|Q2_prom_busy|Q1_ioexp_busy|(~spi_token[3])),
    .this_busy(Q2_ioexp_busy),

    // Signals
    .P30(cur_ctrl[5:8]),
    .P74(amp_disable_f[5:8]),
    .P98({Q2_mv_fb, Q2_safety_fb_n}),

    .P30_error(cur_ctrl_error[5:8]),
    .P74_error(disable_f_error[5:8])
);

// --------------------------------------------------------------------------
// MAX7301: I/O Expanders on DQLA
// --------------------------------------------------------------------------

Max7301x2 #(.IOEXP_ID1(3), .IOEXP_ID2(4)) DQLA_IOExp(
    .clk(sysclk),

    // address & wen
    //.reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_ioexp_3),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),

    // Configuration
    .ioexp_cfg_ok({Q2_DQLA_exp_ok, Q1_DQLA_exp_ok}),

    // spi interface
    .mosi(exp_mosi),
    .miso(exp_miso),
    .sclk(exp_sclk),
    .CSn({Q2_exp_CSn, Q1_exp_CSn}),

    // Signals
    .IOP1_31_28(Q1_IOP[31:28]),
    .IOP1_16_12(Q1_IOP[16:12]),
    .IOP1_read({Q1_IOP[27:17],Q1_IOP[11:4]}),
    .IOP2_31_28(Q2_IOP[31:28]),
    .IOP2_16_12(Q2_IOP[16:12]),
    .IOP2_read({Q2_IOP[27:17],Q2_IOP[11:4]}),

    // Errors
    .IOP1_16_12_error(Q1_IOP_Error[16:12]),
    .IOP2_16_12_error(Q2_IOP_Error[16:12])
);

// --------------------------------------------------------------------------
// DS2505: Dallas 1-wire interface
// --------------------------------------------------------------------------
wire[31:0] ds_status;

DS2505 ds_instrument(
    .clk(sysclk),

    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_wdata(reg_wdata),
    .reg_rdata(reg_rdata_ds),
    .ds_status(ds_status),
    .reg_wen(reg_wen),

    .rxd(Q2_poslim[3]),
    .dout_cfg_bidir(Q2_dout_config_bidir),

    .ds_data_in(Q2_out[3]),
    .ds_data_out(dout3_ds),
    .ds_dir(dir34_ds),
    .ds_enable(ds_enable)
);


// --------------------------------------------------------------------------
// miscellaneous board I/Os
// --------------------------------------------------------------------------

wire[15:0] Q1_tempsense;  // Temperature sensor
wire[15:0] Q2_tempsense;  // Temperature sensor

wire[7:0] neg_limit;
wire[7:0] pos_limit;
wire[7:0] home;
assign neg_limit = { Q2_neglim[4], Q2_neglim[3], Q2_neglim[2], Q2_neglim[1],
                     Q1_neglim[4], Q1_neglim[3], Q1_neglim[2], Q1_neglim[1] };
assign pos_limit = { Q2_poslim[4], Q2_poslim[3], Q2_poslim[2], Q2_poslim[1],
                     Q1_poslim[4], Q1_poslim[3], Q1_poslim[2], Q1_poslim[1] };
assign home = { Q2_home[4], Q2_home[3], Q2_home[2], Q2_home[1],
                Q1_home[4], Q1_home[3], Q1_home[2], Q1_home[1] };


BoardRegsDQLA chan0(
    .sysclk(sysclk),
    .dout(dout),
    .dout_cfg_valid({Q2_dout_config_valid, Q1_dout_config_valid}),
    .dout_cfg_bidir({Q2_dout_config_bidir, Q1_dout_config_bidir}),
    .dout_cfg_reset(dout_config_reset),
    .pwr_enable({Q2_pwr_en, Q1_pwr_en}),
    .pwr_enable_error({Q2_pwr_en_error, Q1_pwr_en_error}),
    .relay_on(relay_on),
    .isQuadDac({Q2_is_quad_dac, Q1_is_quad_dac}),
    .dac_test_reset(dac_test_reset),
    .ioexp_cfg_reset(ioexp_cfg_reset),
    .ioexp_present({Q2_ioexp_cfg_present, Q1_ioexp_cfg_present}),
    .dqla_exp_ok({Q2_DQLA_exp_ok, Q1_DQLA_exp_ok}),
    .neg_limit(neg_limit),
    .pos_limit(pos_limit),
    .home(home),
    .mv_good({Q2_mv_good, Q1_mv_good}),
    .safety_fb({~Q2_safety_fb_n, ~Q1_safety_fb_n}),
    .mv_fb({Q2_mv_fb, Q1_mv_fb}),
    .board_id(board_id),
    .temp_sense({Q2_tempsense, Q1_tempsense}),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_rwait(reg_rwait_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .ds_status(ds_status),
    .pwr_enable_cmd(pwr_enable_cmd),
    .mv_amp_disable({Q2_mv_amp_disable, Q1_mv_amp_disable}),
    .wdog_timeout(wdog_timeout)
);

//------------------------------------------------------------------------------
// LEDs on QLA 
wire clk_12hz;
ClkDiv divclk12(sysclk, clk_12hz); defparam divclk12.width = 22;  // 49.152 MHz / 2**22 ==> 11.71875 Hz

CtrlLED Q1_led(
    .sysclk(sysclk),
    .clk_12hz(clk_12hz),
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .led1_grn(Q1_led1_grn),
    .led1_red(Q1_led1_red),
    .led2_grn(Q1_led2_grn),
    .led2_red(Q1_led2_red)
);

CtrlLED Q2_led(
    .sysclk(sysclk),
    .clk_12hz(clk_12hz),
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .led1_grn(Q2_led1_grn),
    .led1_red(Q2_led1_red),
    .led2_grn(Q2_led2_grn),
    .led2_red(Q2_led2_red)
);

endmodule
