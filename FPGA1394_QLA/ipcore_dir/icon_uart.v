///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2013 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 13.4
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : icon_uart.v
// /___/   /\     Timestamp  : Thu Oct 31 10:56:57 EDT 2013
// \   \  /  \
//  \___\/\___\
//
// Design Name: Verilog Synthesis Wrapper
///////////////////////////////////////////////////////////////////////////////
// This wrapper is used to integrate with Project Navigator and PlanAhead

`timescale 1ns/1ps

module icon_uart(
    CONTROL0,
    CONTROL1,
    CONTROL2);


inout [35 : 0] CONTROL0;
inout [35 : 0] CONTROL1;
inout [35 : 0] CONTROL2;

endmodule
