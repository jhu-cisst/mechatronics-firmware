/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This module contains common code for FPGA V3 and does not make any assumptions
 * about which board is connected.
 *
 * Revision history
 *     12/10/22    Peter Kazanzides    Created from FPGA1394V3-QLA.v
 */

`include "Constants.v"

module FPGA1394V3
    #(parameter NUM_BC_READ_QUADS = 33)
(
    // global clock
    input wire       sysclk,

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
    // Following two directly connected in GMII to RGMII core
    // inout wire       E1_MDIO_D,   // eth1 MDIO data
    // inout wire       E2_MDIO_D,   // eth2 MDIO data
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
    input wire sample_busy,         // Sampling in process
    output wire[5:0] sample_raddr,  // Address in sample_data buffer
    input wire[31:0] sample_rdata,  // Output from sample_data buffer
    output wire sample_read,        // 1 -> either eth or fw sample read
    input wire[31:0] timestamp,     // Timestamp used when sampling

    // Watchdog support
    output wire wdog_period_led,    // 1 -> external LED displays wdog_period_status
    output wire[2:0] wdog_period_status,
    output wire wdog_timeout,       // watchdog timeout status flag
    input  wire wdog_clear          // clear watchdog timeout (e.g., on powerup)
);

// 1394 phy low reset, never reset
assign reset_phy = 1'b1;

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
    wire fw_req_read_bus;       // 1 -> Firewire is requesting read bus (driving reg_raddr to read from board registers)
    wire eth_req_read_bus;      // 1 -> Ethernet is requesting read bus (driving reg_raddr to read from board registers)
    wire fw_req_write_bus;      // 1 -> Firewire is requesting write bus (driving reg_waddr, reg_wdata, reg_wen, blk_wen, blk_wstart)
    wire eth_req_write_bus;     // 1 -> Ethernet is requesting write bus (driving reg_waddr, reg_wdata, reg_wen, blk_wen, blk_wstart)
    wire[5:0] node_id;          // 6-bit phy node id
    wire[31:0] prom_status;
    wire[31:0] prom_result;
    wire[31:0] Eth_Result;
    wire[31:0] ip_address;

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
wire fw_sample_read;
assign sample_read = eth_sample_read | fw_sample_read;
wire[5:0] fw_sample_raddr;
wire[5:0] eth_sample_raddr;
assign sample_raddr = eth_sample_read ? eth_sample_raddr : fw_sample_raddr;

// Signals for PS access to registers
wire[63:0] emio_ps_in;     // EMIO input to PS
wire[63:0] emio_ps_out;    // EMIO output from PS
wire[63:0] emio_ps_tri;    // EMIO tristate from PS (1 -> input to PS, 0 -> output from PS)

reg[31:0]  ps_reg_rdata;                       // emio[31:0]
wire[31:0] ps_reg_wdata = emio_ps_out[31:0];   // emio[31:0]
wire[15:0] ps_reg_addr = emio_ps_out[47:32];   // emio[47:32]
wire       ps_req_bus = emio_ps_out[48];       // emio[48]
reg        ps_read_done;                       // emio[49]
reg        ps_write_done;                      // emio[49]
wire       ps_reg_wen = emio_ps_out[50];       // emio[50]
wire       ps_blk_wstart = emio_ps_out[51];    // emio[51]
wire       ps_blk_wen = emio_ps_out[52];       // emio[52]
wire       ps_write;                           // emio[53]

wire ps_req_read_bus;
wire ps_req_write_bus;

// It is a write when no data lines are tristate; otherwise, we assume a read
assign ps_write = (emio_ps_tri[31:0] == 32'd0) ? 1'b1 : 1'b0;

assign ps_req_read_bus = ps_req_bus & (~ps_write);
assign ps_req_write_bus = ps_req_bus & ps_write;

assign emio_ps_in = {10'd0, ps_write,
                     ps_blk_wen, ps_blk_wstart, ps_reg_wen,
                     (ps_write ? ps_write_done : ps_read_done),
                     ps_req_bus, ps_reg_addr,
                     (ps_write ? ps_reg_wdata : ps_reg_rdata) };

//******************* Arbitration for read bus ****************************

localparam[1:0]
    RB_IDLE = 2'd0,
    RB_PS   = 2'd1,
    RB_FW   = 2'd2,
    RB_ETH  = 2'd3;

reg[1:0] rbState = RB_IDLE;
reg[1:0] rbStateNext;

// Counts number of clocks that we were in the same state.
// Generally, we want at least 3 clocks for a successful read:
//   1 clock to set reg_raddr
//   1 clock to wait for RAM access (in some cases)
//   1 clock to latch reg_rdata
reg[1:0] rbCnt;

// For synchronizing ps_req_read_bus with sysclk and generating triggers
// on the rising and falling edges.
reg  ps_req_read_bus_1;
reg  ps_req_read_bus_2;
wire ps_req_read_bus_trig;
wire ps_req_read_bus_untrig;

// Generate ps_req_read_bus_trig on rising edge of ps_req_read_bus
assign ps_req_read_bus_trig = (ps_req_read_bus_1 & (~ps_req_read_bus_2));

// Generate ps_req_read_bus_untrig on falling edge of ps_req_read_bus
assign ps_req_read_bus_untrig = ((~ps_req_read_bus_1) & ps_req_read_bus_2);

always @(*)
begin

   case (rbState)

   RB_IDLE:
   begin
     // If sample_busy asserted, sampler might be accessing encoder registers
     // (on QLA and DQLA), so to be safe, we stay in IDLE state.
     // We give priority to PS read request because it only requires 3 clocks, so
     // it would be done before the Firewire or Ethernet would need the bus (this
     // is true because the Firewire and Ethernet modules assert the REQ signal
     // several clock cycles in advance).
     if (sample_busy) rbStateNext = RB_IDLE;
     else if (ps_req_read_bus_trig) rbStateNext = RB_PS;
     else if (fw_req_read_bus) rbStateNext = RB_FW;
     else if (eth_req_read_bus) rbStateNext = RB_ETH;
     else rbStateNext = RB_IDLE;
   end

   RB_PS:
     // We only stay in the RB_PS state for 3 clocks
     rbStateNext = (rbCnt != 2'd2) ? RB_PS : RB_IDLE;

   RB_FW:
     // Firewire keeps the bus until it deasserts the REQ signal
     rbStateNext = fw_req_read_bus ? RB_FW : RB_IDLE;

   RB_ETH:
     // Ethernet keeps the bus until it deasserts the REQ signal
     rbStateNext = eth_req_read_bus ? RB_ETH : RB_IDLE;

   endcase
end

always @(posedge sysclk)
begin
    rbState <= rbStateNext;
    if ((rbState != rbStateNext) || sample_busy)
       rbCnt <= 2'd0;           // Reset counter if state change (or sample_busy)
    else if (rbCnt != 2'd2)
       rbCnt <= rbCnt + 2'd1;   // Else, count up to 2

    // Synchronize PS read request with sysclk
    ps_req_read_bus_1 <= (rbState == RB_IDLE) ? ps_req_read_bus : 1'b0;
    ps_req_read_bus_2 <= ps_req_read_bus_1;

    if ((rbState == RB_PS) && (rbCnt == 2'd2)) begin
        // Latch ps_reg_rdata after 3 clocks and set ps_read_done
        ps_reg_rdata <= reg_rdata;
        ps_read_done <= 1'b1;
    end
    if (ps_req_read_bus_untrig) begin
        // Clear ps_read_done when PS deasserts ps_req_read_bus
        ps_read_done <= 1'b0;
    end
end

wire ps_has_read_bus;    // PS has control of the read bus
wire fw_has_read_bus;    // Firewire has control of the read bus
wire eth_has_read_bus;   // Ethernet has control of the read bus

assign ps_has_read_bus = (rbState == RB_PS) ? 1'b1 : 1'b0;
assign fw_has_read_bus = ((rbState == RB_FW) || (rbState == RB_IDLE)) ? 1'b1 : 1'b0;
assign eth_has_read_bus = (rbState == RB_ETH) ? 1'b1 : 1'b0;

assign reg_raddr = ps_has_read_bus  ? ps_reg_addr  :
                   eth_has_read_bus ? eth_reg_raddr :
                                      fw_reg_raddr;

// The xx_reg_rdata_valid signals indicate that reg_rdata should be valid (i.e.,
// should correspond to the data addressed by xx_reg_raddr) since we have been in the
// correct state for at least 3 consecutive clock cycles (including the current clock cycle).
// These can be used for error checking within the Firewire and Ethernet modules.
// Note that ps_read_done is set above.
wire fw_reg_rdata_valid;
wire eth_reg_rdata_valid;

assign fw_reg_rdata_valid = (fw_has_read_bus && (rbCnt == 2'd2)) ? 1'b1 : 1'b0;
assign eth_reg_rdata_valid = (eth_has_read_bus && (rbCnt == 2'd2)) ? 1'b1 : 1'b0;

//***************************************************************************

wire[31:0] reg_rdata;
wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
reg[31:0]  reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_eth;      // for eth memory access (EthernetIO)
wire[31:0] reg_rdata_rtl;      // for eth memory access (RTL8211F)
wire[31:0] reg_rdata_eswrt;    // for eth memory access (EthSwitchRt)
wire[31:0] reg_rdata_fw;       // for fw memory access
wire[31:0] reg_rdata_chan0;    // for reads from board registers

wire isAddrMain;
assign isAddrMain = ((reg_raddr[15:12]==`ADDR_MAIN) && (reg_raddr[7:4]==4'd0)) ? 1'b1 : 1'b0;

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                   (reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                   (reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth|reg_rdata_rtl|reg_rdata_eswrt) :
                   (reg_raddr[15:12]==`ADDR_FW) ? (reg_rdata_fw) :
                   isAddrMain ? reg_rdata_chan0 : reg_rdata_ext;

// Data for channel 0 (board registers) is distributed across several FPGA modules, as well
// as coming from the external board (e.g., QLA). In the following, we mux these together
// and then provide it as input to BoardRegs, which muxes a few additional registers,
// and provides the final result as reg_rdata_chan0, which is muxed to reg_rdata above.
// It is not necessary to check isAddrMain in the following because it is done above.
wire[31:0] reg_rdata_chan0_ext;
assign reg_rdata_chan0_ext =
                   (reg_raddr[3:0]==`REG_PROMSTAT) ? prom_status :
                   (reg_raddr[3:0]==`REG_PROMRES) ? prom_result :
                   (reg_raddr[3:0]==`REG_IPADDR) ? ip_address :
                   (reg_raddr[3:0]==`REG_ETHSTAT) ? Eth_Result :
                   reg_rdata_ext;

//******************* Arbitration for write bus ****************************

localparam[2:0]
    WB_IDLE   = 3'd0,
    WB_PS     = 3'd1,
    WB_FW     = 3'd2,
    WB_ETH    = 3'd3,
    WB_BW     = 3'd4,
    WB_PS_BLK = 3'd5;

reg[2:0] wbState = WB_IDLE;
reg[2:0] wbStateNext;

// For synchronizing ps_req_write_bus with sysclk and generating triggers
// on the rising and falling edges.
reg  ps_req_write_bus_1;
reg  ps_req_write_bus_2;
wire ps_req_write_bus_trig;
wire ps_req_write_bus_untrig;

// Generate ps_req_write_bus_trig on rising edge of ps_req_write_bus
assign ps_req_write_bus_trig = (ps_req_write_bus_1 & (~ps_req_write_bus_2));

// Generate ps_req_write_bus_untrig on falling edge of ps_req_write_bus
assign ps_req_write_bus_untrig = ((~ps_req_write_bus_1) & ps_req_write_bus_2);

always @(*)
begin

   case (wbState)

   WB_IDLE:
   begin
     // We give priority to the BW (WriteRtData block write)
     if (bw_write_en) wbStateNext = WB_BW;
     else if (fw_req_write_bus) wbStateNext = WB_FW;
     else if (eth_req_write_bus) wbStateNext = WB_ETH;
     else if (ps_req_write_bus_trig) wbStateNext = ps_blk_wstart ? WB_PS_BLK : WB_PS;
     else wbStateNext = WB_IDLE;
   end

   WB_PS:
     // We stay in the WB_PS state for 1 clock
     wbStateNext = reg_wen ? WB_IDLE : WB_PS;

   WB_FW:
     // Firewire keeps the bus until it deasserts the REQ signal
     wbStateNext = fw_req_write_bus ? WB_FW : WB_IDLE;

   WB_ETH:
     // Ethernet keeps the bus until it deasserts the REQ signal
     wbStateNext = eth_req_write_bus ? WB_ETH : WB_IDLE;

   WB_BW:
     // WriteRtData keeps the bus until it deasserts the REQ signal
     wbStateNext = bw_write_en ? WB_BW : WB_IDLE;

   WB_PS_BLK:
     // PS holds the bus until it deasserts ps_req_write_bus or
     // issues blk_wen
     wbStateNext = (ps_req_write_bus_untrig | blk_wen) ? WB_IDLE : WB_PS_BLK;

   default:
     // Should not happen
     wbStateNext = WB_IDLE;

   endcase
end

always @(posedge sysclk)
begin
    wbState <= wbStateNext;

    // Synchronize PS write request with sysclk
    ps_req_write_bus_1 <= (wbState == WB_IDLE) ? ps_req_write_bus : 1'b0;
    ps_req_write_bus_2 <= ps_req_write_bus_1;

    if ((wbState == WB_PS) || (wbState == WB_PS_BLK)) begin
        ps_write_done <= reg_wen;
    end

    if (ps_req_write_bus_untrig) begin
        // Clear ps_write_done when PS deasserts ps_req_write_bus
        ps_write_done <= 1'b0;
    end
end

wire ps_has_write_bus;    // PS has control of the write bus
wire fw_has_write_bus;    // Firewire has control of the write bus
wire eth_has_write_bus;   // Ethernet has control of the write bus
wire bw_has_write_bus;    // WriteRtData has control of the write bus

assign ps_has_write_bus = ((wbState == WB_PS) || (wbState == WB_PS_BLK)) ? 1'b1 : 1'b0;
assign fw_has_write_bus = ((wbState == WB_FW) || (wbState == WB_IDLE)) ? 1'b1 : 1'b0;
assign eth_has_write_bus = (wbState == WB_ETH) ? 1'b1 : 1'b0;
assign bw_has_write_bus =  (wbState == WB_BW)  ? 1'b1 : 1'b0;

// Multiplexing of write bus between BW, PS, FW and ETH
always @(*)
begin
   if (bw_has_write_bus) begin
      reg_wen = bw_reg_wen;
      blk_wen = bw_blk_wen;
      blk_wstart = bw_blk_wstart;
      reg_waddr = {8'd0, bw_reg_waddr};
      reg_wdata = bw_reg_wdata;
   end
   else if (eth_has_write_bus) begin
      reg_wen = eth_reg_wen;
      blk_wen = eth_blk_wen;
      blk_wstart = eth_blk_wstart;
      reg_waddr = eth_reg_waddr;
      reg_wdata = eth_reg_wdata;
   end
   else if (ps_has_write_bus) begin
      reg_wen = ps_reg_wen;
      blk_wen = ps_blk_wen;
      blk_wstart = ps_blk_wstart;
      reg_waddr = ps_reg_addr;
      reg_wdata = ps_reg_wdata;
   end
   else begin
      reg_wen = fw_reg_wen;
      blk_wen = fw_blk_wen;
      blk_wstart = fw_blk_wstart;
      reg_waddr = fw_reg_waddr;
      reg_wdata = fw_reg_wdata;
   end
end

//***************************************************************************

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
PhyLinkInterface
    #(.NUM_BC_READ_QUADS(NUM_BC_READ_QUADS))
phy(
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

    .req_read_bus(fw_req_read_bus),        // out: request read bus
    .req_write_bus(fw_req_write_bus),      // out: request read bus

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
    .sample_rdata(sample_rdata),       // Sampled data (for block read)
    .sample_read(fw_sample_read)
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
// from the core are connected to the RTL8211F PHY.

wire clk200_ok;    // Whether the 200 MHz clock (from PS) seems to be running
assign LED = clk200_ok;

// Ethernet reset (to PHY) and  interrupt (from PHY)
wire Eth_RSTn[1:2];
assign E1_RSTn = Eth_RSTn[1];
assign E2_RSTn = Eth_RSTn[2];

wire Eth_IRQn[1:2];
assign Eth_IRQn[1] = E1_IRQn;
assign Eth_IRQn[2] = E2_IRQn;

// The Ethernet result is used to distinguish between FPGA versions
//    Rev 1:  Eth_Result == 32'd0
//    Rev 2:  Eth_Result[31] == 1, other bits variable
//    Rev 3:  Eth_Result[31:30] == 01, other bits variable
// For Rev 3 (this file), Eth_Result is allocated as follows:
//    31:16  (16 bits) Global (board) status and EthernetIO status
//    15:8   (8 bits)  Port 2 status
//    7:0    (8 bits)  Port 1 status
// Note that the eth_status_io bits are intermingled for backward
// compatible bit assignments.
wire eth_port;                   // Current ethernet port (from EthSwitchRt)
wire[7:0] eth_status_phy[1:2];   // Status bits for Ethernet ports 1 and 2
wire[7:0] eth_status_io;         // Status bits from EthernetIO
assign Eth_Result = { 2'b01, eth_port, eth_status_io[7:3],                   // 31:24
                      1'b0, eth_status_io[2], clk200_ok, eth_status_io[0],   // 23:20
                      4'h0,                                                  // 19:16
                      eth_status_phy[2], eth_status_phy[1] };                // 15:0

// We detect FPGA V3.0 by checking whether the IRQ line is connected to the
// RTL8211F PHY (it is not connected in V3.0). There should only be two
// possible states: hasIRQ_e[1]==hasIRQ_e[2]==0 or hasIRQ_e[1]==hasIRQ_e[2]==1.
// The logic below will assume that the board is FPGA V3.1+ if either
// PHY detects that the IRQ is connected.
wire hasIRQ_e[1:2];
assign isV30 = (hasIRQ_e[1]|hasIRQ_e[2]) ? 1'b0 : 1'b1;

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
assign E1_RxD[3:0] = resetActive_e[1] ? 4'b1011 : 4'bzzzz;
assign E2_RxD[3:0] = resetActive_e[2] ? 4'b1011 : 4'bzzzz;

// GMII signals (for gmii_to_rgmii cores)
//    rt -> signals between gmii_to_rgmii core and RTL8211F (i.e., FPGA)
//    ps -> signals between gmii_to_rgmii core and Zynq PS

wire[7:0]  gmii_txd_rt[1:2];
wire[7:0]  gmii_txd_ps[1:2];
wire[7:0]  gmii_txd[1:2];
wire       gmii_tx_en_rt[1:2];
wire       gmii_tx_en_ps[1:2];
wire       gmii_tx_en[1:2];
wire       gmii_tx_clk[1:2];
wire       gmii_tx_err_rt[1:2];
wire       gmii_tx_err_ps[1:2];
wire       gmii_tx_err[1:2];
wire[7:0]  gmii_rxd[1:2];
wire       gmii_rx_dv[1:2];
wire       gmii_rx_er[1:2];
wire       gmii_rx_clk[1:2];
wire[1:0]  clock_speed[1:2];
wire[1:0]  speed_mode[1:2];
wire       tx_req_rt[1:2];
wire       tx_grant_rt[1:2];
wire       ps_eth_enable[1:2];

wire       mdio_o_rt[1:2];      // OUT from RTL8211F module
wire       mdio_o_ps[1:2];      // OUT from Zynq PS
wire       mdio_o[1:2];         // IN to GMII core (or PHY)
wire       mdio_i[1:2];         // IN to RTL8211F module, OUT from GMII core (or PHY)
wire       mdio_t_rt[1:2];      // OUT from RTL8211F module (tristate control)
wire       mdio_t_ps[1:2];      // OUT from Zynq PS (tristate control)
wire       mdio_t[1:2];         // OUT from RTL8211F module (tristate control)
wire       mdio_busy_rt[1:2];   // OUT from RTL8211F module (MDIO busy)
wire       mdio_clk_rt[1:2];    // OUT from RTL8211F module, IN to GMII core (or PHY)
wire       mdio_clk_ps[1:2];    // OUT from Zynq PS
wire       mdio_clk[1:2];       // IN to GMII core (or PHY)

// Wires between RTL8211F and EthSwitchRt
wire       initOK[1:2];
wire       rt_recv_fifo_empty[1:2];
wire       rt_recv_rd_en[1:2];
wire[15:0] rt_recv_fifo_dout[1:2];
wire       rt_recv_info_empty[1:2];
wire       rt_recv_info_rd_en[1:2];
wire[31:0] rt_recv_info_dout[1:2];
wire       rt_recv_fifo_error[1:2];
wire       rt_send_fifo_full[1:2];
wire       rt_send_wr_en[1:2];
wire[15:0] rt_send_fifo_din;
wire       rt_send_info_full[1:2];
wire       rt_send_info_wr_en[1:2];
wire[31:0] rt_send_info_din;
wire       rt_send_fifo_overflow[1:2];
wire       rt_clear_errors[1:2];

// Wires between EthSwitchRt and EthernetIO
wire resetActive_e[1:2];        // Ethernet port reset active
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
wire[15:0] eth_time_recv;       // Time when receive portion finished
wire[15:0] eth_time_now;        // Running time counter since start of packet receive
wire eth_bw_active;             // Indicates that block write module is active
wire eth_InternalError_rt[1:2]; // Error summary bit to EthernetIO
wire[5:0] eth_ioErrors;         // Error bits from EthernetIO

wire[31:0] reg_rdata_rtl_e[1:2];
assign reg_rdata_rtl = (reg_raddr[11:8] == 4'd1) ? reg_rdata_rtl_e[1] :
                       (reg_raddr[11:8] == 4'd2) ? reg_rdata_rtl_e[2] :
                       32'd0;

// Write to Ethernet control register
wire eth_ctrl_wen;
assign eth_ctrl_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHSTAT}) ? reg_wen : 1'b0;

genvar k;
generate
for (k = 1; k <= 2; k = k + 1) begin : eth_loop
    localparam[3:0] chan = k;

    // Simple arbitration between PL (rt) and PS for Tx bus.
    // Current implementation prevents PL side from interrupting PS, but does not
    // prevent PS from trying to transmit while PL is active. In the latter case,
    // the PS transmission will be ignored until the PL side finishes, so a partial
    // packet may be transmitted. In the future, the PS transmission can be stored
    // in a FIFO until the PL side finishes.
    // Note that PS ethernet access can be disabled by clearing ps_eth_enable.
    assign tx_grant_rt[k] = tx_req_rt[k] & ~(ps_eth_enable[k] & gmii_tx_en_ps[k]);

    assign gmii_txd[k] = (gmii_tx_en_rt[k] | (~ps_eth_enable[k])) ? gmii_txd_rt[k] : gmii_txd_ps[k];
    assign gmii_tx_en[k] = gmii_tx_en_rt[k] | (ps_eth_enable[k] & gmii_tx_en_ps[k]);
    assign gmii_tx_err[k] = (gmii_tx_en_rt[k] & gmii_tx_err_rt[k]) | (ps_eth_enable[k] & gmii_tx_en_ps[k] & gmii_tx_err_ps[k]);

    // Can write to 4xay, where x is the Ethernet port number (1 or 2) and y is the offset.
    // Currently, y=0 is the only valid write address.
    wire reg_wen_eth;
    assign reg_wen_eth = (reg_waddr[15:4] == {`ADDR_ETH, chan, 4'ha}) ? reg_wen : 1'b0;

    RTL8211F #(.CHANNEL(chan)) EthPhy(
        .clk(sysclk),             // in:  global clock
        .board_id(board_id),      // in:  board id

        .reg_raddr(reg_raddr),    // in:  read address
        .reg_waddr(reg_waddr),    // in:  write address
        .reg_rdata(reg_rdata_rtl_e[k]), // out: read data
        .reg_wdata(reg_wdata),    // in:  write data
        .reg_wen(reg_wen_eth),    // in:  write enable
        .reg_wen_ctrl(eth_ctrl_wen),  // in: write enable to Ethernet control register

        .RSTn(Eth_RSTn[k]),       // Reset to RTL8211F
        .IRQn(Eth_IRQn[k]),       // Interrupt from RTL8211F (FPGA V3.1+)
        .resetActive(resetActive_e[k]),  // Indicates that reset is active

        .MDC(mdio_clk_rt[k]),     // Clock to GMII core (and RTL8211F PHY)
        .MDIO_I(mdio_i[k]),       // IN to RTL8211F module, OUT from GMII core
        .MDIO_O(mdio_o_rt[k]),    // OUT from RTL8211F module, IN to GMII core
        .MDIO_T(mdio_t_rt[k]),    // Tristate signal from RTL8211F module
        .mdioBusy(mdio_busy_rt[k]), // OUT from RTL8211F module

        .RxClk(gmii_rx_clk[k]),   // Rx Clk
        .RxValid(gmii_rx_dv[k]),  // Rx Valid
        .RxD(gmii_rxd[k]),        // Rx Data
        .RxErr(gmii_rx_er[k]),    // Rx Error

        .TxClk(gmii_tx_clk[k]),   // Tx Clk
        .TxEn(gmii_tx_en_rt[k]),  // Tx Enable
        .TxD(gmii_txd_rt[k]),     // Tx Data
        .TxErr(gmii_tx_err_rt[k]), // Tx Error

        .clock_speed(clock_speed[k]),
        .speed_mode(speed_mode[k]),

        // Arbitration for Tx bus (PS may be using it)
        .tx_bus_req(tx_req_rt[k]),      // Bus request
        .tx_bus_grant(tx_grant_rt[k]),  // Bus grant
        .ps_eth_enable(ps_eth_enable[k]),

        // Feedback bits
        .ethInternalError(eth_InternalError_rt[k]),  // Error summary bit to EthSwitchRt
        .eth_status(eth_status_phy[k]),        // Ethernet status bits
        .hasIRQ(hasIRQ_e[k]),                  // Whether IRQ is connected (FPGA V3.1+)

        // Interface to EthSwitchRt
        .initOK(initOK[k]),

        .recv_fifo_empty(rt_recv_fifo_empty[k]),
        .recv_rd_en(rt_recv_rd_en[k]),
        .recv_fifo_dout(rt_recv_fifo_dout[k]),
        .recv_info_fifo_empty(rt_recv_info_empty[k]),
        .recv_info_rd_en(rt_recv_info_rd_en[k]),
        .recv_info_dout(rt_recv_info_dout[k]),
        .recv_fifo_error(rt_recv_fifo_error[k]),         // First byte in recv_fifo not as expected

        .send_fifo_full(rt_send_fifo_full[k]),
        .send_wr_en(rt_send_wr_en[k]),
        .send_fifo_din(rt_send_fifo_din),
        .send_info_fifo_full(rt_send_info_full[k]),
        .send_info_wr_en(rt_send_info_wr_en[k]),
        .send_info_din(rt_send_info_din),
        .send_fifo_overflow(rt_send_fifo_overflow[k]),   // Overflow (send_fifo was full)

        .clearErrors(rt_clear_errors[k])                 // request to clear errors
    );

    // MDIO Signal routing
    //
    // MDIO_I:  Output from gmii_to_rgmii core, input to PS and PL ethernet
    //   Zynq PS: ENETn_MDIO_I (fpgav3.v, input)  \
    //                                             <--En_MDIO_I-- gmii..n_MDIO_I (fpgav3.v, output)
    //   Zynq PL: MDIO_I (RTL8211F.v, input)      /
    //
    // MDIO_O:  Output from PS and PL ethernet, mux input to gmii_to_rgmii core
    //   Zynq PS: ENETn_MDIO_O (fpgav3.v, output) --En_mdio_o_ps--> \
    //                                                               (mux) --mdio_o--> gmii..n_MDIO_O (fpgav3.v, input)
    //   Zynq PL: MDIO_O (RTL8211F.v, output)     --En_mdio_o_rt--> /
    //
    // MDIO_T:  Output from PS and PL ethernet, mux input to gmii_to_rgmii core
    //   Same routing as MDIO_O
    //
    // MDIO_CLK: Output from PS and PL ethernet, mux input to gmii_to_rgmii core
    //   Same routing as MDIO_O
    //
    // MUXes for MDIO_O, MDIO_T and MDIO_CLK
    //   - PS has MDIO access by default (if ps_eth_enable); RT (PL) gets access when needed.
    //   - Right now, there is no check for collisions on the MDIO bus.
    //   - The PL and PS MDIO clocks are not synchronized.
    assign mdio_clk[k] = (mdio_busy_rt[k]|(~ps_eth_enable[k])) ? mdio_clk_rt[k] : mdio_clk_ps[k];
    assign mdio_o[k] = (mdio_busy_rt[k]|(~ps_eth_enable[k])) ? mdio_o_rt[k] : mdio_o_ps[k];
    assign mdio_t[k] = (mdio_busy_rt[k]|(~ps_eth_enable[k])) ? mdio_t_rt[k] : mdio_t_ps[k];

end
endgenerate

EthSwitchRt eth_switch_rt(
    .clk(sysclk),

    .reg_raddr(reg_raddr),
    .reg_rdata(reg_rdata_eswrt),

    // Interface to RTL8211F (x2)
    .initOK({initOK[2], initOK[1]}),
    .resetActiveIn({resetActive_e[2], resetActive_e[1]}),

    .recv_fifo_empty({rt_recv_fifo_empty[2], rt_recv_fifo_empty[1]}),
    .recv_rd_en({rt_recv_rd_en[2], rt_recv_rd_en[1]}),
    .recv_fifo_dout_vec({rt_recv_fifo_dout[2], rt_recv_fifo_dout[1]}),
    .recv_info_fifo_empty({rt_recv_info_empty[2], rt_recv_info_empty[1]}),
    .recv_info_rd_en({rt_recv_info_rd_en[2], rt_recv_info_rd_en[1]}),
    .recv_info_dout_vec({rt_recv_info_dout[2], rt_recv_info_dout[1]}),
    .recv_fifo_error({rt_recv_fifo_error[2], rt_recv_fifo_error[1]}),

    .send_fifo_full({rt_send_fifo_full[2], rt_send_fifo_full[1]}),
    .send_wr_en({rt_send_wr_en[2], rt_send_wr_en[1]}),
    .send_fifo_din(rt_send_fifo_din),
    .send_info_fifo_full({rt_send_info_full[2], rt_send_info_full[1]}),
    .send_info_wr_en({rt_send_info_wr_en[2], rt_send_info_wr_en[1]}),
    .send_info_din(rt_send_info_din),
    .send_fifo_overflow({rt_send_fifo_overflow[2], rt_send_fifo_overflow[1]}),

    .clearErrors({rt_clear_errors[2], rt_clear_errors[1]}),
    .eth_InternalError_rt({eth_InternalError_rt[2], eth_InternalError_rt[1]}),

    // Interface from Firewire (for sending packets via Ethernet)
    .sendReq(eth_send_req),

    // Interface to EthernetIO
    .resetActiveOut(eth_resetActive), // Indicates that reset is active
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
    .timeReceive(eth_time_recv),      // Time when receive portion finished
    .timeNow(eth_time_now),           // Running time counter since start of packet receive
    .bw_active(eth_bw_active),        // Indicates that block write module is active
    .curPort(eth_port),               // Current Ethernet port
    .eth_InternalError(eth_InternalError)
);

// address decode for IP address access
wire   ip_reg_wen;
assign ip_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_IPADDR}) ? reg_wen : 1'b0;

