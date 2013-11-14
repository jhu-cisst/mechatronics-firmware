/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2012-2013 ERC CISST, Johns Hopkins University.
 *
 * Module: QLA25AA128
 *
 * Purpose: Program the 25AA138 PROM on QLA board
 * 
 * NOTE: 
 *   - only supports byte read/write 
 *   - block read/write may be supported base on
 *   - 25AA128 address space (16-bit)
 *     - bit 15:12 == `ADDR_PROM_QLA 
 *     - bit 11:8 == 0: byte wise operation
 *         - 0x3000: quadlet command (write)
 *         - 0x3001: prom_status (read)
 *         - 0x3002: prom_result (read)
 *     - bit 11:8 == 1: block read/write 
 *         - since 1 page is 64 bytes, we only support 64 bytes read/write (16 quadlets)
 *         - 0x3100 to 0x310F  
 *   - Clock
 *     - 25AA128 Max 10 Mhz
 *     - sysclk 49.125 Mhz / 8 
 * 
 * Revision history
 *     12/31/12    Peter Kazanzides    Initial revision from M25P16
 *     10/24/13    Zihan Chen          Revised for 25AA128 SPI PROM
 */


// ---------------------------------------------------
// 25AA128 PROM SPI Command (Datasheet P7 Table 2-1)
// 

`include "Constants.v"

// ---------------------------------------------------
// 25AA128 PROM SPI Command (Datasheet P7 Table 2-1)
// 
`define CMD_READ_25AA128   8'h03    // Read
`define CMD_WRIT_25AA128   8'h02    // Write
`define CMD_WRDI_25AA128   8'h04    // Write Disable
`define CMD_WREN_25AA128   8'h06    // Write Enable
`define CMD_RDSR_25AA128   8'h05    // Read STATUS register
`define CMD_WRSR_25AA128   8'h01    // Write STATUS register
`define CMD_RBLK_25AA128   8'hFE    // Read Block 
`define CMD_WBLK_25AA128   8'hFF    // Write Block 
`define CMD_IDLE_25AA128   8'h00    // IDLE N/A cmd 

`define REG_PROM_CMD       12'h000  // prom command (write)
`define REG_PROM_STATUS    12'h001  // prom status (read)  
`define REG_PROM_RESULT    12'h002  // prom result (read)


module QLA25AA128(
    input  clk,                    // input clock
    input  reset,                  // global reset signal    

    input  wire[15:0] reg_raddr,   // read address
    input  wire[15:0] reg_waddr,   // write address
    output reg[31:0]  reg_rdata,   // register read data
    input  wire[31:0] reg_wdata,   // register write data 
    input  wire reg_wen,           // reg write enable
    input  wire blk_wen,           // block write enable
    input  wire blk_wstart,        // block write start

    // spi pins
    output prom_mosi,              // Serial out to 25AA128
    input  prom_miso,              // Serial in from 25AA128
    output prom_sclk,              // CLK to 25AA128
    output reg prom_cs             // /CS to 25AA128
);

// State machine
parameter ST_IDLE = 0,
          ST_CHIP_SELECT = 1,
          ST_WRITE = 2,
          ST_WRITE_BLOCK = 3,
          ST_READ = 4,
          ST_CHIP_DESELECT = 5,
          ST_IO_DISABLE = 6;


reg       io_disabled;
reg[2:0]  state;
reg[9:0]  seqn;            // 10-bit counter for sequencing operation (clock)
reg[9:0]  SendCnt;         // (2*NumBits)*8-1
reg[9:0]  RecvCnt;         // (2*NumBits)*8-1 (0 if no bits to receive)
reg[3:0]  RecvQuadCnt;     // Number of quadlets to read, minus 1
reg[4:0]  WriteQuadCnt;    // Number of quadlets to write
reg[31:0] prom_data;       // data to write to PROM (shift register)
reg       blk_wrt;         // true if a block write is in progress (and hasn't been aborted due to an error)
reg[15:0] prom_debug;

// block read/write
reg[31:0] data_block[15:0];  // up to 16 quadlets of data
reg[4:0]  wr_index;    // current write index 4-bit
reg[4:0]  rd_index;    // current read index 4-bit


