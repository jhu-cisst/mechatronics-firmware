/*******************************************************************************
 *
 * Copyright(C) 2011-2012 ERC CISST, Johns Hopkins University.
 *
 * Module: LTC1864x4
 *
 * Purpose: Reads data from a group of 4 LTC2601 set up with common
 *          conv & sclk inputs and providing 4 discrete data outputs.
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
 */

`define CLKIN_PERIOD 80       // approximate input clock period (sysclk/4 ns)

module Ltc1864x4(
    input clk,                // input clock (<20 MHz, >50 ns)
    input reset,              // global reset signal
    output reg[15:0] Out1,    // ADC values captured from the four channels
    output reg[15:0] Out2,
    output reg[15:0] Out3,
    output reg[15:0] Out4,
    output reg sclk,          // sclk signal to all the ADCs
    output reg conv,          // conv signal to all the ADCs
    input wire[3:0] miso      // miso inputs from the ADC
);

    reg[6:0] seqn;            // Master sequence counter
    reg[15:0] Dat1, Dat2;     // Running shift registers for the 4 channels
    reg[15:0] Dat3, Dat4;
    initial seqn = 0;

always @(posedge(clk) or negedge(reset))
begin
    if (reset == 0) begin
        seqn <= 0;
        conv <= 1'b1;
        sclk <= 1'b1;
    end

    else begin
        seqn <= (seqn<7'h67) ? (seqn+1'b1) : 1'b0;
        conv <= (seqn<7'h22) ? 1'b0 : 1'b1;
        sclk <= ((seqn>7'h00)&&(seqn<7'h23)) ? seqn[0] : 1'b1;

        // Continuously capture incoming data on every alternating input sequence
        if (~seqn[0]) begin
            Dat1 <= { Dat1[14:0], miso[0] };
            Dat2 <= { Dat2[14:0], miso[1] };
            Dat3 <= { Dat3[14:0], miso[2] };
            Dat4 <= { Dat4[14:0], miso[3] };
        end

        // Capture data from shift registers right after last bit shifted in
        if (seqn == 7'h23) begin
            Out1 <= Dat1;
            Out2 <= Dat2;
            Out3 <= Dat3;
            Out4 <= Dat4;
        end
    end
end

endmodule
