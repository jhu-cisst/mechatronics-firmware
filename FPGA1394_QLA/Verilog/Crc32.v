///////////////////////////////////////////////////////////////////////
// Date:  Tue May 20 04:24:50 2008
//
// Copyright (C) 1999-2003 Easics NV.
// This source file may be used and distributed without restriction
// provided that this copyright statement is not removed from the file
// and that any derivative work contains the original copyright notice
// and the associated disclaimer.
//
// THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
// OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
// WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// Purpose: Verilog module containing a synthesizable CRC function
//   * polynomial: (0 1 2 4 5 7 8 10 11 12 16 22 23 26 32)
//   * data widths: 2, 4, and 8
//
// Info: tools@easics.be
//       http://www.easics.com
///////////////////////////////////////////////////////////////////////

/*******************************************************************************
 * This module is modified only slightly from the original to accomodate inputs
 * and outputs.  Inputs are new data to add to the checksum and the currect crc
 * value, and the output is the new crc value.  Another change is the inclusion
 * of multiple bit widths in a single module.
 *
 * At the beginning of a new crc calculation the input crc should be something
 * like all ones.  During computation each new crc should be fed back as the
 * input crc of the next iteration.
 *
 * The computation is a continuous assignment, so when a crc value is needed,
 * the input crc should be initialized.  When the data stream is complete, the
 * output crc should be latched immediately.
 *
 * Note that the computed crc is different for identical bitstreams when data
 * data is streamed at different widths.
 */
module crc32(data, crc_in, crc_out_2b, crc_out_4b, crc_out_8b);

    input[7:0] data;
    input[31:0] crc_in;
    output[31:0] crc_out_2b;
    output[31:0] crc_out_4b;
    output[31:0] crc_out_8b;

// assignments of (current crc and data) -> (next crc) for 2, 4, 8-bit data
assign crc_out_2b = nextCRC32_2b(data[7:6], crc_in);
assign crc_out_4b = nextCRC32_4b(data[7:4], crc_in);
assign crc_out_8b = nextCRC32_8b(data[7:0], crc_in);

//------------------------------------------------------------------------------
// 32-bit crc function for data width 2; msb is data[1]
//
function[31:0] nextCRC32_2b;

    input[1:0] data;
    input[31:0] crc_in;

    reg[1:0] d;
    reg[31:0] c;
    reg[31:0] crc_out;

begin

    d = data;
    c = crc_in;

    crc_out[0] = d[0] ^ c[30];
    crc_out[1] = d[1] ^ d[0] ^ c[30] ^ c[31];
    crc_out[2] = d[1] ^ d[0] ^ c[0] ^ c[30] ^ c[31];
    crc_out[3] = d[1] ^ c[1] ^ c[31];
    crc_out[4] = d[0] ^ c[2] ^ c[30];
    crc_out[5] = d[1] ^ d[0] ^ c[3] ^ c[30] ^ c[31];
    crc_out[6] = d[1] ^ c[4] ^ c[31];
    crc_out[7] = d[0] ^ c[5] ^ c[30];
    crc_out[8] = d[1] ^ d[0] ^ c[6] ^ c[30] ^ c[31];
    crc_out[9] = d[1] ^ c[7] ^ c[31];
    crc_out[10] = d[0] ^ c[8] ^ c[30];
    crc_out[11] = d[1] ^ d[0] ^ c[9] ^ c[30] ^ c[31];
    crc_out[12] = d[1] ^ d[0] ^ c[10] ^ c[30] ^ c[31];
    crc_out[13] = d[1] ^ c[11] ^ c[31];
    crc_out[14] = c[12];
    crc_out[15] = c[13];
    crc_out[16] = d[0] ^ c[14] ^ c[30];
    crc_out[17] = d[1] ^ c[15] ^ c[31];
    crc_out[18] = c[16];
    crc_out[19] = c[17];
    crc_out[20] = c[18];
    crc_out[21] = c[19];
    crc_out[22] = d[0] ^ c[20] ^ c[30];
    crc_out[23] = d[1] ^ d[0] ^ c[21] ^ c[30] ^ c[31];
    crc_out[24] = d[1] ^ c[22] ^ c[31];
    crc_out[25] = c[23];
    crc_out[26] = d[0] ^ c[24] ^ c[30];
    crc_out[27] = d[1] ^ c[25] ^ c[31];
    crc_out[28] = c[26];
    crc_out[29] = c[27];
    crc_out[30] = c[28];
    crc_out[31] = c[29];

    nextCRC32_2b = crc_out;

