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
(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg sync_b_0 = 0;
(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg sync_b_1 = 0;
(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg sync_b_2 = 0;

always @(posedge clk_a) toggle_a <= toggle_a ^ data_a;
always @(posedge clk_b) begin
    sync_b_0 <= toggle_a;
    sync_b_1 <= sync_b_0;
    sync_b_2 <= sync_b_1;
end
assign data_b = (sync_b_2 ^ sync_b_1);
endmodule
