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

`include "Constants.v"

module EthSwitch
(
    input wire P0_Active,       // Port0 active (e.g., link on)
    input wire P0_Ready,        // Port0 ready for data
    input wire P0_Fast,         // Port0 is "fast" (1 GB)

    input wire P0_RxClk,        // Port0 receive clock
    input wire P0_RxValid,      // Port0 receive data valid
    input wire[7:0] P0_RxD,     // Port0 receive data
    input wire P0_RxErr,        // Port0 receive error

    input wire P0_TxClk,        // Port0 transmit clock
    output wire P0_TxEn,        // Port0 transmit data valid
    output wire[7:0] P0_TxD,    // Port0 transmit data
    output wire P0_TxErr,       // Port0 transmit error
    output wire[3:0] P0_TxInfo, // Port0 transmit packet info

    input wire P1_Active,       // Port1 active (e.g., link on)
    input wire P1_Ready,        // Port1 ready for data
    input wire P1_Fast,         // Port1 is "fast" (1 GB)

    input wire P1_RxClk,        // Port1 receive clock
    input wire P1_RxValid,      // Port1 receive data valid
    input wire[7:0] P1_RxD,     // Port1 receive data
    input wire P1_RxErr,        // Port1 receive error

    input wire P1_TxClk,        // Port1 transmit clock
    output wire P1_TxEn,        // Port1 transmit data valid
    output wire[7:0] P1_TxD,    // Port1 transmit data
    output wire P1_TxErr,       // Port1 transmit error
    output wire[3:0] P1_TxInfo, // Port1 transmit packet info

    input wire P2_Active,       // Port2 active (e.g., link on)
    input wire P2_Ready,        // Port2 ready for data
    input wire P2_Fast,         // Port2 is "fast" (1 GB)

    input wire P2_RxClk,        // Port2 receive clock
    input wire P2_RxValid,      // Port2 receive data valid
    input wire[7:0] P2_RxD,     // Port2 receive data
    input wire P2_RxErr,        // Port2 receive error

    input wire P2_TxClk,        // Port2 transmit clock
    output wire P2_TxEn,        // Port2 transmit data valid
    output wire[7:0] P2_TxD,    // Port2 transmit data
    output wire P2_TxErr,       // Port2 transmit error
    output wire[3:0] P2_TxInfo, // Port2 transmit packet info

    input wire P3_Active,       // Port3 active (e.g., link on)
    input wire P3_Ready,        // Port3 ready for data
    input wire P3_Fast,         // Port3 is "fast" (1 GB)

    input wire P3_RxClk,        // Port3 receive clock
    input wire P3_RxValid,      // Port3 receive data valid
    input wire[7:0] P3_RxD,     // Port3 receive data
    input wire P3_RxErr,        // Port3 receive error

    input wire P3_TxClk,        // Port3 transmit clock
    output wire P3_TxEn,        // Port3 transmit data valid
    output wire[7:0] P3_TxD,    // Port3 transmit data
    output wire P3_TxErr,       // Port3 transmit error
    output wire[3:0] P3_TxInfo, // Port3 transmit packet info

    input wire[3:0] board_id,   // Board id (used for MAC addresses)

    input wire clearErrors,

    // For external monitoring
    input wire[15:0] reg_raddr,
    output wire[31:0] reg_rdata
);

// Following documents assumptions about port connections
localparam INDEX_ETH1 = 0;
localparam INDEX_ETH2 = 1;
localparam INDEX_PS = 2;
localparam INDEX_RT = 3;

// Create arrays from input parameters

wire PortActive[0:3];
assign PortActive[0] = P0_Active;
assign PortActive[1] = P1_Active;
assign PortActive[2] = P2_Active;
assign PortActive[3] = P3_Active;

wire PortReady[0:3];
assign PortReady[0] = P0_Ready;
assign PortReady[1] = P1_Ready;
assign PortReady[2] = P2_Ready;
assign PortReady[3] = P3_Ready;

// Queueing rules
//   - Wait for packet to be queued if in-port (Rx) is slow and out-port (Tx) is fast
//   - Since we do not distinguish between different rates of slow, we always queue
//     if both ports are slow (not a likely scenario)
// This implies:
//   - Wait for packet to be queued if in-port is slow, regardless of whether or not
//     out-port is fast
wire PortFast[0:3];
assign PortFast[0] = P0_Fast;
assign PortFast[1] = P1_Fast;
assign PortFast[2] = P2_Fast;
assign PortFast[3] = P3_Fast;

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

wire[3:0] TxInfo[0:3];
assign P0_TxInfo = TxInfo[0];
assign P1_TxInfo = TxInfo[1];
assign P2_TxInfo = TxInfo[2];
assign P3_TxInfo = TxInfo[3];

wire[1:0] TxSt[0:3];

// Convention: signal[in][out]
// Note that diagonal elements (e.g., fifo_full[i][i]) are not used
wire fifo_full[0:3][0:3];
wire fifo_empty[0:3][0:3];
wire fifo_valid[0:3][0:3];
wire fifo_underflow[0:3][0:3];
wire fifo_info_full[0:3][0:3];
wire fifo_info_empty[0:3][0:3];

reg  fifo_underflow_latched[0:3][0:3];

wire[7:0] RxD_Int[0:3];      // RxD output of internal Rx FIFO
wire      RxValid_Int[0:3];  // Whether internal Rx FIFO has valid data

reg[1:0] TxInput[0:3];       // Index of current (or most recent) active input port
reg FifoActive[0:3][0:3];    // Whether the switch FIFO is active
wire dataAvail[0:3][0:3];    // Whether data is available between [in] and [out]

wire[7:0] TxD_Switch[0:3][0:3];   // 8-bit switch output
wire[1:0] TxSt_Switch[0:3][0:3];
wire[2:0] TxInfo_Switch[0:3][0:3];

// Following just for Ethernet ports
//    PortForwardFpga[port-num][board-id]:
//        1 --> FPGA board is accessible via port-num (i.e., Eth1 or Eth2 received
//              a packet with the corresponding SrcMac address
//        0 --> Not known whether FPGA board is accessible via port-num
reg[15:0] PortForwardFpga[INDEX_ETH1:INDEX_ETH2];

// Consolidated forwarding information for each FPGA board id
//    PortForwardFpgaAction[board-id][port-num]
//      1 -> forward packets for board-id on port-num
//      0 -> do not forward packets for board-id on port-num
wire[15:0] PortForwardFpgaAction[0:3];

genvar bd;
generate
for (bd = 0; bd < 16; bd = bd + 1) begin : bd_loop
  wire isCurBoard;
  assign isCurBoard = (board_id == bd) ? 1'b1 : 1'b0;
  wire isNoPort;
  assign isNoPort = ~(PortForwardFpga[INDEX_ETH1][bd]|PortForwardFpga[INDEX_ETH2][bd]|isCurBoard);
  assign PortForwardFpgaAction[INDEX_ETH1][bd] = PortForwardFpga[INDEX_ETH1][bd]|isNoPort;
  assign PortForwardFpgaAction[INDEX_ETH2][bd] = PortForwardFpga[INDEX_ETH2][bd]|isNoPort;
  assign PortForwardFpgaAction[INDEX_PS][bd] = isCurBoard;
  assign PortForwardFpgaAction[INDEX_RT][bd] = isCurBoard;
end
endgenerate

// Ethernet broadcast MAC address
localparam[47:0] BroadcastMAC = 48'hFFFFFFFFFFFF;

// FPGA MAC addresses contain the LCSR Company ID (CID) as the first 24-bits,
// followed by 16-bits for the RT or PS interface, followed by 8-bits for the board-id.
localparam[23:0] LCSR_CID    = 24'hfa610e;
localparam[15:0] FPGA_RT_MAC = 16'h1394;
localparam[15:0] FPGA_PS_MAC = 16'h0300;
// Lowest 8-bits contain board-id

// FPGA multicast MAC address. Currently, only used for RT, but implementation supports
// it for PS (or any other middle 16-bits), since we only check for a match on
// LCSR_CID_MULTICAST and the lower 8-bits (8'hff).
localparam[23:0] LCSR_CID_MULTICAST = LCSR_CID | 24'h010000;

// For saving MAC address of host (on Eth1 or Eth2)
reg[47:0] MacAddrHost[INDEX_ETH1:INDEX_ETH2];
initial MacAddrHost[INDEX_ETH1] = BroadcastMAC;
initial MacAddrHost[INDEX_ETH2] = BroadcastMAC;

// Primary MAC address to use for routing (indexed by out-port)
wire[47:0] MacAddrPrimary[0:3];
assign MacAddrPrimary[INDEX_ETH1] = MacAddrHost[INDEX_ETH1];
assign MacAddrPrimary[INDEX_ETH2] = MacAddrHost[INDEX_ETH2];
assign MacAddrPrimary[INDEX_PS] = { LCSR_CID, FPGA_PS_MAC, 4'd0, board_id };
assign MacAddrPrimary[INDEX_RT] = { LCSR_CID, FPGA_RT_MAC, 4'd0, board_id };

// Destination address of current packet on each in-port
wire[47:0] DestMac[0:3];

// 1 --> DestMac[in] matches MacAddrPrimary[out]
wire MacAddrPrimaryMatch[0:3][0:3];

wire CrcError[0:3];     // Frame CRC error
reg  IPv4Error[0:3];    // IPv4 Header checksum error

// Debugging
`ifdef HAS_DEBUG_DATA
reg[15:0] NumPacketRecv[0:3];
reg[15:0] NumPacketSent[0:3];
reg[7:0]  NumPacketFwd[0:1][0:3];
reg[7:0]  NumCrcErrorIn[0:3];
reg[7:0]  NumCrcErrorOut[0:3];
reg[7:0]  NumIPv4ErrorIn[0:3];
reg[7:0]  TxInfoReg[0:3];
// Following indicate whether a packet has been dropped or truncated
// due to a full FIFO.
reg       PacketDropped[0:3][0:3];
reg       PacketTruncated[0:3][0:3];
`endif

// Variables for generate block
genvar in;
genvar out;

generate

for (in = 0; in < 4; in = in + 1) begin : fifo__int_loop

  // crc registers
  wire[7:0] recv_crc_data;    // data into crc module to compute crc on
  reg[31:0] recv_crc_in;      // input to crc module (starts at all ones)
  wire[31:0] recv_crc_2b;     // current crc module output for data width 2 (not used)
  wire[31:0] recv_crc_4b;     // current crc module output for data width 4 (not used)
  wire[31:0] recv_crc_8b;     // current crc module output for data width 8

  // Reverse bits when computing CRC
  assign recv_crc_data = { RxD[in][0], RxD[in][1], RxD[in][2], RxD[in][3], RxD[in][4], RxD[in][5], RxD[in][6], RxD[in][7] };

  // This module computes crc continuously, so it is up to the state machine to
  // initialize, feed back, and latch crc values as necessary
  crc32 recv_crc(recv_crc_data, recv_crc_in, recv_crc_2b, recv_crc_4b, recv_crc_8b);

  // The CRC of the packet, including the FCS (CRC) field should equal 32'hc704dd7b.
  // Due to byte swapping, we check against 32'h7bdd04c7
  // Note that this is only valid after the entire packet has been processed.
  assign CrcError[in] = (recv_crc_in != 32'h7bdd04c7) ? 1'b0 : 1'b1;

  reg[4:0] rxCnt;    // Counts 0-31 (need to count to 19 for UDP header)

  // Basic FIFO for first 14 bytes (8-byte preamble + 6-byte Dest MAC)
  // Implemented as vectors.
  // Note that RxValid_Fifo is 1 bit longer to identify transitions.
  reg[111:0] RxD_Fifo;      // (14*8-1)
  reg[14:0]  RxValid_Fifo;
  reg[13:0]  RxErr_Fifo;

  wire isFirstByteIn;
  wire isLastByteIn;
  assign isFirstByteIn = (~RxValid_Fifo[14])&RxValid_Fifo[13];
  assign isLastByteIn = RxValid_Fifo[13]&(~RxValid_Fifo[12]);

  // First 14 bytes of Ethernet frame (not including preamble)
  reg[7:0] frame_header[0:13];
  wire[47:0] SrcMac;

  assign DestMac[in] = { frame_header[`ETH_Dest_MAC],   frame_header[`ETH_Dest_MAC+1],
                         frame_header[`ETH_Dest_MAC+2], frame_header[`ETH_Dest_MAC+3],
                         frame_header[`ETH_Dest_MAC+4], frame_header[`ETH_Dest_MAC+5] };
  assign SrcMac  = { frame_header[`ETH_Src_MAC],   frame_header[`ETH_Src_MAC+1],
                     frame_header[`ETH_Src_MAC+2], frame_header[`ETH_Src_MAC+3],
                     frame_header[`ETH_Src_MAC+4], frame_header[`ETH_Src_MAC+5] };

  // Ethernet frame length/type and IPv4 protocol are used to compute checksums.
  wire[15:0] recv_length;   // Ethernet frame length/type (0x0800 is IPv4)
  assign recv_length = {frame_header[`ETH_Frame_Length], frame_header[`ETH_Frame_Length+1]};
  wire recv_ipv4;
  assign recv_ipv4 = (recv_length == 16'h0800) ? 1'b1 : 1'b0;
  reg[16:0] recv_ipv4_cksum;   // Used to verify IPv4 header checksum

  assign MacAddrPrimaryMatch[in][in] = 1'b0;   // Should not happen, unless loop
  assign MacAddrPrimaryMatch[in][(in+1)%4] = (DestMac[in] == MacAddrPrimary[(in+1)%4]) ? 1'b1 : 1'b0;
  assign MacAddrPrimaryMatch[in][(in+2)%4] = (DestMac[in] == MacAddrPrimary[(in+2)%4]) ? 1'b1 : 1'b0;
  assign MacAddrPrimaryMatch[in][(in+3)%4] = (DestMac[in] == MacAddrPrimary[(in+3)%4]) ? 1'b1 : 1'b0;

  localparam
      ST_RX_IDLE          = 2'd0,
      ST_RX_FRAME_HEADER  = 2'd1,
      ST_RX_FRAME_DATA    = 2'd2;

  reg[1:0] rxState;

  always @(posedge RxClk[in])
  begin
      RxD_Fifo <= { RxD_Fifo[103:0], RxD[in] };
      RxValid_Fifo <= { RxValid_Fifo[13:0], RxValid[in] };
      RxErr_Fifo <= { RxErr_Fifo[12:0], RxErr[in] };

      if ((in == INDEX_ETH1) || (in == INDEX_ETH2)) begin
          // If Eth1 or Eth2 not active, reset forwarding database
          if (~PortActive[in]) begin
              MacAddrHost[in] <= BroadcastMAC;
              PortForwardFpga[in] <= 16'd0;
          end
      end

`ifdef HAS_DEBUG_DATA
      if (clearErrors) begin
          NumCrcErrorIn[in] <= 8'd0;
      end
`endif

      case (rxState)

      ST_RX_IDLE:
      begin
          if (RxValid[in]) begin
              // Currently, no error checking on preamble
              // (could check rxCnt)
              rxCnt <= rxCnt + 5'd1;
              if (RxD[in] == 8'hd5) begin
                  rxState <= ST_RX_FRAME_HEADER;
                  rxCnt <= 5'd0;
                  recv_crc_in <= 32'hffffffff;    // Initialize CRC
                  IPv4Error[in] <= 1'b0;
              end
          end
          else begin
              rxCnt <= 5'd0;
          end
      end

      ST_RX_FRAME_HEADER:
      begin
          // Save first 14 bytes
          if (RxValid[in]) begin
              rxCnt <= rxCnt + 5'd1;
              recv_crc_in <= recv_crc_8b;
              frame_header[rxCnt[3:0]] <= RxD[in];
              if (rxCnt == 5'd13) begin
                  if ((in == INDEX_ETH1) || (in == INDEX_ETH2)) begin
                      MacAddrHost[in] <= SrcMac;
                      // If the upper 24-bits of SrcMac match LCSR_CID, then
                      // there is an FPGA board accessible via that port.
                      // For this purpose, it does not matter whether the middle
                      // 16-bits are FPGA_RT_MAC or FPGA_PS_MAC.
                      if (SrcMac[47:24] == LCSR_CID)
                          PortForwardFpga[in][SrcMac[3:0]] <= 1'b1;
                  end
                  rxCnt <= 5'd0;
                  rxState <= ST_RX_FRAME_DATA;
              end
          end
          else begin
              rxCnt <= 5'd0;
              rxState <= ST_RX_IDLE;
          end
      end

      ST_RX_FRAME_DATA:
      begin
          if (RxValid[in]) begin
              recv_crc_in <= recv_crc_8b;
              if (rxCnt != 5'd31)
                  rxCnt <= rxCnt + 5'd1;

              // IPv4 header checksum. Note that the carry bit is added to the sum.
              if (rxCnt == (`ETH_IPv4_Begin-`ETH_Frame_End))
                  recv_ipv4_cksum <= {1'b0, RxD[in], 8'd0};
              else if (rxCnt == (`ETH_IPv4_End-`ETH_Frame_End))
                  IPv4Error[in] <= ((recv_ipv4_cksum == 17'h0ffff) || (recv_ipv4_cksum == 17'h1fffe)) ? 1'b0 : recv_ipv4;
              else if (~rxCnt[0])
                  recv_ipv4_cksum <= {1'b0, recv_ipv4_cksum[15:0]} + {RxD[in], 7'd0, recv_ipv4_cksum[16]};
              else
                  recv_ipv4_cksum <= recv_ipv4_cksum + { 9'd0, RxD[in] };
          end
          else begin
`ifdef HAS_DEBUG_DATA
              NumPacketRecv[in] <= NumPacketRecv[in] + 16'd1;
              if (CrcError[in])
                  NumCrcErrorIn[in] <= NumCrcErrorIn[in] + 8'd1;
              if (IPv4Error[in])
                  NumIPv4ErrorIn[in] <= NumIPv4ErrorIn[in] + 8'd1;
`endif
              rxCnt <= 5'd0;
              rxState <= ST_RX_IDLE;
          end
      end

      default:
          // Could note this as an error
          rxState <= ST_RX_IDLE;

      endcase
  end

  assign RxD_Int[in] = RxD_Fifo[111:104];
  assign RxValid_Int[in] = RxValid_Fifo[13];

  assign RxSt[in] = isFirstByteIn ? 2'b01 :
                    isLastByteIn ? 2'b10 :
                    RxErr_Fifo[13] ? 2'b11 : 2'b00;

end

for (in = 0; in < 4; in = in+1) begin : fifo_loop_in

  // Diagonal elements are not used, so initialize them to avoid warnings
  assign fifo_full[in][in] = 1'b0;
  assign fifo_empty[in][in] = 1'b1;
  assign fifo_valid[in][in] = 1'b0;
  assign fifo_underflow[in][in] = 1'b0;
  assign fifo_info_full[in][in] = 1'b0;
  assign fifo_info_empty[in][in] = 1'b1;
  assign TxSt_Switch[in][in] = 2'd0;
  assign TxD_Switch[in][in] = 8'd0;
  assign TxInfo_Switch[in][in] = 3'd0;
  assign dataAvail[in][in] = 1'b0;
  wire isBroadcast;
  assign isBroadcast = (DestMac[in] == BroadcastMAC) ? 1'b1 : 1'b0;
  wire isMulticast;
  assign isMulticast = (DestMac[in][47:24] == LCSR_CID_MULTICAST) && (DestMac[in][7:0] == 8'hff) ? 1'b1 : 1'b0;

  wire isFirstByteIn;
  assign isFirstByteIn = (RxSt[in] == 2'b01) ? 1'b1 : 1'b0;
  wire isLastByteIn;
  assign isLastByteIn = (RxSt[in] == 2'b10) ? 1'b1 : 1'b0;

  for (out = in+1; out < in+4; out = out+1) begin : fifo_loop_out

      //********* Port in (Rx) to Port out (Tx) *****************
      wire isPrimaryMatch;
      assign isPrimaryMatch = MacAddrPrimaryMatch[in][out%4];
      wire RxFwd;         // Whether to forward packet from port "in" to port "out"
      if (((out%4) == INDEX_ETH1) || ((out%4) == INDEX_ETH2)) begin
          wire isFpgaMatch;
          assign isFpgaMatch = (DestMac[in][47:24] == LCSR_CID) ?
                               PortForwardFpgaAction[DestMac[in][3:0]][out%4] : 1'b0;
          wire isNoPrimaryMatch;
          assign isNoPrimaryMatch = ~(MacAddrPrimaryMatch[in][(in+1)%4] | MacAddrPrimaryMatch[in][(in+2)%4] |
                                      MacAddrPrimaryMatch[in][(in+3)%4]);
          wire  isNoMatch;
          assign isNoMatch = isNoPrimaryMatch & (~isFpgaMatch);
          assign RxFwd = RxValid_Int[in] & PortActive[out%4] &
                         (isBroadcast|isMulticast|isPrimaryMatch|isFpgaMatch|isNoMatch);
      end
      else begin
          assign RxFwd = RxValid_Int[in] & PortActive[out%4] & (isBroadcast|isMulticast|isPrimaryMatch);
      end

      wire isLastByteOut;
      assign isLastByteOut = (TxSt_Switch[in][out%4] == 2'b10) ? 1'b1 : 1'b0;

      // fifo_overflow indicates that we could not write due to a full FIFO
      reg  fifo_overflow;
      // fifo_not_ready indicates that the FIFO is either full, or still recovering from a prior full condition
      // (i.e., waiting to write the last byte or the info).
      wire fifo_not_ready;
      // force_last_byte is used to make sure a valid "last byte" flag (TxSt) is written to the FIFO so
      // that the port clients can assume that all packets (even truncated ones) have a last byte indicator.
      reg  force_last_byte;
      // drop_packet is set if the FIFO is full (or recovering from a FIFO full condition), when we
      // get the first byte; this ensures that the entire packet is dropped.
      reg  drop_packet;
      // fifo_write controls whether data is written to the FIFO. If the FIFO is not ready (including due to overflow),
      // we stop storing the packet, unless force_last_byte is set.
      wire fifo_write;
      assign fifo_write = ((RxFwd & (~fifo_not_ready)) | force_last_byte) & (~drop_packet);
      // force_first_byte is used to make sure the first byte is read, even if TxSt still indicates that the
      // last byte (from the previous packet) has been read.
      reg force_first_byte;
      // fifo_read controls whether data is read from the FIFO.
      wire fifo_read;
      assign fifo_read = FifoActive[in][out%4] & PortReady[out%4] & ((~isLastByteOut)|force_first_byte);

      fifo_10x8192 Fifo(
          .rst(~PortActive[out%4]),
          .wr_clk(RxClk[in]),
          .wr_en(fifo_write),
          .din({(force_last_byte ? 2'b10 : RxSt[in]), RxD_Int[in]}),
          .rd_clk(TxClk[out%4]),
          .rd_en(fifo_read),
          .dout({TxSt_Switch[in][out%4], TxD_Switch[in][out%4]}),
          .valid(fifo_valid[in][out%4]),
          .underflow(fifo_underflow[in][out%4]),
          .full(fifo_full[in][out%4]),
          .empty(fifo_empty[in][out%4])
      );

      wire [31:0] packet_info_out;
      assign TxInfo_Switch[in][out%4] = packet_info_out[2:0];
      reg write_info;

      // Needs to be first-word fall-through
      // For now, 32-bits, but will be regenerated with a much smaller width
      fifo_32x32 Fifo_Info(
          .rst(~PortActive[out%4]),
          .wr_clk(RxClk[in]),
          .wr_en(write_info),
          .din({ 29'd0, fifo_overflow, IPv4Error[in], CrcError[in] }),
          .rd_clk(TxClk[out%4]),
          .rd_en(FifoActive[in][out%4] & PortReady[out%4] & isLastByteOut),
          .dout(packet_info_out),
          .full(fifo_info_full[in][out%4]),
          .empty(fifo_info_empty[in][out%4])
      );

      reg fifo_info_overflow;
      //assign fifo_not_ready = fifo_full[in][out%4] | fifo_overflow | fifo_info_overflow;
      assign fifo_not_ready = 1'b0;  // TODO

      always @(posedge RxClk[in])
      begin

`ifdef HAS_DEBUG_DATA
          if (clearErrors) begin
              PacketDropped[in][out%4] <= 1'b0;
              PacketTruncated[in][out%4] <= 1'b0;
          end
`endif

          // Make sure write_info is only asserted for one clock cycle
          write_info <= 1'b0;

`ifdef HAS_DEBUG_DATA
          if ((in == INDEX_ETH1) || (in == INDEX_ETH2)) begin
              if (isFirstByteIn & RxFwd) begin
                  NumPacketFwd[in][out%4] <= NumPacketFwd[in][out%4] + 8'd1;
              end
          end
`endif

          // Check for FIFO overflow
          if (RxFwd) begin
              if (isFirstByteIn)
                  drop_packet <= fifo_not_ready;
              if (fifo_full[in][out%4])
                  fifo_overflow <= 1'b1;
              if (isLastByteIn) begin
                  if (fifo_info_full[in][out%4])
                      fifo_info_overflow <= 1'b1;
                  else
                      write_info <= 1'b1;
              end
          end
          else if (fifo_overflow) begin
              // If there was an overflow, wait to store last byte
              if (force_last_byte) begin
`ifdef HAS_DEBUG_DATA
                  PacketTruncated[in][out%4] <= 1'b1;
`endif
                  force_last_byte <= 1'b0;
                  fifo_overflow <= 1'b0;
                  if (~fifo_info_overflow)
                      write_info <= 1'b1;
              end
              else if (~fifo_full[in][out%4]) begin
                  force_last_byte <= 1'b1;
              end
          end
          else if (fifo_info_overflow) begin
             if (~fifo_info_full[in][out%4]) begin
                 write_info <= 1'b1;
                 fifo_info_overflow <= 1'b0;
              end
          end
          else begin
`ifdef HAS_DEBUG_DATA
              if (drop_packet)
                  PacketDropped[in][out%4] <= 1'b1;
`endif
              drop_packet <= 1'b0;
          end
      end

      always @(posedge TxClk[out%4])
      begin
          if (~FifoActive[in][out%4])
              force_first_byte <= 1'b1;
          else if (~isLastByteOut)
              force_first_byte <= 1'b0;
      end

      // Data is available immediately for a fast in-port, or when the packet has been queued for a slow in-port
      assign dataAvail[in][out%4] = (PortFast[in]&(~fifo_empty[in][out%4])) | ((~PortFast[in])&(~fifo_info_empty[in][out%4]));
  end
end

for (out = 0; out < 4; out = out + 1) begin : fifo_loop_mux

    wire[1:0] curInput;
    assign curInput = TxInput[out];
    // Ethernet specifies a 12-byte interpacket gap (IPG)
    reg[3:0] waitCnt;

    reg PortReady_Latched;

    // A simple round-robin scheduler
    always @(posedge TxClk[out])
    begin

        if (clearErrors) begin
`ifdef HAS_DEBUG_DATA
            NumCrcErrorOut[out] <= 8'd0;
`endif
            fifo_underflow_latched[0][out] <= 1'b0;
            fifo_underflow_latched[1][out] <= 1'b0;
            fifo_underflow_latched[2][out] <= 1'b0;
            fifo_underflow_latched[3][out] <= 1'b0;
        end

        PortReady_Latched <= PortReady[out];
        if (FifoActive[curInput][out]) begin
            if (fifo_underflow[curInput][out]) begin
                // Should not happen, so we set this "sticky" bit to indicate
                // that it has occurred.
                fifo_underflow_latched[curInput][out] <= 1'b1;
            end
            if (PortReady_Latched && (fifo_empty[curInput][out] || (TxSt[out] == 2'b10))) begin
                // If last byte (or fifo_empty, which should not happen except on last byte)
                FifoActive[curInput][out] <= 1'b0;
                waitCnt <= 4'd12;   // Set up for IPG (interpacket gap)
`ifdef HAS_DEBUG_DATA
               TxInfoReg[out] <= { TxSt[out], curInput, TxInfo[out] };
               if (TxInfo[out][0])
                   NumCrcErrorOut[out] <= NumCrcErrorOut[out] + 8'd1;
               NumPacketSent[out] <= NumPacketSent[out] + 16'd1;
`endif
            end
        end
        else if (waitCnt != 4'd0) begin
            // Interpacket gap (12 bytes)
            waitCnt <= waitCnt - 4'd1;
        end
        else if (PortReady[out]) begin
            if (dataAvail[(curInput+1)%4][out]) begin
                TxInput[out] <= (curInput+1)%4;
                FifoActive[(curInput+1)%4][out] <= 1'b1;
            end
            else if (dataAvail[(curInput+2)%4][out]) begin
                TxInput[out] <= (curInput+2)%4;
                FifoActive[(curInput+2)%4][out] <= 1'b1;
            end
            else if (dataAvail[(curInput+3)%4][out]) begin
                TxInput[out] <= (curInput+3)%4;
                FifoActive[(curInput+3)%4][out] <= 1'b1;
            end
            else if (dataAvail[curInput][out]) begin
                // Following already set
                // TxInput[out] <= curInput;
                FifoActive[curInput][out] <= 1'b1;
            end
        end
    end

    assign TxSt[out] = TxSt_Switch[curInput][out];
    assign TxD[out] = TxD_Switch[curInput][out];
    assign TxErr[out] = (fifo_underflow[curInput][out] || (TxSt[out] == 2'b11)) ? 1'b1 : 1'b0;
    assign TxEn[out] = fifo_valid[curInput][out];
    // MSB is 1 to indicate that rest of bits are valid
    assign TxInfo[out] = { (FifoActive[curInput][out]&(~fifo_info_empty[curInput][out])),
                           TxInfo_Switch[curInput][out] };

end
endgenerate

`ifdef HAS_DEBUG_DATA
wire[15:0] fifo_active_bits;
wire[15:0] fifo_empty_bits;
wire[15:0] fifo_full_bits;
wire[15:0] fifo_underflow_bits;
wire[15:0] packet_dropped_bits;
wire[15:0] packet_truncated_bits;
wire[15:0] fifo_info_not_empty_bits;
wire[15:0] data_avail_bits;

genvar i;
generate
for (i = 0; i < 16; i = i +1) begin : fifo_active_loop
    assign fifo_active_bits[i] = FifoActive[i/4][i%4];
    assign fifo_empty_bits[i] = fifo_empty[i/4][i%4];
    assign fifo_full_bits[i] = fifo_full[i/4][i%4];
    assign fifo_underflow_bits[i] = fifo_underflow_latched[i/4][i%4];
    assign packet_dropped_bits[i] = PacketDropped[i/4][i%4];
    assign packet_truncated_bits[i] = PacketTruncated[i/4][i%4];
    assign fifo_info_not_empty_bits[i] = ~fifo_info_empty[i/4][i%4];
    assign data_avail_bits[i] = dataAvail[i/4][i%4];
end
endgenerate

wire[31:0] DebugData[0:15];
assign DebugData[0]  = "0WSE";  // ESW0 byte-swapped
assign DebugData[1]   = { NumPacketSent[0], NumPacketRecv[0] };
assign DebugData[2]   = { NumPacketSent[1], NumPacketRecv[1] };
assign DebugData[3]   = { NumPacketSent[2], NumPacketRecv[2] };
assign DebugData[4]   = { NumPacketSent[3], NumPacketRecv[3] };
assign DebugData[5]   = { fifo_underflow_bits, fifo_active_bits };
assign DebugData[6]   = { fifo_full_bits, fifo_empty_bits };
assign DebugData[7]   = { NumCrcErrorIn[3], NumCrcErrorIn[2], NumCrcErrorIn[1], NumCrcErrorIn[0] };
assign DebugData[8]   = { NumCrcErrorOut[3], NumCrcErrorOut[2], NumCrcErrorOut[1], NumCrcErrorOut[0] };
assign DebugData[9]   = { TxInfoReg[3], TxInfoReg[2], TxInfoReg[1], TxInfoReg[0] };
assign DebugData[10]  = MacAddrHost[0][47:16];
assign DebugData[11]  = MacAddrHost[1][47:16];
assign DebugData[12]  = { packet_truncated_bits, packet_dropped_bits };
assign DebugData[13]  = { NumIPv4ErrorIn[3], NumIPv4ErrorIn[2], NumIPv4ErrorIn[1], NumIPv4ErrorIn[0] };
assign DebugData[14]  = { NumPacketFwd[0][3], NumPacketFwd[0][2], NumPacketFwd[0][1], NumPacketFwd[0][0] };
assign DebugData[15]  = { fifo_info_not_empty_bits, data_avail_bits };

// Debug data: 4090-40bf (currently, only 40a0-40af used)
assign reg_rdata = (reg_raddr[11:4] == 8'h0a) ? DebugData[reg_raddr[3:0]] : 32'd0;
`else
assign reg_rdata = 32'd0;
`endif

endmodule
