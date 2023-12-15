/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 Johns Hopkins University.
 *
 * This module performs address translation for the write address to support the
 * the real-time block write.
 *
 * Starting with Rev 8, the first entry is a header that specifies which board is being
 * addressed. If this is a sequential block write, it addresses this board and we rely
 * on the host PC to send a Rev 8 packet. Similarly, if a broadcast write (to multiple
 * boards), we can assume that the host PC will only use broadcast write if all boards
 * are Rev 8+. The header will also specify the number of motors being addressed (4 for
 * QLA, 8 for DQLA and 10 for dRAC). The last quadlet is for power control.
 * The protocol uses 8 bits for the length (RtLen), even though currently the largest
 * block write is 12 quadlets (for dRAC).
 *
 * Revision history
 *     12/14/23    Peter Kazanzides    Initial revision
 */

module WriteAddressTranslation
(

    input            sysclk,
    input  wire[7:0] reg_waddr_in,   // reg_waddr from host (Firewire, Ethernet, or EMIO)
    input  wire      reg_wen_in,     // reg_wen from host
    output wire[7:0] reg_waddr_out,  // reg_waddr to FPGA registers
    output wire      reg_wen_out,    // reg_wen to FPGA registers
    input  wire      blk_rt_wr,      // 1 -> real-time block write
    input  wire[7:0] reg_wdata_lsb,  // lsb of reg_wdata (block length in header quadlet)
    input  wire      board_equal     // whether board_id matched reg_wdata[11:8]
);

reg blk_rt_wr_prev;       // For finding rising edge of blk_rt_wr
reg[7:0] RtStart;         // Starting address of current RT write block
reg[7:0] RtLen;           // Number of quadlets in current RT write block
reg isLocal;              // Whether this data block is for the current board

wire isThisHeader;        // Whether current real-time header quadlet
wire isNextHeader;        // Whether next real-time header quadlet
wire isHeader;
wire isPowerCtrl;         // Whether power control quadlet

assign isThisHeader = (reg_waddr_in == RtStart) ? 1'b1 : 1'b0;
assign isNextHeader = (reg_waddr_in == RtStart+RtLen) ? 1'b1 : 1'b0;
assign isHead = isThisHeader | isNextHeader;
assign isPowerCtrl = (reg_waddr_in == RtStart+RtLen-8'd1) ? 1'b1 : 1'b0;

always @(posedge sysclk)
begin
    blk_rt_wr_prev <= blk_rt_wr;
    if (blk_rt_wr & (~blk_rt_wr_prev)) begin
        RtStart <= 8'd0;
        RtLen <= 8'd0;
    end
    else if (reg_wen_in & isHeader) begin
        RtStart <= reg_waddr_in;
        RtLen <= reg_wdata_lsb;
        isLocal <= board_equal;
    end
end

// DAC channel number (1..N), where N < 16
wire[7:0] channel;
assign channel = reg_waddr_in - RtStart;

// Set reg_waddr_out to:
//    reg_waddr_in           if not a local block write
//    REG_FVERSION           if header (ignored: reg_wen=0 and REG_FVERSION not writeable)
//    { 4'd0, REG_STATUS }   if power control quadlet
//    { CH, OFF_DAC_CTRL }   otherwise, where CH is channel number
assign reg_waddr_out = (~blk_rt_wr) ? reg_waddr_in :
                       isHeader     ? { 4'd0, `REG_FVERSION } :  // Ignored
                       isPowerCtrl  ? { 4'd0, `REG_STATUS } :
                       { channel[3:0], `OFF_DAC_CTRL };

// Set reg_wen_out to:
//    0            if real-time block write and is header quadlet or is not local
//    reg_wen_in   otherwise
assign reg_wen_out = (blk_rt_wr & (isHeader | (~isLocal))) ? 1'b0 : reg_wen_in;

endmodule
