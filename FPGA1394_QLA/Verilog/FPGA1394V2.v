/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This module contains common code for FPGA V2 and does not make any assumptions
 * about which board is connected.
 *
 * Revision history
 *     12/10/22    Peter Kazanzides    Created from FPGA1394Eth-QLA.v
 */

`include "Constants.v"

module FPGA1394V2
    #(parameter NUM_BC_READ_QUADS = 33)
(
    // global clock
    input wire       sysclk,

    // reboot clock (~12 MHz)
    input wire       reboot_clk,

    // Board ID (rotary switch)
    input wire[3:0]  board_id,

    // Firewire interface
    // phy-link interface bus
    inout[7:0]       data,
    inout[1:0]       ctl,
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
    inout[15:0]      SD,

    // SPI interface to PROM
    output           XCCLK,
    input            XMISO,
    output           XMOSI,
    output           XCSn,

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

// Ethernet
assign ETH_CSn = 0;         // Always select

// The FPGA board is designed to enable the 16-bit bus. If resistor R45
// is populated, then this can be changed by driving ETH_8n low during reset.
// By default, R45 is not populated, so driving this pin has no effect.
assign ETH_8n = 1;          // 16-bit bus

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //
    wire reboot;                // FPGA reboot request
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

assign reg_raddr = eth_req_read_bus ? eth_reg_raddr :
                   fw_reg_raddr;

wire[31:0] reg_rdata;
wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire[31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_eth;      // for eth memory access (EthernetIO)
wire[31:0] reg_rdata_ksz;      // for eth memory access (KSZ8851)
wire[31:0] reg_rdata_fw;       // for fw memory access
wire[31:0] reg_rdata_chan0;    // for reads from board registers

wire isAddrMain;
assign isAddrMain = ((reg_raddr[15:12]==`ADDR_MAIN) && (reg_raddr[7:4]==4'd0)) ? 1'b1 : 1'b0;

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                   (reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                   (reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth|reg_rdata_ksz) :
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
   else if (eth_req_write_bus) begin
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

    .req_read_bus(fw_req_read_bus),    // out: request read bus
    .req_write_bus(fw_req_write_bus),  // out: request read bus

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
    .sample_rdata(sample_rdata),      // Sampled data (for block read)
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

// The Ethernet result is used to distinguish between FPGA versions
//    Rev 1:  Eth_Result == 32'd0
//    Rev 2:  Eth_Result[31] == 1, other bits variable
//    Rev 3:  Eth_Result[31:30] == 01, other bits variable
// For Rev 2 (this file), Eth_Result is allocated as follows:
//    31:24  (8 bits) Ethernet PHY status (sets MSB to 1, as noted above)
//    23:16  (8 bits) EthernetIO (higher level) status
//    15:0   (16 bits)  Ethernet register data
// Note that the eth_status_phy and eth_status_io bits are intermingled for backward
// compatible bit assignments.
wire[7:0] eth_status_phy;
wire[7:0] eth_status_io;
wire[15:0] eth_data;
assign Eth_Result = { eth_status_phy[7:5], eth_status_io[7:3], eth_status_phy[4],
                      eth_status_io[2:0], eth_status_phy[3:0], eth_data };

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
wire[15:0] eth_time_recv;       // Time when receive portion finished
wire[15:0] eth_time_now;        // Running time counter since start of packet receive
wire eth_bw_active;             // Indicates that block write module is active
wire eth_InternalError;         // Error summary bit to EthernetIO
wire[5:0] eth_ioErrors;         // Error bits from EthernetIO
wire useUDP;                    // Whether EthernetIO is using UDP

KSZ8851  EthernetMacPhy(
    .sysclk(sysclk),          // in: global clock

    .board_id(board_id),      // in: board id (rotary switch)

    // Interface to KSZ8851
    .ETH_IRQn(ETH_IRQn),      // in: interrupt request from KSZ8851
    .ETH_RSTn(ETH_RSTn),      // out: reset to KSZ8851
    .ETH_CMD(ETH_CMD),        // out: CMD to KSZ8851 (0=data, 1=addr)
    .ETH_RDn(ETH_RDn),        // out: read strobe to KSZ8851
    .ETH_WRn(ETH_WRn),        // out: write strobe to KSZ8851
    .SD(SD),                  // inout: addr/data bus to KSZ8851

    // Firewire interface to KSZ8851 (for testing). Results are provided
    // via eth_data and eth_status, which are combined in the 32-bit register
    // Eth_Result, which is available via board register REG_ETHSTAT (12).
    .fw_reg_wen(fw_reg_wen),           // in: write enable from FireWire
    .fw_reg_waddr(fw_reg_waddr),       // in: write address from FireWire
    .fw_reg_wdata(fw_reg_wdata),       // in: data from FireWire
    .eth_data(eth_data),               // out: Last register read
    .eth_status(eth_status_phy),       // out: Ethernet status register

    // Register interface to Ethernet memory space (ADDR_ETH=0x4000)
    .reg_rdata(reg_rdata_ksz),         // Data from Ethernet memory space
    .reg_raddr(reg_raddr),             // Read address for Ethernet memory

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
    .timeReceive(eth_time_recv),      // Time when receive portion finished
    .timeSinceIRQ(eth_time_now),      // Running time counter since start of packet receive
    .bw_active(eth_bw_active),        // Indicates that block write module is active
    .ethInternalError(eth_InternalError)   // Error summary bit to EthernetIO
);

// address decode for IP address access
wire   ip_reg_wen;
assign ip_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_IPADDR}) ? reg_wen : 1'b0;

// address decode for Ethernet status/control register access
wire   eth_ctrl_wen;
assign eth_ctrl_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHSTAT}) ? reg_wen : 1'b0;

EthernetIO EthernetTransfers(
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
    .eth_req_read_bus(eth_req_read_bus), // out: reg read enable
    .eth_reg_wdata(eth_reg_wdata),     // out: reg write data
    .eth_reg_waddr(eth_reg_waddr),     // out: reg write addr
    .eth_reg_wen(eth_reg_wen),         // out: reg write enable
    .eth_block_wen(eth_blk_wen),       // out: blk write enable
    .eth_block_wstart(eth_blk_wstart), // out: blk write start
    .eth_req_write_bus(eth_req_write_bus), // out: request write bus

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

    // Interface to KSZ8851
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
// Config prom M25P16
// --------------------------------------------------------------------------

M25P16 prom(
    .clk(sysclk),
    .prom_cmd(reg_wdata),
    .prom_status(prom_status),
    .prom_result(prom_result),
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
// FPGA board regs (Firewire PHY, firmware version, watchdog, partial status)
// --------------------------------------------------------------------------

BoardRegs chan0(
    .sysclk(sysclk),
    .reboot(reboot),

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
// Reboot
// --------------------------------------------------------------------------
Reboot fpga_reboot(
     .clk(reboot_clk),     // Use 12 MHz clock (cannot be more than 20 MHz)
     .reboot(reboot)
);

endmodule
