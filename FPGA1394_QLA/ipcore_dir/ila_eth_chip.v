///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2020 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 14.7
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_eth_chip.v
// /___/   /\     Timestamp  : Fri May 08 02:10:05 EDT 2020
// \   \  /  \
//  \___\/\___\
//
// Design Name: Verilog Synthesis Wrapper
///////////////////////////////////////////////////////////////////////////////
// This wrapper is used to integrate with Project Navigator and PlanAhead

`timescale 1ns/1ps

module ila_eth_chip(
    CONTROL,
    CLK,
    TRIG0,
    TRIG1,
    TRIG2,
    TRIG3,
    TRIG4,
    TRIG5,
    TRIG6,
    TRIG7,
    TRIG8,
    TRIG9) /* synthesis syn_black_box syn_noprune=1 */;


inout [35 : 0] CONTROL;
input CLK;
input [7 : 0] TRIG0;
input [15 : 0] TRIG1;
input [3 : 0] TRIG2;
input [15 : 0] TRIG3;
input [31 : 0] TRIG4;
input [31 : 0] TRIG5;
input [5 : 0] TRIG6;
input [5 : 0] TRIG7;
input [15 : 0] TRIG8;
input [15 : 0] TRIG9;

endmodule
