/*******************************************************************************    
 *
 * Copyright(C) 2011-2012 ERC CISST, Johns Hopkins University.
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


module FPGA1394QLA
(
    // ieee 1394 phy-link interface
    input            clk1394,
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // serial interface
    input wire 	     RxD,
    input wire 	     RTS,
    output wire      TxD,

    // debug I/Os
    input wire       clk29m,
    input wire       clk40m,
    output wire [3:0] DEBUG,

    // misc board I/Os
    input [3:0]      wenid,
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

    wire lreq_trig;
    wire[2:0] lreq_type;
    wire reg_wen, blk_wen, blk_wact;
    wire[7:0] reg_addr;
    wire[31:0] reg_rdata;
    wire[31:0] reg_wdata;
    wire[31:0] reg_rd[0:15];

//------------------------------------------------------------------------------
// hardware description
//

BUFG clksysclk(.I(clk1394), .O(sysclk));

wire prom_blk_enable;
assign prom_blk_enable = (reg_addr[7:6] == 2'b11) ? 1'b1 : 1'b0;

// route read data based on read address (channel 0 is a special axis)
assign reg_rdata = (reg_addr[7:4] == 0) ? reg_rdata_chan0
                   : (prom_blk_enable ? reg_rdata_prom : reg_rd[reg_addr[3:0]]);
assign reset_phy = 1'b1;

// firewire modules ------------------------------------------------------------

// phy-link interface
PhyLinkInterface phy(
    sysclk, reset, ~wenid,    // in: global clock, reset, board id
    ctl, data,                // bi: phy ctl and data lines
    reg_wen, blk_wen, blk_wact,
    reg_addr,                 // out: register write signal/address
    reg_rdata, reg_wdata,     // out/in: register read address/data
    lreq_trig, lreq_type      // out: phy request trigger and type
);

// phy request module
PhyRequest phyreq(
    sysclk, reset,            // in: global clock and reset
    lreq,                     // out: phy request line
    lreq_trig, lreq_type,     // in: phy request trigger and type
    reg_wdata[11:0]           // in: phy request data
);

// adcs ------------------------------------------------------------------------

// ~12 MHz clock for spi communication with the adcs
wire clkdiv2, clkadc;
ClkDiv div2clk(sysclk, clkdiv2);
defparam div2clk.width = 2;
BUFG adcclk(.I(clkdiv2), .O(clkadc));


// map 2 types of  reads to the output of the adc controller; the
//   latter will select the correct data to output based on read address
wire[31:0] reg_radc;
assign reg_rd[0] = reg_radc;    // adc reads
assign reg_rd[10] = reg_radc;   // sync cur

// local wire for cur_fb(1-4) 
wire[15:0] cur_fb[1:4];

// adc controller routes conversion results according to address
CtrlAdc adc(
    .clkadc(clkadc),
    .reset(reset),
    .sclk({IO1[10],IO1[28]}),
    .conv({IO1[11],IO1[27]}),
    .miso({IO1[12:15],IO1[26],IO1[25],IO1[24],IO1[23]}),
    .reg_addr(reg_addr),
    .reg_rdata(reg_radc),
    .cur1(cur_fb[1]),
    .cur2(cur_fb[2]),
    .cur3(cur_fb[3]),
    .cur4(cur_fb[4])
);

// dacs ------------------------------------------------------------------------

// local wire for dac
wire[31:0] reg_rdac;
assign reg_rd[1] = reg_rdac;   // dac reads

wire[15:0] cur_cmd[1:4];

// the dac controller manages access to the dacs
CtrlDac dac(
    .sysclk(sysclk),
    .reset(reset),
    .board_id(~wenid),
    .sclk(IO1[21]),
    .mosi(IO1[20]),
    .csel(IO1[22]),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .reg_addr(reg_addr),
    .reg_wdata(reg_wdata),
    .reg_rdata(reg_rdac),
    .dac1(cur_cmd[1]),
    .dac2(cur_cmd[2]),
    .dac3(cur_cmd[3]),
    .dac4(cur_cmd[4])
);

// encoders --------------------------------------------------------------------

// fast (~1 MHz) / slow (~12 Hz) clocks to measure encoder period / frequency
wire clk_1mhz, clk_12hz;
ClkDiv divenc1(sysclk, clk_1mhz); defparam divenc1.width = 6;
ClkDiv divenc2(sysclk, clk_12hz); defparam divenc2.width = 22;

// map all types of encoder reads to the output of the encoder controller; the
//   latter will select the correct data to output based on read address
wire[31:0] reg_renc;
assign reg_rd[4] = reg_renc;    // preload
assign reg_rd[5] = reg_renc;    // quadrature
assign reg_rd[6] = reg_renc;    // period
assign reg_rd[7] = reg_renc;    // frequency
//assign reg_rd[8] = reg_renc;    // acceleration 
//assign reg_rd[9] = reg_renc;    // acceleration


// encoder controller: the thing that manages encoder reads and preloads
CtrlEnc enc(
    .sysclk(sysclk),
    .reset(reset),
    .clk_1mhz(clk_1mhz),
    .clk_12hz(clk_12hz),
    .enc_a({IO2[23],IO2[21],IO2[19],IO2[17]}),
    .enc_b({IO2[15],IO2[13],IO2[12],IO2[10]}),
    .reg_addr(reg_addr),
    .reg_rdata(reg_renc),
    .reg_wdata(reg_wdata),
    .reg_we(reg_wen)
);

// temperature sensors ---------------------------------------------------------

// divide 40 MHz clock down to 400 kHz for temperature sensor readings
wire clk400k_raw, clk400k;
ClkDivI divtemp(clk40m, clk400k_raw);
defparam divtemp.div = 100;
BUFG clktemp(.I(clk400k_raw), .O(clk400k));

// route temperature data into BoardRegs module for readout
wire[15:0] tempsense;

// tempsense module instantiations
Max6576 T1(.clk400k(clk400k), 
           .reset(reset), 
           .In(IO1[29]), 
           .Out(tempsense[15:8]));
           
Max6576 T2(.clk400k(clk400k), 
           .reset(reset), 
           .In(IO1[30]), 
           .Out(tempsense[7:0]));

// miscellaneous board I/Os ----------------------------------------------------

// Route PROM status result between M25P16 and BoardRegs modules
wire [31:0] PROM_Status;
wire[31:0] PROM_Result;
// reg_rdata_prom is for block reads from PROM
wire[31:0] reg_rdata_prom;

// safety_amp_enable from SafetyCheck moudle
wire[4:1] safety_amp_disable;
   
// 'channel 0' is a special axis that contains various board I/Os
wire[31:0] reg_rdata_chan0;

BoardRegs chan0(
    .sysclk(sysclk),
    .clkaux(clk40m),
    .reset(reset),
    .amp_disable({IO2[38],IO2[36],IO2[34],IO2[32]}),
    .dout({IO1[19],IO1[18],IO1[17],IO1[16]}),
    .pwr_enable(IO1[32]),
    .relay_on(IO1[31]),
    .neg_limit({IO2[26],IO2[24],IO2[25],IO2[22]}),
    .pos_limit({IO2[30],IO2[29],IO2[28],IO2[27]}),
    .home({IO2[20],IO2[18],IO2[16],IO2[14]}),
    .fault({IO2[37],IO2[35],IO2[33],IO2[31]}),
    .relay(IO2[9]),
    .mv_good(IO2[11]),
    .v_fault(IO1[9]),
    .board_id(~wenid),
    .temp_sense(tempsense),
    .reg_addr(reg_addr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .safety_amp_disable(safety_amp_disable)
);


// prom read/write ----------------------------------------------------
wire prom_reg_wen;    // for a quadlet write to PROM (register)
wire prom_blk_start;  // start of a block write to PROM
wire prom_blk_wen;    // for every quadlet in a block write to PROM
wire prom_blk_end;    // for end of block write to PROM

assign prom_reg_wen = (reg_addr == 8'h08) ? reg_wen : 1'b0;
assign prom_blk_start = prom_blk_enable ? blk_wact : 1'b0;
assign prom_blk_wen = prom_blk_enable ? reg_wen : 1'b0;
assign prom_blk_end = prom_blk_enable ? blk_wen : 1'b0;
   
M25P16 prom(
    .clk(sysclk),
    .reset(reset),
    .prom_cmd(reg_wdata),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .prom_rdata(reg_rdata_prom),
    .prom_blk_addr(reg_addr[5:0]),
    .prom_blk_enable(prom_blk_enable),
    .prom_reg_wen(prom_reg_wen),
    .prom_blk_start(prom_blk_start),
    .prom_blk_wen(prom_blk_wen),
    .prom_blk_end(prom_blk_end),
    .prom_mosi(XMOSI),
    .prom_miso(XMISO),
    .prom_sclk(XCCLK),
    .prom_cs(XCSn)
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
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[1])
);

SafetyCheck safe2(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[2]),
    .dac_in(cur_cmd[2]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[2])
);

SafetyCheck safe3(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[3]),
    .dac_in(cur_cmd[3]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[3])
);

SafetyCheck safe4(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[4]),
    .dac_in(cur_cmd[4]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[4])
);


   
//------------------------------------------------------------------------------
// debugging, etc.
//

wire BaudClk;
reg[3:0] Baud;
reg[23:0] CountC;
reg[23:0] CountI;

BUFG clkout(.I(Baud[3]), .O(BaudClk));
always @(posedge(clk29m)) Baud <= Baud + 1'b1;
always @(posedge(clk40m)) CountC <= CountC + 1'b1;
always @(posedge(sysclk)) CountI <= CountI + 1'b1;

assign LED = IO1[32];
assign DEBUG = { clk_1mhz, clk_12hz, CountI[23], CountC[23] };
assign TxD = 0;

//------------------------------------------------------------------------------
reg led_reset_mode;
reg led_reset_signal;
reg[4:0] led_reset_mode_counter;
always @(negedge(reset) or posedge(clk_12hz))
begin
    if (reset == 0) begin
        led_reset_mode_counter <= 5'd0;
        led_reset_signal <= 1'b0;
    end
    else begin
        if (led_reset_mode_counter < 5'd31) begin
            led_reset_mode_counter <= led_reset_mode_counter + 1'b1;
            led_reset_mode <= 1'b1;
            led_reset_signal <= ~led_reset_signal;
        end
        else begin
            led_reset_mode <= 1'b0;
        end
    end
end

// show green 1, red 1, green 2, red 2 leds using pwm
wire led_green1;
LEDPWM led_green_pwm_1(sysclk, reset, led_green1);
defparam led_green_pwm_1.start_phase = 250;

wire led_red1;
LEDPWM led_red_pwm_1(sysclk, reset, led_red1);
defparam led_red_pwm_1.start_phase = 700;

wire led_green2;
LEDPWM led_green_pwm_2(sysclk, reset, led_green2);
defparam led_green_pwm_2.start_phase = 0;

wire led_red2;
LEDPWM led_red_pwm_2(sysclk, reset, led_red2);
defparam led_red_pwm_2.start_phase = 200;

// output to led using mux
assign IO2[1] = (led_reset_mode) ? 1'b0 : led_green1;
assign IO2[3] = (led_reset_mode) ? led_reset_signal : led_red1;
assign IO2[5] = (led_reset_mode) ? 1'b0 : led_green2;
assign IO2[7] = (led_reset_mode) ? led_reset_signal : led_red2;

endmodule
