/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2017 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394-QLA motor controller interface.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/27/11    Paul Thienphrapa    Initial revision (pault at cs.jhu.edu)
 *     02/29/12    Zihan Chen
 */

`timescale 1ns / 1ps

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
    input wire 	     RxD,
    input wire 	     RTS,
    output wire      TxD,

    // debug I/Os
    input wire       clk29m,    // 29.4989 MHz
    input wire       clk40m,    // 40.0000 MHz 
    output wire [3:0] DEBUG,

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

    wire eth1394;               // 1: eth1394 mode 0: firewire mode
    wire lreq_trig;
    wire[2:0] lreq_type;
    wire reg_wen;               // register write signal
    wire blk_wen;               // block write enable
    wire blk_wstart;
    wire[15:0] reg_raddr;       // 16-bit reg read address
    wire[15:0] reg_waddr;       // 16-bit reg write address
    wire[31:0] reg_rdata;       // reg read data
    wire[31:0] reg_wdata;       // reg write data
    wire[31:0] reg_rd[0:15];

//------------------------------------------------------------------------------
// hardware description
//

BUFG clksysclk(.I(clk1394), .O(sysclk));


// Mux routing read data based on read address
//   See Constants.v for detail
//     addr[15:12]  main | hub | prom | prom_qla 
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                  ((reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                  ((reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom_qla) : 
                  ((reg_raddr[7:4]==4'd0) ? reg_rdata_chan0 : reg_rd[reg_raddr[3:0]])));


// 1394 phy low reset, never reset
assign reset_phy = 1'b1; 


// --------------------------------------------------------------------------
// hub register module
// --------------------------------------------------------------------------

// route HubReg data to global reg_rdata
wire[31:0] reg_rdata_hub;
// assign reg_rdata_hub = 32'h0;

HubReg hub(
    .sysclk(sysclk),
    .reg_wen(reg_wen),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_hub),
    .reg_wdata(reg_wdata)
);


// --------------------------------------------------------------------------
// firewire modules
// --------------------------------------------------------------------------

`ifdef USE_CHIPSCOPE
wire [35:0] control_fw;
icon_prom icon(
    .CONTROL0(control_fw)
);
`endif

// phy-link interface
PhyLinkInterface phy(
    .sysclk(sysclk),         // in: global clk  
    .reset(reset),           // in: global reset
    .eth1394(eth1394),       // in: eth1394 mode
    .board_id(~wenid),       // in: board id (rotary switch)
    
    .ctl_ext(ctl),           // bi: phy ctl lines
    .data_ext(data),         // bi: phy data lines
    
    .reg_wen(reg_wen),       // out: reg write signal
    .blk_wen(blk_wen),       // out: block write signal
    .blk_wstart(blk_wstart), // out: block write is starting

    .reg_raddr(reg_raddr),   // out: register address
    .reg_waddr(reg_waddr),   // out: register address
    .reg_rdata(reg_rdata),   // in:  read data to external register
    .reg_wdata(reg_wdata),   // out: write data to external register

    .lreq_trig(lreq_trig),   // out: phy request trigger
    .lreq_type(lreq_type)    // out: phy request type
                     
`ifdef USE_CHIPSCOPE
    ,
    .ila_control(control_fw) // inout: ila control
`endif
);


// phy request module
PhyRequest phyreq(
    .sysclk(sysclk),          // in: global clock
    .reset(reset),            // in: reset
    .lreq(lreq),              // out: phy request line
    .trigger(lreq_trig),      // in: phy request trigger
    .rtype(lreq_type),        // in: phy request type
    .data(reg_wdata[11:0])    // in: phy request data
);



// --------------------------------------------------------------------------
// adcs: pot + current 
// --------------------------------------------------------------------------

// ~12 MHz clock for spi communication with the adcs
wire clkdiv2, clkadc;
ClkDiv div2clk(sysclk, clkdiv2);
defparam div2clk.width = 2;
BUFG adcclk(.I(clkdiv2), .O(clkadc));


// map 2 types of  reads to the output of the adc controller; the
//   latter will select the correct data to output based on read address
wire[31:0] reg_radc;
assign reg_rd[`OFF_ADC_DATA] = reg_radc;    // adc reads

// local wire for cur_fb(1-4) 
wire[15:0] cur_fb[1:4];

// adc controller routes conversion results according to address
CtrlAdc adc(
    .clkadc(clkadc),
    .reset(reset),
    .sclk({IO1[10],IO1[28]}),
    .conv({IO1[11],IO1[27]}),
    .miso({IO1[12:15],IO1[26],IO1[25],IO1[24],IO1[23]}),
    .reg_raddr(reg_raddr),
    .reg_rdata(reg_radc),
    .cur1(cur_fb[1]),
    .cur2(cur_fb[2]),
    .cur3(cur_fb[3]),
    .cur4(cur_fb[4])
);


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
    .reset(reset),
    .sclk(IO1[21]),
    .mosi(IO1[20]),
    .csel(IO1[22]),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdac),
    .reg_wdata(reg_wdata),
    .dac1(cur_cmd[1]),
    .dac2(cur_cmd[2]),
    .dac3(cur_cmd[3]),
    .dac4(cur_cmd[4])
);


// --------------------------------------------------------------------------
// encoders
// --------------------------------------------------------------------------

// fast (~1 MHz) / slow (~12 Hz) clocks to measure encoder period / frequency
wire clk_1mhz, clk_12hz;
ClkDiv divenc1(sysclk, clk_1mhz); defparam divenc1.width = 6;   // 49.152 MHz / 2**6 ==> 768 kHz
ClkDiv divenc2(sysclk, clk_12hz); defparam divenc2.width = 22;  // 49.152 MHz / 2**22 ==> 11.71875 Hz

