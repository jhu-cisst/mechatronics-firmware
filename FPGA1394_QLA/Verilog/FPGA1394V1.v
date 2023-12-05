/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This module contains common code for FPGA V1 and does not make any assumptions
 * about which board is connected.
 *
 * Revision history
 *     12/11/22    Peter Kazanzides    Created from FPGA1394-QLA.v
 */

`include "Constants.v"

module FPGA1394V1
    #(parameter NUM_MOTORS = 4,
      parameter NUM_ENCODERS = 4)
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

    // serial interface
    input wire       RxD,
    input wire       RTS,       // Not used
    output wire      TxD,

    input wire       clk40m,    // 40.0000 MHz

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
    output wire req_blk_rt_rd,    // request for real-time block read
    output wire blk_rt_rd,        // real-time block read in process

    // Timestamp
    input wire[31:0] timestamp,

    // Watchdog support
    output wire wdog_period_led,    // 1 -> external LED displays wdog_period_status
    output wire[2:0] wdog_period_status,
    output wire wdog_timeout,       // watchdog timeout status flag
    input  wire wdog_clear          // clear watchdog timeout (e.g., on powerup)
);

// Number of quadlets in real-time block read (not including Firewire header and CRC)
localparam NUM_RT_READ_QUADS = (4 + 2*NUM_MOTORS + 5*NUM_ENCODERS);
// Number of quadlets in broadcast real-time block; includes sequence number
localparam NUM_BC_READ_QUADS = (1+NUM_RT_READ_QUADS);

// 1394 phy low reset, never reset
assign reset_phy = 1'b1;

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //

    wire reboot;                // FPGA reboot request
    wire lreq_trig;             // phy request trigger
    wire[2:0] lreq_type;        // phy request type
    wire fw_reg_wen;            // register write signal from FireWire
    wire fw_blk_wen;            // block write enable from FireWire
    wire fw_blk_wstart;         // block write start from FireWire
    wire fw_req_blk_rt_rd;      // real-time block read request from FireWire
    wire fw_blk_rt_rd;          // real-time block read from FireWire
    wire[15:0] fw_reg_raddr;    // 16-bit reg read address from FireWire
    wire[15:0] fw_reg_waddr;    // 16-bit reg write address from FireWire
    wire[31:0] fw_reg_wdata;    // reg write data from FireWire
    wire[31:0] prom_status;
    wire[31:0] prom_result;
    wire[31:0] Eth_Result;
    wire[31:0] ip_address;

// There is no Ethernet on this version of board, so set the result to 0
// and the IP address to 255.255.255.255
assign  Eth_Result = 32'b0;
assign ip_address = 32'hffffffff;

//*********************** Read Address Translation *******************************

// Read bus address translation (to support real-time block read).
// This could instead be instantiated in the either the FPGAV1 or QLA modules
// (FPGAV1 module would need NUM_MOTORS and NUM_ENCODERS).

assign req_blk_rt_rd = fw_req_blk_rt_rd;
assign blk_rt_rd = fw_blk_rt_rd;

ReadAddressTranslation
    #(.NUM_MOTORS(NUM_MOTORS), .NUM_ENCODERS(NUM_ENCODERS))
ReadAddr(
    .reg_raddr_in(fw_reg_raddr),
    .reg_raddr_out(reg_raddr),
    .blk_rt_rd(blk_rt_rd)
);

// --------------------------------------------------------------------------
// Write data for real-time block
// --------------------------------------------------------------------------

// For real-time write
wire       rt_wen;
wire[3:0]  rt_waddr;
wire[31:0] rt_wdata;

wire bw_write_en;
wire[7:0] bw_reg_waddr;
wire[31:0] bw_reg_wdata;
wire bw_reg_wen;
wire bw_blk_wen;
wire bw_blk_wstart;

WriteRtData #(.NUM_MOTORS(NUM_MOTORS)) rt_write
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

wire[31:0] reg_rdata;
wire[31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire[31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_chan0;    // for reads from board registers

wire isAddrMain;
assign isAddrMain = ((reg_raddr[15:12]==`ADDR_MAIN) && (reg_raddr[7:4]==4'd0)) ? 1'b1 : 1'b0;

// Mux routing read data based on read address
//   See Constants.v for details
//     addr[15:12]  main | hub | prom | prom_qla | eth | firewire | dallas | databuf | waveform
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                   (reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
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

// phy-link interface
PhyLinkInterface
    #(.NUM_BC_READ_QUADS(NUM_BC_READ_QUADS))
phy(
    .sysclk(sysclk),         // in: global clk  
    .board_id(board_id),     // in: board id (rotary switch)

    .ctl_ext(ctl),           // bi: phy ctl lines
    .data_ext(data),         // bi: phy data lines
    
    .reg_wen(fw_reg_wen),       // out: reg write signal
    .blk_wen(fw_blk_wen),       // out: block write signal
    .blk_wstart(fw_blk_wstart), // out: block write is starting
    .blk_rt_rd(fw_blk_rt_rd),   // out: real-time block read in process
    .req_blk_rt_rd(fw_req_blk_rt_rd),  // out: real-time block read request

    .reg_raddr(fw_reg_raddr),  // out: register address
    .reg_waddr(fw_reg_waddr),  // out: register address
    .reg_rdata(reg_rdata),     // in:  read data to external register
    .reg_wdata(fw_reg_wdata),  // out: write data to external register

    .lreq_trig(lreq_trig),   // out: phy request trigger
    .lreq_type(lreq_type),   // out: phy request type

    .rx_bc_sequence(bc_sequence),  // in: broadcast sequence num
    .write_trig(hub_write_trig),   // in: 1 -> broadcast write this board's hub data
    .write_trig_reset(hub_write_trig_reset),
    .fw_idle(fw_idle),

    // Interface for real-time block write
    .fw_rt_wen(rt_wen),
    .fw_rt_waddr(rt_waddr),
    .fw_rt_wdata(rt_wdata),

    // Timestamp
    .timestamp(timestamp)
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

//---------------------------------------------------------------------------
// USB Serial 
//---------------------------------------------------------------------------

// Clocks for USB Serial 

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

endmodule
