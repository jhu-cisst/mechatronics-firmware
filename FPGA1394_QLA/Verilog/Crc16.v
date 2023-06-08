// Lightly modified from original to replace reset with initialize

//-----------------------------------------------------------------------------
// Copyright (C) 2009 OutputLogic.com 
// This source file may be used and distributed without restriction 
// provided that this copyright statement is not removed from the file 
// and that any derivative work contains the original copyright notice 
// and the associated disclaimer. 
// 
// THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS 
// OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED	
// WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE. 
//-----------------------------------------------------------------------------
// CRC module for data[7:0] ,   crc[15:0]=1+x^1+x^2+x^4+x^5+x^7+x^8+x^10+x^11+x^12+x^16;
//-----------------------------------------------------------------------------
module crc16(
  input clock,
  input init,
  input ena,
  input [7:0] data,
  output reg [15:0] q
  );

  always @(posedge clock) begin
    if (init) begin
        q <= 16'hFFFF;
    end 
    else if (ena) begin
        q[0] <= q[8] ^ q[12] ^ q[13] ^ q[14] ^ data[0] ^ data[4] ^ data[5] ^ data[6];
        q[1] <= q[8] ^ q[9] ^ q[12] ^ q[15] ^ data[0] ^ data[1] ^ data[4] ^ data[7];
        q[2] <= q[8] ^ q[9] ^ q[10] ^ q[12] ^ q[14] ^ data[0] ^ data[1] ^ data[2] ^ data[4] ^ data[6];
        q[3] <= q[9] ^ q[10] ^ q[11] ^ q[13] ^ q[15] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[7];
        q[4] <= q[8] ^ q[10] ^ q[11] ^ q[13] ^ data[0] ^ data[2] ^ data[3] ^ data[5];
        q[5] <= q[8] ^ q[9] ^ q[11] ^ q[13] ^ data[0] ^ data[1] ^ data[3] ^ data[5];
        q[6] <= q[9] ^ q[10] ^ q[12] ^ q[14] ^ data[1] ^ data[2] ^ data[4] ^ data[6];
        q[7] <= q[8] ^ q[10] ^ q[11] ^ q[12] ^ q[14] ^ q[15] ^ data[0] ^ data[2] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
        q[8] <= q[0] ^ q[8] ^ q[9] ^ q[11] ^ q[14] ^ q[15] ^ data[0] ^ data[1] ^ data[3] ^ data[6] ^ data[7];
        q[9] <= q[1] ^ q[9] ^ q[10] ^ q[12] ^ q[15] ^ data[1] ^ data[2] ^ data[4] ^ data[7];
        q[10] <= q[2] ^ q[8] ^ q[10] ^ q[11] ^ q[12] ^ q[14] ^ data[0] ^ data[2] ^ data[3] ^ data[4] ^ data[6];
        q[11] <= q[3] ^ q[8] ^ q[9] ^ q[11] ^ q[14] ^ q[15] ^ data[0] ^ data[1] ^ data[3] ^ data[6] ^ data[7];
        q[12] <= q[4] ^ q[8] ^ q[9] ^ q[10] ^ q[13] ^ q[14] ^ q[15] ^ data[0] ^ data[1] ^ data[2] ^ data[5] ^ data[6] ^ data[7];
        q[13] <= q[5] ^ q[9] ^ q[10] ^ q[11] ^ q[14] ^ q[15] ^ data[1] ^ data[2] ^ data[3] ^ data[6] ^ data[7];
        q[14] <= q[6] ^ q[10] ^ q[11] ^ q[12] ^ q[15] ^ data[2] ^ data[3] ^ data[4] ^ data[7];
        q[15] <= q[7] ^ q[11] ^ q[12] ^ q[13] ^ data[3] ^ data[4] ^ data[5];

        end // always
    end
  endmodule // crc