// map all types of encoder reads to the output of the encoder controller; the
//   latter will select the correct data to output based on read address
wire[31:0] reg_renc;
assign reg_rd[`OFF_ENC_LOAD] = reg_renc;    // preload
assign reg_rd[`OFF_ENC_DATA] = reg_renc;    // quadrature
assign reg_rd[`OFF_PER_DATA] = reg_renc;    // period
assign reg_rd[`OFF_FREQ_DATA] = reg_renc;   // frequency


// encoder controller: the thing that manages encoder reads and preloads
CtrlEnc enc(
    .sysclk(sysclk),
    .reset(reset),
    .enc_a({IO2[23],IO2[21],IO2[19],IO2[17]}),
    .enc_b({IO2[15],IO2[13],IO2[12],IO2[10]}),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_renc),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen)
);

// --------------------------------------------------------------------------
// digital output (DOUT) control
// --------------------------------------------------------------------------

wire[31:0] reg_rdout;
assign reg_rd[`OFF_DOUT_CTRL] = reg_rdout;

// DOUT hardware configuration
wire dout_config_valid;
wire dout_config_bidir;
wire [3:0] dout;

// IO1[16]: DOUT 4
// IO1[17]: DOUT 3
// IO1[18]: DOUT 2
// IO1[19]: DOUT 1
assign {IO1[16],IO1[17],IO1[18],IO1[19]} = (dout_config_bidir) ? (~dout) : dout;

CtrlDout cdout(
    .sysclk(sysclk),
    .reset(reset),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdout),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .dout(dout),
    .dir12(IO1[6]),
    .dir34(IO1[5]),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir)
);

// --------------------------------------------------------------------------
// temperature sensors 
// --------------------------------------------------------------------------

// divide 40 MHz clock down to 400 kHz for temperature sensor readings
wire clk400k_raw, clk400k;
ClkDivI divtemp(clk40m, clk400k_raw);
defparam divtemp.div = 100;
BUFG clktemp(.I(clk400k_raw), .O(clk400k));

// route temperature data into BoardRegs module for readout
wire[15:0] tempsense;

// tempsense module instantiations
Max6576 T1(
    .clk400k(clk400k), 
    .reset(reset), 
    .In(IO1[29]), 
    .Out(tempsense[15:8])
);

Max6576 T2(
    .clk400k(clk400k), 
    .reset(reset), 
    .In(IO1[30]), 
    .Out(tempsense[7:0])
);


// --------------------------------------------------------------------------
// Config prom M25P16
// --------------------------------------------------------------------------

// Route PROM status result between M25P16 and BoardRegs modules
wire[31:0] reg_rdata_prom;   // reg_rdata_prom is for block reads from PROM
wire[31:0] PROM_Status;
wire[31:0] PROM_Result;
   
M25P16 prom(
    .clk(sysclk),
    .reset(reset),
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

wire[31:0] reg_rdata_prom_qla;  // reads from QLA prom

QLA25AA128 prom_qla(
    .clk(sysclk),
    .reset(reset),
    
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
// miscellaneous board I/Os
// --------------------------------------------------------------------------

// safety_amp_enable from SafetyCheck moudle
wire[4:1] safety_amp_disable;

// pwr_enable_cmd and amp_enable_cmd from BoardRegs; used to clear safety_amp_disable
wire pwr_enable_cmd;
wire[4:1] amp_enable_cmd;

// 'channel 0' is a special axis that contains various board I/Os
wire[31:0] reg_rdata_chan0;

// There is no Ethernet on this version of board, so set the result to 0
wire[31:0] Eth_Result;
assign  Eth_Result = 32'b0;

BoardRegs chan0(
    .sysclk(sysclk),
    .clkaux(clk40m),
    .reset(reset),
    .amp_disable({IO2[38],IO2[36],IO2[34],IO2[32]}),
    .dout(dout),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir),
    .pwr_enable(IO1[32]),
    .relay_on(IO1[31]),
    .eth1394(eth1394),
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
    .board_id(~wenid),
    .temp_sense(tempsense),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .eth_result(Eth_Result),
    .safety_amp_disable(safety_amp_disable),
    .pwr_enable_cmd(pwr_enable_cmd),
    .amp_enable_cmd(amp_enable_cmd)
);

// ----------------------------------------------------------------------------
// safety check 
//    1. get adc feedback current & dac command current
//    2. check if cur_fb > 2 * cur_cmd
SafetyCheck safe1(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[1]),
    .dac_in(cur_cmd[1]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[1]),
    .amp_disable(safety_amp_disable[1])
);

SafetyCheck safe2(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[2]),
    .dac_in(cur_cmd[2]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[2]),
    .amp_disable(safety_amp_disable[2])
);

SafetyCheck safe3(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[3]),
    .dac_in(cur_cmd[3]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[3]),
    .amp_disable(safety_amp_disable[3])
);

SafetyCheck safe4(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[4]),
    .dac_in(cur_cmd[4]),
    .clear_disable(pwr_enable_cmd | amp_enable_cmd[4]),
    .amp_disable(safety_amp_disable[4])
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
    .reset(reset),
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
assign DEBUG = { clk_1mhz, clk_12hz, CountI[23], CountC[23] }; 

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
CtrlLED qla_led(
    .sysclk(sysclk),
    .clk_12hz(clk_12hz),
    .reset(reset),
    .led1_grn(IO2[1]),
    .led1_red(IO2[3]),
    .led2_grn(IO2[5]),
    .led2_red(IO2[7])
);

endmodule