// local wires
wire prom_reg_wen;       // main quadlet reg interface
assign prom_reg_wen = (reg_waddr == {`ADDR_PROM_QLA, `REG_PROM_CMD}) ? reg_wen : 1'b0;
assign prom_blk_wen = (reg_waddr[15:12] == `ADDR_PROM_QLA) ? reg_wen : 1'b0;


// prom_status
wire[31:0] prom_status; 
reg[31:0] prom_result; 
assign prom_status[31:16] = prom_debug;
assign prom_status[15:9] = 7'd0;
assign prom_status[8] = io_disabled;
assign prom_status[7] = prom_cs;
assign prom_status[6] = prom_sclk;
assign prom_status[5] = prom_miso;
assign prom_status[4] = prom_mosi;
assign prom_status[3] = blk_wrt;
assign prom_status[2:0] = state;

assign prom_mosi = io_disabled ? 1'bz : prom_data[31];
assign prom_sclk = io_disabled ? 1'bz : seqn[3];    // sysclk/8



// -----------------------------------------
// read/write request
// ------------------------------------------
always @(posedge(clk) or negedge(reset))
begin
    if (reset == 0) begin
        reg_rdata <= 32'd0;                
    end
    else if (reg_raddr[11:8] == 4'h0) begin
        case (reg_raddr[11:0])
        `REG_PROM_RESULT: reg_rdata <= prom_result;
        `REG_PROM_STATUS: reg_rdata <= prom_status;
        // return 32'd0 by default
        default: reg_rdata <= 32'd0;
        endcase
    end
    else if (reg_raddr[11:8] == 4'h1) begin
        reg_rdata <= data_block[reg_raddr[3:0]];
    end
    else begin
        reg_rdata <= 32'd0;
    end
end


// -----------------------------------------
// command processing 
// ------------------------------------------
always @(posedge(clk) or negedge(reset))
begin
    if (reset == 0) begin
        io_disabled <= 1'b1;
        prom_cs     <= 1'bz;
        prom_result <= 32'd0;
        prom_debug  <= 16'd0;
        blk_wrt     <= 1'b0;
        wr_index    <= 5'd0;
        rd_index    <= 5'd0;
        state       <= ST_IDLE;
    end

    else begin

        // block data write from PC
        if (prom_blk_wen) begin
            data_block[reg_waddr[3:0]] <= reg_wdata;
        end

        // command processing
        case (state)

        ST_IDLE: begin
           
          if (prom_reg_wen) begin  
            seqn <= 7'd0;
            blk_wrt <= 1'b0;
            wr_index <= 5'd0;
            rd_index <= 5'd0;
            case (reg_wdata[31:24])
               `CMD_IDLE_25AA128: begin    // Do nothing
               end
               `CMD_WREN_25AA128: begin    // Write Enable
                  SendCnt <= 10'd127;      // 2*8*8-1
                  RecvCnt <= 10'd0;
                  RecvQuadCnt <= 4'd0;
                  WriteQuadCnt <= 5'd0;
                  prom_data <= reg_wdata;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WRDI_25AA128: begin    // Write Disable
                  SendCnt <= 10'd127;
                  RecvCnt <= 10'd0;
                  RecvQuadCnt <= 4'd0;
                  WriteQuadCnt <= 5'd0;
                  prom_data <= reg_wdata;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_RDSR_25AA128: begin    // Read Status Register
                  SendCnt <= 10'd127;      // 1-byte cmd
                  RecvCnt <= 10'd127;      // 1-byte SR
                  RecvQuadCnt <= 4'd0;
                  WriteQuadCnt <= 5'd0;
                  prom_data <= reg_wdata;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WRSR_25AA128: begin    // Write Status Register
                  SendCnt <= 10'd255;      // 1-byte cmd + 1-byte SR
                  RecvCnt <= 10'd0;   
                  RecvQuadCnt <= 4'd0;
                  WriteQuadCnt <= 5'd0;
                  prom_data <= reg_wdata;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_READ_25AA128: begin    // Read Data (64 bytes)
                  SendCnt <= 10'd383;      // 1-byte cmd + 2-byte addr
                  RecvCnt <= 10'd127;      // 1-bype data 
                  RecvQuadCnt <= 4'd0; 
                  WriteQuadCnt <= 5'd0;
                  prom_data <= reg_wdata;    
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WRIT_25AA128: begin   // Write 1 byte data 
                  SendCnt <= 10'd511;     // 1 cmd 2 addr 1 data
                  RecvCnt <= 10'd0;
                  RecvQuadCnt <= 4'd0; 
                  WriteQuadCnt <= 5'd0;
                  prom_data <= reg_wdata;    
                  state <= ST_CHIP_SELECT;  
               end

               // block quadlet read/write
               `CMD_RBLK_25AA128: begin
                  SendCnt <= 10'd383;        // 1-byte cmd + 2-byte addr
                  RecvCnt <= 10'd511;        // 1-quad = 4-byte data
                  RecvQuadCnt <= reg_wdata[3:0];  // num of quad to receive -1 
                  WriteQuadCnt <= 5'd0;
                  prom_data <= {`CMD_READ_25AA128, reg_wdata[23:8], 8'd0}; 
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WBLK_25AA128: begin
                  SendCnt <= 10'd383;       // 1 cmd 2 addr 
                  RecvCnt <= 10'd0;         
                  RecvQuadCnt <= 0; 
                  WriteQuadCnt <= reg_wdata[3:0] + 5'd1;  // num of quad to write
                  prom_data <= {`CMD_WRIT_25AA128, reg_wdata[23:8], 8'd0}; 
                  state <= ST_CHIP_SELECT; 
               end

            endcase // case (prom_cmd[31:24])
          end // if (prom_reg_wen)
        end // case: ST_IDLE

        ST_CHIP_SELECT: begin
           io_disabled <= 1'b0;
           prom_cs     <= 1'b0;
           prom_result <= 32'd0;
           state <= ST_WRITE;
        end
           
        ST_WRITE: begin
            if (seqn[3:0] == 4'b1111) begin  // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn == SendCnt) begin
                if (WriteQuadCnt != 5'd0) begin
                    seqn <= 10'd0;     
                    SendCnt <= 10'd511;  // 4 byte data
                    prom_data <= data_block[rd_index[3:0]];
                    rd_index <= rd_index + 1'd1;
                    WriteQuadCnt <= WriteQuadCnt - 1'b1;
                end
                else begin
                    state <= (RecvCnt == 10'd0) ? ST_CHIP_DESELECT : ST_READ;
                    seqn <= 10'd0;
                end 
            end
            else seqn <= seqn + 1'b1;        // counter, also creates sclk
        end // case: ST_WRITE

        ST_READ: begin
            if (seqn[3:0] == 4'b0111) begin  // latch data on rising sclk
                prom_result <= { prom_result[30:0], prom_miso };
            end
            if (seqn == RecvCnt) begin
                seqn <= 10'd0;
                data_block[wr_index[3:0]] <= prom_result;
                wr_index <= wr_index + 1'b1;
                // deselect when finished
                if (wr_index == RecvQuadCnt) begin
                    state <= ST_CHIP_DESELECT;
                end
            end
            else
                seqn <= seqn + 1'b1;
        end
          
        ST_CHIP_DESELECT: begin
           prom_cs <= 1'b1;
           state <= ST_IO_DISABLE;
        end

        ST_IO_DISABLE: begin
           io_disabled <= 1'b1;
           prom_cs <= 1'bz;
           state <= ST_IDLE;
        end

        endcase // case (state)
    end // else: !if(reset == 0)
end


//------------------------------
// chipscope
//------------------------------
wire[35:0] control_prom;

icon_prom icon_p(
    .CONTROL0(control_prom)
);

wire[3:0] spi_debug;
assign spi_debug = { prom_mosi, prom_miso, prom_sclk, prom_cs };

ila_prom ila_p(
    .CONTROL(control_prom),
    .CLK(clk),
    .TRIG0(spi_debug),         // 4-bit
    .TRIG1(reg_raddr[15:0]),   // 16-bit
    .TRIG2(reg_wdata),         // 32-bit
    .TRIG3(prom_result)        // 32-bit
);



endmodule


// 4 x 64 quad = 256 bytes 
// 2^8 = 256 
// 128 kbits = 16 kbytes --> 14-bit addr space 
// 1 page = 64 bytes = 16 quads = 2^4 quads 
