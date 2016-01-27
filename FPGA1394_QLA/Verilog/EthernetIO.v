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

    // KSZ8851 interrupt
    input wire ETH_IRQn,          // interrupt request

    // Debugging
    input wire receiveEnabled,
    output reg quadRead,
    output reg quadWrite,

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
reg[5:0] state;
reg[5:0] nextState;
   
// state machine states
parameter[5:0]
    ST_IDLE = 6'd0,
    ST_WAIT_ACK = 6'd1,
    ST_WAIT_ACK_CLEAR = 6'd2,
    ST_INIT_CHECK_CHIPID = 6'd3,      // Read chip ID
    ST_INIT_WRITE_MAC_LOW = 6'd4,     // Write MAC address low
    ST_INIT_WRITE_MAC_MID = 6'd5,     // Write MAC address middle
    ST_INIT_WRITE_MAC_HIGH = 6'd6,    // Write MAC address high
    ST_INIT_REG_84 = 6'd7,
    ST_INIT_REG_70 = 6'd8,
    ST_INIT_REG_86 = 6'd9,
    ST_INIT_REG_9C = 6'd10,
    ST_INIT_REG_74 = 6'd11,
    ST_INIT_REG_82 = 6'd12,
    ST_INIT_IRQ_CLEAR = 6'd13,
    ST_INIT_IRQ_ENABLE = 6'd14,
    ST_INIT_TRANSMIT_ENABLE_READ = 6'd15,
    ST_INIT_TRANSMIT_ENABLE_WRITE = 6'd16,
    ST_INIT_RECEIVE_ENABLE_READ = 6'd17,
    ST_INIT_RECEIVE_ENABLE_WRITE = 6'd18,
    ST_INIT_DONE = 6'd19,
    ST_RECEIVE_CLEAR_RXIS = 6'd20,
    ST_RECEIVE_FRAME_COUNT_START = 6'd21,
    ST_RECEIVE_FRAME_COUNT_END = 6'd22,
    ST_RECEIVE_FRAME_STATUS = 6'd23,
    ST_RECEIVE_FRAME_LENGTH = 6'd24,
    ST_RECEIVE_DMA_STATUS_READ = 6'd25,
    ST_RECEIVE_DMA_STATUS_WRITE = 6'd26,
    ST_RECEIVE_DMA_SKIP = 6'd27,
    ST_RECEIVE_DMA_FRAME_HEADER = 6'd28,
    ST_RECEIVE_FLUSH_START = 6'd29,
    ST_RECEIVE_FLUSH_EXECUTE = 6'd30,
    ST_RECEIVE_FLUSH_WAIT = 6'd31,
    ST_SEND_DMA_STATUS_READ = 6'd32,
    ST_SEND_DMA_STATUS_WRITE = 6'd33,
    ST_SEND_DMA_CONTROLWORD = 6'd34,
    ST_SEND_DMA_BYTECOUNT = 6'd35,
    ST_SEND_DMA_DESTADDR = 6'd36,
    ST_SEND_DMA_SRCADDR = 6'd37,
    ST_SEND_DMA_LENGTH = 6'd38,
    ST_SEND_DMA_PACKETDATA = 6'd39,
    ST_SEND_DMA_STOP_READ = 6'd40,
    ST_SEND_DMA_STOP_WRITE = 6'd41,
    ST_SEND_TXQ_ENQUEUE_START = 6'd42,
    ST_SEND_TXQ_ENQUEUE_END = 6'd43;

reg[7:0] FrameCount;   // Number of received frames
reg[2:0] count;        // General use counter

