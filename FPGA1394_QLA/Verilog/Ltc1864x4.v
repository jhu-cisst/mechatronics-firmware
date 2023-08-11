/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2022 ERC CISST, Johns Hopkins University.
 *
 * Module: LTC1864x4
 *
 * Purpose: Reads data from a group of 4 LTC2601 set up with common
 *          conv & sclk inputs and providing 4 discrete data outputs.
 *          The common conv & sclk are handled by a separate module
 *          (LTC1864SPI) to allow more common channels.
 *
 * Theory of operation:
 *     Conversion is initiated by taking the conv line high for at least
 *     4.66 us, followed by taking conv low and clocking out the 16-bit
 *     data. Data is sampled by the Sample & Hold while conv is low.
 *     The value is latched at the rising edge of conv and the data
 *     is converted over the next 4.66 us. During this time the clock
 *     is supposed to be static.
 *
 *     The above is implemented by having a free running counter that
 *     counts from 0 to 0x67 and then rolls over. The conv signal is
 *     low for the first 0x22 counts and high for the remaining 0x46.
 *
 *     sclk is high by default. After providing a setup time for conv
 *     sclk pulses low for a clock following counts 2 4 6......0x22,
 *     resulting in 16 pulses.
 *
 *     The incoming data is continuously shifted into 4 shift registers
 *     on every other count.
 *
 *     On the 0x23 count, the value of the shift registers is latched
 *     as the latest A2D value for the respective channel.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     11/14/11    Paul Thienphrapa    Initial revision
 *     12/17/22    Peter Kazanzides    Move sclk/conv code to Ltc1864SPI
 */

module Ltc1864SPI(
    input clk,                // input clock (<20 MHz, >50 ns)
    output reg sclk,          // sclk signal to all the ADCs
    output reg conv,          // conv signal to all the ADCs
    output reg OutReady,      // 1 -> New ADC values available
    output wire latch_bit,    // bit is ready on MISO
    output wire latch_word    // entire word can be latched
);

    initial conv = 1'b1;
    initial sclk = 1'b1;

    reg[6:0] seqn;            // Master sequence counter
    initial seqn = 0;

    assign latch_bit = ~seqn[0];
    assign latch_word = (seqn == 7'h23) ? 1'b1 : 1'b0;

always @(posedge(clk))
begin
    seqn <= (seqn<7'h67) ? (seqn+1'b1) : 1'b0;
    conv <= (seqn<7'h22) ? 1'b0 : 1'b1;
    sclk <= ((seqn>7'h00)&&(seqn<7'h23)) ? seqn[0] : 1'b1;
    if (latch_bit) OutReady <= 1'b0;
    if (latch_word) OutReady <= 1'b1;
end

endmodule

// Sample 4 ADCs. Since the common SPI sclk and conv signals have been moved
// to a separate module, this could now be implemented as a generate block to
// sample any number of channels. But, currently, it is only necessary to
// sample in multiples of 4 (e.g., 4 for QLA and 8 for DQLA).

module Ltc1864x4(
    input clk,                // input clock (<20 MHz, >50 ns)
    output reg[15:0] Out1,    // ADC values captured from the four channels
    output reg[15:0] Out2,
    output reg[15:0] Out3,
    output reg[15:0] Out4,
    input wire latch_bit,     // 1 -> sample the bit from miso
    input wire latch_word,    // 1 -> latch the 16-bit word
    input wire[3:0] miso      // miso inputs from the ADC
);

    reg[15:0] Dat1, Dat2;     // Running shift registers for the 4 channels
    reg[15:0] Dat3, Dat4;

always @(posedge(clk))
begin
    // Continuously capture incoming data on every alternating input sequence
    if (latch_bit) begin
        Dat1 <= { Dat1[14:0], miso[0] };
        Dat2 <= { Dat2[14:0], miso[1] };
        Dat3 <= { Dat3[14:0], miso[2] };
        Dat4 <= { Dat4[14:0], miso[3] };
    end

    // Capture data from shift registers right after last bit shifted in
    if (latch_word) begin
        Out1 <= Dat1;
        Out2 <= Dat2;
        Out3 <= Dat3;
        Out4 <= Dat4;
    end
end

endmodule
