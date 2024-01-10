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
 * This module implements a 4-port Ethernet switch, where each port has 8 bits
 * of data and 2 bits of status.
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
    input wire P0_RxWait,       // Port0 wait for receive packet to be queued

    input wire P0_TxClk,        // Port0 transmit clock
    input wire P0_TxReady,      // Port0 client ready for data
    output wire[7:0] P0_TxD,    // Port0 transmit data
    output wire[1:0] P0_TxSt,   // Port0 transmit status [last, first]
    input wire P0_TxWait,       // Port0 wait for transmit packet to be queued

    input wire P1_RxClk,        // Port1 receive clock
    input wire P1_RxValid,      // Port1 receive data valid
    input wire[7:0] P1_RxD,     // Port1 receive data
    input wire[1:0] P1_RxSt,    // Port1 receive status [last, first]
    input wire P1_RxWait,       // Port1 wait for receive packet to be queued

    input wire P1_TxClk,        // Port1 transmit clock
    input wire P1_TxReady,      // Port1 client ready for data
    output wire[7:0] P1_TxD,    // Port1 transmit data
    output wire[1:0] P1_TxSt,   // Port1 transmit status [last, first]
    input wire P1_TxWait,       // Port1 wait for transmit packet to be queued

    input wire P2_RxClk,        // Port2 receive clock
    input wire P2_RxValid,      // Port2 receive data valid
    input wire[7:0] P2_RxD,     // Port2 receive data
    input wire[1:0] P2_RxSt,    // Port2 receive status [last, first]
    input wire P2_RxWait,       // Port2 wait for receive packet to be queued

    input wire P2_TxClk,        // Port2 transmit clock
    input wire P2_TxReady,      // Port2 client ready for data
    output wire[7:0] P2_TxD,    // Port2 transmit data
    output wire[1:0] P2_TxSt,   // Port2 transmit status [last, first]
    input wire P2_TxWait,       // Port2 wait for transmit packet to be queued

    input wire P3_RxClk,        // Port3 receive clock
    input wire P3_RxValid,      // Port3 receive data valid
    input wire[7:0] P3_RxD,     // Port3 receive data
    input wire[1:0] P3_RxSt,    // Port3 receive status [last, first]
    input wire P3_RxWait,       // Port3 wait for receive packet to be queued

    input wire P3_TxClk,        // Port3 transmit clock
    input wire P3_TxReady,      // Port3 client ready for data
    output wire[7:0] P3_TxD,    // Port3 transmit data
    output wire[1:0] P3_TxSt,   // Port3 transmit status [last, first]
    input wire P3_TxWait        // Port3 wait for transmit packet to be queued
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

wire[7:0] RxD[0:3];
assign RxD[0] = P0_RxD;
assign RxD[1] = P1_RxD;
assign RxD[2] = P2_RxD;
assign RxD[3] = P3_RxD;

wire[7:0] RxSt[0:3];
assign RxSt[0] = P0_RxSt;
assign RxSt[1] = P1_RxSt;
assign RxSt[2] = P2_RxSt;
assign RxSt[3] = P3_RxSt;

wire RxWait[0:3];
assign RxWait[0] = P0_RxWait;
assign RxWait[1] = P1_RxWait;
assign RxWait[2] = P2_RxWait;
assign RxWait[3] = P3_RxWait;

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

wire[7:0] TxD[0:3];
assign P0_TxD = TxD[0];
assign P1_TxD = TxD[1];
assign P2_TxD = TxD[2];
assign P3_TxD = TxD[3];

wire[7:0] TxSt[0:3];
assign P0_TxSt = TxSt[0];
assign P1_TxSt = TxSt[1];
assign P2_TxSt = TxSt[2];
assign P3_TxSt = TxSt[3];

wire TxWait[0:3];
assign TxWait[0] = P0_TxWait;
assign TxWait[1] = P1_TxWait;
assign TxWait[2] = P2_TxWait;
assign TxWait[3] = P3_TxWait;

// Convention: signal[in][out]
wire fifo_reset[0:3][0:3];
wire fifo_full[0:3][0:3];
wire fifo_empty[0:3][0:3];

wire[7:0] RxD_Int[0:3];    // RxD output of internal Rx FIFO (2 bytes long)
wire[1:0] RxSt_Int[0:3];   // RxSt output of internal Rx FIFO (2 bytes long)
wire Fifo_Int_valid[0:3];  // Whether internal Rx FIFO has valid data

reg[1:0] TxInput[0:3];       // Index of current (or most recent) active input port
reg FifoActive[0:3][0:3];    // Whether the switch FIFO is active

reg[7:0] TxD_Switch[0:3][0:3];   // 8-bit switch output
reg[1:0] TxSt_Switch[0:3];

// Variables for generate block
genvar in;
genvar out;

generate

for (in = 0; in < 4; in = in + 1) begin : fifo__int_loop

  reg[2:0] RxCnt;        // Counts first 8 bytes
  reg DestMacValid;
  reg[23:0] DestMacReg;
  wire[7:0] DestMacLsb;
  wire[23:0] DestMac;       // TODO -- use this
  assign DestMac = DestMacValid ? DestMacReg : {DestMacReg[23:8], DestMacLsb};
  reg[23:0] SrcMac;   // TODO: use SrcMac for Forwarding Database

  // The internal FIFO has 2 bytes and allows us to look at the first 3 bytes
  // (destination MAC address) before deciding whether to forward to the output port.
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
              RxCnt <= 3'd1;
              DestMacReg[23:16] <= RxD[in];
          end
          else if (RxSt[in] == 2'b10) begin
              // Last byte of packet
              RxCnt <= 3'd0;
          end
          else if (RxSt[in] == 2'b00) begin
              RxCnt <= (RxCnt == 3'd7) ? 3'd7 : (RxCnt + 3'd1);
              case (RxCnt)
                3'd1: DestMacReg[15:8] <= RxD[in];
                3'd2: begin
                      DestMacReg[7:0] <= RxD[in];
                      DestMacValid <= 1'b1;
                      end
                3'd3: SrcMacReg[23:16] <= RxD[in];
                3'd4: SrcMacReg[15:8] <= RxD[in];
                3'd5: SrcMacReg[7:0] <= RxD[in];
              endcase
          end
      end
      else begin
          DestMacValid <= 1'b0;
      end
  end
end

for (in = 0; in < 4; in = in+1) begin : fifo_loop_in
  for (out = in+1; out < in+4; out = out+1) begin : fifo_loop_out

        //********* Port in (Rx) to Port out (Tx) *****************
        wire RxFwd;         // Whether to forward packet from port "in" to port "out"
        // TODO: Add forwarding database (for now, just floods all ports)
        assign RxFwd = Fifo_Int_valid[in];

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
    assign TxD[out] = TxD_Switch[curInput][out];
end

endgenerate

endmodule