end
endfunction

//------------------------------------------------------------------------------
// 32-bit crc function for data width 4; msb is data[3]
//
function[31:0] nextCRC32_4b;

    input[3:0] data;
    input[31:0] crc_in;

    reg[3:0] d;
    reg[31:0] c;
    reg[31:0] crc_out;

begin

    d = data;
    c = crc_in;

    crc_out[0] = d[0] ^ c[28];
    crc_out[1] = d[1] ^ d[0] ^ c[28] ^ c[29];
    crc_out[2] = d[2] ^ d[1] ^ d[0] ^ c[28] ^ c[29] ^ c[30];
    crc_out[3] = d[3] ^ d[2] ^ d[1] ^ c[29] ^ c[30] ^ c[31];
    crc_out[4] = d[3] ^ d[2] ^ d[0] ^ c[0] ^ c[28] ^ c[30] ^ c[31];
    crc_out[5] = d[3] ^ d[1] ^ d[0] ^ c[1] ^ c[28] ^ c[29] ^ c[31];
    crc_out[6] = d[2] ^ d[1] ^ c[2] ^ c[29] ^ c[30];
    crc_out[7] = d[3] ^ d[2] ^ d[0] ^ c[3] ^ c[28] ^ c[30] ^ c[31];
    crc_out[8] = d[3] ^ d[1] ^ d[0] ^ c[4] ^ c[28] ^ c[29] ^ c[31];
    crc_out[9] = d[2] ^ d[1] ^ c[5] ^ c[29] ^ c[30];
    crc_out[10] = d[3] ^ d[2] ^ d[0] ^ c[6] ^ c[28] ^ c[30] ^ c[31];
    crc_out[11] = d[3] ^ d[1] ^ d[0] ^ c[7] ^ c[28] ^ c[29] ^ c[31];
    crc_out[12] = d[2] ^ d[1] ^ d[0] ^ c[8] ^ c[28] ^ c[29] ^ c[30];
    crc_out[13] = d[3] ^ d[2] ^ d[1] ^ c[9] ^ c[29] ^ c[30] ^ c[31];
    crc_out[14] = d[3] ^ d[2] ^ c[10] ^ c[30] ^ c[31];
    crc_out[15] = d[3] ^ c[11] ^ c[31];
    crc_out[16] = d[0] ^ c[12] ^ c[28];
    crc_out[17] = d[1] ^ c[13] ^ c[29];
    crc_out[18] = d[2] ^ c[14] ^ c[30];
    crc_out[19] = d[3] ^ c[15] ^ c[31];
    crc_out[20] = c[16];
    crc_out[21] = c[17];
    crc_out[22] = d[0] ^ c[18] ^ c[28];
    crc_out[23] = d[1] ^ d[0] ^ c[19] ^ c[28] ^ c[29];
    crc_out[24] = d[2] ^ d[1] ^ c[20] ^ c[29] ^ c[30];
    crc_out[25] = d[3] ^ d[2] ^ c[21] ^ c[30] ^ c[31];
    crc_out[26] = d[3] ^ d[0] ^ c[22] ^ c[28] ^ c[31];
    crc_out[27] = d[1] ^ c[23] ^ c[29];
    crc_out[28] = d[2] ^ c[24] ^ c[30];
    crc_out[29] = d[3] ^ c[25] ^ c[31];
    crc_out[30] = c[26];
    crc_out[31] = c[27];

    nextCRC32_4b = crc_out;

end
endfunction

//------------------------------------------------------------------------------
// 32-bit crc function for data width 8; msb is data[7]
//
function[31:0] nextCRC32_8b;

    input[7:0] data;
    input[31:0] crc_in;

    reg[7:0] d;
    reg[31:0] c;
    reg[31:0] crc_out;

