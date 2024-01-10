/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2024 Johns Hopkins University.
 *
 * Module: EthSwitch
 *
 * Purpose: Ethernet switch for FPGA V3
 *
 * This module implements a 4-port Ethernet switch, where Ports 0-2 are 8-bit
 * ports and Port 3 is a 16-bit (word) port. This adds a little complexity
 * to the implementation, but is done for efficiency, since it is faster for
 * the Ethernet RxClk (125 MHz clock at 1GB) to assemble bytes into words
 * than it is for EthernetIO (49.152 MHz clock) to do it.
 *
 * It would be even more efficient to make Port 3 a 32-bit port, but that would
 * require extensive changes to EthernetIO.v.
 *
 * Revision history
 *     1/9/24      Peter Kazanzides    Initial revision
 */

module EthSwitch
(
    input wire P0_RxClk,        // Port0 receive clock
    input wire P0_RxValid,      // Port0 receive data valid
    input wire[7:0] P0_RxD,     // Port0 receive data
    input wire[1:0] P0_RxSt,    // Port0 receive status [last, first]

    input wire P0_TxClk,        // Port0 transmit clock
    input wire P0_TxReady,      // Port0 client ready for data
    output wire[7:0] P0_TxD,    // Port0 transmit data
    output wire[1:0] P0_TxSt,   // Port0 transmit status [last, first]

    input wire P1_RxClk,        // Port1 receive clock
    input wire P1_RxValid,      // Port1 receive data valid
    input wire[7:0] P1_RxD,     // Port1 receive data
    input wire[1:0] P1_RxSt,    // Port1 receive status [last, first]

    input wire P1_TxClk,        // Port1 transmit clock
    input wire P1_TxReady,      // Port1 client ready for data
    output wire[7:0] P1_TxD,    // Port1 transmit data
    output wire[1:0] P1_TxSt,   // Port1 transmit status [last, first]

    input wire P2_RxClk,        // Port2 receive clock
    input wire P2_RxValid,      // Port2 receive data valid
    input wire[7:0] P2_RxD,     // Port2 receive data
    input wire[1:0] P2_RxSt,    // Port2 receive status [last, first]

    input wire P2_TxClk,        // Port2 transmit clock
    input wire P2_TxReady,      // Port2 client ready for data
    output wire[7:0] P2_TxD,    // Port2 transmit data
    output wire[1:0] P2_TxSt,   // Port2 transmit status [last, first]

    input wire P3_RxClk,        // Port3 receive clock
    input wire P3_RxValid,      // Port3 receive data valid
    input wire[15:0] P3_RxD,    // Port3 receive data
    input wire[1:0] P3_RxSt,    // Port3 receive status [last, first]

    input wire P3_TxClk,        // Port3 transmit clock
    input wire P3_TxReady,      // Port3 client ready for data
    output wire[15:0] P3_TxD,   // Port3 transmit data
    output wire[1:0] P3_TxSt    // Port3 transmit status [last, first]
);

// Create arrays from input parameters
wire RxClk[0:3];
assign RxClk[0] = P0_RxClk;
assign RxClk[1] = P1_RxClk;
assign RxClk[2] = P2_RxClk;
assign RxClk[3] = P3_RxClk;

wire RxValid[0:3];
assign RxValid[0] = P0_RxValid;
assign RxValid[1] = P1_RxValid;
assign RxValid[2] = P2_RxValid;
assign RxValid[3] = P3_RxValid;

wire[7:0] RxD[0:2];
assign RxD[0] = P0_RxD;
assign RxD[1] = P1_RxD;
assign RxD[2] = P2_RxD;
// RxD[3] is 16-bits

wire[7:0] RxSt[0:3];
assign RxSt[0] = P0_RxSt;
assign RxSt[1] = P1_RxSt;
assign RxSt[2] = P2_RxSt;
assign RxSt[3] = P3_RxSt;

wire TxClk[0:3];
assign TxClk[0] = P0_TxClk;
assign TxClk[1] = P1_TxClk;
assign TxClk[2] = P2_TxClk;
assign TxClk[3] = P3_TxClk;

wire TxReady[0:3];
assign TxReady[0] = P0_TxReady;
assign TxReady[1] = P1_TxReady;
assign TxReady[2] = P2_TxReady;
assign TxReady[3] = P3_TxReady;

