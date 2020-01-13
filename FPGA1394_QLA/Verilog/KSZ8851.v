/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2020 ERC CISST, Johns Hopkins University.
 *
 * This module is the interface to the KSZ8851-16mll Ethernet MAC/PHY chip.
 * Note that 0.05s is needed to warm up the device before any IO operation.
 *
 * Revision history
 *     08/14/14    Long Qian (as Initialization.v and RegIO.v)
 *     11/06/15    Peter Kazanzides
 *      1/12/20    Peter Kazanzides - changed from state machine to shift registers
 */

`include "Constants.v"

// --------------------------------------------------------------------------
// Register Address Translator: from 8-bit offset to 16-bit address required by KSZ8851.
// The addressing is a bit unusual when the KSZ8851 is configured with a 16-bit bus;
// specifically, it appears to split the I/O space into 32-bit chunks. The 4 ByteEnable
// lines can select any one or two 8-bit registers from this 32-bit chunk. For an
// 8-bit transfer, only one ByteEnable should be set. For a 16-bit transfer, the most
// typical scenario would be to select the first two bytes (ByteEnable=4'b0011) or
// the last two bytes (ByteEnable=4'b1100).
// --------------------------------------------------------------------------
module getAddr(
    input wire[7:0] offset,     // register address (0x00-0xFF)
    input wire length,          // length: 0-byte(8-bit), 1-word(16-bit)
    output wire[15:0] Addr      // address recognized by ksz8851 (on SD lines)
    );
    
    // the rule of translation is available in the step-by-step guide of ksz8851-16mll
    wire[1:0] offsetTail;
    assign offsetTail = offset[1:0];

    // SD[15:12]  are for BE[3:0] (BE = Byte Enable)
    // The following code does not handle 16-bit transfers for odd addresses (i.e.,
    // if offsetTail is 1 or 3).
    //   BE[0]=1 if address is multiple of 4 (0x00, 0x04, 0x08, ...)
    //   BE[1]=1 if 16-bit access and multiple of 4 OR 8-bit access and odd (0x01, 0x03, ...)
    //   BE[2]=1 if address has 2 (0x02, 0x06, 0x0A, ...)
    //   BE[3]=1 if 16-bit access and has 2 OR 8-bit access and has 3
    assign Addr[12] = (offsetTail==0) ? 1'b1 : 1'b0;
    assign Addr[13] = ((~length && offsetTail==1) || (length && offsetTail==0)) ? 1'b1 : 1'b0;
    assign Addr[14] = (offsetTail==2) ? 1'b1 : 1'b0;
    assign Addr[15] = ((~length && offsetTail==3) || (length && offsetTail==2)) ? 1'b1 : 1'b0;  
    assign Addr[7:2] = offset[7:2];
    
    assign Addr[1:0] = offsetTail;  // not necessary, for better integrity
    assign Addr[11:8] = 4'h0;       // not necessary, for better integrity
    
endmodule

module KSZ8851(
    // Global clock and reset
    input      sysclk,
    input      reset,

    // Interface to KSZ8851
    output reg ETH_RSTn,  // chip reset (active low)
    output wire ETH_CMD,  // 0 for data, 1 for address
    output wire ETH_RDn,  // read strobe (active low)
    output wire ETH_WRn,  // write strobe (active low)
    inout[15:0] SD,       // address/data bus

    // Interface to/from higher level (EthernetIO.v)
    output reg initReq,           // 1 -> Chip has been reset; higher-level initialization requested
    input wire initAck,           // 1 -> Acknowledgement from higher layer that initialization has begun
    input wire cmdReq,            // 1 -> higher-level requesting a command
    output reg cmdAck,            // 1 -> command accepted (can request next command)
    output reg dataValid,         // 1 -> DataOut is valid
    input wire isDMA,             // 1 -> DMA mode active
    input wire isWrite,           // 0 -> Read, 1 -> Write
    input wire isWord,            // 0 -> Byte, 1 -> Word
    input wire[7:0] RegAddr,      // Register address (N/A for DMA mode)
    input wire[15:0] DataIn,      // Data to be written to chip (N/A for read)
    output reg[15:0] DataOut,     // Data read from chip (N/A for write)
    output reg eth_error,         // 1 -> I/O request received when not in idle state
    output wire ksz_isIdle,

    // Interface from FireWire
    input  wire reg_wen,          // write enable
    input  wire[15:0] reg_waddr,  // write address
    input  wire[31:0] reg_wdata,  // write data
    output reg[15:0]  eth_data,   // Data to/from KSZ8851
    
    // Interface to Chipscope icon
    output wire[3:0] dbg_state    // debug state 
);

// tri-state bus configuration
// Drive bus except when ETH_RDn is active (low)
reg[15:0] SDReg;
assign SD = ETH_RDn ? SDReg : 16'hz;

// address decode for KSZ8851 I/O access
wire   eth_reg_wen;
assign eth_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHRES}) ? reg_wen : 1'b0;

// Following registers hold address/data for requested register reads/writes
// (note: eth_data is declared above, as parameter)
reg[7:0]  eth_addr;     // I/O register address (0-0xFF)
reg       eth_isWord;   // Data length (0->byte, 1->word)
reg       eth_isWrite;  // Write (1) or Read (0)

// Address translator from EthernetIO.v
wire[15:0] Addr16;
getAddr newAddr(
    .offset(RegAddr),
    .length(isWord),
    .Addr(Addr16)
);   

// Address translator for request from FireWire
// Format of 32-bit reg_wdata:
// 0(4) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
// bit 27: DMA
// bit 26: reset
// bit 25: R/W Read or Write
// bit 24: W/B Word or Byte
// bit 23-16: 8-bit address
// bit 15-0 : 16-bit data
wire [15:0] Addr16FW;
getAddr newAddrFW
(
   .offset(reg_wdata[23:16]),
   .length(reg_wdata[24]),
   .Addr(Addr16FW)
);

reg[1:0] state;
reg[20:0] count;

assign dbg_state = state;

// state machine states
parameter[1:0]
    ST_IDLE = 2'd0,
    ST_RESET_ASSERT = 2'd1,     // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 2'd2,       // wait after bringing reset high -- 50 msec
    ST_WAVEFORM_OUTPUT = 2'd3;  // generate read/write waveforms

assign ksz_isIdle = (state == ST_IDLE) ? 1'b1 : 1'b0;

// Following are for generating waveforms for WRn, RDn and CMD
localparam[9:0]
   Init_WRn      = 10'b1111111111,
   Init_RDn      = 10'b1111111111,
   Init_CMD      = 10'b0000000000,
   Read_WRn      = 10'b1001111111,    // all 10 bits
   Read_RDn      = 10'b1111100001,
   Read_CMD      = 10'b1111000000,
   Write_WRn     = 10'b1001100111,    // first 8 bits
   Write_RDn     = 10'b1111111111,
   Write_CMD     = 10'b1111000000,
   DMA_Read_WRn  = 10'b1111111111,    // first 5 bits
   DMA_Read_RDn  = 10'b0000111111,
   DMA_Read_CMD  = 10'b0000000000,
   DMA_Write_WRn = 10'b1001111111,    // first 4 bits
   DMA_Write_RDn = 10'b1111111111,
   DMA_Write_CMD = 10'b0000000000;

reg[9:0] Cur_WRn;
reg[9:0] Cur_RDn;
reg[9:0] Cur_CMD;
reg[3:0] ShiftCnt;

assign ETH_WRn = Cur_WRn[9];
assign ETH_RDn = Cur_RDn[9];
assign ETH_CMD = Cur_CMD[9];

// KSZ8851 timing:
//    RDn, WRn pulses must be kept low for 40 ns (min)
//    RDn to read data valid is 32 ns (max)
always @(posedge sysclk or negedge reset) begin
    if (reset == 0) begin
        count <= 21'd0;            // Clear counter
        state <= ST_RESET_ASSERT;
        initReq <= 0;
        cmdAck <= 0;
        dataValid <= 0;
        eth_error <= 0;
        Cur_WRn <= Init_WRn;
        Cur_RDn <= Init_RDn;
        Cur_CMD <= Init_CMD;
        ShiftCnt <= 4'd0;
    end
    else begin

        // Format of 32-bit reg_wdata:
        // 0(4) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
        // bit 27: DMA
        // bit 26: reset 
        // bit 25: R/W Read (0) or Write (1)
        // bit 24: W/B Word or Byte
        // bit 23-16: 8-bit address
        // bit 15-0 : 16-bit data
        if (eth_reg_wen) begin
            if (reg_wdata[26]) begin   // if reset
                count <= 21'd0;        // Clear counter
                state <= ST_RESET_ASSERT;
                initReq <= 0;
                cmdAck <= 0;
                dataValid <= 0;
                eth_error <= 0;
            end
            else if (state == ST_IDLE) begin
               eth_isWrite <= reg_wdata[25];
               eth_isWord <= reg_wdata[24];
               eth_addr <= reg_wdata[23:16];
               eth_data <= reg_wdata[15:0];
               eth_error <= 0;

               if (reg_wdata[27]) begin   // reg_wdata[27] --> isDMA
                  // reg_wdata[25] --> isWrite
                  ShiftCnt <= reg_wdata[25] ? 4'd3 : 4'd4;
                  Cur_WRn <= reg_wdata[25] ? DMA_Write_WRn : DMA_Read_WRn;
                  Cur_RDn <= reg_wdata[25] ? DMA_Write_RDn : DMA_Read_RDn;
                  Cur_CMD <= reg_wdata[25] ? DMA_Write_CMD : DMA_Read_CMD;
                  if (reg_wdata[25]) SDReg <= reg_wdata[15:0];
               end
               else begin
                  // reg_wdata[25] --> isWrite
                  ShiftCnt <= reg_wdata[25] ? 4'd7 : 4'd9;
                  Cur_WRn <= reg_wdata[25] ? Write_WRn : Read_WRn;
                  Cur_RDn <= reg_wdata[25] ? Write_RDn : Read_RDn;
                  Cur_CMD <= reg_wdata[25] ? Write_CMD : Read_CMD;
                  SDReg <= Addr16FW;
               end

               count <= 21'd0;
               state <= ST_WAVEFORM_OUTPUT;
            end
            else begin
                eth_error <= 1;
            end
        end

        // Remove cmdAck when cmdReq is negated; 
        // also negate dataValid (used for read command)
        if (cmdAck && !cmdReq) begin
            cmdAck <= 0;
            dataValid <= 0;
        end

        // Clear the initReq flag
        if (initAck) initReq <= 0;

        case (state)
        ST_IDLE:
        begin
            if (cmdReq && !eth_reg_wen) begin
                eth_isWrite <= isWrite;
                eth_isWord <= isWord;
                eth_addr <= RegAddr;
                eth_data <= DataIn;
                if (isDMA) begin
                   ShiftCnt <= isWrite ? 4'd3 : 4'd4;
                   Cur_WRn <= isWrite ? DMA_Write_WRn : DMA_Read_WRn;
                   Cur_RDn <= isWrite ? DMA_Write_RDn : DMA_Read_RDn;
                   Cur_CMD <= isWrite ? DMA_Write_CMD : DMA_Read_CMD;
                   if (isWrite) SDReg <= DataIn;
                end 
                else begin
                   ShiftCnt <= isWrite ? 4'd7 : 4'd9;
                   Cur_WRn <= isWrite ? Write_WRn : Read_WRn;
                   Cur_RDn <= isWrite ? Write_RDn : Read_RDn;
                   Cur_CMD <= isWrite ? Write_CMD : Read_CMD;
                   SDReg <= Addr16;
                end
                cmdAck <= 1;
                count <= 21'd0;
                state <= ST_WAVEFORM_OUTPUT;
            end
        end

        ST_WAVEFORM_OUTPUT:
        begin
            if (ShiftCnt != 4'd0) begin
               Cur_WRn <= Cur_WRn << 1;
               Cur_RDn <= Cur_RDn << 1;
               Cur_CMD <= Cur_CMD << 1;
               ShiftCnt <= ShiftCnt - 4'd1;
               // If writing and CMD is going to transition low on
               // this cycle, then write to data bus
               if (isWrite && (Cur_CMD[9:8] == 2'b10)) begin
                  SDReg <= eth_data;
               end
               // If reading and RDn is going to transition high on
               // next cycle, then read from data bus
               else if (~isWrite && (Cur_RDn[8:7] == 2'b01)) begin
                  eth_data <= SD;
                  DataOut <= SD;
                  dataValid <= !isWrite;
               end
            end
            state <= (ShiftCnt == 4'd0) ? ST_IDLE : ST_WAVEFORM_OUTPUT;
        end

        // Assert the reset and wait 10 ms before removing it.
        ST_RESET_ASSERT:
        begin
            if (count == 21'd491520) begin  // 10 ms (49.152 MHz sysclk)
                ETH_RSTn <= 1;   // Remove the reset
                count <= 21'd0;
                state <= ST_RESET_WAIT;
            end
            else begin
                ETH_RSTn <= 0;
                Cur_WRn <= Init_WRn;
                Cur_RDn <= Init_RDn;
                count <= count + 21'd1;
            end
        end

        // The reset has ended, wait 50 ms before doing anything else
        ST_RESET_WAIT:
        begin
            if (count == 21'h1FFFFF) begin
                count <= 21'd0;
                state <= ST_IDLE;
                initReq <= 1;
            end
        else
            count <= count + 21'd1;
        end

        endcase
    end
end

endmodule
