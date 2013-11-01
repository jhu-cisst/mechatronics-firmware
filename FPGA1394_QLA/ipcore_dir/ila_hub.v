///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2013 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 13.4
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_hub.v
// /___/   /\     Timestamp  : Tue Oct 29 11:00:40 EDT 2013
// \   \  /  \
//  \___\/\___\
//
// Design Name: Verilog Synthesis Wrapper
///////////////////////////////////////////////////////////////////////////////
// This wrapper is used to integrate with Project Navigator and PlanAhead

`timescale 1ns/1ps

module ila_hub(
    CONTROL,
    CLK,
    TRIG0,
    TRIG1,
    TRIG2,
    TRIG3,
    TRIG4,
    TRIG5);


inout [35 : 0] CONTROL;
input CLK;
input [0 : 0] TRIG0;
input [15 : 0] TRIG1;
input [15 : 0] TRIG2;
input [31 : 0] TRIG3;
input [31 : 0] TRIG4;
input [31 : 0] TRIG5;

endmodule