EthernetIO
    #(.IPv4_CSUM(1), .IS_V3(1))
EthernetTransfers(
    .sysclk(sysclk),          // in: global clock

    .board_id(board_id),      // in: board id (rotary switch)
    .node_id(node_id),        // in: phy node id

    // Register interface to Ethernet memory space (ADDR_ETH=0x4000)
    // and IP address register (REG_IPADDR=11).
    .reg_rdata(reg_rdata_eth),         // Data from Ethernet memory space
    .reg_raddr(reg_raddr),             // Read address for Ethernet memory
    .reg_wdata(reg_wdata),             // Data to write to IP address register
    .ip_reg_wen(ip_reg_wen),           // Enable write to IP address register
    .ctrl_reg_wen(eth_ctrl_wen),       // Enable write to Ethernet control register
    .ip_address(ip_address),           // IP address of this board

    // Interface to/from board registers. These enable the Ethernet module to drive
    // the internal bus on the FPGA. In particular, they are used to read registers
    // to respond to quadlet read and block read commands.
    .eth_reg_rdata(reg_rdata),         //  in: reg read data
    .eth_reg_raddr(eth_reg_raddr),     // out: reg read addr
    .eth_req_read_bus(eth_req_read_bus),  // out: reg read enable
    .eth_reg_rdata_valid(eth_reg_rdata_valid),  // in: indicates that reg_rdata is valid
    .eth_reg_wdata(eth_reg_wdata),     // out: reg write data
    .eth_reg_waddr(eth_reg_waddr),     // out: reg write addr
    .eth_reg_wen(eth_reg_wen),         // out: reg write enable
    .eth_block_wen(eth_blk_wen),       // out: blk write enable
    .eth_block_wstart(eth_blk_wstart), // out: blk write start
    .eth_req_write_bus(eth_req_write_bus), // out: write bus enable

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

    // Interface to EthSwitchRt
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
    .timeReceive(eth_time_recv),      // Time when receive portion finished
    .timeNow(eth_time_now),           // Running time counter since start of packet receive
    .bw_active(eth_bw_active),        // Indicates that block write module is active
    .ethLLError(eth_InternalError),   // Error summary bit to EthernetIO
    .eth_status(eth_status_io)        // EthernetIO status register
);


