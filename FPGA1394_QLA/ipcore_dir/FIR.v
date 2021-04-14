////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995-2013 Xilinx, Inc.  All rights reserved.
////////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor: Xilinx
// \   \   \/     Version: P.20131013
//  \   \         Application: netgen
//  /   /         Filename: FIR.v
// /___/   /\     Timestamp: Wed Apr 14 11:47:26 2021
// \   \  /  \ 
//  \___\/\___\
//             
// Command	: -w -sim -ofmt verilog "C:/Users/maxwe/Desktop/SMARTS/Fir Filter V7/mechatronics-firmware/FPGA1394_QLA/ipcore_dir/tmp/_cg/FIR.ngc" "C:/Users/maxwe/Desktop/SMARTS/Fir Filter V7/mechatronics-firmware/FPGA1394_QLA/ipcore_dir/tmp/_cg/FIR.v" 
// Device	: 6slx45fgg484-2
// Input file	: C:/Users/maxwe/Desktop/SMARTS/Fir Filter V7/mechatronics-firmware/FPGA1394_QLA/ipcore_dir/tmp/_cg/FIR.ngc
// Output file	: C:/Users/maxwe/Desktop/SMARTS/Fir Filter V7/mechatronics-firmware/FPGA1394_QLA/ipcore_dir/tmp/_cg/FIR.v
// # of Modules	: 1
// Design Name	: FIR
// Xilinx        : C:\Xilinx\14.7\ISE_DS\ISE\
//             
// Purpose:    
//     This verilog netlist is a verification model and uses simulation 
//     primitives which may not represent the true implementation of the 
//     device, however the netlist is functionally correct and should not 
//     be modified. This file cannot be synthesized and should only be used 
//     with supported simulation tools.
//             
// Reference:  
//     Command Line Tools User Guide, Chapter 23 and Synthesis and Simulation Design Guide, Chapter 6
//             
////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns/1 ps

