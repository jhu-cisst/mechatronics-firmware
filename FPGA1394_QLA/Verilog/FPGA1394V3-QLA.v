/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394-QLA motor controller interface.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/27/11    Paul Thienphrapa    Initial revision (pault at cs.jhu.edu)
 *     02/29/12    Zihan Chen
 *     08/29/18    Peter Kazanzides    Added DS2505 module
 *     01/22/20    Peter Kazanzides    Removed global reset
 *     04/28/22    Peter Kazanzides    Adapted for FPGA V3
 */

`timescale 1ns / 1ps

`define HAS_ETHERNET

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"

module FPGA1394V3QLA
(
    // ieee 1394 phy-link interface
    input            clk1394,   // 49.152 MHz
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // misc board I/Os
    input [3:0]      wenid,     // rotary switch
    inout [0:33]     IO1,
    inout [0:39]     IO2,
    output wire      LED,

    // Ethernet PHYs (RTL8211F)
    output wire      E1_MDIO_C,   // eth1 MDIO clock
    output wire      E2_MDIO_C,   // eth2 MDIO clock
    //Following is directly connected via constraint file
    //inout wire     E1_MDIO_D,   // eth1 MDIO data
    inout wire       E2_MDIO_D,   // eth2 MDIO data
    output wire      E1_RSTn,     // eth1 PHY reset
    output wire      E2_RSTn,     // eth2 PHY reset
    input wire       E1_IRQn,     // eth1 IRQ (FPGA V3.1+)
    input wire       E2_IRQn,     // eth2 IRQ (FPGA V3.1+)

    input wire       E1_RxCLK,    // eth1 receive clock (from PHY)
    input wire       E1_RxVAL,    // eth1 receive valid
    input wire[3:0]  E1_RxD,      // eth1 data bits
    output wire      E1_TxCLK,    // eth1 transmit clock
    output wire      E1_TxEN,     // eth1 transmit enable
    output wire[3:0] E1_TxD,      // eth1 transmit data

`ifdef ETHERNET_DUAL
    input wire       E2_RxCLK,    // eth2 receive clock (from PHY)
    input wire       E2_RxVAL,    // eth2 receive valid
    input wire[3:0]  E2_RxD,      // eth2 data bits
    output wire      E2_TxCLK,    // eth2 transmit clock
    output wire      E2_TxEN,     // eth2 transmit enable
    output wire[3:0] E2_TxD,      // eth2 transmit data
`endif

    // PS7 interface
    inout[53:0]      MIO,
    input            PS_SRSTB,
    input            PS_CLK,
    input            PS_PORB
);

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //

    wire LED_Int;               // internal signal to drive LED on FPGA
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

//------------------------------------------------------------------------------
// hardware description
//

BUFG clksysclk(.I(clk1394), .O(sysclk));

// Wires for sampling block read data (shared between Ethernet and Firewire)
wire sample_start;        // Start sampling read data
wire sample_busy;         // 1 -> data sampler has control of bus
wire[3:0] sample_chan;    // Channel for sampling
wire[5:0] sample_raddr;   // Address in sample_data buffer
wire[31:0] sample_rdata;  // Output from sample_data buffer
wire[31:0] timestamp;     // Timestamp used when sampling

