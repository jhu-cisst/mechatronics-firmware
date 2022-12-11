/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * This module contains common code for FPGA V3 and does not make any assumptions
 * about which board is connected.
 *
 * Revision history
 *     12/10/22    Peter Kazanzides    Created from FPGA1394V3-QLA.v
 */

`define ETH1    // Also need to update XC7Z020.ucf

module FPGA1394V3(
    // global clock
    input wire       sysclk,

    // reboot signal (not supported for FPGA V3)
    input wire       reboot,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,

    // LED
    output wire      LED,

    // Indicate whether FPGA V3.0
    output wire      isV30,

    // Firewire interface
    // phy-link interface bus
    inout[7:0]       data,
    inout[1:0]       ctl,
    output wire      lreq,
    output wire      reset_phy,

    // Ethernet PHYs (RTL8211F)
    output wire      E1_MDIO_C,   // eth1 MDIO clock
    output wire      E2_MDIO_C,   // eth2 MDIO clock
    inout wire       E1_MDIO_D,   // eth1 MDIO data
    inout wire       E2_MDIO_D,   // eth2 MDIO data
    output wire      E1_RSTn,     // eth1 PHY reset
    output wire      E2_RSTn,     // eth2 PHY reset
    input wire       E1_IRQn,     // eth1 IRQ (FPGA V3.1+)
    input wire       E2_IRQn,     // eth2 IRQ (FPGA V3.1+)

    input wire       E1_RxCLK,    // eth1 receive clock (from PHY)
    input wire       E1_RxVAL,    // eth1 receive valid
    inout wire[3:0]  E1_RxD,      // eth1 data bits
    output wire      E1_TxCLK,    // eth1 transmit clock
    output wire      E1_TxEN,     // eth1 transmit enable
    output wire[3:0] E1_TxD,      // eth1 transmit data

    input wire       E2_RxCLK,    // eth2 receive clock (from PHY)
    input wire       E2_RxVAL,    // eth2 receive valid
    inout wire[3:0]  E2_RxD,      // eth2 data bits
    output wire      E2_TxCLK,    // eth2 transmit clock
    output wire      E2_TxEN,     // eth2 transmit enable
    output wire[3:0] E2_TxD,      // eth2 transmit data

    // PS7 interface
    inout[53:0]      MIO,
    input            PS_SRSTB,
    input            PS_CLK,
    input            PS_PORB,

    // Read/Write bus
    output wire[15:0] reg_raddr,
    output reg[15:0]  reg_waddr,
    input wire[31:0]  reg_rdata_ext,
    output reg[31:0]  reg_wdata,
    output reg reg_wen,
    output reg blk_wen,
    output reg blk_wstart,

    // Block write support
    input wire bw_write_en,
    input wire[7:0] bw_reg_waddr,
    input wire[31:0] bw_reg_wdata,
    input wire bw_reg_wen,
    input wire bw_blk_wen,
    input wire bw_blk_wstart,

    // Real-time write support
    output reg rt_wen,
    output reg[3:0] rt_waddr,
    output reg[31:0] rt_wdata,

    // Sampling support
    output wire sample_start,       // Start sampling read data
    input wire sample_busy,         // 1 -> data sampler has control of bus
    input wire[3:0] sample_chan,    // Channel for sampling
    output wire[5:0] sample_raddr,  // Address in sample_data buffer
    input wire[31:0] sample_rdata,  // Output from sample_data buffer
    input wire[31:0] timestamp,     // Timestamp used when sampling

    // Board register info
    output wire[31:0] prom_status,       // Not supported in V3
    output wire[31:0] prom_result,       // Not supported in V3
    output wire[31:0] ip_address,
    output wire[31:0] Eth_Result
);

// 1394 phy low reset, never reset
assign reset_phy = 1'b1;
// prom_result not used (see below for prom_status)
assign prom_result = 32'd0;

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //
    wire lreq_trig;             // phy request trigger
    wire fw_lreq_trig;          // phy request trigger from FireWire
    wire eth_lreq_trig;         // phy request trigger from Ethernet
    wire[2:0] lreq_type;        // phy request type
    wire[2:0] fw_lreq_type;     // phy request type from FireWire
    wire[2:0] eth_lreq_type;    // phy request type from Ethernet
    wire fw_reg_wen;            // register write signal from FireWire
    wire eth_reg_wen;           // register write signal from Ethernet
    wire fw_blk_wen;            // block write enable from FireWire
    wire eth_blk_wen;           // block write enable from Ethernet
    wire fw_blk_wstart;         // block write start from FireWire
    wire eth_blk_wstart;        // block write start from Ethernet
    wire[15:0] fw_reg_raddr;    // 16-bit reg read address from FireWire
    wire[15:0] eth_reg_raddr;   // 16-bit reg read address from Ethernet
    wire[15:0] fw_reg_waddr;    // 16-bit reg write address from FireWire
    wire[15:0] eth_reg_waddr;   // 16-bit reg write address from Ethernet
    wire[31:0] fw_reg_wdata;    // reg write data from FireWire
    wire[31:0] eth_reg_wdata;   // reg write data from Ethernet
    wire eth_read_en;           // 1 -> Ethernet is driving reg_raddr to read from board registers
    // Following two wires indicate which module is driving the write bus
    // (reg_waddr, reg_wdata, reg_wen, blk_wen, blk_wstart).
    // If neither is active, then Firewire is driving the write bus.
    wire eth_write_en;          // 1 -> Ethernet is driving write bus
    wire[5:0] node_id;          // 6-bit phy node id

// For real-time write
wire       fw_rt_wen;
wire       eth_rt_wen;
wire[3:0]  fw_rt_waddr;
wire[3:0]  eth_rt_waddr;
wire[31:0] fw_rt_wdata;
wire[31:0] eth_rt_wdata;

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

wire[31:0] reg_rdata;
wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire[31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_eth;      // for eth memory access (EthernetIO)
wire[31:0] reg_rdata_rtl;      // for eth memory access (RTL8211F)
wire[31:0] reg_rdata_fw;       // for fw memory access

// No PROM for FPGA V3
assign reg_rdata_prom = 32'd0;

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                   (reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                   (reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth|reg_rdata_rtl) :
                   (reg_raddr[15:12]==`ADDR_FW) ? (reg_rdata_fw) : reg_rdata_ext;

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

