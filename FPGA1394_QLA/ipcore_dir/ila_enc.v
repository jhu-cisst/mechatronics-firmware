///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2014 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 13.4
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_enc.v
// /___/   /\     Timestamp  : Wed Feb 12 17:40:36 EST 2014
// \   \  /  \
//  \___\/\___\
//
// Design Name: Verilog Synthesis Wrapper
///////////////////////////////////////////////////////////////////////////////
// This wrapper is used to integrate with Project Navigator and PlanAhead

`timescale 1ns/1ps

module ila_enc(
    CONTROL,
    CLK,
    TRIG0,
    TRIG1,
    TRIG2);


inout [35 : 0] CONTROL;
input CLK;
input [7 : 0] TRIG0;
input [15 : 0] TRIG1;
input [15 : 0] TRIG2;

endmodule
