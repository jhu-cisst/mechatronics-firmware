/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2021 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394-QLA motor controller interface.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/27/11    Paul Thienphrapa    Initial revision (pault at cs.jhu.edu)
 *     02/29/12    Zihan Chen
 *     08/29/18    Peter Kazanzides    Added DS2505 module
 *     01/22/20    Peter Kazanzides    Removed global reset
 */

`timescale 1ns / 1ps

// Define DIAGNOSTIC for diagnostic build, where DAC output is determined by
// rotary switch setting (0-15).
// `define DIAGNOSTIC

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"


module FPGA1394QLA
(
    // ieee 1394 phy-link interface
    input            clk1394,   // 49.152 MHz
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // serial interface
    input wire       RxD,
    input wire       RTS,
    output wire      TxD,

    // debug I/Os
    input wire       clk40m,    // 40.0000 MHz 
    // output wire [3:0] DEBUG,

    // misc board I/Os
    input [3:0]      wenid,     // rotary switch
    inout [1:32]     IO1,
    inout [1:38]     IO2,
    output wire      LED,

    // SPI interface to PROM
    output           XCCLK,    
    input            XMISO,
    output           XMOSI,
    output           XCSn
);

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //

    wire lreq_trig;             // phy request trigger
    wire[2:0] lreq_type;        // phy request type
    reg reg_wen;                // register write signal
    wire fw_reg_wen;            // register write signal from FireWire
    wire bw_reg_wen;            // register write signal from WriteRtData
    reg blk_wen;                // block write enable
    wire fw_blk_wen;            // block write enable from FireWire
    wire bw_blk_wen;            // block write enable from WriteRtData
    reg blk_wstart;             // block write start
    wire fw_blk_wstart;         // block write start from FireWire
    wire bw_blk_wstart;         // block write start from WriteRtData
    wire[15:0] reg_raddr;       // 16-bit reg read address
    wire[15:0] fw_reg_raddr;    // 16-bit reg read address from FireWire
    reg[15:0] reg_waddr;        // 16-bit reg write address
    wire[15:0] fw_reg_waddr;    // 16-bit reg write address from FireWire
    wire[7:0] bw_reg_waddr;     // 16-bit reg write address from WriteRtData
    wire[31:0] reg_rdata;       // reg read data
    reg[31:0] reg_wdata;        // reg write data
    wire[31:0] fw_reg_wdata;    // reg write data from FireWire
    wire[31:0] bw_reg_wdata;    // reg write data from WriteRtData
    wire[31:0] reg_rd[0:15];
    // Following wire indicates which module is driving the write bus
    // (reg_waddr, reg_wdata, reg_wen, blk_wen, blk_wstart).
    // If bw_write_en is 0, then Firewire is driving the write bus.
    wire bw_write_en;           // 1 -> WriteRtData (real-time block write) is driving write bus
    wire[3:0] board_id;         // 4-bit board id
    assign board_id = ~wenid;

//------------------------------------------------------------------------------
// hardware description
//

BUFG clksysclk(.I(clk1394), .O(sysclk));

// Wires for sampling block read data
wire sample_start;        // Start sampling read data
wire sample_busy;         // 1 -> data sampler has control of bus
wire[3:0] sample_chan;    // Channel for sampling
wire[4:0] sample_raddr;   // Address in sample_data buffer
wire[31:0] sample_rdata;  // Output from sample_data buffer
wire[31:0] timestamp;     // Timestamp used when sampling

// For real-time write
wire       rt_wen;
wire[2:0]  rt_waddr;
wire[31:0] rt_wdata;

// For data sampling
wire fw_sample_start;
assign sample_start = fw_sample_start & ~sample_busy;

