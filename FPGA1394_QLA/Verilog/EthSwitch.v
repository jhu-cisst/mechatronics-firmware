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
    input wire P0_Active,       // Port0 active (e.g., link on)

    input wire P0_RxClk,        // Port0 receive clock
    input wire P0_RxValid,      // Port0 receive data valid
    input wire[7:0] P0_RxD,     // Port0 receive data
    input wire P0_RxErr,        // Port0 receive error
    input wire P0_RxWait,       // Port0 wait for receive packet to be queued

    input wire P0_TxClk,        // Port0 transmit clock
    output wire P0_TxEn,        // Port0 transmit data valid
    output wire[7:0] P0_TxD,    // Port0 transmit data
    output wire P0_TxErr,       // Port0 transmit error
    input wire P0_TxReady,      // Port0 client ready for data
    input wire P0_TxWait,       // Port0 wait for transmit packet to be queued

    input wire P1_Active,       // Port1 active (e.g., link on)

    input wire P1_RxClk,        // Port1 receive clock
    input wire P1_RxValid,      // Port1 receive data valid
    input wire[7:0] P1_RxD,     // Port1 receive data
    input wire P1_RxErr,        // Port1 receive error
    input wire P1_RxWait,       // Port1 wait for receive packet to be queued

    input wire P1_TxClk,        // Port1 transmit clock
    output wire P1_TxEn,        // Port1 transmit data valid
    output wire[7:0] P1_TxD,    // Port1 transmit data
    output wire P1_TxErr,       // Port1 transmit error
    input wire P1_TxReady,      // Port1 client ready for data
    input wire P1_TxWait,       // Port1 wait for transmit packet to be queued

    input wire P2_Active,       // Port2 active (e.g., link on)

    input wire P2_RxClk,        // Port2 receive clock
    input wire P2_RxValid,      // Port2 receive data valid
    input wire[7:0] P2_RxD,     // Port2 receive data
    input wire P2_RxErr,        // Port2 receive error
    input wire P2_RxWait,       // Port2 wait for receive packet to be queued

    input wire P2_TxClk,        // Port2 transmit clock
    output wire P2_TxEn,        // Port2 transmit data valid
    output wire[7:0] P2_TxD,    // Port2 transmit data
    output wire P2_TxErr,       // Port2 transmit error
    input wire P2_TxReady,      // Port2 client ready for data
    input wire P2_TxWait,       // Port2 wait for transmit packet to be queued

    input wire P3_Active,       // Port3 active (e.g., link on)

    input wire P3_RxClk,        // Port3 receive clock
    input wire P3_RxValid,      // Port3 receive data valid
    input wire[7:0] P3_RxD,     // Port3 receive data
    input wire P3_RxErr,        // Port3 receive error
    input wire P3_RxWait,       // Port3 wait for receive packet to be queued

    input wire P3_TxClk,        // Port3 transmit clock
    output wire P3_TxEn,        // Port3 transmit data valid
    output wire[7:0] P3_TxD,    // Port3 transmit data
    output wire P3_TxErr,       // Port3 transmit error
    input wire P3_TxReady,      // Port3 client ready for data
    input wire P3_TxWait,       // Port3 wait for transmit packet to be queued

    // For external monitoring
    input wire[15:0] reg_raddr,
    output wire[31:0] reg_rdata
);

// Create arrays from input parameters

wire PortActive[0:3];
assign PortActive[0] = P0_Active;
assign PortActive[1] = P1_Active;
assign PortActive[2] = P2_Active;
assign PortActive[3] = P3_Active;

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

wire RxErr[0:3];
assign RxErr[0] = P0_RxErr;
assign RxErr[1] = P1_RxErr;
assign RxErr[2] = P2_RxErr;
assign RxErr[3] = P3_RxErr;

wire[1:0] RxSt[0:3];

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

wire TxEn[0:3];
assign P0_TxEn = TxEn[0];
assign P1_TxEn = TxEn[1];
assign P2_TxEn = TxEn[2];
assign P3_TxEn = TxEn[3];

wire[7:0] TxD[0:3];
assign P0_TxD = TxD[0];
assign P1_TxD = TxD[1];
assign P2_TxD = TxD[2];
assign P3_TxD = TxD[3];

wire TxErr[0:3];
assign P0_TxErr = TxErr[0];
assign P1_TxErr = TxErr[1];
assign P2_TxErr = TxErr[2];
assign P3_TxErr = TxErr[3];

wire[1:0] TxSt[0:3];

wire TxReady[0:3];
assign TxReady[0] = P0_TxReady;
assign TxReady[1] = P1_TxReady;
assign TxReady[2] = P2_TxReady;
assign TxReady[3] = P3_TxReady;

wire TxWait[0:3];
assign TxWait[0] = P0_TxWait;
assign TxWait[1] = P1_TxWait;
assign TxWait[2] = P2_TxWait;
assign TxWait[3] = P3_TxWait;

// Convention: signal[in][out]
// Note that diagonal elements (e.g., fifo_reset[i][i]) are not used
wire fifo_reset[0:3][0:3];
wire fifo_full[0:3][0:3];
wire fifo_empty[0:3][0:3];

wire[7:0] RxD_Int[0:3];    // RxD output of internal Rx FIFO
wire Fifo_Int_valid[0:3];  // Whether internal Rx FIFO has valid data

reg[1:0] TxInput[0:3];       // Index of current (or most recent) active input port
reg FifoActive[0:3][0:3];    // Whether the switch FIFO is active