wire clk200_ok;    // Whether the 200 MHz clock (from PS) seems to be running
assign LED = clk200_ok;

// The Ethernet result is used to distinguish between FPGA versions
//    Rev 1:  Eth_Result == 32'd0
//    Rev 2:  Eth_Result[31] == 1, other bits variable
//    Rev 3:  Eth_Result[31:30] == 01, other bits variable
// For Rev 3 (this file), Eth_Result is allocated as follows:
//    31:24  (8 bits)  Global (board) status
//    23:12 (12 bits)  Port 2 status
//    11:0  (12 bits)  Port 1 status
wire[11:0] e1_status;   // Status bits for Ethernet port 1
wire[11:0] e2_status;   // Status bits for Ethernet port 2
assign  Eth_Result = { 2'b01, 1'b0, clk200_ok, 4'h0, e2_status, e1_status };

wire e1_hasIRQ;
wire e2_hasIRQ;

// We detect FPGA V3.0 by checking whether the IRQ line is connected to the
// RTL8211F PHY (it is not connected in V3.0). There should only be two
// possible states: e1_hasIRQ==e2_hasIRQ==0 or e1_hasIRQ==e2_hasIRQ==1.
// The logic below will assume that the board is FPGA V3.1+ if either
// PHY detects that the IRQ is connected.
assign isV30 = (e1_hasIRQ|e2_hasIRQ) ? 1'b0 : 1'b1;

// Power-on configuration of RTL8211F PHY chip (also works after reset)
//    PhyAddr:  {RxVAL, RxClk, RxD[3]}, default: 001
//    PLLOFF:   RxD[2], default: 0
//    TXDLY:    RxD[1], default: 0
//    RXDLY:    RxD[0], default: 1
// RTL8211F has pullup/pulldown resistors to set default values.
// All default values are fine, except that we want TXDLY=1, so we
// drive RxD[1] high during reset. The other three bits do not need
// to be driven, but the code below drives them to their default values.
//
assign E1_RxD[3:0] = e1_resetActive ? 4'b1011 : 4'bzzzz;
assign E2_RxD[3:0] = e2_resetActive ? 4'b1011 : 4'bzzzz;

// GMII signals (generated by gmii_to_rgmii cores)

`ifdef ETH1
wire[7:0]  E1_gmii_txd;
wire       E1_gmii_tx_en;
wire       E1_gmii_tx_clk;
wire[7:0]  E1_gmii_rxd;
wire       E1_gmii_rx_dv;
wire       E1_gmii_rx_er;
wire       E1_gmii_rx_clk;
wire[1:0]  E1_clock_speed;
wire[1:0]  E1_speed_mode;
`else
wire[7:0]  E2_gmii_txd;
wire       E2_gmii_tx_en;
wire       E2_gmii_tx_clk;
wire[7:0]  E2_gmii_rxd;
wire       E2_gmii_rx_dv;
wire       E2_gmii_rx_er;
wire       E2_gmii_rx_clk;
wire[1:0]  E2_clock_speed;
wire[1:0]  E2_speed_mode;
`endif

wire       E1_mdio_o;         // OUT from RTL8211F module, IN to GMII core (or PHY)
wire       E1_mdio_i;         // IN to RTL8211F module, OUT from GMII core (or PHY)
wire       E1_mdio_t;         // OUT from RTL8211F module (tristate control)
wire       E1_mdio_clk;       // OUT from RTL8211F module, IN to GMII core (or PHY)

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
wire e1_resetActive;            // Ethernet port 1 reset active
wire e2_resetActive;            // Ethernet port 2 reset active
wire eth_resetActive;           // Indicates that Ethernet reset is active
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

// For now, eth_resetActive is OR of e1 and e2
assign eth_resetActive = e1_resetActive|e2_resetActive;

RTL8211F #(.CHANNEL(4'd1)) EthPhy1(
    .clk(sysclk),             // in:  global clock
    .board_id(board_id),      // in:  board id

    .reg_raddr(reg_raddr),    // in:  read address
    .reg_waddr(reg_waddr),    // in:  write address
    .reg_rdata(reg_rdata_rtl_e1), // out: read data
    .reg_wdata(reg_wdata),    // in:  write data
    .reg_wen(reg_wen_e1),     // in:  write enable

    .RSTn(E1_RSTn),           // Reset to RTL8211F
    .IRQn(E1_IRQn),           // Interrupt from RTL8211F (FPGA V3.1+)
    .resetActive(e1_resetActive),     // Indicates that reset is active

    .MDC(E1_mdio_clk),        // Clock to GMII core (and RTL8211F PHY)
    .MDIO_I(E1_mdio_i),       // IN to RTL8211F module, OUT from GMII core
    .MDIO_O(E1_mdio_o),       // OUT from RTL8211F module, IN to GMII core
    .MDIO_T(E1_mdio_t),       // Tristate signal from RTL8211F module

`ifdef ETH1
    .RxClk(E1_gmii_rx_clk),   // Rx Clk
    .RxValid(E1_gmii_rx_dv),  // Rx Valid
    .RxD(E1_gmii_rxd),        // Rx Data
    .RxErr(E1_gmii_rx_er),    // Rx Error

    .TxClk(E1_gmii_tx_clk),   // Tx Clk
    .TxEn(E1_gmii_tx_en),     // Tx Enable
    .TxD(E1_gmii_txd),        // Tx Data

    .clock_speed(E1_clock_speed),
    .speed_mode(E1_speed_mode),

    // Interface from Firewire (for sending packets via Ethernet)
    .sendReq(eth_send_req),

    // Interface to EthernetIO
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
    .useUDP(useUDP),                  // Whether EthernetIO is using UDP
    .eth_status(e1_status),           // Ethernet status bits
    .hasIRQ(e1_hasIRQ)                // Whether IRQ is connected (FPGA V3.1+)
`else
    .RxClk(1'b0),
    .RxValid(1'b0),
    .RxD(8'd0),
    .RxErr(1'b0),
    .TxClk(1'b0),
    .sendReq(1'b0)
`endif
);

