/*******************************************************************************
 *
 * Copyright(C) 2008-2011 ERC CISST, Johns Hopkins University.
 *
 * Simple parameterized clock dividers that output a clock of frequency
 *     f_clkout = f_clkin / 2^width, or
 *     f_clkout = f_clkin / div
 *
 * Parameter 'width' is the bitwidth of the counter, and clkout is the MSB.
 * Parameter 'div' is the divisor, and clkout changes every div/2-1 clkins.
 *
 * Revision history
 *     05/20/08    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Added second divider
 */

// -----------------------------------------------------------------------------
// simple power-of-2 divider
//
module ClkDiv(clkin, clkout);

    input wire clkin;          // input clock to derive from
    output reg clkout;         // divided down output clock
    reg[width-1:0] counter;    // counter for clock divider
    parameter width = 4;       // adjustable width parameter

// free running counter
always @(posedge(clkin))
begin
    counter <= counter + 1'b1;
    clkout <= counter[width-1];
end

endmodule

// -----------------------------------------------------------------------------
// alternate clock divider (not just powers of 2)
//
module ClkDivI(clkin, clkout);

    input wire clkin;              // input clock to derive from
    output reg clkout;             // divided down output clock
    reg[clogb2(div):0] counter;    // counter for clock divider
    parameter div = 100;           // adjustable divisor parameter

// counter from 0 to (div/2)-1, each interval creates half a clkout
always @(posedge(clkin))
begin
    if (counter == (div>>1)-1'b1) begin
        clkout <= ~clkout;
        counter <= 0;
    end
    else
        counter <= counter + 1'b1;
end

// function to get bitwidth of input, via "ceil(log_2(x))"
function integer clogb2;
    input[31:0] x;
    integer i;
    begin
        i = x;
        for (clogb2=0; i>0; clogb2=clogb2+1)
            i = i >> 1;
    end
endfunction

endmodule
