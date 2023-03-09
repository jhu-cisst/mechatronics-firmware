`include "Constants.v"

// This module does not actually sample the feedback data (except for the timestamp), but
// rather performs address translation so that the correct data is provided during the read.
// For compatibility, we set isBusy so that the caller clears doSample.
// Also, we clear the timestamp when isBusy is set, which should replicate the previous
// implementation (in SampleData.v).

module SampleDataAddressTranslation(
    input wire        clk,         // system clock
    input wire        doSample,    // signal to trigger sampling
    output reg        isBusy,      // 1 -> busy sampling
    input wire[5:0]   blk_addr,    // Address for accessing RT_Feedback
    output wire[31:0] blk_data,
    output reg[31:0]  reg_raddr,
    input [31:0]      reg_rdata,
    output reg[31:0]  timestamp    // timestamp counter register
    );

always @(*) begin
    case (blk_addr)
        `include "case_rt_read_addr_to_main_addr.v"
    endcase
end

reg[31:0] timestamp_latched;
assign blk_data = (blk_addr == 6'd0) ? timestamp_latched : reg_rdata;

always @(posedge clk) begin
    isBusy <= doSample;
    if (isBusy) begin
        // doSample is only asserted for one clock cycle due to gating in
        // higher-level module (essentially, doSample = sample_start & ~isBusy)
        timestamp_latched <= timestamp;
        timestamp <= 32'd0;
    end
    else begin
        timestamp <= timestamp + 1'b1;
    end
end
endmodule