RTL8211F #(.CHANNEL(4'd2)) EthPhy2(
    .clk(sysclk),             // in:  global clock
    .board_id(board_id),      // in:  board id

    .reg_raddr(reg_raddr),    // in:  read address
    .reg_waddr(reg_waddr),    // in:  write address
    .reg_rdata(reg_rdata_rtl_e2), // out: read data
    .reg_wdata(reg_wdata),    // in:  write data
    .reg_wen(reg_wen_e2),     // in:  write enable

    .RSTn(E2_RSTn),           // Reset to RTL8211F
    .IRQn(E2_IRQn),           // Interrupt from RTL8211F (FPGA V3.1+)
    .resetActive(e2_resetActive),     // Indicates that reset is active

    .MDC(E2_mdio_clk),        // Clock to GMII core (and RTL8211F PHY)
    .MDIO_I(E2_mdio_i),       // IN to RTL8211F module, OUT from GMII core
    .MDIO_O(E2_mdio_o),       // OUT from RTL8211F module, IN to GMII core
    .MDIO_T(E2_mdio_t),       // Tristate signal from RTL8211F module

`ifndef ETH1
    .RxClk(E2_gmii_rx_clk),   // Rx Clk
    .RxValid(E2_gmii_rx_dv),  // Rx Valid
    .RxD(E2_gmii_rxd),        // Rx Data
    .RxErr(E2_gmii_rx_er),    // Rx Error

    .TxClk(E2_gmii_tx_clk),   // Tx Clk
    .TxEn(E2_gmii_tx_en),     // Tx Enable
    .TxD(E2_gmii_txd),        // Tx Data

    .clock_speed(E2_clock_speed),
    .speed_mode(E2_speed_mode),

    // Interface from Firewire (for sending packets via Ethernet)
    .sendReq(eth_send_req),

    // Interface to EthernetIO
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
    .useUDP(useUDP),                  // Whether EthernetIO is using UDP
    .eth_status(e2_status),           // Ethernet status bits
    .hasIRQ(e2_hasIRQ)                // Whether IRQ is connected (FPGA V3.1+)
`else
    .RxClk(1'b0),
    .RxValid(1'b0),
    .RxD(8'd0),
    .RxErr(1'b0),
    .TxClk(1'b0),
    .sendReq(1'b0)
`endif
);

// address decode for IP address access
wire   ip_reg_wen;
assign ip_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_IPADDR}) ? reg_wen : 1'b0;

EthernetIO  #(.IPv4_CSUM(1)) EthernetTransfers(
    .sysclk(sysclk),          // in: global clock

    .board_id(board_id),      // in: board id (rotary switch)
    .node_id(node_id),        // in: phy node id

    // Register interface to Ethernet memory space (ADDR_ETH=0x4000)
    // and IP address register (REG_IPADDR=11).
`ifdef ETH1
    .reg_rdata(reg_rdata_e1),          // Data from Ethernet memory space
`else
    .reg_rdata(reg_rdata_e2),          // Data from Ethernet memory space
`endif
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


wire clk_200MHz;

fpgav3 zynq_ps7(
    .processing_system7_0_MIO(MIO),
    .processing_system7_0_PS_SRSTB_pin(PS_SRSTB),
    .processing_system7_0_PS_CLK_pin(PS_CLK),
    .processing_system7_0_PS_PORB_pin(PS_PORB),
    .processing_system7_0_GPIO_I_pin({60'd0, board_id}),
    .processing_system7_0_FCLK_CLK0_pin(clk_200MHz),

`ifdef ETH1
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
    .gmii_to_rgmii_1_MDC_pin(E1_MDIO_C),              // MDIO clock from GMII core (derived from E1_mdio_clk)
    .gmii_to_rgmii_1_clock_speed_pin(E1_clock_speed), // Clock speed (Rx)
    .gmii_to_rgmii_1_speed_mode_pin(E1_speed_mode)    // Speed mode (Tx)
`else
    // Temporarily use rgmii_1 (instead of rgmii_2) below
    .gmii_to_rgmii_1_rgmii_txd_pin(E2_TxD),
    .gmii_to_rgmii_1_rgmii_tx_ctl_pin(E2_TxEN),
    .gmii_to_rgmii_1_rgmii_txc_pin(E2_TxCLK),
    .gmii_to_rgmii_1_rgmii_rxd_pin(E2_RxD),
    .gmii_to_rgmii_1_rgmii_rx_ctl_pin(E2_RxVAL),
    .gmii_to_rgmii_1_rgmii_rxc_pin(E2_RxCLK),
    .gmii_to_rgmii_1_gmii_txd_pin(E2_gmii_txd),
    .gmii_to_rgmii_1_gmii_tx_en_pin(E2_gmii_tx_en),
    .gmii_to_rgmii_1_gmii_tx_clk_pin(E2_gmii_tx_clk),
    .gmii_to_rgmii_1_gmii_rxd_pin(E2_gmii_rxd),
    .gmii_to_rgmii_1_gmii_rx_dv_pin(E2_gmii_rx_dv),
    .gmii_to_rgmii_1_gmii_rx_er_pin(E2_gmii_rx_er),
    .gmii_to_rgmii_1_gmii_rx_clk_pin(E2_gmii_rx_clk),
    .gmii_to_rgmii_1_MDIO_MDC_pin(E2_mdio_clk),       // MDIO clock from RTL8211F module
    .gmii_to_rgmii_1_MDIO_I_pin(E2_mdio_i),           // OUT from GMII core, IN to RTL8211F module
    .gmii_to_rgmii_1_MDIO_O_pin(E2_mdio_o),           // IN to GMII core, OUT from RTL8211F module
    .gmii_to_rgmii_1_MDIO_T_pin(E2_mdio_t),           // Tristate control from RTL8211F module
    .gmii_to_rgmii_1_MDC_pin(E2_MDIO_C),              // MDIO clock from GMII core (derived from E2_mdio_clk)
    .gmii_to_rgmii_1_clock_speed_pin(E2_clock_speed), // Clock speed (Rx)
    .gmii_to_rgmii_1_speed_mode_pin(E2_speed_mode)    // Speed mode (Tx)
`endif
);

`ifndef ETH1
assign E1_MDIO_C = E1_mdio_clk;
assign E1_MDIO_D = E1_mdio_t ? 1'bz : E1_mdio_o;
assign E1_mdio_i = E1_MDIO_D;
assign E1_TxCLK = 1'b0;
assign E1_TxEN = 1'b0;
assign E1_TxD = 4'd0;
`else
assign E2_MDIO_C = E2_mdio_clk;
assign E2_MDIO_D = E2_mdio_t ? 1'bz : E2_mdio_o;
assign E2_mdio_i = E2_MDIO_D;
assign E2_TxCLK = 1'b0;
assign E2_TxEN = 1'b0;
assign E2_TxD = 4'd0;
`endif

// *** BEGIN: TEST code for PS clocks

reg[7:0] cnt_200;     // Counter incremented by clk_200MHz
reg[7:0] sysclk200;   // Counter increment by sysclk, sampled and cleared every 128 clk_200MHz
reg[7:0] clk200per;   // Last measured half-period of clk_200MHz (should be about 31 sysclks)
reg cur_msb;
reg last_msb;

// For now, use prom_status feedback (quadlet read from register 8)
assign prom_status = {clk200_ok, 7'd0, clk200per, 8'd0, cnt_200};

always @(posedge clk_200MHz)
begin
    cnt_200 <= cnt_200 + 8'd1;
end

always @(posedge sysclk)
begin
    cur_msb <= cnt_200[7];
    last_msb <= cur_msb;
    if (cur_msb != last_msb) begin
       sysclk200 <= 8'd0;
       clk200per <= sysclk200;
    end
    else begin
       sysclk200 <= sysclk200 + 8'd1;
    end
end

// Empirically verified that clk200per is either 30 or 31
assign clk200_ok = ((clk200per == 6'd30) || (clk200per == 6'd31)) ? 1'b1 : 1'b0;

// *** END: TEST code for PS clocks

endmodule