// For real-time write
reg        rt_wen;
wire       fw_rt_wen;
wire       eth_rt_wen;
reg[3:0]   rt_waddr;
wire[3:0]  fw_rt_waddr;
wire[3:0]  eth_rt_waddr;
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
wire[5:0] fw_sample_raddr;
wire[5:0] eth_sample_raddr;
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
wire[31:0] reg_rdata_eth;      // for eth memory access (EthernetIO)
wire[31:0] reg_rdata_rtl;      // for eth memory access (RTL8211F)
wire[31:0] reg_rdata_fw;       // for fw memory access
wire[31:0] reg_rdata_ds;       // for DS2505 memory access
wire[31:0] reg_rdata_chan0;    // 'channel 0' is a special axis that contains various board I/Os
wire[31:0] reg_rdata_ioexp;    // reads from MAX7317 I/O expander (QLA 1.5+)

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                   (reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                   (reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom_qla) :
                   (reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth|reg_rdata_rtl) :
                   (reg_raddr[15:12]==`ADDR_FW) ? (reg_rdata_fw) :
                   (reg_raddr[15:12]==`ADDR_DS) ? (reg_rdata_ds) :
                   (reg_raddr[15:12]==`ADDR_DATA_BUF) ? (reg_rdata_databuf) :
                   (reg_raddr[15:12]==`ADDR_WAVEFORM) ? (reg_rtable) :
                   (reg_raddr[7:4]!=4'd0) ? (reg_rd[reg_raddr[3:0]]) :
                   (reg_raddr[3:0]==`REG_IO_EXP) ? (reg_rdata_ioexp) : (reg_rdata_chan0);

// Unused channel offsets
assign reg_rd[`OFF_UNUSED_02] = 32'd0;
assign reg_rd[`OFF_UNUSED_03] = 32'd0;
assign reg_rd[`OFF_UNUSED_13] = 32'd0;
assign reg_rd[`OFF_UNUSED_14] = 32'd0;
assign reg_rd[`OFF_UNUSED_15] = 32'd0;

// 1394 phy low reset, never reset
assign reset_phy = 1'b1; 

// Extra IO from FPGA V3.1, not used for QLA
// IO1[0] is used for LED in FPGA V3.0
assign IO1[33] = 1'bz;
assign IO2[0] = 1'bz;
assign IO2[39] = 1'bz;

// --------------------------------------------------------------------------
// hub register module
// --------------------------------------------------------------------------

wire[15:0] bc_sequence;
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
//
// When using the GMII to RGMII core, MDIO signals from the RTL8211F module
// are connected to the GMII to RGMII core, and then the MDIO and MDC signals
// from the core are connected to the RTL8211F PHY. If the GMII to RGMII core
// is not used, the MDIO signals from the RTL8211F module are connected directly
// to the RTL8211F PHY.
//
// Currently, E1 uses the GMII to RGMII core, whereas E2 does not. This is because
// it is not yet possible to instantiate a second GMII to RGMII core due to the
// duplicate IDELAYCTRL.

// The Ethernet result is used to distinguish between FPGA versions
//    Rev 1:  Eth_Result == 32'd0
//    Rev 2:  Eth_Result[31] == 1, other bits variable
//    Rev 3:  Eth_Result[31:30] == 01, other bits variable
wire[31:0] Eth_Result;
assign  Eth_Result = 32'h40000000;

// GMII signals (generated by gmii_to_rgmii cores)
wire[7:0]  E1_gmii_txd;
wire       E1_gmii_tx_en;
wire       E1_gmii_tx_clk;
wire[7:0]  E1_gmii_rxd;
wire       E1_gmii_rx_dv;
wire       E1_gmii_rx_er;
wire       E1_gmii_rx_clk;
wire       E1_mdio_o;         // OUT from RTL8211F module, IN to GMII core (or PHY)
wire       E1_mdio_i;         // IN to RTL8211F module, OUT from GMII core (or PHY)
wire       E1_mdio_t;         // OUT from RTL8211F module (tristate control)
wire       E1_mdio_clk;       // OUT from RTL8211F module, IN to GMII core (or PHY)

`ifdef ETHERNET_DUAL
wire[7:0]  E2_gmii_txd;
wire       E2_gmii_tx_en;
wire       E2_gmii_tx_clk;
wire[7:0]  E2_gmii_rxd;
wire       E2_gmii_rx_dv;
wire       E2_gmii_rx_er;
wire       E2_gmii_rx_clk;
`endif
wire       E2_mdio_o;         // OUT from RTL8211F module, IN to GMII core (or PHY)
wire       E2_mdio_i;         // IN to RTL8211F module, OUT from GMII core (or PHY)
wire       E2_mdio_t;         // OUT from RTL8211F module (tristate control)
wire       E2_mdio_clk;       // OUT from RTL8211F module, IN to GMII core (or PHY)

wire[31:0] reg_rdata_e1;
wire[31:0] reg_rdata_e2;

assign reg_rdata_eth = (reg_raddr[11:8] == 4'd1) ? reg_rdata_e1 :
                       (reg_raddr[11:8] == 4'd2) ? reg_rdata_e2 :
                       32'd0;

wire[31:0] reg_rdata_rtl_e1;
wire[31:0] reg_rdata_rtl_e2;

assign reg_rdata_rtl = (reg_raddr[11:8] == 4'd1) ? reg_rdata_rtl_e1 :
                       (reg_raddr[11:8] == 4'd2) ? reg_rdata_rtl_e2 :
                       32'd0;

// Can write to 4xay, where x is the Ethernet port number (1 or 2) and y is the offset.
// Currently, y=0 is the only valid write address.
wire reg_wen_e1;
assign reg_wen_e1 = (reg_waddr[15:4] == {`ADDR_ETH, 4'h1, 4'ha}) ? reg_wen : 1'b0;
wire reg_wen_e2;
assign reg_wen_e2 = (reg_waddr[15:4] == {`ADDR_ETH, 4'h2, 4'ha}) ? reg_wen : 1'b0;

// Wires between KSZ8851/RTL8211F and EthernetIO
wire eth_resetActive;           // Indicates that reset is active
wire eth_isForward;             // Indicates that FireWire receiver is forwarding to Ethernet
wire eth_responseRequired;      // Indicates that the received packet requires a response
wire[15:0] eth_responseByteCount;   // Number of bytes in required response
wire eth_recvRequest;           // Request EthernetIO to start receiving
wire eth_recvBusy;              // EthernetIO receive state machine busy
wire eth_recvReady;             // Indicates that recv_word is valid
wire[15:0] eth_recv_word;       // Word received via Ethernet (`SDSwapped for KSZ8851)
wire eth_sendRequest;           // Request EthernetIO to get ready to start sending
wire eth_sendBusy;              // EthernetIO send state machine busy
wire eth_sendReady;             // Request EthernetIO to provide next send_word
wire[15:0] eth_send_word;       // Word to send via Ethernet (SDRegDWR for KSZ8851)
wire eth_bw_active;             // Indicates that block write module is active
wire eth_InternalError;         // Error summary bit to EthernetIO
wire[5:0] eth_ioErrors;         // Error bits from EthernetIO
wire useUDP;                    // Whether EthernetIO is using UDP

RTL8211F #(.CHANNEL(4'd1)) EthPhy1(
    .clk(sysclk),             // in:  global clock

    .reg_raddr(reg_raddr),    // in:  read address
    .reg_waddr(reg_waddr),    // in:  write address
    .reg_rdata(reg_rdata_rtl_e1), // out: read data
    .reg_wdata(reg_wdata),    // in:  write data
    .reg_wen(reg_wen_e1),     // in:  write enable

    .RSTn(E1_RSTn),           // Reset to RTL8211F
    .IRQn(E1_IRQn),           // Interrupt from RTL8211F (FPGA V3.1+)

    .MDC(E1_mdio_clk),        // Clock to GMII core (and RTL8211F PHY)
    .MDIO_I(E1_mdio_i),       // IN to RTL8211F module, OUT from GMII core
    .MDIO_O(E1_mdio_o),       // OUT from RTL8211F module, IN to GMII core
    .MDIO_T(E1_mdio_t),       // Tristate signal from RTL8211F module

    .RxClk(E1_gmii_rx_clk),   // Rx Clk
    .RxValid(E1_gmii_rx_dv),  // Rx Valid
    .RxD(E1_gmii_rxd),        // Rx Data
    .RxErr(E1_gmii_rx_er),    // Rx Error

    .TxClk(E1_gmii_tx_clk),   // Tx Clk
    .TxEn(E1_gmii_tx_en),     // Tx Enable
    .TxD(E1_gmii_txd),        // Tx Data

    // Interface from Firewire (for sending packets via Ethernet)
    .sendReq(eth_send_req),

    // Interface to EthernetIO
    .resetActive(eth_resetActive),    // Indicates that reset is active
    .isForward(eth_isForward),        // Indicates that FireWire receiver is forwarding to Ethernet
    .responseRequired(eth_responseRequired),   // Indicates that the received packet requires a response
    .responseByteCount(eth_responseByteCount), // Number of bytes in required response
    .recvRequest(eth_recvRequest),    // Request EthernetIO to start receiving
    .recvBusy(eth_recvBusy),          // To RTL8211F
    .recvReady(eth_recvReady),        // Indicates that recv_word is valid
    .recv_word(eth_recv_word),        // Word received via Ethernet (`SDSwapped for KSZ8851)
    .sendRequest(eth_sendRequest),    // Request EthernetIO to get ready to start sending
    .sendBusy(eth_sendBusy),          // To KSZ8851
    .sendReady(eth_sendReady),        // Request EthernetIO to provide next send_word
    .send_word(eth_send_word),        // Word to send via Ethernet (SDRegDWR for KSZ8851)
    .bw_active(eth_bw_active),        // Indicates that block write module is active
    .ethInternalError(eth_InternalError),   // Error summary bit to EthernetIO
    .useUDP(useUDP)                   // Whether EthernetIO is using UDP
);

RTL8211F #(.CHANNEL(4'd2)) EthPhy2(
    .clk(sysclk),             // in:  global clock

    .reg_raddr(reg_raddr),    // in:  read address
    .reg_waddr(reg_waddr),    // in:  write address
    .reg_rdata(reg_rdata_rtl_e2), // out: read data
    .reg_wdata(reg_wdata),    // in:  write data
    .reg_wen(reg_wen_e2),     // in:  write enable

    .RSTn(E2_RSTn),           // Reset to RTL8211F
    .IRQn(E2_IRQn),           // Interrupt from RTL8211F (FPGA V3.1+)

    .MDC(E2_mdio_clk),        // Clock to GMII core (if present) and RTL8211F PHY
    .MDIO_I(E2_mdio_i),       // IN to RTL8211F module, OUT from GMII core or RTL8211F PHY
    .MDIO_O(E2_mdio_o),       // OUT from RTL8211F module, IN to GMII core or RTL8211F PHY
    .MDIO_T(E2_mdio_t),       // Tristate signal from RTL8211F module

`ifdef ETHERNET_DUAL
    .RxClk(E2_gmii_rx_clk),   // Rx Clk
    .RxValid(E2_gmii_rx_dv),  // Rx Valid
    .RxD(E2_gmii_rxd),        // Rx Data
    .RxErr(E2_gmii_rx_er),    // Rx Error

    .TxClk(E2_gmii_tx_clk),   // Tx Clk
    .TxEn(E2_gmii_tx_en),     // Tx Enable
    .TxD(E2_gmii_txd),        // Tx Data

    // Interface from Firewire (for sending packets via Ethernet)
    .sendReq(eth_send_req),

    // Interface to EthernetIO
    .resetActive(eth_resetActive),    // Indicates that reset is active
    .isForward(eth_isForward),        // Indicates that FireWire receiver is forwarding to Ethernet
    .responseRequired(eth_responseRequired),   // Indicates that the received packet requires a response
    .responseByteCount(eth_responseByteCount), // Number of bytes in required response
    .recvRequest(eth_recvRequest),    // Request EthernetIO to start receiving
    .recvBusy(eth_recvBusy),          // To KSZ8851
    .recvReady(eth_recvReady),        // Indicates that recv_word is valid
    .recv_word(eth_recv_word),        // Word received via Ethernet (`SDSwapped for KSZ8851)
    .sendRequest(eth_sendRequest),    // Request EthernetIO to get ready to start sending
    .sendBusy(eth_sendBusy),          // To KSZ8851
    .sendReady(eth_sendReady),        // Request EthernetIO to provide next send_word
    .send_word(eth_send_word),        // Word to send via Ethernet (SDRegDWR for KSZ8851)
    .bw_active(eth_bw_active),        // Indicates that block write module is active
    .ethInternalError(eth_InternalError),   // Error summary bit to EthernetIO
    .useUDP(useUDP)                   // Whether EthernetIO is using UDP
`else
    .RxClk(1'b0),
    .RxValid(1'b0),
    .RxD(4'd0),
    .RxErr(1'b0),
    .TxClk(1'b0),
    .sendReq(1'b0)
`endif
);

`ifndef ETHERNET_DUAL
assign E2_MDIO_C = E2_mdio_clk;
assign E2_MDIO_D = E2_mdio_t ? 1'bz : E2_mdio_o;
assign E2_mdio_i = E2_MDIO_D;
`endif

// address decode for IP address access
wire   ip_reg_wen;
assign ip_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_IPADDR}) ? reg_wen : 1'b0;
wire[31:0] ip_address;

EthernetIO EthernetTransfers1(
    .sysclk(sysclk),          // in: global clock

    .board_id(board_id),      // in: board id (rotary switch)
    .node_id(node_id),        // in: phy node id

    // Register interface to Ethernet memory space (ADDR_ETH=0x4000)
    // and IP address register (REG_IPADDR=11).
    .reg_rdata(reg_rdata_e1),          // Data from Ethernet memory space
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
    // Note that sendReq(eth_send_req) is in KSZ8851
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
    .timestamp(timestamp),             // timestamp

    // Interface to EthernetIO
    .resetActive(eth_resetActive),    // Indicates that reset is active
    .isForward(eth_isForward),        // Indicates that FireWire receiver is forwarding to Ethernet
    .responseRequired(eth_responseRequired),   // Indicates that the received packet requires a response
    .responseByteCount(eth_responseByteCount), // Number of bytes in required response
    .recvRequest(eth_recvRequest),    // Request EthernetIO to start receiving
    .recvBusy(eth_recvBusy),          // To KSZ8851
    .recvReady(eth_recvReady),        // Indicates that recv_word is valid
    .recv_word(eth_recv_word),        // Word received via Ethernet (`SDSwapped for KSZ8851)
    .sendRequest(eth_sendRequest),    // Request EthernetIO to get ready to start sending
    .sendBusy(eth_sendBusy),          // To KSZ8851
    .sendReady(eth_sendReady),        // Request EthernetIO to provide next send_word
    .send_word(eth_send_word),        // Word to send via Ethernet (SDRegDWR for KSZ8851)
    .bw_active(eth_bw_active),        // Indicates that block write module is active
    .ethLLError(eth_InternalError),   // Error summary bit to EthernetIO
    .ethioErrors(eth_ioErrors),       // Error bits from EthernetIO
    .useUDP(useUDP)                   // Whether EthernetIO is using UDP
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

// ----------------------------------------------------------------------------
// Read/Write of commanded current (cur_cmd) and amplifier enable
//
// This is now done in MotorChannelQLA (rather than CtrlDac) to support digital
// control implementations.
// ----------------------------------------------------------------------------

wire ioexp_cfg_reset;       // 1 -> Check if I/O expander (MAX7317) present
wire ioexp_cfg_present;     // 1 -> I/O expander (MAX7317) detected

// safety_amp_enable from SafetyCheck module
wire[4:1] safety_amp_disable;

// amp_disable is output from BoardRegs (set by host PC)
wire[4:1] amp_disable;

// amp_disable_pin is output from MotorChannelQLA and is output via FPGA
wire[4:1] amp_disable_pin;

// Fault signal from op amp, active low (1 -> amplifier on, 0 -> fault)
wire[4:1] amp_fault;
assign amp_fault = { IO2[37], IO2[35], IO2[33], IO2[31] };

// 1 -> Force follower op amp to always be enabled
wire[4:1] force_disable_f;

wire[4:1] cur_ctrl_error;
wire[4:1] disable_f_error;

wire[15:0] cur_cmd[1:4];     // Commanded current per channel
wire[3:0] ctrl_mode[1:4];    // Control mode per channel
wire cur_ctrl[1:4];          // 1 -> current control, 0 -> voltage control

// Motor status feedback
wire[31:0] motor_status[1:4];
wire[31:0] reg_motor_status;

// Motor configuration
wire[31:0] motor_config[1:4];

// Delay clock, used to delay the amplifier enable.
// 49.152 MHz / 2**10 ==> 48 kHz (1 cnt = 20.83 us)
wire clkdiv32, clk_delay;
ClkDiv div32clk(sysclk, clkdiv32);
defparam div32clk.width = 10;
BUFG delayclk(.I(clkdiv32), .O(clk_delay));

genvar k;
generate
    for (k = 1; k <= 4; k = k + 1) begin : mchan_loop
        wire clr_safety_disable;
        assign clr_safety_disable = pwr_enable_cmd | amp_enable_cmd[k];

        MotorChannelQLA #(.CHANNEL(k)) Motor_instance(
            .clk(sysclk),
            .delay_clk(clk_delay),

            .reg_waddr(reg_waddr),
            .reg_wdata(reg_wdata),
            .reg_wen(reg_wen),
            .motor_status(motor_status[k]),
            .motor_config(motor_config[k]),

            .ioexp_present(ioexp_cfg_present),

            .safety_amp_disable(safety_amp_disable[k]),
            .amp_fault(amp_fault[k]),
            .cur_ctrl_error(cur_ctrl_error[k]),
            .disable_f_error(disable_f_error[k]),
            .amp_disable(amp_disable[k]),
            .amp_disable_pin(amp_disable_pin[k]),
            .force_disable_f(force_disable_f[k]),

            .cur_cmd(cur_cmd[k]),
            .ctrl_mode(ctrl_mode[k]),
            .cur_ctrl(cur_ctrl[k]),

            .cur_fb(cur_fb[k]),
            .clr_safety_disable(clr_safety_disable)
        );
    end
endgenerate

assign IO2[32] = amp_disable_pin[1];
assign IO2[34] = amp_disable_pin[2];
assign IO2[36] = amp_disable_pin[3];
assign IO2[38] = amp_disable_pin[4];

// Check for non-zero channel number (reg_waddr[7:4]) to ignore write to global register.
// It would be even better to check that channel number is 1-4.
wire reg_waddr_dac;
assign reg_waddr_dac = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] != 4'd0) &&
                        (reg_waddr[3:0]==`OFF_DAC_CTRL)) ? 1'd1 : 1'd0;

wire dac_busy;
reg cur_cmd_updated;

reg cur_cmd_req;

always @(posedge(sysclk))
begin
    if (reg_waddr_dac) begin
        cur_cmd_req <= blk_wen;
    end
    else if (cur_cmd_req&(~dac_busy)) begin
        cur_cmd_req <= 0;
    end
    cur_cmd_updated <= cur_cmd_req&(~dac_busy);
end

assign reg_rd[`OFF_DAC_CTRL] = cur_cmd[reg_raddr[7:4]];