reg[15:0] FrameHeader[1:7];
wire[15:0] destMac[0:2];
wire[15:0] srcMac[0:2];
wire [15:0] Length;
assign destMac[0] = FrameHeader[1];
assign destMac[1] = FrameHeader[2];
assign destMac[2] = FrameHeader[3];
assign srcMac[0]  = FrameHeader[4];
assign srcMac[1]  = FrameHeader[5];
assign srcMac[2]  = FrameHeader[6];
assign Length     = FrameHeader[7];
              
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
       quadRead <= 0;
       quadWrite <= 0;
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
            else if (~ETH_IRQn && receiveEnabled) begin
               cmdReq <= 1;
               isDMA <= 0;
               isWrite <= 0;
               isWord <= 1;
               RegAddr <= 8'h92;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_CLEAR_RXIS;
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
         
         //*************** States for initializing Ethernet ******************

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
            // Enable QMU receive frame data pointer auto increment and decrease write data
            // valid sample time to 4 nS (max).
            WriteData <= 16'h5000;
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
            WriteData <= 16'h0020;   // Enable QMU frame count threshold (1), no auto-dequeue
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

         //*************** States for receiving Ethernet packets ******************

         ST_RECEIVE_CLEAR_RXIS:
         begin
            if (readValid) begin
               if (ReadData[13]) begin   // RXIS asserted
                  cmdReq <= 1;
                  isWrite <= 1;
                  WriteData <= {ReadData[15:14],1'b1,ReadData[12:0]};
                  state <= ST_WAIT_ACK;
                  nextState <= ST_RECEIVE_FRAME_COUNT_START;
               end
               else begin
                  state <= ST_IDLE;
               end
            end
         end // case: ST_RECEIVE_CLEAR_RXIS

         ST_RECEIVE_FRAME_COUNT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h9C;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FRAME_COUNT_END;
         end

         ST_RECEIVE_FRAME_COUNT_END:
         begin
            if (readValid) begin
               FrameCount <= ReadData[15:8];
               cmdReq <= 1;
               RegAddr <= 8'h7C;
               state <= ST_WAIT_ACK;
               nextState <= (ReadData[15:8] != 0) ? ST_RECEIVE_FRAME_STATUS : ST_IDLE;
            end
         end

         ST_RECEIVE_FRAME_STATUS:
         begin
            if (readValid) begin
               FrameCount <= FrameCount-1;
               if (ReadData[15]) begin // if valid
                  cmdReq <= 1;
                  isWrite <= 0;
                  RegAddr <= 8'h7E;
                  state <= ST_WAIT_ACK;
                  nextState <= ST_RECEIVE_FRAME_LENGTH;
               end
               else begin
                  state <= ST_RECEIVE_FLUSH_START;
               end
            end
         end

         ST_RECEIVE_FRAME_LENGTH:
         begin
            if (readValid) begin
               // Probably don't need the following
               // PacketWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
               // Set QMU RXQ frame pointer to 0
               cmdReq <= 1;
               isWrite <= 1;
               RegAddr <= 8'h86;
               WriteData <= 16'h5000;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_DMA_STATUS_READ;
            end
         end
         
         ST_RECEIVE_DMA_STATUS_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_STATUS_WRITE;
         end

         ST_RECEIVE_DMA_STATUS_WRITE:
         begin
            if (readValid) begin
               // Enable DMA transfers
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:4],1'b1,ReadData[2:0]};
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_DMA_SKIP;
               count <= 0;
            end
         end

         ST_RECEIVE_DMA_SKIP:
         begin
            // Skip first 3 words in the packet (ignore, status, byte-count)
            cmdReq <= 1;
            isDMA <= 1;
            isWrite <= 0;
            state <= ST_WAIT_ACK;
            if (count == 2) begin
               nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
               count <= 0;
            end
            else begin
               nextState <= ST_RECEIVE_DMA_SKIP;
               count <= count+1;
            end
         end

         ST_RECEIVE_DMA_FRAME_HEADER:
         begin
            // Read dest MAC, source MAC, and length (7 words)
            if (readValid && (count != 0)) begin
               FrameHeader[count] <= ReadData;
            end
            if (count == 7) begin
               if (Length == 16) begin
                  //state <= ST_RECEIVE_DMA_QUADLET_READ_REQ;
                  state <= ST_RECEIVE_FLUSH_START;
                  quadRead <= ~quadRead;
               end
               else if (Length == 20) begin
                  // state <= ST_RECEIVE_DMA_QUADLET_WRITE;
                  state <= ST_RECEIVE_FLUSH_START;
                  quadWrite <= ~quadWrite;
               end
               else begin
                  state <= ST_RECEIVE_FLUSH_START;
                  quadWrite <= ~quadWrite;  // PK TEMP
               end
               count <= 0;
            end
            else begin
               cmdReq <= 1;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
               count <= count+1;
            end
         end // case: ST_RECEIVE_DMA_FRAME_HEADER

         ST_RECEIVE_FLUSH_START:
         begin
            cmdReq <= 1;
            isDMA <= 0;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_EXECUTE;
         end

         ST_RECEIVE_FLUSH_EXECUTE:
         begin
            if (readValid) begin
               // Flush the rest of the packet (also clears DMA bit)
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:4],1'b0,ReadData[2:1],1'b1};
               state <= ST_WAIT_ACK;
               //nextState <= ST_RECEIVE_FLUSH_WAIT;
               nextState <= (FrameCount == 0) ? ST_IDLE : ST_RECEIVE_FRAME_STATUS;
               //nextState <= (FrameCount == 0) ? ST_SEND_DMA_STATUS_READ : ST_RECEIVE_FRAME_STATUS;
            end
         end

         ST_RECEIVE_FLUSH_WAIT:
         begin
            // Wait for bit 0 in Register 0x82 to be cleared
            if (readValid && !ReadData[0]) begin
               state <= (FrameCount == 0) ? ST_IDLE : ST_RECEIVE_FRAME_STATUS;
            end
            else begin
               cmdReq <= 1;
               isWrite <= 0;
               // RegAddr is already set to 8'h82
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_FLUSH_WAIT;
            end
         end

         //*************** States for sending Ethernet packets ******************
         // First, should check if enough memory on QMU TXQ

         ST_SEND_DMA_STATUS_READ:  // same as ST_RECEIVE_DMA_STATUS_READ
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_STATUS_WRITE;
         end

         ST_SEND_DMA_STATUS_WRITE:  // same as ST_RECEIVE_DMA_STATUS_WRITE
         begin
            if (readValid) begin
               // Enable DMA transfers
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:4],1'b1,ReadData[2:0]};
               state <= ST_WAIT_ACK;
               nextState <= ST_SEND_DMA_CONTROLWORD;
            end
         end

         ST_SEND_DMA_CONTROLWORD:
         begin
            cmdReq <= 1;
            WriteData <= 16'h0;  // Control word = 0
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_BYTECOUNT;
         end

         ST_SEND_DMA_BYTECOUNT:
         begin
            cmdReq <= 1;
            WriteData <= 16'd34;  // Byte count = 34 (14+20), quadlet
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_DESTADDR;
            count <= 0;
         end

         ST_SEND_DMA_DESTADDR:
         begin
            cmdReq <= 1;
            WriteData <= srcMac[count];
            state <= ST_WAIT_ACK;
            if (count == 2) begin
               nextState <= ST_SEND_DMA_SRCADDR;
               count <= 0;
            end
            else begin
               nextState <= ST_SEND_DMA_DESTADDR;
               count <= count+1;
            end
         end

         ST_SEND_DMA_SRCADDR:
           begin
            // Rather than using destAddr from last received packet,
            // use our own MAC addr.
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            if (count == 0) begin
               WriteData <= 16'hFA61;    // 0xFA61
               nextState <= ST_SEND_DMA_SRCADDR;
               count <= 1;
            end
            else if (count == 1) begin
               WriteData <= 16'h0E13;    // 0x0E13
               nextState <= ST_SEND_DMA_SRCADDR;
               count <= 2;
            end
            else if (count == 2) begin
               WriteData <= 16'h9400;    // 0x94ff (nn = board id, 0 for now)
               nextState <= ST_SEND_DMA_LENGTH;
               count <= 2;
            end
         end

         ST_SEND_DMA_LENGTH:
         begin
            cmdReq <= 1;
            WriteData <= 16'd20;  // 20 bytes for quadlet read/write
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_PACKETDATA;
            count <= 0;
         end

         ST_SEND_DMA_PACKETDATA:
         begin
            cmdReq <= 1;
            if (count == 6) WriteData <= 16'h1234;
            if (count == 7) WriteData <= 16'h5678;
            else WriteData <= { 13'h0, count };
            state <= ST_WAIT_ACK;
            nextState <= (count == 9) ? ST_SEND_DMA_STOP_READ : ST_SEND_DMA_PACKETDATA;
            count <= count+1;
         end

         ST_SEND_DMA_STOP_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_STOP_WRITE;
         end

         ST_SEND_DMA_STOP_WRITE:
         begin
            if (readValid) begin
               // Disable DMA transfers
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:4],1'b0,ReadData[2:0]};
               state <= ST_WAIT_ACK;
               nextState <= ST_SEND_TXQ_ENQUEUE_START;
            end
         end

         ST_SEND_TXQ_ENQUEUE_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h80;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_TXQ_ENQUEUE_END;
         end

         ST_SEND_TXQ_ENQUEUE_END:
         begin
            if (readValid) begin
               cmdReq <= 1;
               isWrite <= 1;
               WriteData <= {ReadData[15:1],1'b1};
               state <= ST_WAIT_ACK;
               nextState <= ST_IDLE;
            end
         end

         endcase // case (state)
    end
end

endmodule