wire[7:0] TxD_Switch[0:3][0:3];   // 8-bit switch output
wire[1:0] TxSt_Switch[0:3][0:3];

// Following just for Ethernet ports
reg[15:0] PortForwardFpga[0:1];

wire[47:8] FPGA_RT_MAC;
wire[47:8] FPGA_PS_MAC;
assign FPGA_RT_MAC = 40'hfa610e1394;
assign FPGA_PS_MAC = 40'hfa610e0300;

// Debugging
`ifdef HAS_DEBUG_DATA
reg[15:0] NumPacketRecv[0:3];
reg[15:0] NumPacketSent[0:3];
`endif

// Variables for generate block
genvar in;
genvar out;

generate

for (in = 0; in < 4; in = in + 1) begin : fifo__int_loop

  reg[3:0] RxCnt;
  reg[47:0] DestMac;
  reg[47:0] SrcMac;

  reg RxValid_1;
  reg RxValid_2;
  reg[7:0] RxD_1;
  reg RxErr_1;

  wire isFirstByte;
  wire isLastByte;
  assign isFirstByte = RxValid_1&(~RxValid_2);
  assign isLastByte = (~RxValid[in])&RxValid_1;

  always @(posedge RxClk[in])
  begin
      RxValid_1 <= RxValid[in];
      RxValid_2 <= RxValid_1;
      RxD_1 <= RxD[in];
      RxErr_1 <= RxErr[in];
`ifdef HAS_DEBUG_DATA
      if (isLastByte)
          NumPacketRecv[in] <= NumPacketRecv[in] + 16'd1;
`endif
  end

  // TODO: Add input FIFO
  assign RxD_Int[in] = RxD_1;
  assign RxSt[in] = isFirstByte ? 2'b01 :
                    isLastByte ? 2'b10 :
                    RxErr_1 ? 2'b11 : 2'b00;
  assign Fifo_Int_valid[in] = RxValid_1;

end

for (in = 0; in < 4; in = in+1) begin : fifo_loop_in
  for (out = in+1; out < in+4; out = out+1) begin : fifo_loop_out

        //********* Port in (Rx) to Port out (Tx) *****************
        wire RxFwd;         // Whether to forward packet from port "in" to port "out"
        // TODO: Add forwarding database (for now, just floods all ports)
        assign RxFwd = Fifo_Int_valid[in];
        // TODO: Implement FIFO reset (if desired)
        assign fifo_reset[in][out%4] = 1'b0;

        fifo_10x8192 Fifo(
            .rst(fifo_reset[in][out%4]),
            .wr_clk(RxClk[in]),
            .wr_en(RxFwd),
            .din({RxSt[in], RxD_Int[in]}),
            .rd_clk(TxClk[out%4]),
            .rd_en(FifoActive[in][out%4] & TxReady[out%4]),
            .dout({TxSt_Switch[in][out%4], TxD_Switch[in][out%4]}),
            .full(fifo_full[in][out%4]),
            .empty(fifo_empty[in][out%4])
        );
  end
end

for (out = 0; out < 4; out = out + 1) begin : fifo_loop_mux

    wire[1:0] curInput;
    assign curInput = TxInput[out];

    // A simple round-robin scheduler
    always @(posedge TxClk[out])
    begin
        if (FifoActive[curInput][out]) begin
            if (fifo_empty[curInput][out] || (TxSt[out] == 2'b10)) begin
                // If last byte (or fifo_empty, which should not happen)
                FifoActive[curInput][out] <= 1'b0;
`ifdef HAS_DEBUG_DATA
               NumPacketSent[out] <= NumPacketSent[out] + 16'd1;
`endif
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
        else if (~fifo_empty[(out+3)%4][out]) begin
            TxInput[out] <= (out+3)%4;
            FifoActive[(out+3)%4][out] <= 1'b1;
        end
    end

    assign TxSt[out] = TxSt_Switch[curInput][out];
    assign TxD[out] = TxD_Switch[curInput][out];
    assign TxErr[out] = (TxSt[out] == 2'b11) ? 1'b1 : 1'b0;
    assign TxEn[out] = FifoActive[curInput][out] & TxReady[out];
end

endgenerate

`ifdef HAS_DEBUG_DATA
wire[15:0] fifo_active_bits;

genvar i;
generate
for (i = 0; i < 16; i = i +1) begin : fifo_active_loop
    assign fifo_active_bits[i] = FifoActive[i/4][i%4];
end
endgenerate

wire[31:0] DebugData[0:7];      // Could increase to [0:15]
assign DebugData[0]  = 32'd0;
assign DebugData[1]  = { NumPacketSent[0], NumPacketRecv[0] };
assign DebugData[2]  = { NumPacketSent[1], NumPacketRecv[1] };
assign DebugData[3]  = { NumPacketSent[2], NumPacketRecv[2] };
assign DebugData[4]  = { NumPacketSent[3], NumPacketRecv[3] };
assign DebugData[5]  = { 16'd0, fifo_active_bits };
assign DebugData[6]  = 32'd0;
assign DebugData[7]  = 32'd0;

// address a0 used in RTL8211F.v; address af used in VirtualPhy.v
assign reg_rdata = (reg_raddr[7:4] == 4'ha) ? DebugData[reg_raddr[2:0]] : 32'd0;
`else
assign reg_rdata = 32'd0;
`endif

endmodule
