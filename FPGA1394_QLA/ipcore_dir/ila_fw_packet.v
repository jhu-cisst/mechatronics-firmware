///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2013 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 13.4
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_fw_packet.v
// /___/   /\     Timestamp  : Fri Sep 06 01:18:37 EDT 2013
// \   \  /  \
//  \___\/\___\
//
// Design Name: Verilog Synthesis Wrapper
///////////////////////////////////////////////////////////////////////////////
// This wrapper is used to integrate with Project Navigator and PlanAhead

`timescale 1ns/1ps

module ila_fw_packet(
    CONTROL,
    CLK,
    TRIG0,
    TRIG1,
    TRIG2,
    TRIG3,
    TRIG4);


inout [35 : 0] CONTROL;
input CLK;
input [7 : 0] TRIG0;
input [31 : 0] TRIG1;
input [15 : 0] TRIG2;
input [1 : 0] TRIG3;
input [7 : 0] TRIG4;

endmodule
