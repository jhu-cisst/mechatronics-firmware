/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2024 ERC CISST, Johns Hopkins University.
 *
 * This module implements a virtual Ethernet PHY.
 *
 * Revision history
 *     1/6/24      Peter Kazanzides    Initial Revision
*/


module VirtualPhy(

    output wire mdio_i,   // mdio_i to PS
    input  wire mdio_o,   // mdio_o from PS
    input  wire mdio_t,   // mdio_t from PS
    input  wire mdc,      // mdc (clock) from PS

    input  wire ctrl_wen,         // write to Ethernet control register
    input  wire link_on_mask,     // mask for setting link_on
    input  wire link_on_bit,      // value for setting link_on

    output reg  link_on,          // whether link is on

    // For debugging
    input  wire[15:0] reg_raddr,   // read address
    output wire[31:0] reg_rdata    // register read data
);

always @(posedge ctrl_wen)
begin
    if (link_on_mask) link_on <= link_on_bit;
end

// Default register values, obtained by reading RTL8211F when cable connnected and then simplifying.
// Changed PHYID1 and PHYID2 to use JHU LCSR CID (FA:61:0E), so that Linux will use
// Generic PHY driver rather than RealTek RTL8211F driver. The Xilinx standalone lwIP library
// will assume a Marvell PHY.
// PHYID2 also specifies a model number of 1 and a revision of 0.
wire [15:0] regValue[0:15];
assign regValue[0]  = 16'h1040;    // BMCR: 1GB link, auto-negotiation enabled
// BMSR: Xilinx standalone lwIP expects this register to at least contain 0x1808 when detecting
//       the PHY (these bits indicate 10Base-T and auto-negotation ability).
//       In addition, we specify 100Base-T (bits 14-13) and 1000Base-T extended status register (bit 8).
//       We use use link_on to specify both auto-negotiation complete (bit 5) and link status (bit 2).
assign regValue[1]  = { 8'h79, 2'b00, link_on, 1'b0,
                        1'b1, link_on, 2'b00 };
assign regValue[2]  = 16'h7e19;    // PHYID1 (JHU LCSR)
assign regValue[3]  = 16'hc010;    // PHYID2 (JHU LCSR)
assign regValue[4]  = 16'h0801;    // ANAR: asymmetric PAUSE, support IEEE 802.3
assign regValue[5]  = 16'h0c01;    // ANLPAR (Partner Ability): also supports PAUSE
assign regValue[6]  = 16'h0000;    // ANER
assign regValue[7]  = 16'h0000;    // ANNPTR
assign regValue[8]  = 16'h0000;    // ANNPRR
assign regValue[9]  = 16'h0200;    // GBCR: advertise 1GB full-duplex
assign regValue[10] = 16'h7c00;    // GBSR: PHY is MASTER
assign regValue[11] = 16'h0000;    // Reserved
assign regValue[12] = 16'h0000;    // Reserved
assign regValue[13] = 16'h0000;    // MACR
assign regValue[14] = 16'h0000;    // MAADR
assign regValue[15] = 16'h2000;    // GBESR: 1GB full-duplex capable

// State machine
localparam[1:0]
    ST_MDIO_IDLE = 2'd0,
    ST_MDIO_RECV_DATA = 2'd1,
    ST_MDIO_SAVE_DATA = 2'd2;

reg[1:0] mdioState;
initial mdioState = ST_MDIO_IDLE;

reg[4:0] cnt;         // 5-bit counter (0-31)

assign mdio_i = replyData[~cnt];

reg[31:0] mdio_data;  // save MDIO data

