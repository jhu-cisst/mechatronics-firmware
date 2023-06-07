/*******************************************************************************
 *
 * Copyright(C) 2008-2011 ERC CISST, Johns Hopkins University.
 * 
 * Moves a pulse from one clock domain to another.
 */

// -----------------------------------------------------------------------------

module cdc_pulse(
    input clk_a,
    input data_a,
    input clk_b,
    output data_b
);

reg toggle_a = 0;
reg [2:0] sync_b = 0;

always @(posedge clk_a) toggle_a <= toggle_a ^ data_a;
always @(posedge clk_b) sync_b <= {sync_b[1:0], toggle_a};
assign data_b = (sync_b[2] ^ sync_b[1]);
endmodule