wire[7:0] TxD[0:2];
assign TxD[0] = P0_TxD;
assign TxD[1] = P1_TxD;
assign TxD[2] = P2_TxD;
// TxD[3] is 16-bits

wire[7:0] TxSt[0:3];
assign TxSt[0] = P0_TxSt;
assign TxSt[1] = P1_TxSt;
assign TxSt[2] = P2_TxSt;
assign TxSt[3] = P3_TxSt;

// Convention: signal[in][out]
wire fifo_reset[0:3][0:3];
wire fifo_full[0:3][0:3];
wire fifo_empty[0:3][0:3];

wire[7:0] RxD_Int[0:2];    // RxD output of internal Rx FIFO (3 bytes long)
reg[15:0] RxD_Int3;        // RxD output of internal Rx FIFO (1 quadlet long)
wire[1:0] RxSt_Int[0:3];   // RxSt output of internal Rx FIFO (3 bytes long)
wire Fifo_Int_valid[0:3];  // Whether internal Rx FIFO has valid data

reg[1:0] TxInput[0:3];       // Index of current (or most recent) active input port
reg FifoActive[0:3][0:3];    // Whether the switch FIFO is active

reg [7:0] TxD_Switch[0:3][0:2];   // 8-bit switch output
reg[15:0] TxD3_Switch[0:2];       // 16-bit switch output

reg[1:0] TxSt_Switch[0:3];

// Variables for generate block
genvar in;
genvar out;

generate