assign reg_raddr = sample_busy ? {`ADDR_MAIN, 4'd0, sample_chan, 4'd0} : fw_reg_raddr;

// Multiplexing of write bus between WriteRtData (bw = real-time block write module)
// and Firewire.
always @(*)
begin
   if (bw_write_en) begin
      reg_wen = bw_reg_wen;
      blk_wen = bw_blk_wen;
      blk_wstart = bw_blk_wstart;
      reg_waddr = {8'd0, bw_reg_waddr};
      reg_wdata = bw_reg_wdata;
   end
   else begin
      reg_wen = fw_reg_wen;
      blk_wen = fw_blk_wen;
      blk_wstart = fw_blk_wstart;
      reg_waddr = fw_reg_waddr;
      reg_wdata = fw_reg_wdata;
   end
end

wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire[31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_prom_qla; // reads from QLA prom
wire[31:0] reg_rdata_ds;       // for DS2505 memory access
wire[31:0] reg_rdata_chan0;    // 'channel 0' is a special axis that contains various board I/Os

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                  ((reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                  ((reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom_qla) : 
                  ((reg_raddr[15:12]==`ADDR_DS) ? (reg_rdata_ds) :
                  ((reg_raddr[15:12]==`ADDR_DATA_BUF) ? (reg_rdata_databuf) :
                  ((reg_raddr[15:12]==`ADDR_WAVEFORM) ? (reg_rtable) :
                  ((reg_raddr[7:4]==4'd0) ? reg_rdata_chan0 : reg_rd[reg_raddr[3:0]]))))));

// Unused channel offsets
assign reg_rd[`OFF_UNUSED_02] = 32'd0;
assign reg_rd[`OFF_UNUSED_03] = 32'd0;
assign reg_rd[`OFF_UNUSED_11] = 32'd0;
assign reg_rd[`OFF_UNUSED_12] = 32'd0;
assign reg_rd[`OFF_UNUSED_13] = 32'd0;
assign reg_rd[`OFF_UNUSED_14] = 32'd0;
assign reg_rd[`OFF_UNUSED_15] = 32'd0;

// 1394 phy low reset, never reset
assign reset_phy = 1'b1; 

// --------------------------------------------------------------------------
// hub register module
// --------------------------------------------------------------------------

wire[15:0] bc_sequence;
wire[15:0] bc_board_mask;
//wire       bc_request;
wire       hub_write_trig;
wire       hub_write_trig_reset;
wire       fw_idle;

HubReg hub(
    .sysclk(sysclk),
    .reg_wen(reg_wen),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_hub),
    .reg_wdata(reg_wdata),
    .sequence(bc_sequence),
    .board_mask(bc_board_mask),
    //.hub_reg_wen(bc_request),
    .board_id(board_id),
    .write_trig(hub_write_trig),
    .write_trig_reset(hub_write_trig_reset),
    .fw_idle(fw_idle)
);


// --------------------------------------------------------------------------
// firewire modules
// --------------------------------------------------------------------------

// phy-link interface
PhyLinkInterface phy(
    .sysclk(sysclk),         // in: global clk  
    .board_id(board_id),     // in: board id (rotary switch)

    .ctl_ext(ctl),           // bi: phy ctl lines
    .data_ext(data),         // bi: phy data lines
    
    .reg_wen(fw_reg_wen),       // out: reg write signal
    .blk_wen(fw_blk_wen),       // out: block write signal
    .blk_wstart(fw_blk_wstart), // out: block write is starting

    .reg_raddr(fw_reg_raddr),  // out: register address
    .reg_waddr(fw_reg_waddr),  // out: register address
    .reg_rdata(reg_rdata),     // in:  read data to external register
    .reg_wdata(fw_reg_wdata),  // out: write data to external register

    .lreq_trig(lreq_trig),   // out: phy request trigger
    .lreq_type(lreq_type),   // out: phy request type

    .rx_bc_sequence(bc_sequence),  // in: broadcast sequence num
    .rx_bc_fpga(bc_board_mask),    // in: mask of boards involved in broadcast read
    .write_trig(hub_write_trig),   // in: 1 -> broadcast write this board's hub data
    .write_trig_reset(hub_write_trig_reset),
    .fw_idle(fw_idle),

    // Interface for real-time block write
    .fw_rt_wen(rt_wen),
    .fw_rt_waddr(rt_waddr),
    .fw_rt_wdata(rt_wdata),

    // Interface for sampling data (for block read)
    .sample_start(fw_sample_start),   // 1 -> start sampling for block read
    .sample_busy(sample_busy),        // Sampling in process
    .sample_raddr(sample_raddr),      // Read address for sampled data
    .sample_rdata(sample_rdata)       // Sampled data (for block read)
);


// phy request module
PhyRequest phyreq(
    .sysclk(sysclk),          // in: global clock
    .lreq(lreq),              // out: phy request line
    .trigger(lreq_trig),      // in: phy request trigger
    .rtype(lreq_type),        // in: phy request type
    .data(fw_reg_wdata[11:0]) // in: phy request data
);

// --------------------------------------------------------------------------
// adcs: pot + current 
// --------------------------------------------------------------------------

// ~12 MHz clock for spi communication with the adcs
wire clkdiv2, clkadc;
ClkDiv div2clk(sysclk, clkdiv2);
defparam div2clk.width = 2;
BUFG adcclk(.I(clkdiv2), .O(clkadc));


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

wire[31:0] reg_adc_data;
assign reg_adc_data = {pot_fb[reg_raddr[7:4]], cur_fb[reg_raddr[7:4]]};

assign reg_rd[`OFF_ADC_DATA] = reg_adc_data;

// --------------------------------------------------------------------------
// dacs
// --------------------------------------------------------------------------

// local wire for dac
wire[31:0] reg_rdac;
assign reg_rd[`OFF_DAC_CTRL] = reg_rdac;   // dac reads

wire[15:0] cur_cmd[1:4];

// the dac controller manages access to the dacs
CtrlDac dac(
    .sysclk(sysclk),
    .sclk(IO1[21]),
    .mosi(IO1[20]),
    .csel(IO1[22]),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .reg_rchan(reg_raddr[7:4]),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdac),
`ifdef DIAGNOSTIC
    .reg_wdata({ board_id, 12'h000 }),
`else
    .reg_wdata(reg_wdata[15:0]),
`endif
    .dac1(cur_cmd[1]),
    .dac2(cur_cmd[2]),
    .dac3(cur_cmd[3]),
    .dac4(cur_cmd[4])
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
// Note that ds_enable==1 implies that dout_config_bidir==1. Also, DS2505 output (dout3_ds) does not
// need to be inverted.
assign IO1[16] = dout_config_bidir ^ dout[3];
assign IO1[17] = ds_enable ? (dir34_ds ? dout3_ds : 1'bz) : (dout_config_bidir ^ dout[2]);
assign IO1[18] = dout_config_bidir ^ dout[1];
assign IO1[19] = dout_config_bidir ^ dout[0];

// IO1[6]: DIR 1+2
// IO1[5]: DIR 3+4
assign IO1[6] = (dout_config_valid && dout_config_bidir) ? dir12_cd : 1'bz;
assign IO1[5] = (dout_config_valid && dout_config_bidir) ? (ds_enable ? dir34_ds : dir34_cd) : 1'bz;

CtrlDout cdout(
    .sysclk(sysclk),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdout),
    .table_rdata(reg_rtable),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .dout(dout),
    .dir12_read(IO1[6]),
    .dir34_read(IO1[5]),
    .dir12_reg(dir12_cd),
    .dir34_reg(dir34_cd),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir),
    .dout_cfg_reset(dout_config_reset)
);

// --------------------------------------------------------------------------
// temperature sensors 
// --------------------------------------------------------------------------

// divide 40 MHz clock down to 400 kHz for temperature sensor readings
wire clk400k_raw, clk400k;
ClkDivI divtemp(clk40m, clk400k_raw);
defparam divtemp.div = 100;
BUFG clktemp(.I(clk400k_raw), .O(clk400k));

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


// --------------------------------------------------------------------------
// Config prom M25P16
// --------------------------------------------------------------------------

// Route PROM status result between M25P16 and BoardRegs modules
wire[31:0] PROM_Status;
wire[31:0] PROM_Result;
   
M25P16 prom(
    .clk(sysclk),
    .prom_cmd(reg_wdata),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .prom_rdata(reg_rdata_prom),

    // address & wen 
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),

    // spi pins
    .prom_mosi(XMOSI),
    .prom_miso(XMISO),
    .prom_sclk(XCCLK),
    .prom_cs(XCSn)
);


// --------------------------------------------------------------------------
// QLA prom 25AA138 
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

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
    .prom_mosi(IO1[2]),
    .prom_miso(IO1[1]),
    .prom_sclk(IO1[3]),
    .prom_cs(IO1[4])
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

    .dout_cfg_bidir(dout_config_bidir),

    .ds_data_in(IO1[17]),
    .ds_data_out(dout3_ds),
    .ds_dir(dir34_ds),
    .ds_enable(ds_enable)
);


// --------------------------------------------------------------------------
// miscellaneous board I/Os
// --------------------------------------------------------------------------

// safety_amp_enable from SafetyCheck module
wire[4:1] safety_amp_disable;

// pwr_enable_cmd and amp_enable_cmd from BoardRegs; used to clear safety_amp_disable
wire pwr_enable_cmd;
wire[4:1] amp_enable_cmd;

// There is no Ethernet on this version of board, so set the result to 0
wire[31:0] Eth_Result;
assign  Eth_Result = 32'b0;

wire[31:0] reg_status;    // Status register
wire[31:0] reg_digio;     // Digital I/O register
wire[15:0] tempsense;     // Temperature sensor
wire[15:0] reg_databuf;   // Data collection status

wire reboot;              // Reboot the FPGA

// used to check status of user defined watchdog period; used to control LED 
wire      wdog_period_led;
wire[2:0] wdog_period_status;
wire wdog_timeout;

BoardRegs chan0(
    .sysclk(sysclk),
    .reboot(reboot),
    .amp_disable({IO2[38],IO2[36],IO2[34],IO2[32]}),
    .dout(dout),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir),
    .dout_cfg_reset(dout_config_reset),
    .pwr_enable(IO1[32]),
    .relay_on(IO1[31]),
    .enc_a({IO2[17], IO2[19], IO2[21], IO2[23]}),    // axis 4:1
    .enc_b({IO2[10], IO2[12], IO2[13], IO2[15]}),
    .enc_i({IO2[2], IO2[4], IO2[6], IO2[8]}),
    .neg_limit({IO2[26],IO2[24],IO2[25],IO2[22]}),
    .pos_limit({IO2[30],IO2[29],IO2[28],IO2[27]}),
    .home({IO2[20],IO2[18],IO2[16],IO2[14]}),
    .fault({IO2[37],IO2[35],IO2[33],IO2[31]}),
    .relay(IO2[9]),
    .mv_faultn(IO1[7]),
    .mv_good(IO2[11]),
    .v_fault(IO1[9]),
    .io1_8(IO1[8]),
    .board_id(board_id),
    .temp_sense(tempsense),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .ip_address(32'hffffffff),
    .eth_result(Eth_Result),
    .ds_status(ds_status),
`ifdef DISABLE_SAFETY_CHECK
    .safety_amp_disable(4'd0),
`else
    .safety_amp_disable(safety_amp_disable),
`endif
    .pwr_enable_cmd(pwr_enable_cmd),
    .amp_enable_cmd(amp_enable_cmd),
    .reg_status(reg_status),
    .reg_digin(reg_digio),
    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout)
);

// --------------------------------------------------------------------------
// Sample data for block read
// --------------------------------------------------------------------------

SampleData sampler(
    .clk(sysclk),
    .doSample(sample_start),
    .isBusy(sample_busy),
    .reg_status(reg_status),
    .reg_digio(reg_digio),
    .reg_temp({reg_databuf, tempsense}),
    .chan(sample_chan),
    .adc_in(reg_adc_data),
    .enc_pos(reg_quad_data),
    .enc_period(reg_perd_data),
    .enc_qtr1(reg_qtr1_data),
    .enc_qtr5(reg_qtr5_data),
    .enc_run(reg_run_data),
    .blk_addr(sample_raddr),
    .blk_data(sample_rdata),
    .timestamp(timestamp),
    .bc_sequence(bc_sequence),
    .bc_board_mask(bc_board_mask)
);

// --------------------------------------------------------------------------
// Write data for real-time block
// --------------------------------------------------------------------------

WriteRtData rt_write(
    .clk(sysclk),
    .rt_write_en(rt_wen),       // Write enable
    .rt_write_addr(rt_waddr),   // Write address (0-4)
    .rt_write_data(rt_wdata),   // Write data
    .bw_write_en(bw_write_en),
    .bw_reg_wen(bw_reg_wen),
    .bw_block_wen(bw_blk_wen),
    .bw_block_wstart(bw_blk_wstart),
    .bw_reg_waddr(bw_reg_waddr),
    .bw_reg_wdata(bw_reg_wdata)
);

// ----------------------------------------------------------------------------
// safety check 
//    1. get adc feedback current & dac command current
//    2. check if cur_fb > 2 * cur_cmd
SafetyCheck safe1(
    .clk(sysclk),
    .cur_in(cur_fb[1]),
    .dac_in(cur_cmd[1]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[1]),
    .amp_disable(safety_amp_disable[1])
);

SafetyCheck safe2(
    .clk(sysclk),
    .cur_in(cur_fb[2]),
    .dac_in(cur_cmd[2]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[2]),
    .amp_disable(safety_amp_disable[2])
);

SafetyCheck safe3(
    .clk(sysclk),
    .cur_in(cur_fb[3]),
    .dac_in(cur_cmd[3]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[3]),
    .amp_disable(safety_amp_disable[3])
);

SafetyCheck safe4(
    .clk(sysclk),
    .cur_in(cur_fb[4]),
    .dac_in(cur_cmd[4]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[4]),
    .amp_disable(safety_amp_disable[4])
);

// --------------------------------------------------------------------------
// Reboot
// --------------------------------------------------------------------------
Reboot fpga_reboot(
     .clk(clkadc),     // Use 12 MHz clock (cannot be more than 20 MHz)
     .reboot(reboot)
);

// --------------------------------------------------------------------------
// Data Buffer
// --------------------------------------------------------------------------
wire[3:0] data_channel;
wire[31:0] reg_rdata_databuf;

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
    // status and timestamp
    .databuf_status(reg_databuf),   // status for SampleData
    .ts(timestamp)                  // timestamp from SampleData
);

//------------------------------------------------------------------------------
// USB Serial 
//

wire clkfb;    // Clock feedback
wire _out29;   // 29.491 MHz Clock signal
wire _out14;   // 14.746 MHz Clock signal
wire _ref40;   // 40.000 MHz Clock reference (Input)

//-----------------------------------------------------------------------------
//
// Input/Output Buffering
//
//   The Inputs/Outputs of the PLL module are regular signals, NOT clocks.
//
//   The output signals have to connected to BUFG buffers, which are among the
//   specialized primitives that can drive the global clock lines.
//
//   Similarly, an external reference clock connected to a clock pin on the
//   FPGA needs to be routed through an IBUFG primitive to get an ordinary
//   signal that can be used by the PLL Module
//
//-----------------------------------------------------------------------------
BUFG  clk_buf1 (.I(clk40m),  .O(_ref40));
BUFG  clk_buf2 (.I(_out29),  .O(clk_29_pll));
BUFG  clk_buf3 (.I(_out14),  .O(clk_14_pll));

//-----------------------------------------------------------------------------
//
// PLL Primitive
//
//   The "Base PLL" primitive has a PLL, a feedback path and 6 clock outputs,
//   each with its own 7 bit divider to generate 6 different output frequencies
//   that are integer division of the PLL frequency. The "Base" PLL provides
//   basic PLL/Clock-Generation capabilities. For detailed information, see
//   Chapter 3, "General Usage Description" section of the Spartan-6 FPGA 
//   Clocking Resource, Xilinx Document # UG382.
//
//   The PLL has a dedicated Feedback Output and Feedback Input. This output
//   must be connected to this input outside the primitive. For applications
//   where the phase relationship between the reference input and the output
//   clock is not critical (present application), this connection can be made
//   in the module. Where this phase relationship is critical, the feedback
//   path can include routing on the FPGA or even off-chip connections.
//
//   The Input/Output of the PLL module are ordinary signals, NOT clocks.
//   These signals must be routed through specialized buffers in order for
//   them to be connected to the global clock buses and be used as clocks.
//
//-----------------------------------------------------------------------------
PLL_BASE # (.BANDWIDTH         ("OPTIMIZED"),
            .CLK_FEEDBACK      ("CLKFBOUT"),
            .COMPENSATION      ("INTERNAL"),
            .DIVCLK_DIVIDE     (1),
            .CLKFBOUT_MULT     (14),        // VCO = 40.000* 14/1 = 560.0000MHz
            .CLKFBOUT_PHASE    (0.000),
            .CLKOUT0_DIVIDE    (  19  ),    // CLK0 = 560.00/19 = 29.474
            .CLKOUT0_PHASE     (  0.00),
            .CLKOUT0_DUTY_CYCLE(  0.50),
            .CLKOUT1_DIVIDE    (  38  ),    // CLK1 = 560.00/38 = 14.737
            .CLKOUT1_PHASE     (  0.00),
            .CLKOUT1_DUTY_CYCLE(  0.50),
            .CLKOUT2_DIVIDE    (  32  ),    // Unused Output. The divider still needs a
            .CLKOUT3_DIVIDE    (  32  ),    //    reasonable value because the clock is
            .CLKOUT4_DIVIDE    (  32  ),    //    still being generated even if unconnected.
            .CLKOUT5_DIVIDE    (  32  ))    //
_PLL1 (     .CLKFBOUT          (clkfb),     // The FB-Out is connected to FB-In inside
            .CLKFBIN           (clkfb),     //    the module.
            .CLKIN             (_ref40),    // 40.00 MHz reference clock
            .CLKOUT0           (_out29),    // 29.49 MHz Output signal
            .CLKOUT1           (_out14),    // 14.75 MHz Output signal
            .CLKOUT2           (),          // Unused outputs
            .CLKOUT3           (),          //
            .CLKOUT4           (),          //
            .CLKOUT5           (),          //
            .LOCKED            (),          //
            .RST               (1'b0));     // Reset Disable

CtrlUart uart_debug(
    .clk_14_pll(clk_14_pll),  // not used
    .clk_29_pll(clk_29_pll),
    .RxD(RxD),
    .TxD(TxD)
);

//------------------------------------------------------------------------------
// debugging, etc.
//
reg[23:0] CountC;
reg[23:0] CountI;
always @(posedge(clk40m)) CountC <= CountC + 1'b1;
always @(posedge(sysclk)) CountI <= CountI + 1'b1;

assign LED = IO1[32];     // NOTE: IO1[32] pwr_enable
// assign LED = reg_led;
// assign DEBUG = { clk_1mhz, clk_12hz, CountI[23], CountC[23] }; 

// --- debug LED ----------
// reg reg_led;
// reg[4:0] reg_led_counter;
// always @(posedge(rx_active) or posedge(clk_12hz)) begin
//     if (rx_active == 1'b1) begin
//         reg_led_counter <= 0;
//         reg_led <= 1'b1;
//     end
//     else if (reg_led_counter <= 5'd16) begin
//         reg_led_counter <= reg_led_counter + 1'b1;
//         reg_led <= 1'b1;
//     end
//     else begin
//         reg_led <= 1'b0;
//     end
// end


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