assign reg_motor_status = motor_status[reg_raddr[7:4]];
assign reg_rd[`OFF_MOTOR_STATUS] = reg_motor_status;
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

// divide 49.152 MHz clock down to 400 kHz for temperature sensor readings
ClkDivI divtemp(sysclk, clk400k_raw);
defparam divtemp.div = 122;

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
// QLA prom 25AA128
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
    .prom_mosi(qla_prom_mosi),
    .prom_miso(IO1[1]),
    .prom_sclk(qla_prom_sclk),
    .prom_cs(IO1[4]),
    .other_busy(io_exp_busy),
    .this_busy(qla_prom_busy)
);

// --------------------------------------------------------------------------
// MAX7317: I/O Expander
// --------------------------------------------------------------------------

// amp_disable, bit reversed; if force_disable_f, then output is 0
wire[4:1] amp_disable_rev;
assign amp_disable_rev = { (~force_disable_f[1])&amp_disable[1],
                           (~force_disable_f[2])&amp_disable[2],
                           (~force_disable_f[3])&amp_disable[3],
                           (~force_disable_f[4])&amp_disable[4] };

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
    .other_busy(qla_prom_busy),
    .this_busy(io_exp_busy),

    // Signals
    .P30({cur_ctrl[1], cur_ctrl[2], cur_ctrl[3], cur_ctrl[4]}),
    .P74(amp_disable_rev),
    .P98({mv_fb, safety_fb_n}),

    .P30_error({cur_ctrl_error[1], cur_ctrl_error[2], cur_ctrl_error[3], cur_ctrl_error[4]}),
    .P74_error({disable_f_error[1], disable_f_error[2], disable_f_error[3], disable_f_error[4]})
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

// pwr_enable_cmd and amp_enable_cmd from BoardRegs; used to clear safety_amp_disable
wire pwr_enable_cmd;
wire[4:1] amp_enable_cmd;

wire[31:0] reg_status;    // Status register
wire[31:0] reg_digio;     // Digital I/O register
wire[15:0] tempsense;     // Temperature sensor
wire[15:0] reg_databuf;   // Data collection status

wire reboot;              // Reboot the FPGA

// used to check status of user defined watchdog period; used to control LED 
wire      wdog_period_led;
wire[2:0] wdog_period_status;
wire wdog_timeout;
wire[31:0] clk_test;

BoardRegs chan0(
    .sysclk(sysclk),
    .reboot(reboot),
    .amp_disable(amp_disable),
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
    .enc_b({IO2[10], IO2[12], IO2[13], IO2[15]}),
    .enc_i({IO2[2], IO2[4], IO2[6], IO2[8]}),
    .neg_limit({IO2[26],IO2[24],IO2[25],IO2[22]}),
    .pos_limit({IO2[30],IO2[29],IO2[28],IO2[27]}),
    .home({IO2[20],IO2[18],IO2[16],IO2[14]}),
    .fault(amp_fault),
    .relay(IO2[9]),
    .mv_faultn(IO1[7]),
    .mv_good(IO2[11]),
    .v_fault(IO1[9]),
    .safety_fb(~safety_fb_n),
    .mv_fb(mv_fb),
    .board_id(board_id),
    .temp_sense(tempsense),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .prom_status(clk_test),       // Not supported in V3
    .prom_result(32'd0),          // Not supported in V3
    .ip_address(ip_address),
    .eth_result(Eth_Result),
    .ds_status(ds_status),
    .safety_amp_disable(safety_amp_disable),
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
    .motor_status(reg_motor_status),
    .blk_addr(sample_raddr),
    .blk_data(sample_rdata),
    .timestamp(timestamp)
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

// LED on FPGA
assign LED_Int = IO1[32];     // NOTE: IO1[32] pwr_enable

// LED is connected to different pins on V3.0 and V3.1
// For V3.0, it is fine to drive both pins
// TODO: For V3.1, should comment out first line below
assign IO1[0] = LED_Int;     // FPGA V3.0 (pin N18)
assign LED = LED_Int;        // FPGA V3.1 (pin U13)

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

wire clk_200MHz;

fpgav3 zynq_ps7(
    .processing_system7_0_MIO(MIO),
    .processing_system7_0_PS_SRSTB_pin(PS_SRSTB),
    .processing_system7_0_PS_CLK_pin(PS_CLK),
    .processing_system7_0_PS_PORB_pin(PS_PORB),
    .processing_system7_0_GPIO_I_pin({60'd0, board_id}),
    .processing_system7_0_FCLK_CLK0_pin(clk_200MHz),

    .gmii_to_rgmii_1_rgmii_txd_pin(E1_TxD),
    .gmii_to_rgmii_1_rgmii_tx_ctl_pin(E1_TxEN),
    .gmii_to_rgmii_1_rgmii_txc_pin(E1_TxCLK),
    .gmii_to_rgmii_1_rgmii_rxd_pin(E1_RxD),
    .gmii_to_rgmii_1_rgmii_rx_ctl_pin(E1_RxVAL),
    .gmii_to_rgmii_1_rgmii_rxc_pin(E1_RxCLK),
    .gmii_to_rgmii_1_gmii_txd_pin(E1_gmii_txd),
    .gmii_to_rgmii_1_gmii_tx_en_pin(E1_gmii_tx_en),
    .gmii_to_rgmii_1_gmii_tx_clk_pin(E1_gmii_tx_clk),
    .gmii_to_rgmii_1_gmii_rxd_pin(E1_gmii_rxd),
    .gmii_to_rgmii_1_gmii_rx_dv_pin(E1_gmii_rx_dv),
    .gmii_to_rgmii_1_gmii_rx_er_pin(E1_gmii_rx_er),
    .gmii_to_rgmii_1_gmii_rx_clk_pin(E1_gmii_rx_clk),
    .gmii_to_rgmii_1_MDIO_MDC_pin(E1_mdio_clk),       // MDIO clock from RTL8211F module
    .gmii_to_rgmii_1_MDIO_I_pin(E1_mdio_i),           // OUT from GMII core, IN to RTL8211F module
    .gmii_to_rgmii_1_MDIO_O_pin(E1_mdio_o),           // IN to GMII core, OUT from RTL8211F module
    .gmii_to_rgmii_1_MDIO_T_pin(E1_mdio_t),           // Tristate control from RTL8211F module
    .gmii_to_rgmii_1_MDC_pin(E1_MDIO_C)               // MDIO clock from GMII core (derived from E1_mdio_clk)

`ifdef ETHERNET_DUAL
    ,
    .gmii_to_rgmii_2_rgmii_txd_pin(E2_TxD),
    .gmii_to_rgmii_2_rgmii_tx_ctl_pin(E2_TxEN),
    .gmii_to_rgmii_2_rgmii_txc_pin(E2_TxCLK),
    .gmii_to_rgmii_2_rgmii_rxd_pin(E2_RxD),
    .gmii_to_rgmii_2_rgmii_rx_ctl_pin(E2_RxVAL),
    .gmii_to_rgmii_2_rgmii_rxc_pin(E2_RxCLK),
    .gmii_to_rgmii_2_gmii_txd_pin(E2_gmii_txd),
    .gmii_to_rgmii_2_gmii_tx_en_pin(E2_gmii_tx_en),
    .gmii_to_rgmii_2_gmii_tx_clk_pin(E2_gmii_tx_clk),
    .gmii_to_rgmii_2_gmii_rxd_pin(E2_gmii_rxd),
    .gmii_to_rgmii_2_gmii_rx_dv_pin(E2_gmii_rx_dv),
    .gmii_to_rgmii_2_gmii_rx_er_pin(E2_gmii_rx_er),
    .gmii_to_rgmii_2_gmii_rx_clk_pin(E2_gmii_rx_clk),
    .gmii_to_rgmii_1_MDIO_MDC_pin(E2_mdio_clk),       // MDIO clock from RTL8211F module
    .gmii_to_rgmii_2_MDIO_I_pin(E2_mdio_i),           // OUT from GMII core, IN to RTL8211F module
    .gmii_to_rgmii_2_MDIO_O_pin(E2_mdio_o),           // IN to GMII core, OUT from RTL8211F module
    .gmii_to_rgmii_2_MDIO_T_pin(E2_mdio_t),           // Tristate control from RTL8211F module
    .gmii_to_rgmii_2_MDC(E2_MDIO_C)                   // MDIO clock from GMII core (derived from E2_mdio_clk)
`endif
);

// *** BEGIN: TEST code for PS clocks
reg[15:0] cnt_200;
assign clk_test = {16'd0, cnt_200};   // quadlet read from 8 (PROM Status)

always @(posedge clk_200MHz)
begin
    cnt_200 <= cnt_200 + 16'd1;
end

// *** END: TEST code for PS clocks

endmodule
