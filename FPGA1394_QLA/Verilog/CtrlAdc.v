/*******************************************************************************
 *
 * Copyright(C) 2011 ERC CISST, Johns Hopkins University.
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
    input  wire reset,             // system reset
    output wire[1:2] sclk,         // sclk signal to each set of adcs
    output wire[1:2] conv,         // conv signal to each set of adcs
    input  wire[1:8] miso,         // data lines from each individual adc
    input  wire[7:0] reg_addr,     // register file addr from outside world
    output wire[31:0] reg_rdata,   // outgoing register file data
    output wire[15:0] cur1,        // current axis 1
    output wire[15:0] cur2,        // current axis 2
    output wire[15:0] cur3,        // current axis 3
    output wire[15:0] cur4         // current axis 4
);


    // local wires
    wire[1:4] miso_pot;
    wire[1:4] miso_cur;
    wire[15:0] potval[0:15];       // 4 channels of analog pot values
    wire[15:0] curval[0:15];       // 4 channels of current feedback values

    // for array-style access to the adc data
    wire[31:0] mem_data[0:15][0:15];

//------------------------------------------------------------------------------
// hardware description
//

// assign miso to local miso wire
assign miso_pot = miso[1:4];
assign miso_cur = miso[5:8];

// output selected read register
assign reg_rdata = mem_data[reg_addr[7:4]][reg_addr[3:0]];


// pot feedback module
Ltc1864x4 adc_pot(
    .clk(clkadc),
    .reset(reset),
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
    .reset(reset),
    .Out1(curval[1]),
    .Out2(curval[2]),
    .Out3(curval[3]),
    .Out4(curval[4]),
    .sclk(sclk[2]),
    .conv(conv[2]),
    .miso(miso_cur)
);

// map the data lines to access them as memory: [channel #][device #]
// channel 1
assign mem_data[1][`OFF_ADC_DATA] = { potval[1], curval[1] };
// channel 2
assign mem_data[2][`OFF_ADC_DATA] = { potval[2], curval[2] };
// channel 3
assign mem_data[3][`OFF_ADC_DATA] = { potval[3], curval[3] };
// channel 4
assign mem_data[4][`OFF_ADC_DATA] = { potval[4], curval[4] };

// connect to cur value output
assign cur1 = curval[1];
assign cur2 = curval[2];
assign cur3 = curval[3];
assign cur4 = curval[4];

endmodule