module FIR (
  aclk, s_axis_data_tvalid, s_axis_data_tready, m_axis_data_tvalid, s_axis_data_tdata, m_axis_data_tdata
)/* synthesis syn_black_box syn_noprune=1 */;
  input aclk;
  input s_axis_data_tvalid;
  output s_axis_data_tready;
  output m_axis_data_tvalid;
  input [15 : 0] s_axis_data_tdata;
  output [39 : 0] m_axis_data_tdata;
  
  // synthesis translate_off
  
  wire NlwRenamedSig_OI_s_axis_data_tready;
  wire \blk00000001/sig00000139 ;
  wire \blk00000001/sig00000138 ;
  wire \blk00000001/sig00000137 ;
  wire \blk00000001/sig00000136 ;
  wire \blk00000001/sig00000135 ;
  wire \blk00000001/sig00000134 ;
  wire \blk00000001/sig00000133 ;
  wire \blk00000001/sig00000132 ;
  wire \blk00000001/sig00000131 ;
  wire \blk00000001/sig00000130 ;
  wire \blk00000001/sig0000012f ;
  wire \blk00000001/sig0000012e ;
  wire \blk00000001/sig0000012d ;
  wire \blk00000001/sig0000012c ;
  wire \blk00000001/sig0000012b ;
  wire \blk00000001/sig0000012a ;
  wire \blk00000001/sig00000129 ;
  wire \blk00000001/sig00000128 ;
  wire \blk00000001/sig00000127 ;
  wire \blk00000001/sig00000126 ;
  wire \blk00000001/sig00000125 ;
  wire \blk00000001/sig00000124 ;
  wire \blk00000001/sig00000123 ;
  wire \blk00000001/sig00000122 ;
  wire \blk00000001/sig00000121 ;
  wire \blk00000001/sig00000120 ;
  wire \blk00000001/sig0000011f ;
  wire \blk00000001/sig0000011e ;
  wire \blk00000001/sig0000011d ;
  wire \blk00000001/sig0000011c ;
  wire \blk00000001/sig0000011b ;
  wire \blk00000001/sig0000011a ;
  wire \blk00000001/sig00000119 ;
  wire \blk00000001/sig00000118 ;
  wire \blk00000001/sig00000117 ;
  wire \blk00000001/sig00000116 ;
  wire \blk00000001/sig00000115 ;
  wire \blk00000001/sig00000114 ;
  wire \blk00000001/sig00000113 ;
  wire \blk00000001/sig00000112 ;
  wire \blk00000001/sig00000111 ;
  wire \blk00000001/sig00000110 ;
  wire \blk00000001/sig0000010f ;
  wire \blk00000001/sig0000010e ;
  wire \blk00000001/sig0000010d ;
  wire \blk00000001/sig0000010c ;
  wire \blk00000001/sig0000010b ;
  wire \blk00000001/sig0000010a ;
  wire \blk00000001/sig00000109 ;
  wire \blk00000001/sig00000108 ;
  wire \blk00000001/sig00000107 ;
  wire \blk00000001/sig00000106 ;
  wire \blk00000001/sig00000105 ;
  wire \blk00000001/sig00000104 ;
  wire \blk00000001/sig00000103 ;
  wire \blk00000001/sig00000102 ;
  wire \blk00000001/sig00000101 ;
  wire \blk00000001/sig00000100 ;
  wire \blk00000001/sig000000ff ;
  wire \blk00000001/sig000000fe ;
  wire \blk00000001/sig000000fd ;
  wire \blk00000001/sig000000fc ;
  wire \blk00000001/sig000000fb ;
  wire \blk00000001/sig000000fa ;
  wire \blk00000001/sig000000f9 ;
  wire \blk00000001/sig000000f8 ;
  wire \blk00000001/sig000000f7 ;
  wire \blk00000001/sig000000f6 ;
  wire \blk00000001/sig000000f5 ;
  wire \blk00000001/sig000000f4 ;
  wire \blk00000001/sig000000f3 ;
  wire \blk00000001/sig000000f2 ;
  wire \blk00000001/sig000000f1 ;
  wire \blk00000001/sig000000f0 ;
  wire \blk00000001/sig000000ef ;
  wire \blk00000001/sig000000ee ;
  wire \blk00000001/sig000000ed ;
  wire \blk00000001/sig000000ec ;
  wire \blk00000001/sig000000eb ;
  wire \blk00000001/sig000000ea ;
  wire \blk00000001/sig000000e9 ;
  wire \blk00000001/sig000000e8 ;
  wire \blk00000001/sig000000e2 ;
  wire \blk00000001/sig000000e1 ;
  wire \blk00000001/sig000000e0 ;
  wire \blk00000001/sig000000df ;
  wire \blk00000001/sig000000de ;
  wire \blk00000001/sig000000dd ;
  wire \blk00000001/sig000000dc ;
  wire \blk00000001/sig000000db ;
  wire \blk00000001/sig000000da ;
  wire \blk00000001/sig000000d9 ;
  wire \blk00000001/sig000000d8 ;
  wire \blk00000001/sig000000d7 ;
  wire \blk00000001/sig000000d6 ;
  wire \blk00000001/sig000000d5 ;
  wire \blk00000001/sig000000d4 ;
  wire \blk00000001/sig000000d3 ;
  wire \blk00000001/sig000000d2 ;
  wire \blk00000001/sig000000d1 ;
  wire \blk00000001/sig000000d0 ;
  wire \blk00000001/sig000000cf ;
  wire \blk00000001/sig000000ce ;
  wire \blk00000001/sig000000cd ;
  wire \blk00000001/sig000000cc ;
  wire \blk00000001/sig000000cb ;
  wire \blk00000001/sig000000ca ;
  wire \blk00000001/sig000000c9 ;
  wire \blk00000001/sig000000c8 ;
  wire \blk00000001/sig000000c7 ;
  wire \blk00000001/sig000000c6 ;
  wire \blk00000001/sig000000c5 ;
  wire \blk00000001/sig000000c4 ;
  wire \blk00000001/sig000000c3 ;
  wire \blk00000001/sig000000c2 ;
  wire \blk00000001/sig000000c1 ;
  wire \blk00000001/sig000000c0 ;
  wire \blk00000001/sig000000bf ;
  wire \blk00000001/sig000000be ;
  wire \blk00000001/sig000000bd ;
  wire \blk00000001/sig000000bc ;
  wire \blk00000001/sig000000bb ;
  wire \blk00000001/sig000000ba ;
  wire \blk00000001/sig000000b9 ;
  wire \blk00000001/sig000000b8 ;
  wire \blk00000001/sig000000b7 ;
  wire \blk00000001/sig000000b6 ;
  wire \blk00000001/sig000000b5 ;
  wire \blk00000001/sig000000b4 ;
  wire \blk00000001/sig000000b3 ;
  wire \blk00000001/sig000000ae ;
  wire \blk00000001/sig000000ad ;
  wire \blk00000001/sig000000ac ;
  wire \blk00000001/sig000000aa ;
  wire \blk00000001/sig000000a9 ;
  wire \blk00000001/sig000000a7 ;
  wire \blk00000001/sig000000a6 ;
  wire \blk00000001/sig000000a5 ;
  wire \blk00000001/sig000000a4 ;
  wire \blk00000001/sig000000a3 ;
  wire \blk00000001/sig000000a2 ;
  wire \blk00000001/sig000000a1 ;
  wire \blk00000001/sig000000a0 ;
  wire \blk00000001/sig0000009f ;
  wire \blk00000001/sig0000009e ;
  wire \blk00000001/sig0000009d ;
  wire \blk00000001/sig0000009c ;
  wire \blk00000001/sig0000009b ;
  wire \blk00000001/sig0000009a ;
  wire \blk00000001/sig00000099 ;
  wire \blk00000001/sig00000098 ;
  wire \blk00000001/sig00000097 ;
  wire \blk00000001/sig00000096 ;
  wire \blk00000001/sig00000095 ;
  wire \blk00000001/sig00000094 ;
  wire \blk00000001/sig00000093 ;
  wire \blk00000001/sig00000092 ;
  wire \blk00000001/sig00000091 ;
  wire \blk00000001/sig00000090 ;
  wire \blk00000001/sig0000008f ;
  wire \blk00000001/sig0000008e ;
  wire \blk00000001/sig0000008d ;
  wire \blk00000001/sig0000008c ;
  wire \blk00000001/sig0000008b ;
  wire \blk00000001/sig0000008a ;
  wire \blk00000001/sig00000089 ;
  wire \blk00000001/sig00000088 ;
  wire \blk00000001/sig00000087 ;
  wire \blk00000001/sig00000086 ;
  wire \blk00000001/sig00000085 ;
  wire \blk00000001/sig00000084 ;
  wire \blk00000001/sig00000083 ;
  wire \blk00000001/sig00000082 ;
  wire \blk00000001/sig00000081 ;
  wire \blk00000001/sig00000080 ;
  wire \blk00000001/sig0000007f ;
  wire \blk00000001/sig0000007e ;
  wire \blk00000001/sig0000007d ;
  wire \blk00000001/sig0000007c ;
  wire \blk00000001/sig0000007b ;
  wire \blk00000001/sig0000007a ;
  wire \blk00000001/sig00000079 ;
  wire \blk00000001/sig00000078 ;
  wire \blk00000001/sig00000077 ;
  wire \blk00000001/sig00000076 ;
  wire \blk00000001/sig00000075 ;
  wire \blk00000001/sig00000074 ;
  wire \blk00000001/sig00000073 ;
  wire \blk00000001/sig00000072 ;
  wire \blk00000001/sig00000071 ;
  wire \blk00000001/sig00000070 ;
  wire \blk00000001/sig0000006f ;
  wire \blk00000001/sig0000006e ;
  wire \blk00000001/sig0000006d ;
  wire \blk00000001/sig0000006c ;
  wire \blk00000001/sig0000006b ;
  wire \blk00000001/sig0000006a ;
  wire \blk00000001/sig00000069 ;
  wire \blk00000001/sig00000068 ;
  wire \blk00000001/sig00000067 ;
  wire \blk00000001/sig00000066 ;
  wire \blk00000001/sig00000065 ;
  wire \blk00000001/sig00000064 ;
  wire \blk00000001/sig00000063 ;
  wire \blk00000001/sig00000062 ;
  wire \blk00000001/sig00000061 ;
  wire \blk00000001/sig00000060 ;
  wire \blk00000001/sig0000005f ;
  wire \blk00000001/sig0000005e ;
  wire \blk00000001/sig0000005d ;
  wire \blk00000001/sig0000005c ;
  wire \blk00000001/sig0000005b ;
  wire \blk00000001/sig0000005a ;
  wire \blk00000001/sig00000059 ;
  wire \blk00000001/sig00000058 ;
  wire \blk00000001/sig00000057 ;
  wire \blk00000001/sig00000056 ;
  wire \blk00000001/sig00000055 ;
  wire \blk00000001/sig00000054 ;
  wire \blk00000001/sig00000053 ;
  wire \blk00000001/sig00000052 ;
  wire \blk00000001/sig00000051 ;
  wire \blk00000001/sig00000050 ;
  wire \blk00000001/sig0000004f ;
  wire \blk00000001/sig0000004e ;
  wire \blk00000001/sig0000004d ;
  wire \blk00000001/sig0000004c ;
  wire \blk00000001/sig0000004b ;
  wire \blk00000001/sig0000004a ;
  wire \blk00000001/sig00000049 ;
  wire \blk00000001/sig00000048 ;
  wire \blk00000001/sig00000047 ;
  wire \blk00000001/sig00000046 ;
  wire \blk00000001/sig00000045 ;
  wire \blk00000001/sig00000044 ;
  wire \blk00000001/sig00000043 ;
  wire \blk00000001/sig00000042 ;
  wire \blk00000001/sig00000041 ;
  wire \blk00000001/sig00000040 ;
  wire \blk00000001/sig0000003f ;
  wire \blk00000001/sig0000003e ;
  wire \blk00000001/sig0000003d ;
  wire \blk00000001/sig0000003c ;
  wire \blk00000001/sig0000003b ;
  wire \blk00000001/sig0000003a ;
  wire \blk00000001/sig00000039 ;
  wire \blk00000001/blk0000003e/sig00000186 ;
  wire \blk00000001/blk0000003e/sig00000185 ;
  wire \blk00000001/blk0000003e/sig00000184 ;
  wire \blk00000001/blk0000003e/sig00000183 ;
  wire \blk00000001/blk0000003e/sig00000182 ;
  wire \blk00000001/blk0000003e/sig00000181 ;
  wire \blk00000001/blk0000003e/sig00000180 ;
  wire \blk00000001/blk0000003e/sig0000017f ;
  wire \blk00000001/blk0000003e/sig0000017e ;
  wire \blk00000001/blk0000003e/sig0000017d ;
  wire \blk00000001/blk0000003e/sig0000017c ;
  wire \blk00000001/blk0000003e/sig0000017b ;
  wire \blk00000001/blk0000003e/sig0000017a ;
  wire \blk00000001/blk0000003e/sig00000179 ;
  wire \blk00000001/blk0000003e/sig00000178 ;
  wire \blk00000001/blk0000003e/sig00000177 ;
  wire \blk00000001/blk0000003e/sig00000176 ;
  wire \blk00000001/blk0000003e/sig00000175 ;
  wire \blk00000001/blk0000003e/sig00000174 ;
  wire \blk00000001/blk0000003e/sig00000173 ;
  wire \blk00000001/blk0000003e/sig00000172 ;
  wire \blk00000001/blk0000003e/sig00000171 ;
  wire \blk00000001/blk0000003e/sig00000170 ;
  wire \blk00000001/blk0000003e/sig0000016f ;
  wire \blk00000001/blk0000003e/sig0000016e ;
  wire \blk00000001/blk0000003e/sig0000016d ;
  wire \blk00000001/blk0000003e/sig0000016c ;
  wire \blk00000001/blk0000003e/sig0000016b ;
  wire \blk00000001/blk0000003e/sig0000016a ;
  wire \blk00000001/blk0000003e/sig00000169 ;
  wire \blk00000001/blk0000003e/sig00000168 ;
  wire \blk00000001/blk0000003e/sig00000167 ;
  wire \blk00000001/blk0000003e/sig00000166 ;
  wire \blk00000001/blk0000003e/sig00000165 ;
  wire \blk00000001/blk0000003e/sig00000153 ;
  wire \blk00000001/blk0000003e/sig00000152 ;
  wire \blk00000001/blk0000003e/sig00000151 ;
  wire \blk00000001/blk0000003e/sig00000150 ;
  wire \blk00000001/blk0000003e/sig0000014f ;
  wire \blk00000001/blk0000007b/sig000001be ;
  wire \blk00000001/blk0000007b/sig000001bd ;
  wire \blk00000001/blk0000007b/sig000001bc ;
  wire \blk00000001/blk0000007b/sig000001bb ;
  wire \blk00000001/blk0000007b/sig000001ba ;
  wire \blk00000001/blk0000007b/sig000001b9 ;
  wire \blk00000001/blk0000007b/sig000001b8 ;
  wire \blk00000001/blk0000007b/sig000001b7 ;
  wire \blk00000001/blk0000007b/sig000001b6 ;
  wire \blk00000001/blk0000007b/sig000001b5 ;
  wire \blk00000001/blk0000007b/sig000001b4 ;
  wire \blk00000001/blk0000007b/sig000001b3 ;
  wire \blk00000001/blk0000007b/sig000001b2 ;
  wire \blk00000001/blk0000007b/sig000001b1 ;
  wire \blk00000001/blk0000007b/sig000001b0 ;
  wire \blk00000001/blk0000007b/sig000001af ;
  wire \blk00000001/blk0000007b/sig000001ae ;
  wire \blk00000001/blk0000009d/sig000001f6 ;
  wire \blk00000001/blk0000009d/sig000001f5 ;
  wire \blk00000001/blk0000009d/sig000001f4 ;
  wire \blk00000001/blk0000009d/sig000001f3 ;
  wire \blk00000001/blk0000009d/sig000001f2 ;
  wire \blk00000001/blk0000009d/sig000001f1 ;
  wire \blk00000001/blk0000009d/sig000001f0 ;
  wire \blk00000001/blk0000009d/sig000001ef ;
  wire \blk00000001/blk0000009d/sig000001ee ;
  wire \blk00000001/blk0000009d/sig000001ed ;
  wire \blk00000001/blk0000009d/sig000001ec ;
  wire \blk00000001/blk0000009d/sig000001eb ;
  wire \blk00000001/blk0000009d/sig000001ea ;
  wire \blk00000001/blk0000009d/sig000001e9 ;
  wire \blk00000001/blk0000009d/sig000001e8 ;
  wire \blk00000001/blk0000009d/sig000001e7 ;
  wire \blk00000001/blk0000009d/sig000001e6 ;
  wire \blk00000001/blk000000bf/sig0000021c ;
  wire \blk00000001/blk000000bf/sig0000021b ;
  wire \blk00000001/blk000000bf/sig0000021a ;
  wire \blk00000001/blk000000bf/sig00000219 ;
  wire \blk00000001/blk000000bf/sig00000218 ;
  wire \blk00000001/blk000000bf/sig00000217 ;
  wire \blk00000001/blk000000bf/sig00000216 ;
  wire \blk00000001/blk000000bf/sig00000215 ;
  wire \blk00000001/blk000000bf/sig00000214 ;
  wire \blk00000001/blk000000bf/sig00000213 ;
  wire \blk00000001/blk000000bf/sig00000212 ;
  wire \blk00000001/blk000000bf/sig00000211 ;
  wire \blk00000001/blk000000bf/sig00000210 ;
  wire \blk00000001/blk000000bf/sig0000020f ;
  wire \blk00000001/blk000000bf/sig0000020e ;
  wire \blk00000001/blk000000bf/sig0000020d ;
  wire \blk00000001/blk000000e0/sig0000022f ;
  wire \blk00000001/blk000000e0/sig0000022e ;
  wire \blk00000001/blk000000e0/sig0000022d ;
  wire \blk00000001/blk000000e0/sig0000022b ;
  wire \blk00000001/blk000000e0/sig0000022a ;
  wire \blk00000001/blk000000e0/sig00000229 ;
  wire \NLW_blk00000001/blk00000157_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000155_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000153_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000151_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000014f_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000014d_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000014b_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000149_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000147_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000145_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000143_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000141_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000013f_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000013d_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000013b_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000139_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000137_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000135_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000133_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk00000131_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000012f_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000012d_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000012b_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_CARRYOUTF_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_CARRYOUT_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<17>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<16>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<15>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<14>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<13>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<12>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<11>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<10>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<9>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<8>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<7>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<6>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<5>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<4>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<3>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<2>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<1>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_BCOUT<0>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<47>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<46>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<45>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<44>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<43>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<42>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<41>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<40>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<39>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<38>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<37>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_P<36>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<47>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<46>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<45>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<44>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<43>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<42>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<41>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<40>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<39>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<38>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<37>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<36>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<35>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<34>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<33>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<32>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<31>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<30>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<29>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<28>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<27>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<26>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<25>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<24>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<23>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<22>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<21>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<20>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<19>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<18>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<17>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<16>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<15>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<14>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<13>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<12>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<11>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<10>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<9>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<8>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<7>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<6>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<5>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<4>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<3>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<2>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<1>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_PCOUT<0>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<35>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<34>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<33>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<32>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<31>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<30>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<29>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<28>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<27>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<26>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<25>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<24>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<23>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<22>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<21>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<20>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<19>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<18>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<17>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<16>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<15>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<14>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<13>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<12>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<11>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<10>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<9>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<8>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<7>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<6>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<5>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<4>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<3>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<2>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<1>_UNCONNECTED ;
  wire \NLW_blk00000001/blk000000e1_M<0>_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000065_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000064_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000063_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000062_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000061_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000060_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk0000005f_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk0000005e_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk0000005d_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk0000005c_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk0000005b_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk0000005a_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000059_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000058_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000057_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000003e/blk00000056_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk0000009c_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk0000009b_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk0000009a_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000099_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000098_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000097_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000096_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000095_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000094_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000093_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000092_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000091_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk00000090_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk0000008f_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk0000008e_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000007b/blk0000008d_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000be_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000bd_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000bc_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000bb_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000ba_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b9_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b8_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b7_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b6_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b5_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b4_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b3_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b2_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b1_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000b0_Q15_UNCONNECTED ;
  wire \NLW_blk00000001/blk0000009d/blk000000af_Q15_UNCONNECTED ;
  wire [35 : 0] NlwRenamedSig_OI_m_axis_data_tdata;
  assign
    m_axis_data_tdata[39] = NlwRenamedSig_OI_m_axis_data_tdata[35],
    m_axis_data_tdata[38] = NlwRenamedSig_OI_m_axis_data_tdata[35],
    m_axis_data_tdata[37] = NlwRenamedSig_OI_m_axis_data_tdata[35],
    m_axis_data_tdata[36] = NlwRenamedSig_OI_m_axis_data_tdata[35],
    m_axis_data_tdata[35] = NlwRenamedSig_OI_m_axis_data_tdata[35],
    m_axis_data_tdata[34] = NlwRenamedSig_OI_m_axis_data_tdata[34],
    m_axis_data_tdata[33] = NlwRenamedSig_OI_m_axis_data_tdata[33],
    m_axis_data_tdata[32] = NlwRenamedSig_OI_m_axis_data_tdata[32],
    m_axis_data_tdata[31] = NlwRenamedSig_OI_m_axis_data_tdata[31],
    m_axis_data_tdata[30] = NlwRenamedSig_OI_m_axis_data_tdata[30],
    m_axis_data_tdata[29] = NlwRenamedSig_OI_m_axis_data_tdata[29],
    m_axis_data_tdata[28] = NlwRenamedSig_OI_m_axis_data_tdata[28],
    m_axis_data_tdata[27] = NlwRenamedSig_OI_m_axis_data_tdata[27],
    m_axis_data_tdata[26] = NlwRenamedSig_OI_m_axis_data_tdata[26],
    m_axis_data_tdata[25] = NlwRenamedSig_OI_m_axis_data_tdata[25],
    m_axis_data_tdata[24] = NlwRenamedSig_OI_m_axis_data_tdata[24],
    m_axis_data_tdata[23] = NlwRenamedSig_OI_m_axis_data_tdata[23],
    m_axis_data_tdata[22] = NlwRenamedSig_OI_m_axis_data_tdata[22],
    m_axis_data_tdata[21] = NlwRenamedSig_OI_m_axis_data_tdata[21],
    m_axis_data_tdata[20] = NlwRenamedSig_OI_m_axis_data_tdata[20],
    m_axis_data_tdata[19] = NlwRenamedSig_OI_m_axis_data_tdata[19],
    m_axis_data_tdata[18] = NlwRenamedSig_OI_m_axis_data_tdata[18],
    m_axis_data_tdata[17] = NlwRenamedSig_OI_m_axis_data_tdata[17],
    m_axis_data_tdata[16] = NlwRenamedSig_OI_m_axis_data_tdata[16],
    m_axis_data_tdata[15] = NlwRenamedSig_OI_m_axis_data_tdata[15],
    m_axis_data_tdata[14] = NlwRenamedSig_OI_m_axis_data_tdata[14],
    m_axis_data_tdata[13] = NlwRenamedSig_OI_m_axis_data_tdata[13],
    m_axis_data_tdata[12] = NlwRenamedSig_OI_m_axis_data_tdata[12],
    m_axis_data_tdata[11] = NlwRenamedSig_OI_m_axis_data_tdata[11],
    m_axis_data_tdata[10] = NlwRenamedSig_OI_m_axis_data_tdata[10],
    m_axis_data_tdata[9] = NlwRenamedSig_OI_m_axis_data_tdata[9],
    m_axis_data_tdata[8] = NlwRenamedSig_OI_m_axis_data_tdata[8],
    m_axis_data_tdata[7] = NlwRenamedSig_OI_m_axis_data_tdata[7],
    m_axis_data_tdata[6] = NlwRenamedSig_OI_m_axis_data_tdata[6],
    m_axis_data_tdata[5] = NlwRenamedSig_OI_m_axis_data_tdata[5],
    m_axis_data_tdata[4] = NlwRenamedSig_OI_m_axis_data_tdata[4],
    m_axis_data_tdata[3] = NlwRenamedSig_OI_m_axis_data_tdata[3],
    m_axis_data_tdata[2] = NlwRenamedSig_OI_m_axis_data_tdata[2],
    m_axis_data_tdata[1] = NlwRenamedSig_OI_m_axis_data_tdata[1],
    m_axis_data_tdata[0] = NlwRenamedSig_OI_m_axis_data_tdata[0],
    s_axis_data_tready = NlwRenamedSig_OI_s_axis_data_tready;
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000158  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000139 ),
    .Q(\blk00000001/sig00000071 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000157  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000114 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000112 ),
    .Q(\blk00000001/sig00000139 ),
    .Q15(\NLW_blk00000001/blk00000157_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000156  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000138 ),
    .Q(\blk00000001/sig00000073 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000155  (
    .A0(\blk00000001/sig00000114 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000aa ),
    .Q(\blk00000001/sig00000138 ),
    .Q15(\NLW_blk00000001/blk00000155_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000154  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000137 ),
    .Q(\blk00000001/sig00000098 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000153  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d3 ),
    .Q(\blk00000001/sig00000137 ),
    .Q15(\NLW_blk00000001/blk00000153_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000152  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000136 ),
    .Q(\blk00000001/sig00000099 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000151  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d4 ),
    .Q(\blk00000001/sig00000136 ),
    .Q15(\NLW_blk00000001/blk00000151_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000150  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000135 ),
    .Q(\blk00000001/sig00000072 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000014f  (
    .A0(\blk00000001/sig00000114 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000006e ),
    .Q(\blk00000001/sig00000135 ),
    .Q15(\NLW_blk00000001/blk0000014f_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000014e  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000134 ),
    .Q(\blk00000001/sig0000009b )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000014d  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d6 ),
    .Q(\blk00000001/sig00000134 ),
    .Q15(\NLW_blk00000001/blk0000014d_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000014c  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000133 ),
    .Q(\blk00000001/sig0000009c )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000014b  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d7 ),
    .Q(\blk00000001/sig00000133 ),
    .Q15(\NLW_blk00000001/blk0000014b_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000014a  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000132 ),
    .Q(\blk00000001/sig0000009a )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000149  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d5 ),
    .Q(\blk00000001/sig00000132 ),
    .Q15(\NLW_blk00000001/blk00000149_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000148  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000131 ),
    .Q(\blk00000001/sig0000009e )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000147  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d9 ),
    .Q(\blk00000001/sig00000131 ),
    .Q15(\NLW_blk00000001/blk00000147_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000146  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000130 ),
    .Q(\blk00000001/sig0000009f )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000145  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000da ),
    .Q(\blk00000001/sig00000130 ),
    .Q15(\NLW_blk00000001/blk00000145_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000144  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig0000012f ),
    .Q(\blk00000001/sig0000009d )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000143  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000d8 ),
    .Q(\blk00000001/sig0000012f ),
    .Q15(\NLW_blk00000001/blk00000143_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000142  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig0000012e ),
    .Q(\blk00000001/sig000000a1 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000141  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000dc ),
    .Q(\blk00000001/sig0000012e ),
    .Q15(\NLW_blk00000001/blk00000141_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000140  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig0000012d ),
    .Q(\blk00000001/sig000000a2 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000013f  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000dd ),
    .Q(\blk00000001/sig0000012d ),
    .Q15(\NLW_blk00000001/blk0000013f_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000013e  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig0000012c ),
    .Q(\blk00000001/sig000000a0 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000013d  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000db ),
    .Q(\blk00000001/sig0000012c ),
    .Q15(\NLW_blk00000001/blk0000013d_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000013c  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig0000012b ),
    .Q(\blk00000001/sig000000a4 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000013b  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000df ),
    .Q(\blk00000001/sig0000012b ),
    .Q15(\NLW_blk00000001/blk0000013b_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000013a  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig0000012a ),
    .Q(\blk00000001/sig000000a5 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000139  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000e0 ),
    .Q(\blk00000001/sig0000012a ),
    .Q15(\NLW_blk00000001/blk00000139_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000138  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000129 ),
    .Q(\blk00000001/sig000000a3 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000137  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000de ),
    .Q(\blk00000001/sig00000129 ),
    .Q15(\NLW_blk00000001/blk00000137_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000136  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000128 ),
    .Q(\blk00000001/sig000000a7 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000135  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000e2 ),
    .Q(\blk00000001/sig00000128 ),
    .Q15(\NLW_blk00000001/blk00000135_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000134  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000127 ),
    .Q(\blk00000001/sig000000e8 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000133  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000063 ),
    .Q(\blk00000001/sig00000127 ),
    .Q15(\NLW_blk00000001/blk00000133_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000132  (
    .C(aclk),
    .CE(\blk00000001/sig00000070 ),
    .D(\blk00000001/sig00000126 ),
    .Q(\blk00000001/sig000000a6 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk00000131  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000070 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000e1 ),
    .Q(\blk00000001/sig00000126 ),
    .Q15(\NLW_blk00000001/blk00000131_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000130  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000125 ),
    .Q(\blk00000001/sig000000ea )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000012f  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000061 ),
    .Q(\blk00000001/sig00000125 ),
    .Q15(\NLW_blk00000001/blk0000012f_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000012e  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000124 ),
    .Q(\blk00000001/sig000000eb )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000012d  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000060 ),
    .Q(\blk00000001/sig00000124 ),
    .Q15(\NLW_blk00000001/blk0000012d_Q15_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000012c  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000123 ),
    .Q(\blk00000001/sig000000e9 )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000012b  (
    .A0(\blk00000001/sig00000039 ),
    .A1(\blk00000001/sig00000039 ),
    .A2(\blk00000001/sig00000039 ),
    .A3(\blk00000001/sig00000039 ),
    .CE(\blk00000001/sig00000114 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000062 ),
    .Q(\blk00000001/sig00000123 ),
    .Q15(\NLW_blk00000001/blk0000012b_Q15_UNCONNECTED )
  );
  INV   \blk00000001/blk0000012a  (
    .I(\blk00000001/sig0000006c ),
    .O(\blk00000001/sig0000006b )
  );
  INV   \blk00000001/blk00000129  (
    .I(\blk00000001/sig00000112 ),
    .O(\blk00000001/sig00000111 )
  );
  LUT3 #(
    .INIT ( 8'h52 ))
  \blk00000001/blk00000128  (
    .I0(\blk00000001/sig0000006e ),
    .I1(\blk00000001/sig00000070 ),
    .I2(\blk00000001/sig00000063 ),
    .O(\blk00000001/sig0000011e )
  );
  LUT4 #(
    .INIT ( 16'h0A6A ))
  \blk00000001/blk00000127  (
    .I0(\blk00000001/sig00000062 ),
    .I1(\blk00000001/sig00000063 ),
    .I2(\blk00000001/sig0000006e ),
    .I3(\blk00000001/sig00000070 ),
    .O(\blk00000001/sig0000011d )
  );
  LUT5 #(
    .INIT ( 32'h00AA6AAA ))
  \blk00000001/blk00000126  (
    .I0(\blk00000001/sig00000061 ),
    .I1(\blk00000001/sig00000062 ),
    .I2(\blk00000001/sig00000063 ),
    .I3(\blk00000001/sig0000006e ),
    .I4(\blk00000001/sig00000070 ),
    .O(\blk00000001/sig0000011c )
  );
  LUT6 #(
    .INIT ( 64'h0000AAAA6AAAAAAA ))
  \blk00000001/blk00000125  (
    .I0(\blk00000001/sig00000060 ),
    .I1(\blk00000001/sig00000061 ),
    .I2(\blk00000001/sig00000062 ),
    .I3(\blk00000001/sig00000063 ),
    .I4(\blk00000001/sig0000006e ),
    .I5(\blk00000001/sig00000070 ),
    .O(\blk00000001/sig0000011b )
  );
  LUT4 #(
    .INIT ( 16'hFA9A ))
  \blk00000001/blk00000124  (
    .I0(\blk00000001/sig000000ac ),
    .I1(\blk00000001/sig00000064 ),
    .I2(\blk00000001/sig0000006e ),
    .I3(\blk00000001/sig000000aa ),
    .O(\blk00000001/sig0000011a )
  );
  LUT5 #(
    .INIT ( 32'hFFAAA9AA ))
  \blk00000001/blk00000123  (
    .I0(\blk00000001/sig000000ad ),
    .I1(\blk00000001/sig00000064 ),
    .I2(\blk00000001/sig000000ac ),
    .I3(\blk00000001/sig0000006e ),
    .I4(\blk00000001/sig000000aa ),
    .O(\blk00000001/sig00000120 )
  );
  LUT6 #(
    .INIT ( 64'hFFAAFFAAAAAAA9AA ))
  \blk00000001/blk00000122  (
    .I0(\blk00000001/sig000000ae ),
    .I1(\blk00000001/sig000000ad ),
    .I2(\blk00000001/sig00000064 ),
    .I3(\blk00000001/sig0000006e ),
    .I4(\blk00000001/sig000000ac ),
    .I5(\blk00000001/sig000000aa ),
    .O(\blk00000001/sig00000121 )
  );
  LUT6 #(
    .INIT ( 64'h444444446CCCCCCC ))
  \blk00000001/blk00000121  (
    .I0(\blk00000001/sig0000006e ),
    .I1(\blk00000001/sig00000065 ),
    .I2(\blk00000001/sig00000066 ),
    .I3(\blk00000001/sig00000067 ),
    .I4(\blk00000001/sig00000068 ),
    .I5(\blk00000001/sig000000aa ),
    .O(\blk00000001/sig00000122 )
  );
  LUT5 #(
    .INIT ( 32'h52707070 ))
  \blk00000001/blk00000120  (
    .I0(\blk00000001/sig0000006e ),
    .I1(\blk00000001/sig000000aa ),
    .I2(\blk00000001/sig00000066 ),
    .I3(\blk00000001/sig00000068 ),
    .I4(\blk00000001/sig00000067 ),
    .O(\blk00000001/sig0000011f )
  );
  LUT4 #(
    .INIT ( 16'h5270 ))
  \blk00000001/blk0000011f  (
    .I0(\blk00000001/sig0000006e ),
    .I1(\blk00000001/sig000000aa ),
    .I2(\blk00000001/sig00000067 ),
    .I3(\blk00000001/sig00000068 ),
    .O(\blk00000001/sig00000119 )
  );
  LUT3 #(
    .INIT ( 8'h52 ))
  \blk00000001/blk0000011e  (
    .I0(\blk00000001/sig0000006e ),
    .I1(\blk00000001/sig000000aa ),
    .I2(\blk00000001/sig00000064 ),
    .O(\blk00000001/sig00000118 )
  );
  LUT3 #(
    .INIT ( 8'h52 ))
  \blk00000001/blk0000011d  (
    .I0(\blk00000001/sig0000006e ),
    .I1(\blk00000001/sig000000aa ),
    .I2(\blk00000001/sig00000068 ),
    .O(\blk00000001/sig00000117 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000011c  (
    .C(aclk),
    .D(\blk00000001/sig00000122 ),
    .Q(\blk00000001/sig00000065 )
  );
  FD #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000011b  (
    .C(aclk),
    .D(\blk00000001/sig00000121 ),
    .Q(\blk00000001/sig000000ae )
  );
  FD #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000011a  (
    .C(aclk),
    .D(\blk00000001/sig00000120 ),
    .Q(\blk00000001/sig000000ad )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000119  (
    .C(aclk),
    .D(\blk00000001/sig0000011f ),
    .Q(\blk00000001/sig00000066 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000118  (
    .C(aclk),
    .D(\blk00000001/sig0000011e ),
    .Q(\blk00000001/sig00000063 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000117  (
    .C(aclk),
    .D(\blk00000001/sig0000011d ),
    .Q(\blk00000001/sig00000062 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000116  (
    .C(aclk),
    .D(\blk00000001/sig0000011c ),
    .Q(\blk00000001/sig00000061 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000115  (
    .C(aclk),
    .D(\blk00000001/sig0000011b ),
    .Q(\blk00000001/sig00000060 )
  );
  FD #(
    .INIT ( 1'b1 ))
  \blk00000001/blk00000114  (
    .C(aclk),
    .D(\blk00000001/sig0000011a ),
    .Q(\blk00000001/sig000000ac )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000113  (
    .C(aclk),
    .D(\blk00000001/sig00000119 ),
    .Q(\blk00000001/sig00000067 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000112  (
    .C(aclk),
    .D(\blk00000001/sig00000118 ),
    .Q(\blk00000001/sig00000064 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000111  (
    .C(aclk),
    .D(\blk00000001/sig00000117 ),
    .Q(\blk00000001/sig00000068 )
  );
  LUT2 #(
    .INIT ( 4'h1 ))
  \blk00000001/blk00000110  (
    .I0(\blk00000001/sig00000073 ),
    .I1(\blk00000001/sig00000072 ),
    .O(\blk00000001/sig00000113 )
  );
  LUT4 #(
    .INIT ( 16'hA0EC ))
  \blk00000001/blk0000010f  (
    .I0(\blk00000001/sig000000fc ),
    .I1(\blk00000001/sig0000006e ),
    .I2(\blk00000001/sig0000005f ),
    .I3(\blk00000001/sig00000070 ),
    .O(\blk00000001/sig00000116 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000010e  (
    .C(aclk),
    .D(\blk00000001/sig000000ff ),
    .Q(NlwRenamedSig_OI_s_axis_data_tready)
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000010d  (
    .C(aclk),
    .D(\blk00000001/sig00000116 ),
    .Q(\blk00000001/sig0000006e )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000010c  (
    .C(aclk),
    .D(\blk00000001/sig00000115 ),
    .Q(\blk00000001/sig0000006d )
  );
  LUT2 #(
    .INIT ( 4'h4 ))
  \blk00000001/blk0000010b  (
    .I0(\blk00000001/sig00000073 ),
    .I1(\blk00000001/sig00000072 ),
    .O(\blk00000001/sig00000115 )
  );
  FD #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000010a  (
    .C(aclk),
    .D(\blk00000001/sig00000113 ),
    .Q(\blk00000001/sig0000006c )
  );
  LUT2 #(
    .INIT ( 4'h8 ))
  \blk00000001/blk00000109  (
    .I0(NlwRenamedSig_OI_s_axis_data_tready),
    .I1(s_axis_data_tvalid),
    .O(\blk00000001/sig000000fd )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000108  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[0]),
    .I1(\blk00000001/sig00000074 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000005d )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000107  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[1]),
    .I1(\blk00000001/sig00000075 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000005c )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000106  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[2]),
    .I1(\blk00000001/sig00000076 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000005b )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000105  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[3]),
    .I1(\blk00000001/sig00000077 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000005a )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000104  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[4]),
    .I1(\blk00000001/sig00000078 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000059 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000103  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[5]),
    .I1(\blk00000001/sig00000079 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000058 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000102  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[6]),
    .I1(\blk00000001/sig0000007a ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000057 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000101  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[7]),
    .I1(\blk00000001/sig0000007b ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000056 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk00000100  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[8]),
    .I1(\blk00000001/sig0000007c ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000055 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000ff  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[9]),
    .I1(\blk00000001/sig0000007d ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000054 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000fe  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[10]),
    .I1(\blk00000001/sig0000007e ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000053 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000fd  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[11]),
    .I1(\blk00000001/sig0000007f ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000052 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000fc  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[12]),
    .I1(\blk00000001/sig00000080 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000051 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000fb  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[13]),
    .I1(\blk00000001/sig00000081 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000050 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000fa  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[14]),
    .I1(\blk00000001/sig00000082 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000004f )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f9  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[15]),
    .I1(\blk00000001/sig00000083 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000004e )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f8  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[16]),
    .I1(\blk00000001/sig00000084 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000004d )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f7  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[17]),
    .I1(\blk00000001/sig00000085 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000004c )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f6  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[18]),
    .I1(\blk00000001/sig00000086 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000004b )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f5  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[19]),
    .I1(\blk00000001/sig00000087 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000004a )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f4  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[20]),
    .I1(\blk00000001/sig00000088 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000049 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f3  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[21]),
    .I1(\blk00000001/sig00000089 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000048 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f2  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[22]),
    .I1(\blk00000001/sig0000008a ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000047 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f1  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[23]),
    .I1(\blk00000001/sig0000008b ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000046 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000f0  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[24]),
    .I1(\blk00000001/sig0000008c ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000045 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000ef  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[25]),
    .I1(\blk00000001/sig0000008d ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000044 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000ee  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[26]),
    .I1(\blk00000001/sig0000008e ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000043 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000ed  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[27]),
    .I1(\blk00000001/sig0000008f ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000042 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000ec  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[28]),
    .I1(\blk00000001/sig00000090 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000041 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000eb  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[29]),
    .I1(\blk00000001/sig00000091 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig00000040 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000ea  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[30]),
    .I1(\blk00000001/sig00000092 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000003f )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000e9  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[31]),
    .I1(\blk00000001/sig00000093 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000003e )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000e8  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[32]),
    .I1(\blk00000001/sig00000094 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000003d )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000e7  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[33]),
    .I1(\blk00000001/sig00000095 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000003c )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000e6  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[34]),
    .I1(\blk00000001/sig00000096 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000003b )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000001/blk000000e5  (
    .I0(NlwRenamedSig_OI_m_axis_data_tdata[35]),
    .I1(\blk00000001/sig00000097 ),
    .I2(\blk00000001/sig00000071 ),
    .O(\blk00000001/sig0000003a )
  );
  LUT6 #(
    .INIT ( 64'h3333333300A00000 ))
  \blk00000001/blk000000e4  (
    .I0(\blk00000001/sig00000060 ),
    .I1(\blk00000001/sig000000fc ),
    .I2(\blk00000001/sig00000061 ),
    .I3(\blk00000001/sig00000062 ),
    .I4(\blk00000001/sig00000063 ),
    .I5(\blk00000001/sig0000005f ),
    .O(\blk00000001/sig0000005e )
  );
  LUT2 #(
    .INIT ( 4'h8 ))
  \blk00000001/blk000000e3  (
    .I0(\blk00000001/sig0000005f ),
    .I1(\blk00000001/sig000000fc ),
    .O(\blk00000001/sig0000006a )
  );
  LUT4 #(
    .INIT ( 16'h2000 ))
  \blk00000001/blk000000e2  (
    .I0(\blk00000001/sig00000063 ),
    .I1(\blk00000001/sig00000062 ),
    .I2(\blk00000001/sig00000061 ),
    .I3(\blk00000001/sig00000060 ),
    .O(\blk00000001/sig00000069 )
  );
  DSP48A1 #(
    .A0REG ( 0 ),
    .A1REG ( 1 ),
    .B0REG ( 1 ),
    .B1REG ( 1 ),
    .CARRYINREG ( 0 ),
    .CARRYINSEL ( "OPMODE5" ),
    .CARRYOUTREG ( 0 ),
    .CREG ( 1 ),
    .DREG ( 1 ),
    .MREG ( 1 ),
    .OPMODEREG ( 1 ),
    .PREG ( 1 ),
    .RSTTYPE ( "SYNC" ))
  \blk00000001/blk000000e1  (
    .CECARRYIN(\blk00000001/sig00000114 ),
    .RSTC(\blk00000001/sig00000039 ),
    .RSTCARRYIN(\blk00000001/sig00000039 ),
    .CED(\blk00000001/sig00000114 ),
    .RSTD(\blk00000001/sig00000039 ),
    .CEOPMODE(\blk00000001/sig00000114 ),
    .CEC(\blk00000001/sig00000114 ),
    .CARRYOUTF(\NLW_blk00000001/blk000000e1_CARRYOUTF_UNCONNECTED ),
    .RSTOPMODE(\blk00000001/sig00000039 ),
    .RSTM(\blk00000001/sig00000039 ),
    .CLK(aclk),
    .RSTB(\blk00000001/sig00000039 ),
    .CEM(\blk00000001/sig00000114 ),
    .CEB(\blk00000001/sig00000114 ),
    .CARRYIN(\blk00000001/sig00000039 ),
    .CEP(\blk00000001/sig00000114 ),
    .CEA(\blk00000001/sig00000114 ),
    .CARRYOUT(\NLW_blk00000001/blk000000e1_CARRYOUT_UNCONNECTED ),
    .RSTA(\blk00000001/sig00000039 ),
    .RSTP(\blk00000001/sig00000039 ),
    .B({\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig000000d2 , \blk00000001/sig000000d1 , \blk00000001/sig000000d0 , 
\blk00000001/sig000000cf , \blk00000001/sig000000ce , \blk00000001/sig000000cd , \blk00000001/sig000000cc , \blk00000001/sig000000cb , 
\blk00000001/sig000000ca , \blk00000001/sig000000c9 , \blk00000001/sig000000c8 , \blk00000001/sig000000c7 , \blk00000001/sig000000c6 , 
\blk00000001/sig000000c5 , \blk00000001/sig000000c4 , \blk00000001/sig000000c3 }),
    .BCOUT({\NLW_blk00000001/blk000000e1_BCOUT<17>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<16>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<15>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<14>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<13>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<12>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<11>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<10>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<9>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<8>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<7>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<6>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<5>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<4>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<3>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<2>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_BCOUT<1>_UNCONNECTED , \NLW_blk00000001/blk000000e1_BCOUT<0>_UNCONNECTED }),
    .PCIN({\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 }),
    .C({\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , 
\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 }),
    .P({\NLW_blk00000001/blk000000e1_P<47>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<46>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_P<45>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<44>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<43>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_P<42>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<41>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<40>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_P<39>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<38>_UNCONNECTED , \NLW_blk00000001/blk000000e1_P<37>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_P<36>_UNCONNECTED , \blk00000001/sig00000097 , \blk00000001/sig00000096 , \blk00000001/sig00000095 , 
\blk00000001/sig00000094 , \blk00000001/sig00000093 , \blk00000001/sig00000092 , \blk00000001/sig00000091 , \blk00000001/sig00000090 , 
\blk00000001/sig0000008f , \blk00000001/sig0000008e , \blk00000001/sig0000008d , \blk00000001/sig0000008c , \blk00000001/sig0000008b , 
\blk00000001/sig0000008a , \blk00000001/sig00000089 , \blk00000001/sig00000088 , \blk00000001/sig00000087 , \blk00000001/sig00000086 , 
\blk00000001/sig00000085 , \blk00000001/sig00000084 , \blk00000001/sig00000083 , \blk00000001/sig00000082 , \blk00000001/sig00000081 , 
\blk00000001/sig00000080 , \blk00000001/sig0000007f , \blk00000001/sig0000007e , \blk00000001/sig0000007d , \blk00000001/sig0000007c , 
\blk00000001/sig0000007b , \blk00000001/sig0000007a , \blk00000001/sig00000079 , \blk00000001/sig00000078 , \blk00000001/sig00000077 , 
\blk00000001/sig00000076 , \blk00000001/sig00000075 , \blk00000001/sig00000074 }),
    .OPMODE({\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig00000111 , \blk00000001/sig0000006d , 
\blk00000001/sig00000039 , \blk00000001/sig0000006c , \blk00000001/sig0000006b }),
    .D({\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig000000e2 , \blk00000001/sig000000e1 , \blk00000001/sig000000e0 , 
\blk00000001/sig000000df , \blk00000001/sig000000de , \blk00000001/sig000000dd , \blk00000001/sig000000dc , \blk00000001/sig000000db , 
\blk00000001/sig000000da , \blk00000001/sig000000d9 , \blk00000001/sig000000d8 , \blk00000001/sig000000d7 , \blk00000001/sig000000d6 , 
\blk00000001/sig000000d5 , \blk00000001/sig000000d4 , \blk00000001/sig000000d3 }),
    .PCOUT({\NLW_blk00000001/blk000000e1_PCOUT<47>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<46>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<45>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<44>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<43>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<42>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<41>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<40>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<39>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<38>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<37>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<36>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<35>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<34>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<33>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<32>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<31>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<30>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<29>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<28>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<27>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<26>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<25>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<24>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<23>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<22>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<21>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<20>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<19>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<18>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<17>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<16>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<15>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<14>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<13>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<12>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<11>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<10>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<9>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<8>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<7>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<6>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<5>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<4>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<3>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<2>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_PCOUT<1>_UNCONNECTED , \NLW_blk00000001/blk000000e1_PCOUT<0>_UNCONNECTED }),
    .A({\blk00000001/sig00000039 , \blk00000001/sig00000039 , \blk00000001/sig000000c2 , \blk00000001/sig000000c1 , \blk00000001/sig000000c0 , 
\blk00000001/sig000000bf , \blk00000001/sig000000be , \blk00000001/sig000000bd , \blk00000001/sig000000bc , \blk00000001/sig000000bb , 
\blk00000001/sig000000ba , \blk00000001/sig000000b9 , \blk00000001/sig000000b8 , \blk00000001/sig000000b7 , \blk00000001/sig000000b6 , 
\blk00000001/sig000000b5 , \blk00000001/sig000000b4 , \blk00000001/sig000000b3 }),
    .M({\NLW_blk00000001/blk000000e1_M<35>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<34>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<33>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<32>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<31>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<30>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<29>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<28>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<27>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<26>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<25>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<24>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<23>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<22>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<21>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<20>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<19>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<18>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<17>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<16>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<15>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<14>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<13>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<12>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<11>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<10>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<9>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<8>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<7>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<6>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<5>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<4>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<3>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<2>_UNCONNECTED , \NLW_blk00000001/blk000000e1_M<1>_UNCONNECTED , 
\NLW_blk00000001/blk000000e1_M<0>_UNCONNECTED })
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007a  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000070 ),
    .R(\blk00000001/sig00000039 ),
    .Q(\blk00000001/sig00000110 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000079  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig00000110 ),
    .R(\blk00000001/sig00000039 ),
    .Q(\blk00000001/sig00000112 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000078  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/sig0000006f ),
    .R(\blk00000001/sig00000039 ),
    .Q(\blk00000001/sig000000a9 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003d  (
    .C(aclk),
    .D(s_axis_data_tdata[0]),
    .Q(\blk00000001/sig00000100 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003c  (
    .C(aclk),
    .D(s_axis_data_tdata[1]),
    .Q(\blk00000001/sig00000101 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003b  (
    .C(aclk),
    .D(s_axis_data_tdata[2]),
    .Q(\blk00000001/sig00000102 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003a  (
    .C(aclk),
    .D(s_axis_data_tdata[3]),
    .Q(\blk00000001/sig00000103 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000039  (
    .C(aclk),
    .D(s_axis_data_tdata[4]),
    .Q(\blk00000001/sig00000104 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000038  (
    .C(aclk),
    .D(s_axis_data_tdata[5]),
    .Q(\blk00000001/sig00000105 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000037  (
    .C(aclk),
    .D(s_axis_data_tdata[6]),
    .Q(\blk00000001/sig00000106 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000036  (
    .C(aclk),
    .D(s_axis_data_tdata[7]),
    .Q(\blk00000001/sig00000107 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000035  (
    .C(aclk),
    .D(s_axis_data_tdata[8]),
    .Q(\blk00000001/sig00000108 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000034  (
    .C(aclk),
    .D(s_axis_data_tdata[9]),
    .Q(\blk00000001/sig00000109 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000033  (
    .C(aclk),
    .D(s_axis_data_tdata[10]),
    .Q(\blk00000001/sig0000010a )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000032  (
    .C(aclk),
    .D(s_axis_data_tdata[11]),
    .Q(\blk00000001/sig0000010b )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000031  (
    .C(aclk),
    .D(s_axis_data_tdata[12]),
    .Q(\blk00000001/sig0000010c )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000030  (
    .C(aclk),
    .D(s_axis_data_tdata[13]),
    .Q(\blk00000001/sig0000010d )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000002f  (
    .C(aclk),
    .D(s_axis_data_tdata[14]),
    .Q(\blk00000001/sig0000010e )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000002e  (
    .C(aclk),
    .D(s_axis_data_tdata[15]),
    .Q(\blk00000001/sig0000010f )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000002d  (
    .C(aclk),
    .D(\blk00000001/sig000000fd ),
    .Q(\blk00000001/sig000000fe )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000002c  (
    .C(aclk),
    .D(\blk00000001/sig0000006a ),
    .Q(\blk00000001/sig000000aa )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000002b  (
    .C(aclk),
    .D(\blk00000001/sig00000069 ),
    .Q(\blk00000001/sig00000070 )
  );
  FD #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000002a  (
    .C(aclk),
    .D(\blk00000001/sig00000069 ),
    .Q(\blk00000001/sig0000006f )
  );
  FD #(
    .INIT ( 1'b1 ))
  \blk00000001/blk00000029  (
    .C(aclk),
    .D(\blk00000001/sig0000005e ),
    .Q(\blk00000001/sig0000005f )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000028  (
    .C(aclk),
    .D(\blk00000001/sig00000071 ),
    .Q(m_axis_data_tvalid)
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000027  (
    .C(aclk),
    .D(\blk00000001/sig0000005d ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[0])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000026  (
    .C(aclk),
    .D(\blk00000001/sig0000005c ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[1])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000025  (
    .C(aclk),
    .D(\blk00000001/sig0000005b ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[2])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000024  (
    .C(aclk),
    .D(\blk00000001/sig0000005a ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[3])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000023  (
    .C(aclk),
    .D(\blk00000001/sig00000059 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[4])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000022  (
    .C(aclk),
    .D(\blk00000001/sig00000058 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[5])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000021  (
    .C(aclk),
    .D(\blk00000001/sig00000057 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[6])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000020  (
    .C(aclk),
    .D(\blk00000001/sig00000056 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[7])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000001f  (
    .C(aclk),
    .D(\blk00000001/sig00000055 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[8])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000001e  (
    .C(aclk),
    .D(\blk00000001/sig00000054 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[9])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000001d  (
    .C(aclk),
    .D(\blk00000001/sig00000053 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[10])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000001c  (
    .C(aclk),
    .D(\blk00000001/sig00000052 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[11])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000001b  (
    .C(aclk),
    .D(\blk00000001/sig00000051 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[12])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000001a  (
    .C(aclk),
    .D(\blk00000001/sig00000050 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[13])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000019  (
    .C(aclk),
    .D(\blk00000001/sig0000004f ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[14])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000018  (
    .C(aclk),
    .D(\blk00000001/sig0000004e ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[15])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000017  (
    .C(aclk),
    .D(\blk00000001/sig0000004d ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[16])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000016  (
    .C(aclk),
    .D(\blk00000001/sig0000004c ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[17])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000015  (
    .C(aclk),
    .D(\blk00000001/sig0000004b ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[18])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000014  (
    .C(aclk),
    .D(\blk00000001/sig0000004a ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[19])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000013  (
    .C(aclk),
    .D(\blk00000001/sig00000049 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[20])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000012  (
    .C(aclk),
    .D(\blk00000001/sig00000048 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[21])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000011  (
    .C(aclk),
    .D(\blk00000001/sig00000047 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[22])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000010  (
    .C(aclk),
    .D(\blk00000001/sig00000046 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[23])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000000f  (
    .C(aclk),
    .D(\blk00000001/sig00000045 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[24])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000000e  (
    .C(aclk),
    .D(\blk00000001/sig00000044 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[25])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000000d  (
    .C(aclk),
    .D(\blk00000001/sig00000043 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[26])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000000c  (
    .C(aclk),
    .D(\blk00000001/sig00000042 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[27])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000000b  (
    .C(aclk),
    .D(\blk00000001/sig00000041 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[28])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000000a  (
    .C(aclk),
    .D(\blk00000001/sig00000040 ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[29])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000009  (
    .C(aclk),
    .D(\blk00000001/sig0000003f ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[30])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000008  (
    .C(aclk),
    .D(\blk00000001/sig0000003e ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[31])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000007  (
    .C(aclk),
    .D(\blk00000001/sig0000003d ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[32])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000006  (
    .C(aclk),
    .D(\blk00000001/sig0000003c ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[33])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000005  (
    .C(aclk),
    .D(\blk00000001/sig0000003b ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[34])
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000001/blk00000004  (
    .C(aclk),
    .D(\blk00000001/sig0000003a ),
    .Q(NlwRenamedSig_OI_m_axis_data_tdata[35])
  );
  GND   \blk00000001/blk00000003  (
    .G(\blk00000001/sig00000039 )
  );
  VCC   \blk00000001/blk00000002  (
    .P(\blk00000001/sig00000114 )
  );
  LUT2 #(
    .INIT ( 4'hE ))
  \blk00000001/blk0000003e/blk00000077  (
    .I0(\blk00000001/blk0000003e/sig0000014f ),
    .I1(\blk00000001/sig0000005f ),
    .O(\blk00000001/blk0000003e/sig00000184 )
  );
  LUT3 #(
    .INIT ( 8'h9C ))
  \blk00000001/blk0000003e/blk00000076  (
    .I0(\blk00000001/blk0000003e/sig0000014f ),
    .I1(\blk00000001/blk0000003e/sig00000150 ),
    .I2(\blk00000001/sig0000005f ),
    .O(\blk00000001/blk0000003e/sig00000182 )
  );
  LUT3 #(
    .INIT ( 8'h9C ))
  \blk00000001/blk0000003e/blk00000075  (
    .I0(\blk00000001/blk0000003e/sig0000014f ),
    .I1(\blk00000001/blk0000003e/sig00000151 ),
    .I2(\blk00000001/sig0000005f ),
    .O(\blk00000001/blk0000003e/sig00000180 )
  );
  LUT3 #(
    .INIT ( 8'h9C ))
  \blk00000001/blk0000003e/blk00000074  (
    .I0(\blk00000001/blk0000003e/sig0000014f ),
    .I1(\blk00000001/blk0000003e/sig00000152 ),
    .I2(\blk00000001/sig0000005f ),
    .O(\blk00000001/blk0000003e/sig0000017e )
  );
  LUT3 #(
    .INIT ( 8'h9C ))
  \blk00000001/blk0000003e/blk00000073  (
    .I0(\blk00000001/blk0000003e/sig0000014f ),
    .I1(\blk00000001/blk0000003e/sig00000153 ),
    .I2(\blk00000001/sig0000005f ),
    .O(\blk00000001/blk0000003e/sig0000017c )
  );
  LUT6 #(
    .INIT ( 64'hAAAABAAAAAAA8AAA ))
  \blk00000001/blk0000003e/blk00000072  (
    .I0(\blk00000001/sig000000ff ),
    .I1(\blk00000001/blk0000003e/sig00000152 ),
    .I2(\blk00000001/blk0000003e/sig00000150 ),
    .I3(\blk00000001/blk0000003e/sig00000151 ),
    .I4(\blk00000001/blk0000003e/sig00000153 ),
    .I5(\blk00000001/blk0000003e/sig00000186 ),
    .O(\blk00000001/blk0000003e/sig00000175 )
  );
  LUT4 #(
    .INIT ( 16'h2B0A ))
  \blk00000001/blk0000003e/blk00000071  (
    .I0(\blk00000001/sig000000ff ),
    .I1(\blk00000001/blk0000003e/sig0000014f ),
    .I2(\blk00000001/sig000000fe ),
    .I3(\blk00000001/sig0000005f ),
    .O(\blk00000001/blk0000003e/sig00000186 )
  );
  LUT6 #(
    .INIT ( 64'hEEAAFFAAEEA8FFAA ))
  \blk00000001/blk0000003e/blk00000070  (
    .I0(\blk00000001/sig000000fc ),
    .I1(\blk00000001/blk0000003e/sig0000014f ),
    .I2(\blk00000001/blk0000003e/sig00000150 ),
    .I3(\blk00000001/sig000000fe ),
    .I4(\blk00000001/sig0000005f ),
    .I5(\blk00000001/blk0000003e/sig00000185 ),
    .O(\blk00000001/blk0000003e/sig00000176 )
  );
  LUT3 #(
    .INIT ( 8'hFE ))
  \blk00000001/blk0000003e/blk0000006f  (
    .I0(\blk00000001/blk0000003e/sig00000151 ),
    .I1(\blk00000001/blk0000003e/sig00000152 ),
    .I2(\blk00000001/blk0000003e/sig00000153 ),
    .O(\blk00000001/blk0000003e/sig00000185 )
  );
  XORCY   \blk00000001/blk0000003e/blk0000006e  (
    .CI(\blk00000001/blk0000003e/sig00000183 ),
    .LI(\blk00000001/blk0000003e/sig00000184 ),
    .O(\blk00000001/blk0000003e/sig0000017b )
  );
  XORCY   \blk00000001/blk0000003e/blk0000006d  (
    .CI(\blk00000001/blk0000003e/sig00000181 ),
    .LI(\blk00000001/blk0000003e/sig00000182 ),
    .O(\blk00000001/blk0000003e/sig0000017a )
  );
  MUXCY   \blk00000001/blk0000003e/blk0000006c  (
    .CI(\blk00000001/blk0000003e/sig00000181 ),
    .DI(\blk00000001/blk0000003e/sig00000150 ),
    .S(\blk00000001/blk0000003e/sig00000182 ),
    .O(\blk00000001/blk0000003e/sig00000183 )
  );
  XORCY   \blk00000001/blk0000003e/blk0000006b  (
    .CI(\blk00000001/blk0000003e/sig0000017f ),
    .LI(\blk00000001/blk0000003e/sig00000180 ),
    .O(\blk00000001/blk0000003e/sig00000179 )
  );
  MUXCY   \blk00000001/blk0000003e/blk0000006a  (
    .CI(\blk00000001/blk0000003e/sig0000017f ),
    .DI(\blk00000001/blk0000003e/sig00000151 ),
    .S(\blk00000001/blk0000003e/sig00000180 ),
    .O(\blk00000001/blk0000003e/sig00000181 )
  );
  XORCY   \blk00000001/blk0000003e/blk00000069  (
    .CI(\blk00000001/blk0000003e/sig0000017d ),
    .LI(\blk00000001/blk0000003e/sig0000017e ),
    .O(\blk00000001/blk0000003e/sig00000178 )
  );
  MUXCY   \blk00000001/blk0000003e/blk00000068  (
    .CI(\blk00000001/blk0000003e/sig0000017d ),
    .DI(\blk00000001/blk0000003e/sig00000152 ),
    .S(\blk00000001/blk0000003e/sig0000017e ),
    .O(\blk00000001/blk0000003e/sig0000017f )
  );
  XORCY   \blk00000001/blk0000003e/blk00000067  (
    .CI(\blk00000001/sig000000fe ),
    .LI(\blk00000001/blk0000003e/sig0000017c ),
    .O(\blk00000001/blk0000003e/sig00000177 )
  );
  MUXCY   \blk00000001/blk0000003e/blk00000066  (
    .CI(\blk00000001/sig000000fe ),
    .DI(\blk00000001/blk0000003e/sig00000153 ),
    .S(\blk00000001/blk0000003e/sig0000017c ),
    .O(\blk00000001/blk0000003e/sig0000017d )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000065  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig0000010f ),
    .Q(\blk00000001/blk0000003e/sig00000165 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000065_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000064  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig0000010e ),
    .Q(\blk00000001/blk0000003e/sig00000166 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000064_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000063  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig0000010d ),
    .Q(\blk00000001/blk0000003e/sig00000167 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000063_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000062  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig0000010c ),
    .Q(\blk00000001/blk0000003e/sig00000168 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000062_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000061  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig0000010b ),
    .Q(\blk00000001/blk0000003e/sig00000169 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000061_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000060  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig0000010a ),
    .Q(\blk00000001/blk0000003e/sig0000016a ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000060_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk0000005f  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000109 ),
    .Q(\blk00000001/blk0000003e/sig0000016b ),
    .Q15(\NLW_blk00000001/blk0000003e/blk0000005f_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk0000005e  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000108 ),
    .Q(\blk00000001/blk0000003e/sig0000016c ),
    .Q15(\NLW_blk00000001/blk0000003e/blk0000005e_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk0000005d  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000107 ),
    .Q(\blk00000001/blk0000003e/sig0000016d ),
    .Q15(\NLW_blk00000001/blk0000003e/blk0000005d_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk0000005c  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000106 ),
    .Q(\blk00000001/blk0000003e/sig0000016e ),
    .Q15(\NLW_blk00000001/blk0000003e/blk0000005c_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk0000005b  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000105 ),
    .Q(\blk00000001/blk0000003e/sig0000016f ),
    .Q15(\NLW_blk00000001/blk0000003e/blk0000005b_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk0000005a  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000104 ),
    .Q(\blk00000001/blk0000003e/sig00000170 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk0000005a_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000059  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000103 ),
    .Q(\blk00000001/blk0000003e/sig00000171 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000059_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000058  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000102 ),
    .Q(\blk00000001/blk0000003e/sig00000172 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000058_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000057  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000101 ),
    .Q(\blk00000001/blk0000003e/sig00000173 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000057_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000003e/blk00000056  (
    .A0(\blk00000001/blk0000003e/sig00000153 ),
    .A1(\blk00000001/blk0000003e/sig00000152 ),
    .A2(\blk00000001/blk0000003e/sig00000151 ),
    .A3(\blk00000001/blk0000003e/sig00000150 ),
    .CE(\blk00000001/sig000000fe ),
    .CLK(aclk),
    .D(\blk00000001/sig00000100 ),
    .Q(\blk00000001/blk0000003e/sig00000174 ),
    .Q15(\NLW_blk00000001/blk0000003e/blk00000056_Q15_UNCONNECTED )
  );
  FDS #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000003e/blk00000055  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig0000017b ),
    .S(\blk00000001/sig00000039 ),
    .Q(\blk00000001/blk0000003e/sig0000014f )
  );
  FDS #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000003e/blk00000054  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig0000017a ),
    .S(\blk00000001/sig00000039 ),
    .Q(\blk00000001/blk0000003e/sig00000150 )
  );
  FDS #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000003e/blk00000053  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig00000179 ),
    .S(\blk00000001/sig00000039 ),
    .Q(\blk00000001/blk0000003e/sig00000151 )
  );
  FDS #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000003e/blk00000052  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig00000178 ),
    .S(\blk00000001/sig00000039 ),
    .Q(\blk00000001/blk0000003e/sig00000152 )
  );
  FDS #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000003e/blk00000051  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig00000177 ),
    .S(\blk00000001/sig00000039 ),
    .Q(\blk00000001/blk0000003e/sig00000153 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000050  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000165 ),
    .Q(\blk00000001/sig000000fb )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000004f  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000166 ),
    .Q(\blk00000001/sig000000fa )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000004e  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000167 ),
    .Q(\blk00000001/sig000000f9 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000004d  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000168 ),
    .Q(\blk00000001/sig000000f8 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000004c  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000169 ),
    .Q(\blk00000001/sig000000f7 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000004b  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig0000016a ),
    .Q(\blk00000001/sig000000f6 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000004a  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig0000016b ),
    .Q(\blk00000001/sig000000f5 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000049  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig0000016c ),
    .Q(\blk00000001/sig000000f4 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000048  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig0000016d ),
    .Q(\blk00000001/sig000000f3 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000047  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig0000016e ),
    .Q(\blk00000001/sig000000f2 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000046  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig0000016f ),
    .Q(\blk00000001/sig000000f1 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000045  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000170 ),
    .Q(\blk00000001/sig000000f0 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000044  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000171 ),
    .Q(\blk00000001/sig000000ef )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000043  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000172 ),
    .Q(\blk00000001/sig000000ee )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000042  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000173 ),
    .Q(\blk00000001/sig000000ed )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk00000041  (
    .C(aclk),
    .CE(\blk00000001/sig0000005f ),
    .D(\blk00000001/blk0000003e/sig00000174 ),
    .Q(\blk00000001/sig000000ec )
  );
  FDS #(
    .INIT ( 1'b1 ))
  \blk00000001/blk0000003e/blk00000040  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig00000175 ),
    .S(\blk00000001/sig00000039 ),
    .Q(\blk00000001/sig000000ff )
  );
  FDR #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000003e/blk0000003f  (
    .C(aclk),
    .D(\blk00000001/blk0000003e/sig00000176 ),
    .R(\blk00000001/sig00000039 ),
    .Q(\blk00000001/sig000000fc )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk0000009c  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a7 ),
    .Q(\blk00000001/blk0000007b/sig000001ae ),
    .Q15(\NLW_blk00000001/blk0000007b/blk0000009c_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk0000009b  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a6 ),
    .Q(\blk00000001/blk0000007b/sig000001af ),
    .Q15(\NLW_blk00000001/blk0000007b/blk0000009b_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk0000009a  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a5 ),
    .Q(\blk00000001/blk0000007b/sig000001b0 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk0000009a_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000099  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a4 ),
    .Q(\blk00000001/blk0000007b/sig000001b1 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000099_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000098  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a3 ),
    .Q(\blk00000001/blk0000007b/sig000001b2 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000098_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000097  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a2 ),
    .Q(\blk00000001/blk0000007b/sig000001b3 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000097_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000096  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a1 ),
    .Q(\blk00000001/blk0000007b/sig000001b4 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000096_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000095  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig000000a0 ),
    .Q(\blk00000001/blk0000007b/sig000001b5 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000095_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000094  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000009f ),
    .Q(\blk00000001/blk0000007b/sig000001b6 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000094_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000093  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000009e ),
    .Q(\blk00000001/blk0000007b/sig000001b7 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000093_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000092  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000009d ),
    .Q(\blk00000001/blk0000007b/sig000001b8 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000092_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000091  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000009c ),
    .Q(\blk00000001/blk0000007b/sig000001b9 ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000091_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk00000090  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000009b ),
    .Q(\blk00000001/blk0000007b/sig000001ba ),
    .Q15(\NLW_blk00000001/blk0000007b/blk00000090_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk0000008f  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig0000009a ),
    .Q(\blk00000001/blk0000007b/sig000001bb ),
    .Q15(\NLW_blk00000001/blk0000007b/blk0000008f_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk0000008e  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000099 ),
    .Q(\blk00000001/blk0000007b/sig000001bc ),
    .Q15(\NLW_blk00000001/blk0000007b/blk0000008e_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000007b/blk0000008d  (
    .A0(\blk00000001/sig00000064 ),
    .A1(\blk00000001/sig000000ac ),
    .A2(\blk00000001/sig000000ad ),
    .A3(\blk00000001/sig000000ae ),
    .CE(\blk00000001/sig000000a9 ),
    .CLK(aclk),
    .D(\blk00000001/sig00000098 ),
    .Q(\blk00000001/blk0000007b/sig000001bd ),
    .Q15(\NLW_blk00000001/blk0000007b/blk0000008d_Q15_UNCONNECTED )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk0000008c  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001ae ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000d2 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk0000008b  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001af ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000d1 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk0000008a  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b0 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000d0 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000089  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b1 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000cf )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000088  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b2 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000ce )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000087  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b3 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000cd )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000086  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b4 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000cc )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000085  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b5 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000cb )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000084  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b6 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000ca )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000083  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b7 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c9 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000082  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b8 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c8 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000081  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001b9 ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c7 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk00000080  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001ba ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c6 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk0000007f  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001bb ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c5 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk0000007e  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001bc ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c4 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000007b/blk0000007d  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000007b/sig000001bd ),
    .R(\blk00000001/blk0000007b/sig000001be ),
    .Q(\blk00000001/sig000000c3 )
  );
  GND   \blk00000001/blk0000007b/blk0000007c  (
    .G(\blk00000001/blk0000007b/sig000001be )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000be  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000fb ),
    .Q(\blk00000001/blk0000009d/sig000001e6 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000be_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000bd  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000fa ),
    .Q(\blk00000001/blk0000009d/sig000001e7 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000bd_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000bc  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f9 ),
    .Q(\blk00000001/blk0000009d/sig000001e8 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000bc_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000bb  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f8 ),
    .Q(\blk00000001/blk0000009d/sig000001e9 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000bb_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000ba  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f7 ),
    .Q(\blk00000001/blk0000009d/sig000001ea ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000ba_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b9  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f6 ),
    .Q(\blk00000001/blk0000009d/sig000001eb ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b9_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b8  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f5 ),
    .Q(\blk00000001/blk0000009d/sig000001ec ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b8_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b7  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f4 ),
    .Q(\blk00000001/blk0000009d/sig000001ed ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b7_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b6  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f3 ),
    .Q(\blk00000001/blk0000009d/sig000001ee ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b6_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b5  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f2 ),
    .Q(\blk00000001/blk0000009d/sig000001ef ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b5_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b4  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f1 ),
    .Q(\blk00000001/blk0000009d/sig000001f0 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b4_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b3  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000f0 ),
    .Q(\blk00000001/blk0000009d/sig000001f1 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b3_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b2  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000ef ),
    .Q(\blk00000001/blk0000009d/sig000001f2 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b2_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b1  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000ee ),
    .Q(\blk00000001/blk0000009d/sig000001f3 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b1_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000b0  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000ed ),
    .Q(\blk00000001/blk0000009d/sig000001f4 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000b0_Q15_UNCONNECTED )
  );
  SRLC16E #(
    .INIT ( 16'h0000 ))
  \blk00000001/blk0000009d/blk000000af  (
    .A0(\blk00000001/sig00000068 ),
    .A1(\blk00000001/sig00000067 ),
    .A2(\blk00000001/sig00000066 ),
    .A3(\blk00000001/sig00000065 ),
    .CE(\blk00000001/sig000000aa ),
    .CLK(aclk),
    .D(\blk00000001/sig000000ec ),
    .Q(\blk00000001/blk0000009d/sig000001f5 ),
    .Q15(\NLW_blk00000001/blk0000009d/blk000000af_Q15_UNCONNECTED )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000ae  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001e6 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000e2 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000ad  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001e7 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000e1 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000ac  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001e8 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000e0 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000ab  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001e9 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000df )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000aa  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001ea ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000de )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a9  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001eb ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000dd )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a8  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001ec ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000dc )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a7  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001ed ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000db )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a6  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001ee ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000da )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a5  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001ef ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d9 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a4  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001f0 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d8 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a3  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001f1 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d7 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a2  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001f2 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d6 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a1  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001f3 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d5 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk000000a0  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001f4 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d4 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk0000009d/blk0000009f  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk0000009d/sig000001f5 ),
    .R(\blk00000001/blk0000009d/sig000001f6 ),
    .Q(\blk00000001/sig000000d3 )
  );
  GND   \blk00000001/blk0000009d/blk0000009e  (
    .G(\blk00000001/blk0000009d/sig000001f6 )
  );
  LUT4 #(
    .INIT ( 16'h1517 ))
  \blk00000001/blk000000bf/blk000000df  (
    .I0(\blk00000001/sig000000e9 ),
    .I1(\blk00000001/sig000000eb ),
    .I2(\blk00000001/sig000000ea ),
    .I3(\blk00000001/sig000000e8 ),
    .O(\blk00000001/blk000000bf/sig00000214 )
  );
  LUT4 #(
    .INIT ( 16'h6E66 ))
  \blk00000001/blk000000bf/blk000000de  (
    .I0(\blk00000001/sig000000e8 ),
    .I1(\blk00000001/sig000000e9 ),
    .I2(\blk00000001/sig000000ea ),
    .I3(\blk00000001/sig000000eb ),
    .O(\blk00000001/blk000000bf/sig00000217 )
  );
  LUT4 #(
    .INIT ( 16'h2667 ))
  \blk00000001/blk000000bf/blk000000dd  (
    .I0(\blk00000001/sig000000eb ),
    .I1(\blk00000001/sig000000e8 ),
    .I2(\blk00000001/sig000000e9 ),
    .I3(\blk00000001/sig000000ea ),
    .O(\blk00000001/blk000000bf/sig00000216 )
  );
  LUT4 #(
    .INIT ( 16'h4117 ))
  \blk00000001/blk000000bf/blk000000dc  (
    .I0(\blk00000001/sig000000e9 ),
    .I1(\blk00000001/sig000000ea ),
    .I2(\blk00000001/sig000000eb ),
    .I3(\blk00000001/sig000000e8 ),
    .O(\blk00000001/blk000000bf/sig00000211 )
  );
  LUT4 #(
    .INIT ( 16'h41F6 ))
  \blk00000001/blk000000bf/blk000000db  (
    .I0(\blk00000001/sig000000e9 ),
    .I1(\blk00000001/sig000000eb ),
    .I2(\blk00000001/sig000000e8 ),
    .I3(\blk00000001/sig000000ea ),
    .O(\blk00000001/blk000000bf/sig00000215 )
  );
  LUT4 #(
    .INIT ( 16'h61F4 ))
  \blk00000001/blk000000bf/blk000000da  (
    .I0(\blk00000001/sig000000ea ),
    .I1(\blk00000001/sig000000e9 ),
    .I2(\blk00000001/sig000000e8 ),
    .I3(\blk00000001/sig000000eb ),
    .O(\blk00000001/blk000000bf/sig00000212 )
  );
  LUT4 #(
    .INIT ( 16'h27A6 ))
  \blk00000001/blk000000bf/blk000000d9  (
    .I0(\blk00000001/sig000000ea ),
    .I1(\blk00000001/sig000000e9 ),
    .I2(\blk00000001/sig000000eb ),
    .I3(\blk00000001/sig000000e8 ),
    .O(\blk00000001/blk000000bf/sig0000021b )
  );
  LUT4 #(
    .INIT ( 16'h7A29 ))
  \blk00000001/blk000000bf/blk000000d8  (
    .I0(\blk00000001/sig000000e8 ),
    .I1(\blk00000001/sig000000ea ),
    .I2(\blk00000001/sig000000e9 ),
    .I3(\blk00000001/sig000000eb ),
    .O(\blk00000001/blk000000bf/sig00000210 )
  );
  LUT4 #(
    .INIT ( 16'h6461 ))
  \blk00000001/blk000000bf/blk000000d7  (
    .I0(\blk00000001/sig000000eb ),
    .I1(\blk00000001/sig000000ea ),
    .I2(\blk00000001/sig000000e8 ),
    .I3(\blk00000001/sig000000e9 ),
    .O(\blk00000001/blk000000bf/sig00000218 )
  );
  LUT4 #(
    .INIT ( 16'h4111 ))
  \blk00000001/blk000000bf/blk000000d6  (
    .I0(\blk00000001/sig000000e8 ),
    .I1(\blk00000001/sig000000e9 ),
    .I2(\blk00000001/sig000000ea ),
    .I3(\blk00000001/sig000000eb ),
    .O(\blk00000001/blk000000bf/sig0000020d )
  );
  LUT4 #(
    .INIT ( 16'h14AF ))
  \blk00000001/blk000000bf/blk000000d5  (
    .I0(\blk00000001/sig000000ea ),
    .I1(\blk00000001/sig000000e8 ),
    .I2(\blk00000001/sig000000eb ),
    .I3(\blk00000001/sig000000e9 ),
    .O(\blk00000001/blk000000bf/sig0000020e )
  );
  LUT4 #(
    .INIT ( 16'h11ED ))
  \blk00000001/blk000000bf/blk000000d4  (
    .I0(\blk00000001/sig000000e9 ),
    .I1(\blk00000001/sig000000eb ),
    .I2(\blk00000001/sig000000e8 ),
    .I3(\blk00000001/sig000000ea ),
    .O(\blk00000001/blk000000bf/sig0000021a )
  );
  LUT4 #(
    .INIT ( 16'h6345 ))
  \blk00000001/blk000000bf/blk000000d3  (
    .I0(\blk00000001/sig000000eb ),
    .I1(\blk00000001/sig000000ea ),
    .I2(\blk00000001/sig000000e8 ),
    .I3(\blk00000001/sig000000e9 ),
    .O(\blk00000001/blk000000bf/sig00000219 )
  );
  LUT4 #(
    .INIT ( 16'h1F28 ))
  \blk00000001/blk000000bf/blk000000d2  (
    .I0(\blk00000001/sig000000e9 ),
    .I1(\blk00000001/sig000000ea ),
    .I2(\blk00000001/sig000000eb ),
    .I3(\blk00000001/sig000000e8 ),
    .O(\blk00000001/blk000000bf/sig00000213 )
  );
  LUT4 #(
    .INIT ( 16'h6028 ))
  \blk00000001/blk000000bf/blk000000d1  (
    .I0(\blk00000001/sig000000e8 ),
    .I1(\blk00000001/sig000000e9 ),
    .I2(\blk00000001/sig000000eb ),
    .I3(\blk00000001/sig000000ea ),
    .O(\blk00000001/blk000000bf/sig0000020f )
  );
  LUT4 #(
    .INIT ( 16'h7AAA ))
  \blk00000001/blk000000bf/blk000000d0  (
    .I0(\blk00000001/sig000000eb ),
    .I1(\blk00000001/sig000000e8 ),
    .I2(\blk00000001/sig000000ea ),
    .I3(\blk00000001/sig000000e9 ),
    .O(\blk00000001/blk000000bf/sig0000021c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000cf  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig0000021c ),
    .Q(\blk00000001/sig000000c2 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000ce  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig0000021b ),
    .Q(\blk00000001/sig000000c1 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000cd  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig0000021a ),
    .Q(\blk00000001/sig000000c0 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000cc  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000219 ),
    .Q(\blk00000001/sig000000bf )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000cb  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000218 ),
    .Q(\blk00000001/sig000000be )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000ca  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000217 ),
    .Q(\blk00000001/sig000000bd )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c9  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000216 ),
    .Q(\blk00000001/sig000000bc )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c8  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000215 ),
    .Q(\blk00000001/sig000000bb )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c7  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000214 ),
    .Q(\blk00000001/sig000000ba )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c6  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000213 ),
    .Q(\blk00000001/sig000000b9 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c5  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000212 ),
    .Q(\blk00000001/sig000000b8 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c4  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000211 ),
    .Q(\blk00000001/sig000000b7 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c3  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig00000210 ),
    .Q(\blk00000001/sig000000b6 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c2  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig0000020f ),
    .Q(\blk00000001/sig000000b5 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c1  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig0000020e ),
    .Q(\blk00000001/sig000000b4 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000001/blk000000bf/blk000000c0  (
    .C(aclk),
    .CE(\blk00000001/sig00000114 ),
    .D(\blk00000001/blk000000bf/sig0000020d ),
    .Q(\blk00000001/sig000000b3 )
  );

// synthesis translate_on

endmodule

// synthesis translate_off

`ifndef GLBL
`define GLBL

`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;

    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (weak1, weak0) GSR = GSR_int;
    assign (weak1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

endmodule

`endif

// synthesis translate_on