// --------------------------------------------------------------------------
// FPGA V3 PROM, accessible via PS
//
// Initial implementation relies on PS to read FPGA serial number (16 bytes)
// from QSPI PROM and write to prom_data registers. We then check for the
// PC software attempting to read from PROM address 0x1fff000, which is where
// the S/N is stored in the M25P16 PROM used for FPGA V1 and V2.
// --------------------------------------------------------------------------

// Indicates that PC is attempting to read from address 1fff000
reg prom_sn_read;

// 16 bits of PROM data for FPGA S/N
reg[31:0] prom_data[0:3];
initial begin
   prom_data[0] = 32'hffffffff;
   prom_data[1] = 32'hffffffff;
   prom_data[2] = 32'hffffffff;
   prom_data[3] = 32'hffffffff;
end

// Default values for prom_result and prom_status
// PC software expects prom_result to contain number of quadlets read, which
// should always be 64.
// PC software uses lower 4 bits of prom_status to indicate that data is ready
// (when all bits are 0).
assign prom_result = 32'd64;
assign prom_status = 32'd0;

wire prom_reg_wen;   // main quadlet reg interface
wire prom_blk_wen;   // PROM data reg interface

assign prom_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_PROMSTAT}) ? reg_wen : 1'b0;
assign prom_blk_wen = (reg_waddr[15:12] == `ADDR_PROM) ? reg_wen : 1'b0;

always @(posedge sysclk)
begin
    // handle block read, first 4 quadlets come from registers
    if (prom_sn_read && (reg_raddr[5:2] == 4'd0))
        reg_rdata_prom <= prom_data[reg_raddr[1:0]];
    else
        reg_rdata_prom <= 32'hffffffff;

    if (prom_reg_wen) begin
        // Emulate read command (03) from address 1fff000 for FPGA S/N
        prom_sn_read <= (reg_wdata == 32'h031fff00) ? 1'b1 : 1'b0;
    end
    if (prom_blk_wen && (reg_waddr[5:2] == 4'd0)) begin
        prom_data[reg_waddr[1:0]] <= reg_wdata;
    end
end

// --------------------------------------------------------------------------
// FPGA board regs (Firewire PHY, firmware version, watchdog, partial status)
// --------------------------------------------------------------------------

BoardRegs chan0(
    .sysclk(sysclk),

    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .reg_rdata_ext(reg_rdata_chan0_ext),

    .wdog_period_led(wdog_period_led),
    .wdog_period_status(wdog_period_status),
    .wdog_timeout(wdog_timeout),
    .wdog_clear(wdog_clear)
);

// --------------------------------------------------------------------------
// Zynq PS interface
// --------------------------------------------------------------------------

wire clk_200MHz;

fpgav3 zynq_ps7(
    .processing_system7_0_MIO(MIO),
    .processing_system7_0_PS_SRSTB_pin(PS_SRSTB),
    .processing_system7_0_PS_CLK_pin(PS_CLK),
    .processing_system7_0_PS_PORB_pin(PS_PORB),
    .processing_system7_0_GPIO_I_pin(emio_ps_in),
    .processing_system7_0_GPIO_O_pin(emio_ps_out),
    .processing_system7_0_GPIO_T_pin(emio_ps_tri),
    .processing_system7_0_FCLK_CLK0_pin(clk_200MHz),

    .gmii_to_rgmii_1_rgmii_txd_pin(E1_TxD),
    .gmii_to_rgmii_1_rgmii_tx_ctl_pin(E1_TxEN),
    .gmii_to_rgmii_1_rgmii_txc_pin(E1_TxCLK),
    .gmii_to_rgmii_1_rgmii_rxd_pin(E1_RxD),
    .gmii_to_rgmii_1_rgmii_rx_ctl_pin(E1_RxVAL),
    .gmii_to_rgmii_1_rgmii_rxc_pin(E1_RxCLK),
    .gmii_to_rgmii_1_gmii_rxd_pin(gmii_rxd[1]),
    .gmii_to_rgmii_1_gmii_rx_dv_pin(gmii_rx_dv[1]),
    .gmii_to_rgmii_1_gmii_rx_er_pin(gmii_rx_er[1]),
    .gmii_to_rgmii_1_gmii_rx_clk_pin(gmii_rx_clk[1]),
    .gmii_to_rgmii_1_MDIO_MDC_pin(mdio_clk[1]),       // MDIO clock from RTL8211F module or Zynq PS
    .gmii_to_rgmii_1_MDIO_I_pin(mdio_i[1]),           // OUT from GMII core, IN to RTL8211F module or Zynq PS
    .gmii_to_rgmii_1_MDIO_O_pin(mdio_o[1]),           // IN to GMII core, OUT from RTL8211F module or Zynq PS
    .gmii_to_rgmii_1_MDIO_T_pin(mdio_t[1]),           // Tristate control from RTL8211F module or Zynq PS
    .gmii_to_rgmii_1_gmii_txd_pin(gmii_txd[1]),
    .gmii_to_rgmii_1_gmii_tx_en_pin(gmii_tx_en[1]),
    .gmii_to_rgmii_1_gmii_tx_clk_pin(gmii_tx_clk[1]),
    .gmii_to_rgmii_1_gmii_tx_er_pin(gmii_tx_err[1]),
    .gmii_to_rgmii_1_MDC_pin(E1_MDIO_C),              // MDIO clock from GMII core (derived from mdio_clk[1])
    .gmii_to_rgmii_1_clock_speed_pin(clock_speed[1]), // Clock speed (Rx)
    .gmii_to_rgmii_1_speed_mode_pin(speed_mode[1]),   // Speed mode (Tx)

    .processing_system7_0_ENET0_GMII_RX_CLK_pin(gmii_rx_clk[1]&ps_eth_enable[1]),
    .processing_system7_0_ENET0_GMII_RX_DV_pin(gmii_rx_dv[1]&ps_eth_enable[1]),
    .processing_system7_0_ENET0_GMII_RX_ER_pin(gmii_rx_er[1]&ps_eth_enable[1]),
    .processing_system7_0_ENET0_GMII_RXD_pin(gmii_rxd[1]),
    .processing_system7_0_ENET0_GMII_TX_EN_pin(gmii_tx_en_ps[1]),
    .processing_system7_0_ENET0_GMII_TX_ER_pin(gmii_tx_err_ps[1]),
    .processing_system7_0_ENET0_GMII_TX_CLK_pin(gmii_tx_clk[1]&ps_eth_enable[1]),
    .processing_system7_0_ENET0_GMII_TXD_pin(gmii_txd_ps[1]),
    .processing_system7_0_ENET0_MDIO_MDC_pin(mdio_clk_ps[1]),
    .processing_system7_0_ENET0_MDIO_I_pin(mdio_i[1]&ps_eth_enable[1]),
    .processing_system7_0_ENET0_MDIO_O_pin(mdio_o_ps[1]),
    .processing_system7_0_ENET0_MDIO_T_pin(mdio_t_ps[1]),

    .gmii_to_rgmii_2_rgmii_txd_pin(E2_TxD),
    .gmii_to_rgmii_2_rgmii_tx_ctl_pin(E2_TxEN),
    .gmii_to_rgmii_2_rgmii_txc_pin(E2_TxCLK),
    .gmii_to_rgmii_2_rgmii_rxd_pin(E2_RxD),
    .gmii_to_rgmii_2_rgmii_rx_ctl_pin(E2_RxVAL),
    .gmii_to_rgmii_2_rgmii_rxc_pin(E2_RxCLK),
    .gmii_to_rgmii_2_gmii_rxd_pin(gmii_rxd[2]),
    .gmii_to_rgmii_2_gmii_rx_dv_pin(gmii_rx_dv[2]),
    .gmii_to_rgmii_2_gmii_rx_er_pin(gmii_rx_er[2]),
    .gmii_to_rgmii_2_gmii_rx_clk_pin(gmii_rx_clk[2]),
    .gmii_to_rgmii_2_MDIO_MDC_pin(mdio_clk[2]),       // MDIO clock from RTL8211F module
    .gmii_to_rgmii_2_MDIO_I_pin(mdio_i[2]),           // OUT from GMII core, IN to RTL8211F module
    .gmii_to_rgmii_2_MDIO_O_pin(mdio_o[2]),           // IN to GMII core, OUT from RTL8211F module
    .gmii_to_rgmii_2_MDIO_T_pin(mdio_t[2]),           // Tristate control from RTL8211F module
    .gmii_to_rgmii_2_gmii_txd_pin(gmii_txd[2]),
    .gmii_to_rgmii_2_gmii_tx_en_pin(gmii_tx_en[2]),
    .gmii_to_rgmii_2_gmii_tx_clk_pin(gmii_tx_clk[2]),
    .gmii_to_rgmii_2_gmii_tx_er_pin(gmii_tx_err[2]),
    .gmii_to_rgmii_2_MDC_pin(E2_MDIO_C),              // MDIO clock from GMII core (derived from mdio_clk[2])
    .gmii_to_rgmii_2_clock_speed_pin(clock_speed[2]), // Clock speed (Rx)
    .gmii_to_rgmii_2_speed_mode_pin(speed_mode[2]),   // Speed mode (Tx)

    .processing_system7_0_ENET1_GMII_RX_CLK_pin(gmii_rx_clk[2]&ps_eth_enable[2]),
    .processing_system7_0_ENET1_GMII_RX_DV_pin(gmii_rx_dv[2]&ps_eth_enable[2]),
    .processing_system7_0_ENET1_GMII_RX_ER_pin(gmii_rx_er[2]&ps_eth_enable[2]),
    .processing_system7_0_ENET1_GMII_RXD_pin(gmii_rxd[2]),
    .processing_system7_0_ENET1_GMII_TX_EN_pin(gmii_tx_en_ps[2]),
    .processing_system7_0_ENET1_GMII_TX_ER_pin(gmii_tx_err_ps[2]),
    .processing_system7_0_ENET1_GMII_TX_CLK_pin(gmii_tx_clk[2]&ps_eth_enable[2]),
    .processing_system7_0_ENET1_GMII_TXD_pin(gmii_txd_ps[2]),
    .processing_system7_0_ENET1_MDIO_MDC_pin(mdio_clk_ps[2]),
    .processing_system7_0_ENET1_MDIO_I_pin(mdio_i[2]&ps_eth_enable[2]),
    .processing_system7_0_ENET1_MDIO_O_pin(mdio_o_ps[2]),
    .processing_system7_0_ENET1_MDIO_T_pin(mdio_t_ps[2])
);

// Ethernet Rx/Tx Routing
//
// Rx (receive) -- all GMII signals output from gmii_to_rgmii core, input to both PS and PL ethernet
//
// Tx (transmit)
//    tx_clk: output from gmii_to_rgmii core, input to both PS and PL ethernet
//    txd:    output from PS and PL ethernet, mux input to gmii_to_rgmii core
//    tx_en:  output from PS and PL ethernet, mux input to gmii_to_rgmii core
//    tx_err: output from PS and PL ethernet, mux input to gmii_to_rgmii core

// *** BEGIN: TEST code for PS clocks

reg[7:0] cnt_200;     // Counter incremented by clk_200MHz
reg[7:0] sysclk200;   // Counter increment by sysclk, sampled and cleared every 128 clk_200MHz
reg[7:0] clk200per;   // Last measured half-period of clk_200MHz (should be about 31 sysclks)
reg cur_msb;
reg last_msb;

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
