///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2013 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 13.4
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_3_8_8_8.v
// /___/   /\     Timestamp  : Thu Oct 31 11:14:08 EDT 2013
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
    TRIG3);


inout [35 : 0] CONTROL;
input CLK;
input [2 : 0] TRIG0;
input [7 : 0] TRIG1;
input [7 : 0] TRIG2;
input [7 : 0] TRIG3;

endmodule
