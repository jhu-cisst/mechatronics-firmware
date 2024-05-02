/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2024 ERC CISST, Johns Hopkins University.
 *
 * This module contains common code for the QLA and used with all FPGA versions
 *
 * Revision history
 *     12/10/22    Peter Kazanzides    Created from FPGA1394V3-QLA.v
 */

`include "Constants.v"

module QLA(
    // global clock
    input wire       sysclk,

    // 400k clock for temperature sensors
    input wire       clk400k,

    // ~12MHz clock for SPI to ADCs
    input wire       clkadc,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,

    // I/O between FPGA and QLA (connectors J1 and J2)
    inout[1:32]      IO1,
    inout[1:38]      IO2,
    input wire[3:0]  io_extra,

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
    output reg[31:0] timestamp,

    // Watchdog support
    input wire wdog_period_led,     // 1 -> external LED displays wdog_period_status
    input wire[2:0] wdog_period_status,
    input wire wdog_timeout,        // watchdog timeout status flag
    output wire wdog_clear          // clear watchdog timeout (e.g., on powerup)
);

    // SPI interface to QLA PROM and I/O Expander
    // IO1[1] is MISO (input to FPGA), so can be shared between QLA PROM and I/O Expander
    wire qla_prom_mosi;
    wire io_exp_mosi;
    wire qla_prom_sclk;
    wire io_exp_sclk;
    wire qla_prom_busy;         // 1 -> QLA PROM using SPI
    wire io_exp_busy;           // 1 -> I/O Expander using SPI

    // Multiplex MOSI (output from FPGA) and SCLK (SPI clock)
    assign IO1[2] = qla_prom_busy ? qla_prom_mosi :
                    io_exp_busy   ? io_exp_mosi : 1'bz;
    assign IO1[3] = qla_prom_busy ? qla_prom_sclk :
                    io_exp_busy   ? io_exp_sclk : 1'bz;

    wire[31:0] reg_rd[0:15];

//------------------------------------------------------------------------------
// hardware description
//

wire[31:0] reg_rdata_prom_qla; // reads from QLA prom
wire[31:0] reg_rdata_ds;       // for DS2505 memory access
wire[31:0] reg_rdata_chan0;    // 'channel 0' is a special axis that contains various board I/Os
wire reg_rwait_chan0;          // 'channel 0' read wait state
wire[31:0] reg_rdata_ioexp;    // reads from MAX7317 I/O expander (QLA 1.5+)

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
// reg_rwait indicates when reg_rdata is valid
//   0 --> same sysclk as reg_raddr (e.g., register read)
//   1 --> one sysclk after reg_raddr set (e.g., reading from memory)
// reg_rdata_prom_qla should be fine with rwait=0, but EMIO interface seems work better with rwait=1
assign {reg_rdata, reg_rwait} =
                   (reg_raddr[15:12]==`ADDR_PROM_QLA) ? {reg_rdata_prom_qla, 1'b1} :
                   (reg_raddr[15:12]==`ADDR_DS) ? {reg_rdata_ds, 1'b0} :
                   (reg_raddr[15:12]==`ADDR_DATA_BUF) ? {reg_rdata_databuf, reg_rwait_databuf} :
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

// local wire for cur_fb(1-4) 
wire[15:0] cur_fb[1:4];
wire       cur_fb_wen;

// local wire for pot_fb(1-4)
wire[15:0] pot_fb[1:4];
wire       pot_fb_wen;

// adc controller routes conversion results according to address
CtrlAdc adc(
    .clkadc(clkadc),
    .sclk({IO1[10],IO1[28]}),
    .conv({IO1[11],IO1[27]}),
    .miso({IO1[12:15],IO1[26],IO1[25],IO1[24],IO1[23]}),
    .cur1(cur_fb[1]),
    .cur2(cur_fb[2]),
    .cur3(cur_fb[3]),
    .cur4(cur_fb[4]),
    .cur_ready(cur_fb_wen),
    .pot1(pot_fb[1]),
    .pot2(pot_fb[2]),
    .pot3(pot_fb[3]),
    .pot4(pot_fb[4]),
    .pot_ready(pot_fb_wen)
);

assign reg_rd[`OFF_ADC_DATA] = {pot_fb[reg_raddr[7:4]], cur_fb[reg_raddr[7:4]]};

// ----------------------------------------------------------------------------
// Read/Write of commanded current (cur_cmd) and amplifier enable
//
// This is now done in MotorChannelQLA (rather than CtrlDac) to support digital
// control implementations.
// ----------------------------------------------------------------------------

wire ioexp_cfg_reset;       // 1 -> Check if I/O expander (MAX7317) present
wire ioexp_cfg_present;     // 1 -> I/O expander (MAX7317) detected

// mv_amp_disable is from BoardRegsQLA and is used to disable amplifiers
// for a specified time (~40 ms) after mv_good is detected.
wire mv_amp_disable;

// amp_disable_pin is output from MotorChannelQLA and is output via FPGA
wire[1:4] amp_disable_pin;

// amp_disable_f is output from MotorChannelQLA and is provided to the
// follower op amp via the Max7317 I/O expander (QLA Rev 1.5+)
wire[1:4] amp_disable_f;

// Fault signal from op amp, active low (1 -> amplifier on, 0 -> fault)
wire[1:4] amp_fault;
assign amp_fault = { IO2[31], IO2[33], IO2[35], IO2[37] };

wire[1:4] cur_ctrl_error;
wire[1:4] disable_f_error;

wire[15:0] cur_cmd[1:4];     // Commanded current per channel
wire[3:0] ctrl_mode[1:4];    // Control mode per channel
wire[1:4] cur_ctrl;          // 1 -> current control, 0 -> voltage control

// Motor status feedback
wire[31:0] motor_status[1:4];

// Motor configuration
wire[31:0] motor_config[1:4];

// pwr_enable_cmd (from BoardRegsQLA) and amp_enable_cmd (from MotorChannelQLA) are
// used to clear safety_amp_disable (in MotorChannelQLA) and wdog_timeout (wdog_clear to FPGA)
wire pwr_enable_cmd;
wire[1:4] amp_enable_cmd;

// wdog_clear is true if the host is attempting to enable board power or any amplifier.
// This is used to clear the watchdog status flag (wdog_timeout).
assign wdog_clear = (pwr_enable_cmd || (amp_enable_cmd != 4'd0)) ? 1'b1 : 1'b0;

// Delay clock, used to delay the amplifier enable.
// 49.152 MHz / 2**10 ==> 48 kHz (1 cnt = 20.83 us)
wire clkdiv32, clk_delay;
ClkDiv div32clk(sysclk, clkdiv32);
defparam div32clk.width = 10;
BUFG delayclk(.I(clkdiv32), .O(clk_delay));

genvar k;
generate
    for (k = 1; k <= 4; k = k + 1) begin : mchan_loop
        MotorChannelQLA #(.CHANNEL(k), .USE_STATUS_REG(1)) Motor_instance(
            .clk(sysclk),
            .delay_clk(clk_delay),

            .reg_waddr(reg_waddr),
            .reg_wdata(reg_wdata),
            .reg_wen(reg_wen),
            .motor_status(motor_status[k]),
            .motor_config(motor_config[k]),

            .ioexp_present(ioexp_cfg_present),

            .pwr_enable(IO1[32]),
            .pwr_enable_cmd(pwr_enable_cmd),
            .amp_enable_cmd(amp_enable_cmd[k]),
            .mv_amp_disable(mv_amp_disable),
            .wdog_timeout(wdog_timeout),
            .amp_fault(amp_fault[k]),
            .amp_disable_error(1'b0),   // DQLA only
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

assign IO2[32] = amp_disable_pin[1];
assign IO2[34] = amp_disable_pin[2];
assign IO2[36] = amp_disable_pin[3];
assign IO2[38] = amp_disable_pin[4];

// Set up status register 12 LSB (reg_status12) to provide amplifier feedback.
// This preserves backward compatibility with previous versions of firmware and
// may be eliminated in the future.
wire[11:0] reg_status12;

assign reg_status12 = {
       // amplifier: 1 -> amplifier on, 0 -> fault (4 axes)
       amp_fault[4], amp_fault[3], amp_fault[2], amp_fault[1],
       // safety_amp_disable
       motor_status[4][17], motor_status[3][17], motor_status[2][17], motor_status[1][17],
       // ~reg_disable
       motor_status[4][29], motor_status[3][29], motor_status[2][29], motor_status[1][29]
       };

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
// --------------------------------------------------------------------------

wire is_quad_dac;         // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
wire dac_test_reset;      // reset (repeat) detection of DAC type

// the dac controller manages access to the dacs
CtrlDac dac(
    .sysclk(sysclk),
    .sclk(IO1[21]),
    .mosi(IO1[20]),
    .csel(IO1[22]),
    .dac1(cur_cmd[1]),
    .dac2(cur_cmd[2]),
    .dac3(cur_cmd[3]),
    .dac4(cur_cmd[4]),
    .busy(dac_busy),
    .data_ready(cur_cmd_updated),
    .mosi_read(IO1[20]),
    .isQuadDac(is_quad_dac),
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
CtrlEnc enc(
    .sysclk(sysclk),
    .enc_a({IO2[23],IO2[21],IO2[19],IO2[17]}),
    .enc_b({IO2[15],IO2[13],IO2[12],IO2[10]}),
    .enc_i({IO2[8], IO2[6], IO2[4], IO2[2]}),
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
wire dir12_cd;
wire dir34_cd;

// Overrides from DS2505 module. When interfacing to the Dallas DS2505
// via 1-wire interface, the DS2505 module sets ds_enable and takes over
// control of DOUT3 and DIR34.
wire ds_enable;
wire dout3_ds;
wire dir34_ds;

// IO1[16]: DOUT 4
// IO1[17]: DOUT 3
// IO1[18]: DOUT 2
// IO1[19]: DOUT 1
// If dout_config_dir==1, then invert logic; note that this is accomplished using the XOR operator.
// Note that old version QLA IOs are not bi-directional, thus dout_config_bidir==0. In that case, dout3_ds logic needs to be inverted via XNOR.
// Meanwhile, new version QLA does have bi-dir driver for IOs, therefore dou3_ds doesn't need to be inverted, which is still achieved by XNOR.
assign IO1[16] = dout_config_bidir ^ dout[3];
assign IO1[17] = ds_enable ? (dir34_ds ?  (dout3_ds ^~ dout_config_bidir) : 1'bz) : (dout_config_bidir ^ dout[2]);
assign IO1[18] = dout_config_bidir ^ dout[1];
assign IO1[19] = dout_config_bidir ^ dout[0];

// IO1[6]: DIR 1+2
// IO1[5]: DIR 3+4
assign IO1[6] = (dout_config_valid && dout_config_bidir) ? dir12_cd : 1'bz;
assign IO1[5] = (dout_config_valid && dout_config_bidir) ? (ds_enable ? dir34_ds : dir34_cd) : 1'bz;

DoutCfgCheck dconf(
    .sysclk(sysclk),
    .dir12_read(IO1[6]),
    .dir34_read(IO1[5]),
    .dir12_reg(dir12_cd),
    .dir34_reg(dir34_cd),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir),
    .dout_cfg_reset(dout_config_reset)
);

CtrlDout cdout(
    .sysclk(sysclk),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdout),
    .table_rdata(reg_rtable),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .dout(dout),
    .io_extra(io_extra)
);

// --------------------------------------------------------------------------
// temperature sensors 
// --------------------------------------------------------------------------

wire[15:0] tempsense;

// tempsense module instantiations
Max6576 T1(
    .clk400k(clk400k), 
    .In(IO1[29]), 
    .Out(tempsense[15:8])
);

Max6576 T2(
    .clk400k(clk400k), 
    .In(IO1[30]), 
    .Out(tempsense[7:0])
);


//---------------------------------------------------------------------------
// Simple mechanism to avoid contention of SPI bus between QLA PROM and
// Max7317 I/O expander. Basically, the spi_token is used as a "tie-breaker"
// if the SPI bus is idle, and both devices wish to access it at the same time.
//---------------------------------------------------------------------------

reg spi_token;

always @(posedge sysclk)
begin
    spi_token <= ~spi_token;
end

// --------------------------------------------------------------------------
// QLA prom 25AA128
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

wire reg_wen_prom_qla;
assign reg_wen_prom_qla = ((reg_waddr[15:12] == `ADDR_PROM_QLA) && (reg_waddr[7:4] == 4'd0)) ?
                           reg_wen : 1'b0;

QLA25AA128 prom_qla(
    .clk(sysclk),
    
    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom_qla),
    .reg_wdata(reg_wdata),
        
    .reg_wen(reg_wen_prom_qla),
    .blk_wen(blk_wen),       // not used
    .blk_wstart(blk_wstart), // not used

    // spi interface
    .prom_mosi(qla_prom_mosi),
    .prom_miso(IO1[1]),
    .prom_sclk(qla_prom_sclk),
    .prom_cs(IO1[4]),
    .other_busy(io_exp_busy|spi_token),
    .this_busy(qla_prom_busy)
);

// --------------------------------------------------------------------------
// MAX7317: I/O Expander
// --------------------------------------------------------------------------

wire safety_fb_n;           // 0 -> voltage present on safety line
wire mv_fb;                 // Feedback from comparator between DAC4 and motor supply

Max7317 IO_Exp(
    .clk(sysclk),

    // address & wen
    //.reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_ioexp),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),

    // Configuration
    .ioexp_cfg_reset(ioexp_cfg_reset),
    .ioexp_cfg_present(ioexp_cfg_present),

    // spi interface
    .mosi(io_exp_mosi),
    .miso(IO1[1]),
    .sclk(io_exp_sclk),
    .CSn(IO1[8]),
    .other_busy(qla_prom_busy|(~spi_token)),
    .this_busy(io_exp_busy),

    // Signals
    .P30({cur_ctrl[1], cur_ctrl[2], cur_ctrl[3], cur_ctrl[4]}),
    .P74(amp_disable_f),
    .P98({mv_fb, safety_fb_n}),

    .P30_error(cur_ctrl_error),
    .P74_error(disable_f_error)
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

    .rxd(IO2[29]),
    .dout_cfg_bidir(dout_config_bidir),

    .ds_data_in(IO1[17]),
    .ds_data_out(dout3_ds),
    .ds_dir(dir34_ds),
    .ds_enable(ds_enable)
);


// --------------------------------------------------------------------------
// miscellaneous board I/Os
// --------------------------------------------------------------------------

wire[15:0] reg_databuf;   // Data collection status

BoardRegsQLA chan0(
    .sysclk(sysclk),
    .dout(dout),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir),
    .dout_cfg_reset(dout_config_reset),
    .pwr_enable(IO1[32]),
    .relay_on(IO1[31]),
    .isQuadDac(is_quad_dac),
    .dac_test_reset(dac_test_reset),
    .ioexp_cfg_reset(ioexp_cfg_reset),
    .ioexp_present(ioexp_cfg_present),
    .enc_a({IO2[17], IO2[19], IO2[21], IO2[23]}),    // axis 4:1
    .enc_b({IO2[10], IO2[12], IO2[13], IO2[15]}),    // axis 4:1
    .enc_i({IO2[2], IO2[4], IO2[6], IO2[8]}),        // axis 4:1
    .neg_limit({IO2[26],IO2[24],IO2[25],IO2[22]}),   // axis 4:1
    .pos_limit({IO2[30],IO2[29],IO2[28],IO2[27]}),   // axis 4:1
    .home({IO2[20],IO2[18],IO2[16],IO2[14]}),        // axis 4:1
    .relay(IO2[9]),
    .mv_faultn(IO1[7]),
    .mv_good(IO2[11]),
    .mv_amp_disable(mv_amp_disable),
    .v_fault(IO1[9]),
    .safety_fb(~safety_fb_n),
    .mv_fb(mv_fb),
    .board_id(board_id),
    .temp_sense({(blk_rt_rd ? reg_databuf : 16'd0), tempsense}),
    .reg_status12(reg_status12),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_rwait(reg_rwait_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .ds_status(ds_status),
    .pwr_enable_cmd(pwr_enable_cmd),
    .wdog_timeout(wdog_timeout)
);

// --------------------------------------------------------------------------
// Data Buffer
// --------------------------------------------------------------------------
wire[3:0] data_channel;
wire[31:0] reg_rdata_databuf;
wire reg_rwait_databuf;

DataBuffer data_buffer(
    .clk(sysclk),
    // data collection interface
    .cur_fb_wen(cur_fb_wen),
    .cur_fb(cur_fb[data_channel]),
    .chan(data_channel),
    // cpu interface
    .reg_waddr(reg_waddr),          // write address
    .reg_wdata(reg_wdata),          // write data
    .reg_wen(reg_wen),              // write enable
    .reg_raddr(reg_raddr),          // read address
    .reg_rdata(reg_rdata_databuf),  // read data
    .reg_rwait(reg_rwait_databuf),  // read wait state
    // status and timestamp
    .databuf_status(reg_databuf),   // status for real-time block read
    .ts(timestamp)                  // timestamp
);

//------------------------------------------------------------------------------
// LEDs on QLA 
wire clk_12hz;
ClkDiv divclk12(sysclk, clk_12hz); defparam divclk12.width = 22;  // 49.152 MHz / 2**22 ==> 11.71875 Hz

CtrlLED qla_led(
    .sysclk(sysclk),
    .clk_12hz(clk_12hz),
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .led1_grn(IO2[1]),
    .led1_red(IO2[3]),
    .led2_grn(IO2[5]),
    .led2_red(IO2[7])
);

endmodule
