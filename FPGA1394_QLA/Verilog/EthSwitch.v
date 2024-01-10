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
 * This module implements a 4-port Ethernet switch, where Ports 0-3 are 8-bit
 * ports and Port 4 is a 32-bit (quadlet) port. This adds a little complexity
 * to the implementation, but is done for efficiency, since it is faster for
 * the Ethernet RxClk (125 MHz clock at 1GB) to assemble bytes into quadlets
 * than it is for EthernetIO (49.152 MHz clock) to do it.
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
    input wire[7:0] P3_RxD,     // Port3 receive data
    input wire[1:0] P3_RxSt,    // Port3 receive status [last, first]

    input wire P3_TxClk,        // Port3 transmit clock
    input wire P3_TxReady,      // Port3 client ready for data
    output wire[7:0] P3_TxD,    // Port3 transmit data
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
// RxD[3] is 32-bits

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
// TxD[3] is 32-bits

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
reg[31:0] RxD_Int3;        // RxD output of internal Rx FIFO (1 quadlet long)
wire[1:0] RxSt_Int[0:3];   // RxSt output of internal Rx FIFO (3 bytes long)
wire Fifo_Int_empty[0:3];  // Whether internal Rx FIFO empty

reg[1:0] TxInput[0:3];       // Index of current (or most recent) active input port
reg FifoActive[0:3][0:3];    // Whether the switch FIFO is active

reg [7:0] TxD_Switch[0:3][0:2];   // 8-bit switch output
reg[31:0] TxD3_Switch[0:2];       // 32-bit switch output

reg[1:0] TxSt_Switch[0:3];

// Variables for generate block
genvar in;
genvar out;

generate

for (in = 0; in < 3; in = in + 1) begin : fifo__int_loop
    // The internal FIFO has only 3 bytes and allows us to look at the
    // first 3 bytes (destination MAC address) before deciding whether
    // to forward to the output port.
    // Note that it is not needed for Port3, which is 32-bits
    fifo_8x3 Fifo_Int(
        .rst(1'b0),
        .wr_clk(RxClk[in]),
        .wr_en(RxValid[in]),
        .din({RxSt[in], RxD[in]}),
        .rd_clk(RxClk[in]),
        .rd_en(1'b1),
        .dout({RxSt_Int[in], RxD_Int[in]})
        .empty(Fifo_Int_empty[in])
    );
end

// Port 3 is 32-bits, so we only need a 1-element FIFO, which
// is implemented below (RxD_Int3 declared above)
reg[1:0] RxSt_Int3_reg;
reg Fifo_Int3_empty_reg;
initial Fifo_Int3_empty_reg = 1'b1;

assign RxSt_Int[3] = RxSt_Int3_reg;
assign Fifo_Int_empty[3] = Fifo_Int3_empty_reg;

always @(posedge RxClk[3])
begin
    if (RxValid[3]) begin
        RxD_Int3 <= P3_RxD;
        RxSt_Int3_reg <= RxSt[3];
        Fifo_Int3_empty_reg <= 1'b0;
    end
    else begin
        Fifo_Int3_empty_reg <= 1'b1;
    end
end

for (in = 0; in < 4; in = in+1) begin : fifo_loop_in
  for (out = in+1; out < in+4; out = out+1) begin : fifo_loop_out

        //********* Port in (Rx) to Port out (Tx) *****************

        wire RxFwd;         // Whether to forward packet from port "in" to port "out"
        // TODO: Add forwarding database (for now, just floods all ports)
        assign RxFwd = ~Fifo_Int_empty[in];

        if (in == 3) begin
            // Input is 32-bits, output is 8-bits
            fifo_32x2048_8 Fifo_D(
                .rst(fifo_reset[in][out%4]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din(RxD_Int3),
                .rd_clk(TxClk[out%4]),
                .rd_en(FifoActive[in][out%4] & TxReady[out%4]),
                .dout(TxD_Switch[in][out%4]}),
                .full(fifo_full[in][out%4]),
                .empty(fifo_empty[in][out%4])
            );
            // Status bits
            fifo_2x2048 Fifo_S(
                .rst(fifo_reset[in][out%4]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din(RxSt[in]),
                .rd_clk(TxClk[out%4]),
                .rd_en(FifoActive[in][out%4] & TxReady[out%4]),
                .dout({TxSt[in][out%4]}),
                .full(fifo_full[in][out%4]),
                .empty(fifo_empty[in][out%4])
            );
        end
        else if (out == 3) begin
            // Input is 8-bits, output is 32-bits
            fifo_8x8192_32 Fifo_D(
                .rst(fifo_reset[in][out]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din(RxD_Int[in]),
                .rd_clk(TxClk[out]),
                .rd_en(FifoActive[in][out] & TxReady[out]),
                .dout(TxD3_Switch[in]),
                .full(fifo_full[in][out%4]),
                .empty(fifo_empty[in][out%4])
            );
            // Status bits
            fifo_2x8192 Fifo_S(
                .rst(fifo_reset[in][out]),
                .wr_clk(RxClk[in]),
                .wr_en(RxFwd),
                .din(RxSt_Int[in]),
                .rd_clk(TxClk[out]),
                .rd_en(FifoActive[in][out] & TxReady[out]),
                .dout(TxSt_Switch[in][out]),
                .full(fifo_full[in][out]),
                .empty(fifo_empty[in][out])
            );
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

        reg[1:0] RxCnt;         // Counts first 3 bytes
        reg[7:0] DestMac[0:2];  // TODO -- use this

        always @(posedge RxClk[in])
        begin
            if (RxValid[in]) begin
                if (RxSt[in] == 2'b01) begin
                    // First byte of packet
                    RxCnt <= 2'd1;
                    DestMac[0] <= RxD[in];
                end
                else if (RxSt[in] == 2'b10) begin
                    // Last byte of packet
                    RxCnt <= 2'd0;
                end
                else if (RxCnt == 2'd1) begin
                    DestMac[1] <= RxD[in];
                    RxCnt <= 2'd2;
                end
                else if (RxCnt == 2'd2) begin
                    DestMac[2] <= RxD[in];
                    RxCnt <= 2'd3;
                end
            end
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
