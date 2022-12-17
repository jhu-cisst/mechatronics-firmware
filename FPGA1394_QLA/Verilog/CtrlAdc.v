/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * This module controls access to the adc modules.
 * It is implemented to simultaneously interface with 4 adcs for the pots (with common
 * sclk/conv) and with 4 adcs for the motor current feedback (with common sclk/conv).
 *
 * For a different number of channels (e.g., 8 instead of 4), it is easier to
 * directly instantiate the Ltc1864SPI and Ltc1864x4 modules rather than this module.
 *
 * Revision history
 *     11/22/11    Paul Thienphrapa    Initial revision
 *     12/17/22    Peter Kazanzides    Moved sclk/conv to Ltc1864SPI
 */

// device register file offset
`include "Constants.v" 

module CtrlAdc(
    input  wire clkadc,            // adc clock
    output wire[1:2] sclk,         // sclk signal to each set of adcs
    output wire[1:2] conv,         // conv signal to each set of adcs
    input  wire[1:8] miso,         // data lines from each individual adc
    output wire[15:0] cur1,        // current axis 1
    output wire[15:0] cur2,        // current axis 2
    output wire[15:0] cur3,        // current axis 3
    output wire[15:0] cur4,        // current axis 4
    output wire       cur_ready,   // new current data available
    output wire[15:0] pot1,        // pot axis 1
    output wire[15:0] pot2,        // pot axis 2
    output wire[15:0] pot3,        // pot axis 3
    output wire[15:0] pot4,        // pot axis 4
    output wire       pot_ready    // new pot data available
);


    // local wires
    wire[1:4] miso_pot;
    wire[1:4] miso_cur;

//------------------------------------------------------------------------------
// hardware description
//

// assign miso to local miso wire
assign miso_pot = miso[1:4];
assign miso_cur = miso[5:8];

// pot feedback module

wire pot_latch_bit;
wire pot_latch_word;

Ltc1864SPI spi_pot(
    .clk(clkadc),
    .sclk(sclk[1]),
    .conv(conv[1]),
    .OutReady(pot_ready),
    .latch_bit(pot_latch_bit),
    .latch_word(pot_latch_word)
);

Ltc1864x4 adc_pot(
    .clk(clkadc),
    .Out1(pot1),
    .Out2(pot2),
    .Out3(pot3),
    .Out4(pot4),
    .latch_bit(pot_latch_bit),
    .latch_word(pot_latch_word),
    .miso(miso_pot)
);

// cur feedback module

wire cur_latch_bit;
wire cur_latch_word;

Ltc1864SPI spi_cur(
    .clk(clkadc),
    .sclk(sclk[2]),
    .conv(conv[2]),
    .OutReady(cur_ready),
    .latch_bit(cur_latch_bit),
    .latch_word(cur_latch_word)
);

Ltc1864x4 adc_cur(
    .clk(clkadc),
    .Out1(cur1),
    .Out2(cur2),
    .Out3(cur3),
    .Out4(cur4),
    .latch_bit(cur_latch_bit),
    .latch_word(cur_latch_word),
    .miso(miso_cur)
);

endmodule
