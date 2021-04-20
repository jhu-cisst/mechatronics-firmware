///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2020 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 14.7
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_3_8_8_8.v
// /___/   /\     Timestamp  : Fri May 08 02:07:12 EDT 2020
// \   \  /  \
//  \___\/\___\
//
// Design Name: Verilog Synthesis Wrapper
///////////////////////////////////////////////////////////////////////////////
// This wrapper is used to integrate with Project Navigator and PlanAhead

`timescale 1ns/1ps

module ila_3_8_8_8(
    CONTROL,
    CLK,
    TRIG0,
    TRIG1,
    TRIG2,
    TRIG3) /* synthesis syn_black_box syn_noprune=1 */;


inout [35 : 0] CONTROL;
input CLK;
input [2 : 0] TRIG0;
input [7 : 0] TRIG1;
input [7 : 0] TRIG2;
input [7 : 0] TRIG3;

endmodule
