///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2020 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 14.7
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : ila_prom.veo
// /___/   /\     Timestamp  : Fri May 08 02:14:26 EDT 2020
// \   \  /  \
//  \___\/\___\
//
// Design Name: ISE Instantiation template
///////////////////////////////////////////////////////////////////////////////

// The following must be inserted into your Verilog file for this
// core to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
ila_prom YourInstanceName (
    .CONTROL(CONTROL), // INOUT BUS [35:0]
    .CLK(CLK), // IN
    .TRIG0(TRIG0), // IN BUS [3:0]
    .TRIG1(TRIG1), // IN BUS [15:0]
    .TRIG2(TRIG2), // IN BUS [31:0]
    .TRIG3(TRIG3) // IN BUS [31:0]
);

// INST_TAG_END ------ End INSTANTIATION Template ---------