wire mdio_st_ok;      // ST bit pattern (01) detected
wire[1:0] mdio_rw;    // OP indicates Read (10) or Write (01)
wire[4:0] phyAddr;    // PHY address (1)
wire[4:0] regAddr;    // Register address
assign mdio_st_ok = (mdio_data[31:30] == 2'b01) ? 1'b1 : 1'b0;
assign mdio_rw = mdio_data[29:28];
assign phyAddr = mdio_data[27:23];
assign regAddr = mdio_data[22:18];

wire isRegStandard;    // 1 -> standard GMII register (0-15)
wire isRegNew;         // 1 -> not a standard GMII register (not yet supported)
assign isRegStandard = ((phyAddr == 1) && (~regAddr[4])) ? 1'b1 : 1'b0;
// Support register 17 (IEEE_SPECIFIC_STATUS_REG) because it is used by
// the Xilinx standalone lwIP library, which assumes a Marvell PHY for
// any unknown PHYID.
wire isReg17;          // 1 -> Register 17
assign isReg17 = ((phyAddr == 1) && (regAddr == 5'd17)) ? 1'b1 : 1'b0;
assign isRegNew = ((phyAddr == 1) && regAddr[4] && !isReg17) ? 1'b1 : 1'b0;
reg[4:0] regNew;       // Register not yet supported (for debugging)

// Data to write to host via mdio_i.
// Note that this data should only be used for the last 17 or 18 bits during
// an MDIO register read, where bits 17:16 correspond to the turnaround time (TA)
// and bits 15:0 correspond to the register data. It should not hurt to write
// it all the time, since the tri-state control from the host (mdio_t) should
// prevent it from interfering during a register write.
wire[31:0] replyData;
assign replyData[31:16] = 16'd0;
assign replyData[15:0] = isRegStandard ? regValue[regAddr[3:0]] :
                         (isReg17 & link_on) ? 16'hac00 :   // 1GB, full-duplex, link_on
                         16'd0;    // Unknown register (see regNew)

reg doRead;           // 1 -> read from mdio_i (more reliable than checking mdio_t)

wire isRead;
wire isWrite;
assign isRead = (mdio_rw == 2'b10) ? 1'b1 : 1'b0;
assign isWrite = (mdio_rw == 2'b01) ? 1'b1 : 1'b0;

// Debug address space: 43a0-43af and 43b0-43bf
//    (43a0-43ae not used)
reg[31:0] DebugData[0:15];
reg[3:0] debugCnt;

reg[3:0] preamble_err_cnt;

assign reg_rdata = (reg_raddr[7:4] == 4'hb) ? DebugData[reg_raddr[3:0]] :
                   (reg_raddr[7:0] == 8'haf) ? { 3'd0, regNew,
                                                 3'd0, phyAddr,
                                                 3'd0, regAddr,
                                                 preamble_err_cnt, 1'b0, mdio_st_ok, mdio_rw } :
                   32'd0;

always @(posedge mdc)
begin

    case (mdioState)

    ST_MDIO_IDLE:
        begin
            doRead <= 1'b0;
            if (mdio_t) begin
                cnt <= 5'd0;
            end
            else if (mdio_o) begin
                // Look for preamble (32 consecutive 1s)
                cnt <= cnt + 5'd1;
                if (cnt == 5'd31)
                    mdioState <= ST_MDIO_RECV_DATA;
            end
            else begin
                preamble_err_cnt <= preamble_err_cnt + 4'd1;
                cnt <= 5'd0;
            end
        end

    ST_MDIO_RECV_DATA:
        begin
            cnt <= cnt + 5'd1;
            mdio_data[~cnt] <= doRead ? mdio_i : mdio_o;

            if (cnt == 5'd15)
                doRead <= isRead;
            else if (cnt == 5'd31)
                mdioState <= ST_MDIO_SAVE_DATA;
        end

    ST_MDIO_SAVE_DATA:
        begin
            // For debugging
            DebugData[debugCnt] <= mdio_data;
            debugCnt <= debugCnt + 4'd1;
            if (isRegNew) begin
                regNew <= regAddr;        // Need to handle this register
            end
            mdioState <= ST_MDIO_IDLE;
        end

    default:
        // Could note this as an error
        mdioState <= ST_MDIO_IDLE;

    endcase

end

endmodule
