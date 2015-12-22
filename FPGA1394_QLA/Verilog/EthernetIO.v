/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2015 ERC CISST, Johns Hopkins University.
 *
 * This module implements the higher-level Ethernet I/O, which interfaces
 * to the KSZ8851 MAC/PHY chip.
 *
 * Revision history
 *     12/21/15    Peter Kazanzides
 */

module EthernetIO(
    // global clock and reset
    input      sysclk,
    input      reset,

    // Interface to lower layer (KSZ8851)
    input wire initReq,           // 1 -> Chip has been reset; initialization requested
    output reg initAck,           // 1 -> Acknowledge (clear) initReq
    output reg cmdReq,            // 1 -> higher-level requesting a command
    input wire cmdAck,            // 1 -> command accepted (can request next command)
    input wire readValid,         // 1 -> ReadData is valid
    output reg isDMA,             // 1 -> DMA mode active
    output reg isWrite,           // 0 -> Read, 1 -> Write
    output reg isWord,            // 0 -> Byte, 1 -> Word
    output reg[7:0] RegAddr,      // Register address (N/A for DMA mode)
    output reg[15:0] WriteData,   // Data to be written to chip (N/A for read)
    input wire[15:0] ReadData,    // Data read from chip (N/A for write)
    output reg initOK             // 1 -> Initialization successful
);

// Current state and next state
reg[4:0] state;
reg[4:0] nextState;
   
// state machine states
parameter[4:0]
    ST_IDLE = 5'd0,
    ST_WAIT_ACK = 5'd1,
    ST_WAIT_ACK_CLEAR = 5'd2,
    ST_INIT_CHECK_CHIPID = 5'd3,      // Read chip ID
    ST_INIT_WRITE_MAC_LOW = 5'd4,     // Write MAC address low
    ST_INIT_WRITE_MAC_MID = 5'd5,     // Write MAC address middle   
    ST_INIT_WRITE_MAC_HIGH = 5'd6,    // Write MAC address high
    ST_INIT_REG_84 = 5'd7,
    ST_INIT_REG_70 = 5'd8,
    ST_INIT_REG_86 = 5'd9,
    ST_INIT_REG_9C = 5'd10,
    ST_INIT_REG_74 = 5'd11,
    ST_INIT_REG_82 = 5'd12,
    ST_INIT_IRQ_CLEAR = 5'd13,
    ST_INIT_IRQ_ENABLE = 5'd14,
    ST_INIT_TRANSMIT_ENABLE_READ = 5'd15,
    ST_INIT_TRANSMIT_ENABLE_WRITE = 5'd16,
    ST_INIT_RECEIVE_ENABLE_READ = 5'd17,
    ST_INIT_RECEIVE_ENABLE_WRITE = 5'd18,
    ST_INIT_DONE = 5'd19;

              
always @(posedge sysclk or negedge reset) begin
    if (reset == 0) begin
       cmdReq <= 0;
       isDMA <= 0;
       isWrite <= 0;
       isWord <= 1;   // all transfers are word
       state <= ST_IDLE;
       nextState <= ST_IDLE;
       initAck <= 0;
       initOK <= 0;
    end
    else begin

       case (state)

         ST_IDLE:
         begin
            if (initReq) begin
               cmdReq <= 1;
               isDMA <= 0;
               isWrite <= 0;
               isWord <= 1;       // all transfers are word
               RegAddr <= 8'hC0;  // Read Chip ID
               state <= ST_WAIT_ACK;
               nextState <= ST_INIT_CHECK_CHIPID;
               initAck <= 1;
               initOK <= 0;
            end
         end

         ST_WAIT_ACK:
         begin
            if (cmdAck) begin
               cmdReq <= 0;
               state <= ST_WAIT_ACK_CLEAR;
               end
         end

         ST_WAIT_ACK_CLEAR:
         begin
            if (~cmdAck) state <= nextState;
         end
         
         ST_INIT_CHECK_CHIPID:
         begin
            initAck <= 0;   // By now, it is fine to finish acknowledgement of init request
            if (readValid) begin
               if (ReadData[15:4] == 12'h887) begin
                  // Chip ID is ok, go to next state
                  // (could have started next state here, but code would be less readable)
                  state <= ST_INIT_WRITE_MAC_LOW;
               end
               else begin
                  initOK <= 0;
                  state <= ST_IDLE;
               end
            end
         end
         
         ST_INIT_WRITE_MAC_LOW:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= 8'h10;       // MAC address low
            WriteData <= 16'h9400;  //   0x94nn (nn = board id, 0 for now)
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_WRITE_MAC_MID;
         end

         ST_INIT_WRITE_MAC_MID:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h12;       // MAC address mid
            WriteData <= 16'h0E13;  //   0x0E13
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_WRITE_MAC_HIGH;
         end
         
         ST_INIT_WRITE_MAC_HIGH:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h14;       // MAC address high
            WriteData <= 16'hFA61;  //   0xFA61
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_84;
         end
              
         ST_INIT_REG_84:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h84;
            WriteData <= 16'h4000;   // Enable QMU transmit frame data pointer auto increment
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_70;
         end

         ST_INIT_REG_70:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h70;
            WriteData <= 16'h01EE;   // Enable QMU transmit flow control, CRC, and padding
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_86;
         end

         ST_INIT_REG_86:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h86;
            WriteData <= 16'h4000;   // Enable QMU receive frame data pointer auto increment
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_9C;
         end

         ST_INIT_REG_9C:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h9C;
            WriteData <= 16'h0001;   // Configure receive frame threshold for 1 frame
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_74;
         end

         ST_INIT_REG_74:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h74;
            // 7: enable UDP, TCP, and IP checksums
            // C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
            // E: enable broadcast, multicast, and unicast
            // Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
            WriteData <= 16'h7CE0;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_82;
         end

         ST_INIT_REG_82:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h82;
            WriteData <= 16'h0030;   // Enable QMU frame count threshold (1) and auto-dequeue
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_IRQ_CLEAR;
         end

         ST_INIT_IRQ_CLEAR:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h92;
            WriteData <= 16'hFFFF;   // Clear all pending interrupts
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_IRQ_ENABLE;
         end

         ST_INIT_IRQ_ENABLE:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h90;
            WriteData <= 16'h2000;   // Enable receive interrupts (TODO: also consider link change interrupt)
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_TRANSMIT_ENABLE_READ;
         end

         ST_INIT_TRANSMIT_ENABLE_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h70;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_TRANSMIT_ENABLE_WRITE;
         end

         ST_INIT_TRANSMIT_ENABLE_WRITE:
         begin
            if (readValid) begin
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:1],1'b1};
               state <= ST_WAIT_ACK;
               nextState <= ST_INIT_RECEIVE_ENABLE_READ;
            end
         end

         ST_INIT_RECEIVE_ENABLE_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h74;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_RECEIVE_ENABLE_WRITE;
         end

         ST_INIT_RECEIVE_ENABLE_WRITE:
         begin
            if (readValid) begin
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:1],1'b1};
               state <= ST_WAIT_ACK;
               nextState <= ST_INIT_DONE;
            end
         end

         ST_INIT_DONE:
         begin
            initOK <= 1;
            state <= ST_IDLE;
         end
          
         endcase // case (state)
    end
end

endmodule