for (in = 0; in < 4; in = in + 1) begin : fifo__int_loop

  reg[1:0] RxCnt;        // Counts first 3 bytes
  reg DestMacValid;
  reg[23:0] DestMacReg;
  wire[7:0] DestMacLsb;
  wire[23:0] DestMac;       // TODO -- use this
  assign DestMac = DestMacValid ? DestMacReg : {DestMacReg[23:8], DestMacLsb};
  // TODO: use SrcMac for Forwarding Database

  if (in != 3) begin

      // Ports 0-2 are 8-bits, so the internal FIFO has 2 bytes and allows us to
      // look at the first 3 bytes (destination MAC address) before deciding whether
      // to forward to the output port.
      reg[7:0] RxD_Fifo[0:1];
      reg[1:0] RxSt_Fifo[0:1];
      reg      Valid_Fifo[0:1];

      assign RxD_Int[in] = RxD_Fifo[1];
      assign RxSt_Int[in] = RxSt_Fifo[1];
      assign Fifo_Int_valid[in] = Valid_Fifo[1];

      assign DestMacLsb = RxD[in];

      always @(posedge RxClk[in])
      begin
          RxD_Fifo[0] <= RxD[in];
          RxD_Fifo[1] <= RxD_Fifo[0];
          RxSt_Fifo[0] <= RxSt[in];
          RxSt_Fifo[1] <= RxSt_Fifo[0];
          Valid_Fifo[0] <= RxValid[in];
          Valid_Fifo[1] <= Valid_Fifo[0];
          if (RxValid[in]) begin
              if (RxSt[in] == 2'b01) begin
                  // First byte of packet
                  RxCnt <= 2'd1;
                  DestMacReg[23:16] <= RxD[in];
              end
              else if (RxSt[in] == 2'b10) begin
                  // Last byte of packet
                  RxCnt <= 2'd0;
              end
              else if (RxCnt == 2'd1) begin
                  DestMacReg[15:8] <= RxD[in];
                  RxCnt <= 2'd2;
              end
              else if (RxCnt == 2'd2) begin
                  DestMacReg[7:0] <= DestMacLsb;
                  DestMacValid <= 1'b1;
                  RxCnt <= 2'd3;
              end
          end
          else begin
              DestMacValid <= 1'b0;
          end
      end
  end
  else begin  // port3
      // Port 3 is 16-bits, so we only need a 1-word FIFO, which
      // is implemented below (RxD_Int3 declared above)
      reg[1:0] RxSt_Fifo;
      reg Valid_Fifo;

      assign RxSt_Int[3] = RxSt_Fifo;
      assign Fifo_Int_valid[3] = Valid_Fifo;

      assign DestMacLsb = P3_RxD[15:8];

      always @(posedge RxClk[3])
      begin
          RxD_Int3 <= P3_RxD;
          RxSt_Fifo <= RxSt[3];
          Valid_Fifo <= RxValid[3];
          if (RxValid[3]) begin
              if (RxSt[3] == 2'b01) begin
                  // First word of packet
                  RxCnt <= 2'd2;
                  DestMacReg[23:8] <= P3_RxD;
              end
              else if (RxSt[in] == 2'b10) begin
                  // Last word of packet
                  RxCnt <= 2'd0;
              end
              else if (RxCnt == 2'd2) begin
                  DestMacReg[7:0] <= DestMacLsb;
                  DestMacValid <= 1'b1;
                  RxCnt <= 2'd3;
              end
          end
          else begin
              DestMacValid <= 1'b0;
          end
      end

  end
end

for (in = 0; in < 4; in = in+1) begin : fifo_loop_in
  for (out = in+1; out < in+4; out = out+1) begin : fifo_loop_out

        //********* Port in (Rx) to Port out (Tx) *****************

        wire RxFwd;         // Whether to forward packet from port "in" to port "out"
        // TODO: Add forwarding database (for now, just floods all ports)
        assign RxFwd = Fifo_Int_valid[in];

        if (in == 3) begin
            // Input is 16-bits, output is 8-bits (+2 status)
            wire[3:0] TxSt_Temp;
            assign TxSt_Temp[in] = (TxSt[in] == 2'b01) ? 4'b0001 :
                                   (TxSt[in] == 2'b10) ? 4'b1000 :
                                   (TxSt[in] == 2'b11) ? 4'b1111 :
                                   4'b0000;
            fifo_20x4096_10 Fifo(
                .rst(fifo_reset[in][out%4]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din({RxSt_Temp[3:2], RxD_Int3[15:8], RxSt_Temp[1:0], RxDInt3[7:0]}),
                .rd_clk(TxClk[out%4]),
                .rd_en(FifoActive[in][out%4] & TxReady[out%4]),
                .dout(TxD_Switch[in][out%4]}),
                .full(fifo_full[in][out%4]),
                .empty(fifo_empty[in][out%4])
            );
        end
        else if (out == 3) begin
            // Input is 8-bits, output is 16-bits (+2 status)
            wire[3:0] TxSt_Temp;
            fifo_10x8192_20 Fifo(
                .rst(fifo_reset[in][out]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din({RxSt_Int[in], RxD_Int[in]}),
                .rd_clk(TxClk[out]),
                .rd_en(FifoActive[in][out] & TxReady[out]),
                .dout({TxSt_Temp[3:2], TxD3_Switch[in][15:8], TxSt_Temp[1:0], TxD3_Switch[in][7:0]}),
                .full(fifo_full[in][out%4]),
                .empty(fifo_empty[in][out%4])
            );
            assign TxSt[in][3] = TxSt_Temp[3:2] | TxSt_Temp[1:0];
        end
        else begin
            // Input and output are both 8-bits (+2 for Status)
            fifo_10x8192 Fifo(
                .rst(fifo_reset[in][out%4]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din({RxSt_Int[in], RxD_Int[in]}),
                .rd_clk(TxClk[out%4]),
                .rd_en(FifoActive[in][out%4] & TxReady[out%4]),
                .dout({TxSt_Switch[in][out%4], TxD_Switch[in][out%4]}),
                .full(fifo_full[in][out%4]),
                .empty(fifo_empty[in][out%4])
            );
        end

  end
end

for (out = 0; out < 4; out = out + 1) begin : fifo_loop_mux

    wire curInput;
    assign curInput = TxInput[out];

    // A simple round-robin scheduler
    always @(posedge TxClk[out])
    begin
        if (FifoActive[curInput][out]) begin
            if (fifo_empty[curInput][out] || (TxSt_Switch[curInput][out] == 2'b10)) begin
                // If last byte (or fifo_empty, which should not happen)
                FifoActive[curInput][out] <= 1'b0;
            end
        end
        else if (~fifo_empty[(out+1)%4][out]) begin
            TxInput[out] <= (out+1)%4;
            FifoActive[(out+1)%4][out] <= 1'b1;
        end
        else if (~fifo_empty[(out+2)%4][out]) begin
            TxInput[out] <= (out+2)%4;
            FifoActive[(out+2)%4][out] <= 1'b1;
        end
    end

    assign TxSt[out] = TxSt_Switch[curInput][out];
    if (out != 3) begin
        assign TxD[out] = TxD_Switch[curInput][out];
    end
    else begin
        assign P3_TxD = TxD3_Switch[curInput];
    end
end

endgenerate

endmodule
