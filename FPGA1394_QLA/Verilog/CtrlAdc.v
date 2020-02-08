/*******************************************************************************
 *
 * Copyright(C) 2011-2020 ERC CISST, Johns Hopkins University.
 *
 * This module controls access to the adc modules by selecting the data to
 * output based on the read address, and by combining the 16-bit values for
 * analog pot and motor current into a single 32-bit word.
 *
 * Revision history
 *     11/22/11    Paul Thienphrapa    Initial revision
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
    output wire[15:0] pot1,        // pot axis 1
    output wire[15:0] pot2,        // pot axis 2
    output wire[15:0] pot3,        // pot axis 3
    output wire[15:0] pot4         // pot axis 4
);


    // local wires
    wire[1:4] miso_pot;
    wire[1:4] miso_cur;
    wire[15:0] potval[1:4];       // 4 channels of analog pot values
    wire[15:0] curval[1:4];       // 4 channels of current feedback values

//------------------------------------------------------------------------------
// hardware description
//

// assign miso to local miso wire
assign miso_pot = miso[1:4];
assign miso_cur = miso[5:8];

// pot feedback module
Ltc1864x4 adc_pot(
    .clk(clkadc),
    .Out1(potval[1]),
    .Out2(potval[2]),
    .Out3(potval[3]),
    .Out4(potval[4]),
    .sclk(sclk[1]),
    .conv(conv[1]),
    .miso(miso_pot)
);

// cur feedback module
Ltc1864x4 adc_cur(
    .clk(clkadc),
    .Out1(curval[1]),
    .Out2(curval[2]),
    .Out3(curval[3]),
    .Out4(curval[4]),
    .sclk(sclk[2]),
    .conv(conv[2]),
    .miso(miso_cur)
);

// connect to cur value output
assign cur1 = curval[1];
assign cur2 = curval[2];
assign cur3 = curval[3];
assign cur4 = curval[4];

endmodule
