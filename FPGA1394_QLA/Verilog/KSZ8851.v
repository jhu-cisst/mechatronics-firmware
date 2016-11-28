/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2016 ERC CISST, Johns Hopkins University.
 *
 * This module is the interface to the KSZ8851-16mll Ethernet MAC/PHY chip.
 * Note that 0.05s is needed to warm up the device before any IO operation.
 *
 * Revision history
 *     08/14/14    Long Qian (as Initialization.v and RegIO.v)
 *     11/06/15    Peter Kazanzides
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
    output reg ETH_CMD,   // 0 for data, 1 for address
    output reg ETH_RDn,   // read strobe (active low)
    output reg ETH_WRn,   // write strobe (active low)
    inout[15:0] SD,       // address/data bus
    input wire ETH_IRQn,  // interrupt request
    input wire ETH_PME,   // power management event

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

    output reg sendReq,
    input wire sendAck,
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

// Address translator
wire[15:0] Addr16;
getAddr newAddr(
    .offset(eth_addr),
    .length(eth_isWord),
    .Addr(Addr16)
);

reg[3:0] state;
reg[20:0] count;

assign dbg_state = state;

// state machine states
parameter[3:0]
    ST_IDLE = 4'd0,
    ST_RESET_ASSERT = 4'd1,    // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 4'd2,      // wait after bringing reset high -- 50 msec
    ST_ADDR_START = 4'd3,
    ST_ADDR_HOLD = 4'd4,
    ST_ADDR_END = 4'd5,
    ST_READ_START = 4'd6,
    ST_READ_HOLD = 4'd7,
    ST_READ_END = 4'd8,
    ST_WRITE_START = 4'd9,
    ST_WRITE_HOLD = 4'd10,
    ST_WRITE_END = 4'd11;

assign ksz_isIdle = (state == ST_IDLE) ? 1 : 0;

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
        sendReq <= 0;
        eth_error <= 0;
    end
    else begin

        // Format of 32-bit reg_wdata:
        // 0(4) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
        if (eth_reg_wen) begin
            if (reg_wdata[26]) begin   // if reset
                count <= 21'd0;        // Clear counter
                state <= ST_RESET_ASSERT;
                initReq <= 0;
                cmdAck <= 0;
                dataValid <= 0;
                sendReq <= 0;
                eth_error <= 0;
            end
            else if (state == ST_IDLE) begin
                eth_isWord <= reg_wdata[24];
                eth_addr <= reg_wdata[23:16];
                eth_data <= reg_wdata[15:0];
                eth_error <= 0;
                eth_isWrite <= reg_wdata[25];
                // If DMA bit (reg_wdata[27]) is set, next state is either ST_WRITE_START or ST_READ_START;
                // otherwise, starting state is ST_ADDR_START
                state <= (reg_wdata[27] ? (reg_wdata[25] ? ST_WRITE_START : ST_READ_START) : ST_ADDR_START);
                ETH_CMD <= reg_wdata[27] ? 1'd0 : 1'd1;
            end
            else begin
                eth_error <= 1;
            end
        end

        // Remove cmdAck when cmdReq is negated; also negate dataValid (used for read command)
        if (cmdAck && !cmdReq) begin
            cmdAck <= 0;
            dataValid <= 0;
        end

        // Clear the initReq flag
        if (initAck) initReq <= 0;

        // Clear the sendReq flag
        if (sendAck) sendReq <= 0;

        case (state)

        ST_IDLE:
        begin
            if (cmdReq && !eth_reg_wen) begin
                eth_isWrite <= isWrite;
                eth_isWord <= isWord;
                eth_addr <= RegAddr;
                eth_data <= DataIn;
//                state <= (isDMA ? (isWrite ? ST_WRITE_START : ST_READ_START) : ST_ADDR_START);
                if (isDMA && isWrite) begin
                    state <= ST_WRITE_START;
                end 
                else if (isDMA && !isWrite) begin
                    state <= ST_READ_START;
//                    ETH_RDn <= 0;
                end
                else begin
                    state <= ST_ADDR_START;
//                    SDReg <= Addr16;
                end
               
                ETH_CMD <= isDMA ? 1'd0 : 1'd1;
                cmdAck <= 1;
                count <= 21'd0;
            end
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
                ETH_WRn <= 1;
                ETH_RDn <= 1;
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

        ST_ADDR_START:
        begin
            if (count[0] == 1'd0) begin
               ETH_CMD <= 1;
               SDReg <= Addr16;
               count[0] <= 1'd1;
            end
            else begin
               ETH_WRn <= 0;
               state <= ST_ADDR_HOLD;
               count[0] <= 1'd0;
            end
        end

        ST_ADDR_HOLD:
        begin
            if (count[0] == 1'd0)
                count[0] <= 1'd1;
            else begin
                state <= ST_ADDR_END;
                count[0] <= 1'd0;
            end
        end

        ST_ADDR_END:
        begin
            if (count[0] == 1'd0) begin
                ETH_WRn <= 1;
                count[0] <= 1'd1;
            end
            else begin
                ETH_CMD <= 0;
//                state <= eth_isWrite ? ST_WRITE_START : ST_READ_START;
                if (eth_isWrite) begin
                    state <= ST_WRITE_START;
                end 
                else begin
                    state <= ST_READ_START;
                end
                count[0] <= 1'd0;
            end
        end

        ST_WRITE_START:
        begin
           if (count[0] == 1'd0) begin
              ETH_CMD <= 0;
              SDReg <= eth_data;
              count[0] <= 1'd1;
           end
           else begin
              ETH_WRn <= 0;
              state <= ST_WRITE_HOLD;
              count[0] <= 1'd0;
           end
        end

        ST_WRITE_HOLD:
//        begin
//           state <= ST_WRITE_END;
//           
//        end
        begin
            if (count[0] == 1'd0)
                count[0] <= 1'd1;
            else begin
                state <= ST_WRITE_END;
                count[0] <= 1'd0;
            end
        end

        ST_WRITE_END:
        begin
            ETH_WRn <= 1;
            state <= ST_IDLE;
        end

        ST_READ_START:
        begin
            state <= ST_READ_HOLD;
            ETH_RDn <= 0;
            count[0] <= 1'd0;
        end

        ST_READ_HOLD:
        begin
           if (count[0] == 1'd0) begin
               count[0] <= 1'd1;
           end
           else begin
               state <= ST_READ_END;
               count[0] <= 1'd0;
           end
        end

        ST_READ_END:
        begin
            if (count[0] == 1'd0) begin
                eth_data <= SD;
                DataOut <= SD;
                count[0] <= 1'd1;
                // Set the dataValid signal here. The higher-level
                // should wait one cycle to be sure that the data
                // has propagated through the latch.
                // An alternate design would be to set dataValid
                // in the else clause below.
                dataValid <= 1;
            end
            else begin 
                ETH_RDn <= 1;
                state <= ST_IDLE;
                count[0] <= 1'd0;
            end                       
        end

        endcase
    end
end

endmodule
