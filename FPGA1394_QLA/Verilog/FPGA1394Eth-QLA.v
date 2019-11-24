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
 *     11/01/15    Peter Kazanzides    Modified for FPGA Rev 2 (Ethernet)
 *     08/29/18    Peter Kazanzides    Added DS2505 module
 *     01/13/20    Peter Kazanzides    Removed KSZ8851 module (now in EthernetIO)
 *     01/22/20    Peter Kazanzides    Removed global reset
 */

`timescale 1ns / 1ps

`define HAS_ETHERNET

// Define DIAGNOSTIC for diagnostic build, where DAC output is determined by
// rotary switch setting (0-15).
// `define DIAGNOSTIC

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"


module FPGA1394EthQLA
(
    // ieee 1394 phy-link interface
    input            clk1394,   // 49.152 MHz
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // ksz8851-16mll ethernet interface
    output wire      ETH_CSn,       // chip select
    output wire      ETH_RSTn,      // reset
    input wire       ETH_PME,       // power management event, unused
    output wire      ETH_CMD,       // command input for ksz8851 register IO
    output wire      ETH_8n,        // 8 or 16 bit bus
    input wire       ETH_IRQn,      // interrupt request
    output wire      ETH_RDn,
    output wire      ETH_WRn,
    inout [15:0]     SD,

    // debug I/Os
    input wire       clk25m,    // 25.0000 MHz 
    //output wire [3:0] DEBUG,

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
    wire fw_lreq_trig;          // phy request trigger from FireWire
    wire eth_lreq_trig;         // phy request trigger from Ethernet
    wire[2:0] lreq_type;        // phy request type
    wire[2:0] fw_lreq_type;     // phy request type from FireWire
    wire[2:0] eth_lreq_type;    // phy request type from Ethernet
    reg reg_wen;                // register write signal
    wire fw_reg_wen;            // register write signal from FireWire
    wire eth_reg_wen;           // register write signal from Ethernet
    wire bw_reg_wen;            // register write signal from WriteRtData
    reg blk_wen;                // block write enable
    wire fw_blk_wen;            // block write enable from FireWire
    wire eth_blk_wen;           // block write enable from Ethernet
    wire bw_blk_wen;            // block write enable from WriteRtData
    reg blk_wstart;             // block write start
    wire fw_blk_wstart;         // block write start from FireWire
    wire eth_blk_wstart;        // block write start from Ethernet
    wire bw_blk_wstart;         // block write start from WriteRtData
    wire[15:0] reg_raddr;       // 16-bit reg read address
    wire[15:0] fw_reg_raddr;    // 16-bit reg read address from FireWire
    wire[15:0] eth_reg_raddr;   // 16-bit reg read address from Ethernet
    reg[15:0] reg_waddr;        // 16-bit reg write address
    wire[15:0] fw_reg_waddr;    // 16-bit reg write address from FireWire
    wire[15:0] eth_reg_waddr;   // 16-bit reg write address from Ethernet
    wire[7:0] bw_reg_waddr;     // 16-bit reg write address from WriteRtData
    wire[31:0] reg_rdata;       // reg read data
    reg[31:0] reg_wdata;        // reg write data
    wire[31:0] fw_reg_wdata;    // reg write data from FireWire
    wire[31:0] eth_reg_wdata;   // reg write data from Ethernet
    wire[31:0] bw_reg_wdata;    // reg write data from WriteRtData
    wire[31:0] reg_rd[0:15];
    wire eth_read_en;           // 1 -> Ethernet is driving reg_raddr to read from board registers
    // Following two wires indicate which module is driving the write bus
    // (reg_waddr, reg_wdata, reg_wen, blk_wen, blk_wstart).
    // If neither is active, then Firewire is driving the write bus.
    wire eth_write_en;          // 1 -> Ethernet is driving write bus
    wire bw_write_en;           // 1 -> WriteRtData (real-time block write) is driving write bus
    wire[5:0] node_id;          // 6-bit phy node id
    wire[3:0] board_id;         // 4-bit board id
    assign board_id = ~wenid;

//------------------------------------------------------------------------------
// hardware description
//

BUFG clksysclk(.I(clk1394), .O(sysclk));

// Wires for sampling block read data (shared between Ethernet and Firewire)
wire sample_start;        // Start sampling read data
wire sample_busy;         // 1 -> data sampler has control of bus
wire[3:0] sample_chan;    // Channel for sampling
wire[4:0] sample_raddr;   // Address in sample_data buffer
wire[31:0] sample_rdata;  // Output from sample_data buffer
wire[31:0] timestamp;     // Timestamp used when sampling

// For real-time write
reg        rt_wen;
wire       fw_rt_wen;
wire       eth_rt_wen;
reg[2:0]   rt_waddr;
wire[2:0]  fw_rt_waddr;
wire[2:0]  eth_rt_waddr;
reg[31:0]  rt_wdata;
wire[31:0] fw_rt_wdata;
wire[31:0] eth_rt_wdata;

// Manage access to data sampling between Ethernet and Firewire.
// As with most shared Ethernet/Firewire functionality, it is assumed that
// only one interface will be receiving packets from the host PC, so this is
// likely to fail if the host PC sends packets by both Ethernet and Firewire.
wire fw_sample_start;
wire eth_sample_start;
assign sample_start = (eth_sample_start|fw_sample_start) & ~sample_busy;

wire eth_sample_read;      // 1 -> Ethernet module has control of sample_raddr
wire[4:0] fw_sample_raddr;
wire[4:0] eth_sample_raddr;
assign sample_raddr = eth_sample_read ? eth_sample_raddr : fw_sample_raddr;

assign reg_raddr = sample_busy ? {`ADDR_MAIN, 4'd0, sample_chan, 4'd0} :
                   eth_read_en ? eth_reg_raddr :
                   fw_reg_raddr;

// Multiplexing of write bus between WriteRtData (bw = real-time block write module),
// Ethernet (eth) and Firewire.
always @(*)
begin
   if (bw_write_en) begin
      reg_wen = bw_reg_wen;
      blk_wen = bw_blk_wen;
      blk_wstart = bw_blk_wstart;
      reg_waddr = {8'd0, bw_reg_waddr};
      reg_wdata = bw_reg_wdata;
   end
   else if (eth_write_en) begin
      reg_wen = eth_reg_wen;
      blk_wen = eth_blk_wen;
      blk_wstart = eth_blk_wstart;
      reg_waddr = eth_reg_waddr;
      reg_wdata = eth_reg_wdata;
   end
   else begin
      reg_wen = fw_reg_wen;
      blk_wen = fw_blk_wen;
      blk_wstart = fw_blk_wstart;
      reg_waddr = fw_reg_waddr;
      reg_wdata = fw_reg_wdata;
   end
end

// Following is for debugging; it is a little risky to allow Ethernet to
// access the FireWire PHY registers without some type of arbitration.
assign lreq_trig = eth_lreq_trig | fw_lreq_trig;
assign lreq_type = eth_lreq_trig ? eth_lreq_type : fw_lreq_type;

wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire[31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_prom_qla; // reads from QLA prom
wire[31:0] reg_rdata_eth;      // for eth memory access
wire[31:0] reg_rdata_fw;       // for fw memory access
wire[31:0] reg_rdata_ds;       // for DS2505 memory access
wire[31:0] reg_rdata_chan0;    // 'channel 0' is a special axis that contains various board I/Os

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                  ((reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                  ((reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom_qla) : 
                  ((reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth) :
                  ((reg_raddr[15:12]==`ADDR_FW) ? (reg_rdata_fw) :
                  ((reg_raddr[15:12]==`ADDR_DS) ? (reg_rdata_ds) :
                  ((reg_raddr[15:12]==`ADDR_DATA_BUF) ? (reg_rdata_databuf) :
                  ((reg_raddr[15:12]==`ADDR_WAVEFORM) ? (reg_rtable) :
                  ((reg_raddr[7:4]==4'd0) ? reg_rdata_chan0 : reg_rd[reg_raddr[3:0]]))))))));

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

// Ethernet
assign ETH_CSn = 0;         // Always select

// The FPGA board is designed to enable the 16-bit bus. If resistor R45
// is populated, then this can be changed by driving ETH_8n low during reset.
// By default, R45 is not populated, so driving this pin has no effect.
assign ETH_8n = 1;          // 16-bit bus

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
wire eth_send_fw_req;
wire eth_send_fw_ack;
wire[8:0] eth_fwpkt_raddr;
wire[31:0] eth_fwpkt_rdata;
wire[15:0] eth_fwpkt_len;
wire[15:0] eth_host_fw_addr;

wire eth_send_req;
wire eth_send_ack;
wire[8:0]  eth_send_addr;
wire[15:0] eth_send_len;

wire fw_bus_reset;

wire[8:0] eth_send_addr_mux;
assign eth_send_addr_mux = eth_send_ack ? eth_send_addr : reg_raddr[8:0];

// phy-link interface
PhyLinkInterface phy(
    .sysclk(sysclk),         // in: global clk  
    .board_id(board_id),     // in: board id (rotary switch)
    .node_id(node_id),       // out: phy node id

    .ctl_ext(ctl),           // bi: phy ctl lines
    .data_ext(data),         // bi: phy data lines
    
    .reg_wen(fw_reg_wen),       // out: reg write signal
    .blk_wen(fw_blk_wen),       // out: block write signal
    .blk_wstart(fw_blk_wstart), // out: block write is starting

    .reg_raddr(fw_reg_raddr),  // out: register address
    .reg_waddr(fw_reg_waddr),  // out: register address
    .reg_rdata(reg_rdata),     // in:  read data to external register
    .reg_wdata(fw_reg_wdata),  // out: write data to external register

    .eth_send_fw_req(eth_send_fw_req), // in: send req from eth
    .eth_send_fw_ack(eth_send_fw_ack), // out: ack send req to eth
    .eth_fwpkt_raddr(eth_fwpkt_raddr), // out: eth fw packet addr
    .eth_fwpkt_rdata(eth_fwpkt_rdata), // in: eth fw packet data
    .eth_fwpkt_len(eth_fwpkt_len),     // out: eth fw packet length
    .eth_fw_addr(eth_host_fw_addr),    // in: eth fw host address (e.g., ffd0)

    // Request from Firewire to send Ethernet packet
    // Note that if !eth_send_ack, then the Firewire packet memory
    // is accessible via reg_raddr/reg_rdata.
    .eth_send_req(eth_send_req),
    .eth_send_ack(eth_send_ack),
    .eth_send_addr(eth_send_addr_mux),
    .eth_send_data(reg_rdata_fw),
    .eth_send_len(eth_send_len),

    // Signal indicating bus reset in process
    .fw_bus_reset(fw_bus_reset),

    .lreq_trig(fw_lreq_trig),  // out: phy request trigger
    .lreq_type(fw_lreq_type),  // out: phy request type

    .rx_bc_sequence(bc_sequence),  // in: broadcast sequence num
    .rx_bc_fpga(bc_board_mask),    // in: mask of boards involved in broadcast read
    .write_trig(hub_write_trig),   // in: 1 -> broadcast write this board's hub data
    .write_trig_reset(hub_write_trig_reset),
    .fw_idle(fw_idle),

    // Interface for real-time block write
    .fw_rt_wen(fw_rt_wen),
    .fw_rt_waddr(fw_rt_waddr),
    .fw_rt_wdata(fw_rt_wdata),

    // Interface for sampling data (for block read)
    .sample_start(fw_sample_start),   // 1 -> start sampling for block read
    .sample_busy(sample_busy),        // Sampling in process
    .sample_raddr(fw_sample_raddr),   // Read address for sampled data
    .sample_rdata(sample_rdata)       // Sampled data (for block read)
);


// phy request module
PhyRequest phyreq(
    .sysclk(sysclk),          // in: global clock
    .lreq(lreq),              // out: phy request line
    .trigger(lreq_trig),      // in: phy request trigger
    .rtype(lreq_type),        // in: phy request type
    .data(reg_wdata[11:0])    // in: phy request data
);

// --------------------------------------------------------------------------
// Ethernet module
// --------------------------------------------------------------------------

wire[31:0] Eth_Result;

// address decode for IP address access
wire   ip_reg_wen;
assign ip_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_IPADDR}) ? reg_wen : 1'b0;
wire[31:0] ip_address;

EthernetIO EthernetTransfers(
    .sysclk(sysclk),          // in: global clock

    .board_id(board_id),      // in: board id (rotary switch)
    .node_id(node_id),        // in: phy node id

    // Interface to KSZ8851
    .ETH_IRQn(ETH_IRQn),      // in: interrupt request from KSZ8851
    .ETH_RSTn(ETH_RSTn),      // out: reset to KSZ8851
    .ETH_CMD(ETH_CMD),        // out: CMD to KSZ8851 (0=data, 1=addr)
    .ETH_RDn(ETH_RDn),        // out: read strobe to KSZ8851
    .ETH_WRn(ETH_WRn),        // out: write strobe to KSZ8851
    .SD(SD),                  // inout: addr/data bus to KSZ8851

    // Firewire interface to KSZ8851 (for testing). Results are provided
    // via eth_data and eth_status, which are combined in the 32-bit register
    // Eth_Result, which is available via board register REG_ETHRES (12).
    .fw_reg_wen(fw_reg_wen),           // in: write enable from FireWire
    .fw_reg_waddr(fw_reg_waddr),       // in: write address from FireWire
    .fw_reg_wdata(fw_reg_wdata),       // in: data from FireWire
    .eth_data(Eth_Result[15:0]),       // out: Last register read
    .eth_status(Eth_Result[31:16]),    // out: Ethernet status register

    // Register interface to Ethernet memory space (ADDR_ETH=0x4000)
    // and IP address register (REG_IPADDR=11).
    .reg_rdata(reg_rdata_eth),         // Data from Ethernet memory space
    .reg_raddr(reg_raddr),             // Read address for Ethernet memory
    .reg_wdata(reg_wdata),             // Data to write to IP address register
    .ip_reg_wen(ip_reg_wen),           // Enable write to IP address register
    .ip_address(ip_address),           // IP address of this board

    // Interface to/from board registers. These enable the Ethernet module to drive
    // the internal bus on the FPGA. In particular, they are used to read registers
    // to respond to quadlet read and block read commands.
    .eth_reg_rdata(reg_rdata),         //  in: reg read data
    .eth_reg_raddr(eth_reg_raddr),     // out: reg read addr
    .eth_read_en(eth_read_en),         // out: reg read enable
    .eth_reg_wdata(eth_reg_wdata),     // out: reg write data
    .eth_reg_waddr(eth_reg_waddr),     // out: reg write addr
    .eth_reg_wen(eth_reg_wen),         // out: reg write enable
    .eth_block_wen(eth_blk_wen),       // out: blk write enable
    .eth_block_wstart(eth_blk_wstart), // out: blk write start
    .eth_write_en(eth_write_en),       // out: write bus enable

    // Low-level Firewire PHY access
    .lreq_trig(eth_lreq_trig),   // out: phy request trigger
    .lreq_type(eth_lreq_type),   // out: phy request type

    // Interface to FireWire module (for sending packets via FireWire)
    .eth_send_fw_req(eth_send_fw_req), // out: req to send fw pkt
    .eth_send_fw_ack(eth_send_fw_ack), // in: ack from fw module
    .eth_fwpkt_raddr(eth_fwpkt_raddr), // out: eth fw packet addr
    .eth_fwpkt_rdata(eth_fwpkt_rdata), // in: eth fw packet data
    .eth_fwpkt_len(eth_fwpkt_len),     // out: eth fw packet len
    .host_fw_addr(eth_host_fw_addr),   // out: eth fw host address (e.g., ffd0)

    // Interface from Firewire (for sending packets via Ethernet)
    .sendReq(eth_send_req),
    .sendAck(eth_send_ack),
    .sendAddr(eth_send_addr),
    .sendData(reg_rdata_fw),
    .sendLen(eth_send_len),

    // Signal from Firewire indicating bus reset in process
    .fw_bus_reset(fw_bus_reset),

    // Interface for real-time block write
    .eth_rt_wen(eth_rt_wen),
    .eth_rt_waddr(eth_rt_waddr),
    .eth_rt_wdata(eth_rt_wdata),

    // Interface for sampling data (for block read)
    .sample_start(eth_sample_start),   // 1 -> start sampling for block read
    .sample_busy(sample_busy),         // Sampling in process
    .sample_read(eth_sample_read),     // 1 -> reading from sample memory
    .sample_raddr(eth_sample_raddr),   // Read address for sampled data
    .sample_rdata(sample_rdata),       // Sampled data (for block read)
    .timestamp(timestamp)              // timestamp
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
`ifdef DIAGNOSTIC
    .board_id(board_id),
`endif
    .sclk(IO1[21]),
    .mosi(IO1[20]),
    .csel(IO1[22]),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .reg_rchan(reg_raddr[7:4]),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdac),
    .reg_wdata(reg_wdata[15:0]),
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

// divide 25 MHz clock down to 400 kHz for temperature sensor readings
// TO FIX: dividing by 63 gives ~397 kHz (actual factor is 62.5)
wire clk400k_raw, clk400k;
ClkDivI divtemp(clk25m, clk400k_raw);
defparam divtemp.div = 63;
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

wire[31:0] reg_status;    // Status register
wire[31:0] reg_digio;     // Digital I/O register
wire[15:0] tempsense;     // Temperature sensor
wire[15:0] reg_databuf;   // Data collection status

wire reboot;              // Reboot the FPGA

`ifdef WDOG_LED
// used to check status of user defined watchdog period; used to control LED 
wire[2:0] wdog_period_status;
wire wdog_timeout_led;
`endif

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
    .ip_address(ip_address),
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
    .reg_digin(reg_digio)
`ifdef WDOG_LED
    ,
    .wdog_period_status(wdog_period_status),
    .wdog_timeout_led(wdog_timeout_led)
`endif
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

always @(*)
begin
   if (eth_rt_wen) begin
      rt_wen = eth_rt_wen;
      rt_waddr = eth_rt_waddr;
      rt_wdata = eth_rt_wdata;
   end
   else begin
      rt_wen = fw_rt_wen;
      rt_waddr = fw_rt_waddr;
      rt_wdata = fw_rt_wdata;
   end
end

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
// debugging, etc.
//
reg[23:0] CountC;
reg[23:0] CountI;
// TO FIX: clk40m changed to clk25m
always @(posedge(clk25m)) CountC <= CountC + 1'b1;
always @(posedge(sysclk)) CountI <= CountI + 1'b1;

assign LED = IO1[32];     // NOTE: IO1[32] pwr_enable
// assign LED = reg_led;

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
`ifdef WDOG_LED
    .wdog_period_status(wdog_period_status),
    .wdog_timeout_led(wdog_timeout_led),
`endif
    .led1_grn(IO2[1]),
    .led1_red(IO2[3]),
    .led2_grn(IO2[5]),
    .led2_red(IO2[7])
);

endmodule
