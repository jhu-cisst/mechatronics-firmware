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

    // For debugging
    input  wire[15:0] reg_raddr,   // read address
    output wire[31:0] reg_rdata    // register read data
);

// Default register values (obtained by reading RTL8211F when cable connnected)
wire [15:0] regValue[0:15];
assign regValue[0]  = 16'h1040;    // BMCR: 1GB link
assign regValue[1]  = 16'h79ad;    // BMSR: AN complete, link on
assign regValue[2]  = 16'h001c;    // PHYID1 (RTL8211F)
assign regValue[3]  = 16'hc916;    // PHYID2 (RTL8211F)
assign regValue[4]  = 16'h09e1;    // ANAR
assign regValue[5]  = 16'hcde1;    // ANLPAR
assign regValue[6]  = 16'h006f;    // ANER
assign regValue[7]  = 16'h2801;    // ANNPTR
assign regValue[8]  = 16'h6001;    // ANNPRR
assign regValue[9]  = 16'h0200;    // GBCR: advertise 1GB full-duplex
assign regValue[10] = 16'h7c00;    // GBSR
assign regValue[11] = 16'h0000;    //
assign regValue[12] = 16'h0000;    //
assign regValue[13] = 16'h0000;    // MACR
assign regValue[14] = 16'h0000;    // MAADR
assign regValue[15] = 16'h2000;    // GBESR: 1GB full-duplex capable

reg[15:0] replyData;
assign mdio_i = replyData[15];

// State machine (only 3 for now, but more expected)
localparam[2:0]
    ST_MDIO_IDLE = 3'd0,
    ST_MDIO_RECV_DATA = 3'd1,
    ST_MDIO_SAVE_DATA = 3'd2;

reg[2:0] mdioState;
initial mdioState = ST_MDIO_IDLE;

reg[4:0] cnt;         // 5-bit counter (0-31)

reg[31:0] mdio_data;  // save MDIO data

reg mdio_st_ok;       // ST bit pattern (01) detected
reg[1:0] mdio_rw;     // OP indicates Read (10) or Write (01)
reg[4:0] phyAddr;     // PHY address (1 or 8)
reg[4:0] regAddr;     // Register address
reg[4:0] regNew;      // Register not yet supported (for debugging)
reg doRead;           // 1 -> read from mdio_i (more reliable than checking mdio_t)

wire isRead;
wire isWrite;
assign isRead = (mdio_rw == 2'b10) ? 1'b1 : 1'b0;
assign isWrite = (mdio_rw == 2'b01) ? 1'b1 : 1'b0;

// Debug address space: 4xb0-4xbf
reg[31:0] DebugData[0:15];
reg[3:0]  debug_cnt;  // 4-bit counter (0-15)

reg[3:0] preamble_err_cnt;

reg[15:0] regWriteMask;
reg[15:0] regReadMask;

assign reg_rdata = (reg_raddr[7:4] == 4'hb) ? DebugData[reg_raddr[3:0]] :
                   (reg_raddr[7:0] == 8'hae) ? { regWriteMask, regReadMask } :
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
            replyData <= 16'd0;   // MSB drives mdio_i
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
            replyData <= { replyData[14:0], 1'b0 };  // Drives mdio_i
            mdio_data <= { mdio_data[30:0], (doRead ? mdio_i : mdio_o) };

            case (cnt)

              5'd2:   // First 2 bits (ST) should be 01
                  mdio_st_ok <= (mdio_data[1:0] == 2'b01) ? 1'b1 : 1'b0;

              5'd4:   // Next 2 bits (OP) indicate Read (10) or Write (01)
                  mdio_rw <= mdio_data[1:0];

              5'd9:
                  phyAddr <= mdio_data[4:0];

              5'd14:
                  regAddr <= mdio_data[4:0];

              5'd15:
                  begin
                      // Set replyData for read (note that it will be ignored if
                      // the current command is a write)
                      doRead <= isRead;
                      if (phyAddr == 1) begin           // Physical PHY
                          if (regAddr[4] == 0) begin    // Standard register 0-15
                              replyData <= regValue[regAddr[3:0]];
                              // For debugging
                              if (isRead)
                                  regReadMask[regAddr[3:0]] <= 1'b1;
                              else if (isWrite)
                                  regWriteMask[regAddr[3:0]] <= 1'b1;
                          end
                          else begin
                              regNew <= regAddr;        // Need to handle this register
                          end
                      end
                      else if (phyAddr == 8) begin      // gmii-to-rgmii PHY
                          replyData <= 16'h0040;        //   - 1GB link (regAddr==16)
                      end
                  end

              5'd31:
                  mdioState <= ST_MDIO_SAVE_DATA;
            endcase

        end

    ST_MDIO_SAVE_DATA:
        begin
           if ((phyAddr != 8) && (regAddr != 0) && (regAddr != 1)) begin
               DebugData[debug_cnt] <= mdio_data;
               debug_cnt <= debug_cnt + 4'd1;
           end
           mdioState <= ST_MDIO_IDLE;
        end

    endcase

end

endmodule
