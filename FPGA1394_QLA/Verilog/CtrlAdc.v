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

// device register file offsets from channel base
`define OFF_ADC_DATA 4'd0          // adc data register offset
`define OFF_DAC_CTRL 4'd1          // dac control register offset
`define OFF_POT_CTRL 4'd2          // pot control register offset
`define OFF_POT_DATA 4'd3          // pot data register offset
`define OFF_ENC_LOAD 4'd4          // enc data preload offset
`define OFF_ENC_DATA 4'd5          // enc quadrature register offset
`define OFF_PER_DATA 4'd6          // enc period register offset
`define OFF_FREQ_DATA 4'd7         // enc frequency register offset
`define OFF_ACC1_DATA 4'd8         // enc acc1 register offset
`define OFF_ACC2_DATA 4'd9         // enc acc2 register offset 
`define OFF_SCUR_DATA 4'd10        // enc sync motor cur offset 


module CtrlAdc(
    clkadc, clk_slow, reset,
    sclk, conv, miso,
    reg_addr, reg_rdata
);

    // define I/Os
    input clkadc, clk_slow, reset; // adc clock and global reset signals
    output[1:2] sclk;              // sclk signal to each set of adcs
    output[1:2] conv;              // conv signal to each set of adcs
    input[1:4] miso[1:2];          // data lines from each individual adc
    input[7:0] reg_addr;           // register file addr from outside world
    output[31:0] reg_rdata;        // outgoing register file data

    // local wires
    wire[31:0] reg_rdata;          // outgoing register file data
    wire[15:0] potval[0:15];       // 4 channels of analog pot values
    wire[15:0] curval[0:15];       // 4 channels of current feedback values

    // for array-style access to the adc data
    wire[31:0] mem_data[0:15][0:15];
    reg[15:0] scur_data[0:15];

//------------------------------------------------------------------------------
// hardware description
//

/*
// concatenate pot and cur data from the desired channel for output
assign reg_rdata = { potval[reg_addr[6:4]], curval[reg_addr[6:4]] };
*/


// output selected read register
assign reg_rdata = mem_data[reg_addr[7:4]][reg_addr[3:0]];


// latch cur using slow clk
always @(posedge clk_slow or negedge reset)
begin
    if (reset == 0) begin
        scur_data[1] <= 0;
        scur_data[2] <= 0;
        scur_data[3] <= 0;
        scur_data[4] <= 0;
        end
    else begin
        scur_data[1] <= curval[1];
        scur_data[2] <= curval[2];
        scur_data[3] <= curval[3];
        scur_data[4] <= curval[4];
        end
end


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
    .miso(miso[1])
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
    .miso(miso[2])
);

// map the data lines to access them as memory: [channel #][device #]
// channel 1
assign mem_data[1][`OFF_ADC_DATA] = { potval[1], curval[1] };
assign mem_data[1][`OFF_SCUR_DATA] = scur_data[1];
// channel 2
assign mem_data[2][`OFF_ADC_DATA] = { potval[2], curval[2] };
assign mem_data[2][`OFF_SCUR_DATA] = scur_data[2];
// channel 3
assign mem_data[3][`OFF_ADC_DATA] = { potval[3], curval[3] };
assign mem_data[3][`OFF_SCUR_DATA] = scur_data[3];
// channel 4
assign mem_data[4][`OFF_ADC_DATA] = { potval[4], curval[4] };
assign mem_data[4][`OFF_SCUR_DATA] = scur_data[4];

endmodule