begin

    d = data;
    c = crc_in;

    crc_out[0] = d[6] ^ d[0] ^ c[24] ^ c[30];
    crc_out[1] = d[7] ^ d[6] ^ d[1] ^ d[0] ^ c[24] ^ c[25] ^ c[30] ^ c[31];
    crc_out[2] = d[7] ^ d[6] ^ d[2] ^ d[1] ^ d[0] ^ c[24] ^ c[25] ^ c[26] ^ c[30] ^ c[31];
    crc_out[3] = d[7] ^ d[3] ^ d[2] ^ d[1] ^ c[25] ^ c[26] ^ c[27] ^ c[31];
    crc_out[4] = d[6] ^ d[4] ^ d[3] ^ d[2] ^ d[0] ^ c[24] ^ c[26] ^ c[27] ^ c[28] ^ c[30];
    crc_out[5] = d[7] ^ d[6] ^ d[5] ^ d[4] ^ d[3] ^ d[1] ^ d[0] ^ c[24] ^ c[25] ^ c[27] ^ c[28] ^ c[29] ^ c[30] ^ c[31];
    crc_out[6] = d[7] ^ d[6] ^ d[5] ^ d[4] ^ d[2] ^ d[1] ^ c[25] ^ c[26] ^ c[28] ^ c[29] ^ c[30] ^ c[31];
    crc_out[7] = d[7] ^ d[5] ^ d[3] ^ d[2] ^ d[0] ^ c[24] ^ c[26] ^ c[27] ^ c[29] ^ c[31];
    crc_out[8] = d[4] ^ d[3] ^ d[1] ^ d[0] ^ c[0] ^ c[24] ^ c[25] ^ c[27] ^ c[28];
    crc_out[9] = d[5] ^ d[4] ^ d[2] ^ d[1] ^ c[1] ^ c[25] ^ c[26] ^ c[28] ^ c[29];
    crc_out[10] = d[5] ^ d[3] ^ d[2] ^ d[0] ^ c[2] ^ c[24] ^ c[26] ^ c[27] ^ c[29];
    crc_out[11] = d[4] ^ d[3] ^ d[1] ^ d[0] ^ c[3] ^ c[24] ^ c[25] ^ c[27] ^ c[28];
    crc_out[12] = d[6] ^ d[5] ^ d[4] ^ d[2] ^ d[1] ^ d[0] ^ c[4] ^ c[24] ^ c[25] ^ c[26] ^ c[28] ^ c[29] ^ c[30];
    crc_out[13] = d[7] ^ d[6] ^ d[5] ^ d[3] ^ d[2] ^ d[1] ^ c[5] ^ c[25] ^ c[26] ^ c[27] ^ c[29] ^ c[30] ^ c[31];
    crc_out[14] = d[7] ^ d[6] ^ d[4] ^ d[3] ^ d[2] ^ c[6] ^ c[26] ^ c[27] ^ c[28] ^ c[30] ^ c[31];
    crc_out[15] = d[7] ^ d[5] ^ d[4] ^ d[3] ^ c[7] ^ c[27] ^ c[28] ^ c[29] ^ c[31];
    crc_out[16] = d[5] ^ d[4] ^ d[0] ^ c[8] ^ c[24] ^ c[28] ^ c[29];
    crc_out[17] = d[6] ^ d[5] ^ d[1] ^ c[9] ^ c[25] ^ c[29] ^ c[30];
    crc_out[18] = d[7] ^ d[6] ^ d[2] ^ c[10] ^ c[26] ^ c[30] ^ c[31];
    crc_out[19] = d[7] ^ d[3] ^ c[11] ^ c[27] ^ c[31];
    crc_out[20] = d[4] ^ c[12] ^ c[28];
    crc_out[21] = d[5] ^ c[13] ^ c[29];
    crc_out[22] = d[0] ^ c[14] ^ c[24];
    crc_out[23] = d[6] ^ d[1] ^ d[0] ^ c[15] ^ c[24] ^ c[25] ^ c[30];
    crc_out[24] = d[7] ^ d[2] ^ d[1] ^ c[16] ^ c[25] ^ c[26] ^ c[31];
    crc_out[25] = d[3] ^ d[2] ^ c[17] ^ c[26] ^ c[27];
    crc_out[26] = d[6] ^ d[4] ^ d[3] ^ d[0] ^ c[18] ^ c[24] ^ c[27] ^ c[28] ^ c[30];
    crc_out[27] = d[7] ^ d[5] ^ d[4] ^ d[1] ^ c[19] ^ c[25] ^ c[28] ^ c[29] ^ c[31];
    crc_out[28] = d[6] ^ d[5] ^ d[2] ^ c[20] ^ c[26] ^ c[29] ^ c[30];
    crc_out[29] = d[7] ^ d[6] ^ d[3] ^ c[21] ^ c[27] ^ c[30] ^ c[31];
    crc_out[30] = d[7] ^ d[4] ^ c[22] ^ c[28] ^ c[31];
    crc_out[31] = d[5] ^ c[23] ^ c[29];

    nextCRC32_8b = crc_out;

end
endfunction

endmodule

