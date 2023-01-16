// ==============================================================
// RTL generated by Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC
// Version: 2015.4
// Copyright (C) 2015 Xilinx Inc. All rights reserved.
// 
// ===========================================================

`timescale 1 ns / 1 ps 

(* CORE_GENERATION_INFO="pi_controller,hls_ip_2015_4,{HLS_INPUT_TYPE=cxx,HLS_INPUT_FLOAT=0,HLS_INPUT_FIXED=1,HLS_INPUT_PART=xc7z020clg400-2,HLS_INPUT_CLOCK=6.104000,HLS_INPUT_ARCH=others,HLS_SYN_CLOCK=5.550000,HLS_SYN_LAT=6,HLS_SYN_TPT=none,HLS_SYN_MEM=0,HLS_SYN_DSP=0,HLS_SYN_FF=353,HLS_SYN_LUT=344}" *)

module pi_controller (
        ap_clk,
        ap_rst,
        ap_start,
        ap_done,
        ap_idle,
        ap_ready,
        feedback_V,
        setpoint_V,
        kp_V,
        ki_V,
        i_term_limit_V,
        output_limit_V,
        error_out_V,
        i_term_out_V,
        ap_return
);

parameter    ap_const_logic_1 = 1'b1;
parameter    ap_const_logic_0 = 1'b0;
parameter    ap_ST_st1_fsm_0 = 7'b1;
parameter    ap_ST_st2_fsm_1 = 7'b10;
parameter    ap_ST_st3_fsm_2 = 7'b100;
parameter    ap_ST_st4_fsm_3 = 7'b1000;
parameter    ap_ST_st5_fsm_4 = 7'b10000;
parameter    ap_ST_st6_fsm_5 = 7'b100000;
parameter    ap_ST_st7_fsm_6 = 7'b1000000;
parameter    ap_const_lv32_0 = 32'b00000000000000000000000000000000;
parameter    ap_const_lv1_1 = 1'b1;
parameter    ap_const_lv36_0 = 36'b000000000000000000000000000000000000;
parameter    ap_const_lv32_1 = 32'b1;
parameter    ap_const_lv32_2 = 32'b10;
parameter    ap_const_lv32_3 = 32'b11;
parameter    ap_const_lv32_4 = 32'b100;
parameter    ap_const_lv32_5 = 32'b101;
parameter    ap_const_lv17_0 = 17'b00000000000000000;
parameter    ap_const_lv18_0 = 18'b000000000000000000;
parameter    ap_const_lv32_23 = 32'b100011;
parameter    ap_const_lv32_12 = 32'b10010;
parameter    ap_const_lv32_1C = 32'b11100;
parameter    ap_const_lv11_1 = 11'b1;
parameter    ap_const_lv32_6 = 32'b110;
parameter    ap_const_lv35_0 = 35'b00000000000000000000000000000000000;
parameter    ap_const_lv1_0 = 1'b0;
parameter    ap_const_lv11_0 = 11'b00000000000;
parameter    ap_true = 1'b1;

input   ap_clk;
input   ap_rst;
input   ap_start;
output   ap_done;
output   ap_idle;
output   ap_ready;
input  [15:0] feedback_V;
input  [15:0] setpoint_V;
input  [17:0] kp_V;
input  [17:0] ki_V;
input  [15:0] i_term_limit_V;
input  [15:0] output_limit_V;
output  [16:0] error_out_V;
output  [35:0] i_term_out_V;
output  [10:0] ap_return;

reg ap_done;
reg ap_idle;
reg ap_ready;
reg[16:0] error_out_V;
reg[35:0] i_term_out_V;
(* fsm_encoding = "none" *) reg   [6:0] ap_CS_fsm = 7'b1;
reg    ap_sig_cseq_ST_st1_fsm_0;
reg    ap_sig_bdd_23;
reg   [35:0] i_term_V = 36'b000000000000000000000000000000000000;
wire   [16:0] r_V_fu_126_p2;
reg  signed [16:0] r_V_reg_362 = 17'b00000000000000000;
wire  signed [34:0] OP2_V_fu_132_p1;
reg  signed [34:0] OP2_V_reg_368 = 35'b00000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st2_fsm_1;
reg    ap_sig_bdd_53;
wire  signed [35:0] grp_fu_347_p3;
reg  signed [35:0] p_Val2_3_reg_373 = 36'b000000000000000000000000000000000000;
wire  signed [35:0] tmp_6_fu_178_p1;
reg  signed [35:0] tmp_6_reg_380 = 36'b000000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st3_fsm_2;
reg    ap_sig_bdd_64;
wire   [35:0] sel_tmp_fu_187_p3;
reg   [35:0] sel_tmp_reg_385 = 36'b000000000000000000000000000000000000;
wire   [0:0] sel_tmp2_fu_200_p2;
reg   [0:0] sel_tmp2_reg_390 = 1'b0;
wire  signed [35:0] grp_fu_355_p3;
reg  signed [35:0] p_Val2_9_reg_395 = 36'b000000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st4_fsm_3;
reg    ap_sig_bdd_77;
wire  signed [35:0] tmp_11_fu_257_p1;
reg  signed [35:0] tmp_11_reg_402 = 36'b000000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st5_fsm_4;
reg    ap_sig_bdd_86;
wire   [35:0] sel_tmp4_fu_266_p3;
reg   [35:0] sel_tmp4_reg_407 = 36'b000000000000000000000000000000000000;
wire   [0:0] sel_tmp6_fu_279_p2;
reg   [0:0] sel_tmp6_reg_412 = 1'b0;
reg   [0:0] tmp_13_reg_417 = 1'b0;
reg    ap_sig_cseq_ST_st6_fsm_5;
reg    ap_sig_bdd_99;
wire   [10:0] tmp_16_fu_318_p4;
reg   [10:0] tmp_16_reg_422 = 11'b00000000000;
wire   [10:0] tmp_18_fu_334_p3;
reg   [10:0] tmp_18_reg_427 = 11'b00000000000;
wire   [35:0] p_Val2_5_fu_210_p3;
reg   [16:0] error_out_V_preg = 17'b00000000000000000;
reg   [35:0] i_term_out_V_preg = 36'b000000000000000000000000000000000000;
wire   [16:0] lhs_V_fu_118_p1;
wire   [16:0] rhs_V_fu_122_p1;
wire   [33:0] tmp_8_fu_143_p3;
wire   [35:0] tmp_9_fu_151_p1;
wire   [16:0] rhs_V_1_fu_160_p1;
wire   [16:0] r_V_1_fu_164_p2;
wire   [34:0] tmp_3_fu_170_p3;
wire   [0:0] tmp_s_fu_155_p2;
wire   [0:0] tmp_1_fu_182_p2;
wire   [0:0] sel_tmp1_fu_194_p2;
wire   [33:0] tmp_5_fu_222_p3;
wire   [35:0] tmp_7_fu_230_p1;
wire   [16:0] rhs_V_2_fu_239_p1;
wire   [16:0] r_V_2_fu_243_p2;
wire   [34:0] tmp_10_fu_249_p3;
wire   [0:0] tmp_2_fu_234_p2;
wire   [0:0] tmp_12_fu_261_p2;
wire   [0:0] sel_tmp5_fu_273_p2;
wire   [35:0] p_Val2_7_fu_285_p3;
wire   [17:0] tmp_14_fu_298_p1;
wire   [10:0] tmp_17_fu_308_p4;
wire   [0:0] tmp_15_fu_302_p2;
wire   [10:0] tmp_19_fu_328_p2;
reg    ap_sig_cseq_ST_st7_fsm_6;
reg    ap_sig_bdd_222;
wire   [17:0] grp_fu_347_p0;
wire   [17:0] grp_fu_355_p0;
wire  signed [16:0] grp_fu_355_p1;
wire   [35:0] grp_fu_355_p2;
reg   [6:0] ap_NS_fsm;
wire   [34:0] grp_fu_347_p00;
wire   [34:0] grp_fu_355_p00;


pi_controller_mac_muladd_18ns_17s_36ns_36_1 #(
    .ID( 1 ),
    .NUM_STAGE( 1 ),
    .din0_WIDTH( 18 ),
    .din1_WIDTH( 17 ),
    .din2_WIDTH( 36 ),
    .dout_WIDTH( 36 ))
pi_controller_mac_muladd_18ns_17s_36ns_36_1_U1(
    .din0( grp_fu_347_p0 ),
    .din1( r_V_reg_362 ),
    .din2( i_term_V ),
    .dout( grp_fu_347_p3 )
);

pi_controller_mac_muladd_18ns_17s_36ns_36_1 #(
    .ID( 1 ),
    .NUM_STAGE( 1 ),
    .din0_WIDTH( 18 ),
    .din1_WIDTH( 17 ),
    .din2_WIDTH( 36 ),
    .dout_WIDTH( 36 ))
pi_controller_mac_muladd_18ns_17s_36ns_36_1_U2(
    .din0( grp_fu_355_p0 ),
    .din1( grp_fu_355_p1 ),
    .din2( grp_fu_355_p2 ),
    .dout( grp_fu_355_p3 )
);



always @ (posedge ap_clk) begin : ap_ret_OP2_V_reg_368
    if (ap_rst == 1'b1) begin
        OP2_V_reg_368 <= ap_const_lv35_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
            OP2_V_reg_368 <= OP2_V_fu_132_p1;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_ap_CS_fsm
    if (ap_rst == 1'b1) begin
        ap_CS_fsm <= ap_ST_st1_fsm_0;
    end else begin
        ap_CS_fsm <= ap_NS_fsm;
    end
end

always @ (posedge ap_clk) begin : ap_ret_error_out_V_preg
    if (ap_rst == 1'b1) begin
        error_out_V_preg <= ap_const_lv17_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
            error_out_V_preg <= r_V_reg_362;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_i_term_V
    if (ap_rst == 1'b1) begin
        i_term_V <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
            i_term_V <= p_Val2_5_fu_210_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_i_term_out_V_preg
    if (ap_rst == 1'b1) begin
        i_term_out_V_preg <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
            i_term_out_V_preg <= p_Val2_5_fu_210_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_p_Val2_3_reg_373
    if (ap_rst == 1'b1) begin
        p_Val2_3_reg_373 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
            p_Val2_3_reg_373 <= grp_fu_347_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_p_Val2_9_reg_395
    if (ap_rst == 1'b1) begin
        p_Val2_9_reg_395 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
            p_Val2_9_reg_395 <= grp_fu_355_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_r_V_reg_362
    if (ap_rst == 1'b1) begin
        r_V_reg_362 <= ap_const_lv17_0;
    end else begin
        if (((ap_const_logic_1 == ap_sig_cseq_ST_st1_fsm_0) & ~(ap_start == ap_const_logic_0))) begin
            r_V_reg_362 <= r_V_fu_126_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_sel_tmp2_reg_390
    if (ap_rst == 1'b1) begin
        sel_tmp2_reg_390 <= ap_const_lv1_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st3_fsm_2)) begin
            sel_tmp2_reg_390 <= sel_tmp2_fu_200_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_sel_tmp4_reg_407
    if (ap_rst == 1'b1) begin
        sel_tmp4_reg_407 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
            sel_tmp4_reg_407 <= sel_tmp4_fu_266_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_sel_tmp6_reg_412
    if (ap_rst == 1'b1) begin
        sel_tmp6_reg_412 <= ap_const_lv1_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
            sel_tmp6_reg_412 <= sel_tmp6_fu_279_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_sel_tmp_reg_385
    if (ap_rst == 1'b1) begin
        sel_tmp_reg_385 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st3_fsm_2)) begin
            sel_tmp_reg_385 <= sel_tmp_fu_187_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_11_reg_402
    if (ap_rst == 1'b1) begin
        tmp_11_reg_402[18] <= 1'b0;
        tmp_11_reg_402[19] <= 1'b0;
        tmp_11_reg_402[20] <= 1'b0;
        tmp_11_reg_402[21] <= 1'b0;
        tmp_11_reg_402[22] <= 1'b0;
        tmp_11_reg_402[23] <= 1'b0;
        tmp_11_reg_402[24] <= 1'b0;
        tmp_11_reg_402[25] <= 1'b0;
        tmp_11_reg_402[26] <= 1'b0;
        tmp_11_reg_402[27] <= 1'b0;
        tmp_11_reg_402[28] <= 1'b0;
        tmp_11_reg_402[29] <= 1'b0;
        tmp_11_reg_402[30] <= 1'b0;
        tmp_11_reg_402[31] <= 1'b0;
        tmp_11_reg_402[32] <= 1'b0;
        tmp_11_reg_402[33] <= 1'b0;
        tmp_11_reg_402[34] <= 1'b0;
        tmp_11_reg_402[35] <= 1'b0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
                        tmp_11_reg_402[35 : 18] <= tmp_11_fu_257_p1[35 : 18];
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_13_reg_417
    if (ap_rst == 1'b1) begin
        tmp_13_reg_417 <= ap_const_lv1_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_13_reg_417 <= p_Val2_7_fu_285_p3[ap_const_lv32_23];
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_16_reg_422
    if (ap_rst == 1'b1) begin
        tmp_16_reg_422 <= ap_const_lv11_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_16_reg_422 <= {{p_Val2_7_fu_285_p3[ap_const_lv32_1C : ap_const_lv32_12]}};
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_18_reg_427
    if (ap_rst == 1'b1) begin
        tmp_18_reg_427 <= ap_const_lv11_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_18_reg_427 <= tmp_18_fu_334_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_6_reg_380
    if (ap_rst == 1'b1) begin
        tmp_6_reg_380[18] <= 1'b0;
        tmp_6_reg_380[19] <= 1'b0;
        tmp_6_reg_380[20] <= 1'b0;
        tmp_6_reg_380[21] <= 1'b0;
        tmp_6_reg_380[22] <= 1'b0;
        tmp_6_reg_380[23] <= 1'b0;
        tmp_6_reg_380[24] <= 1'b0;
        tmp_6_reg_380[25] <= 1'b0;
        tmp_6_reg_380[26] <= 1'b0;
        tmp_6_reg_380[27] <= 1'b0;
        tmp_6_reg_380[28] <= 1'b0;
        tmp_6_reg_380[29] <= 1'b0;
        tmp_6_reg_380[30] <= 1'b0;
        tmp_6_reg_380[31] <= 1'b0;
        tmp_6_reg_380[32] <= 1'b0;
        tmp_6_reg_380[33] <= 1'b0;
        tmp_6_reg_380[34] <= 1'b0;
        tmp_6_reg_380[35] <= 1'b0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st3_fsm_2)) begin
                        tmp_6_reg_380[35 : 18] <= tmp_6_fu_178_p1[35 : 18];
        end
    end
end

always @ (ap_sig_cseq_ST_st7_fsm_6) begin
    if ((ap_const_logic_1 == ap_sig_cseq_ST_st7_fsm_6)) begin
        ap_done = ap_const_logic_1;
    end else begin
        ap_done = ap_const_logic_0;
    end
end

always @ (ap_start or ap_sig_cseq_ST_st1_fsm_0) begin
    if ((~(ap_const_logic_1 == ap_start) & (ap_const_logic_1 == ap_sig_cseq_ST_st1_fsm_0))) begin
        ap_idle = ap_const_logic_1;
    end else begin
        ap_idle = ap_const_logic_0;
    end
end

always @ (ap_sig_cseq_ST_st7_fsm_6) begin
    if ((ap_const_logic_1 == ap_sig_cseq_ST_st7_fsm_6)) begin
        ap_ready = ap_const_logic_1;
    end else begin
        ap_ready = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_23) begin
    if (ap_sig_bdd_23) begin
        ap_sig_cseq_ST_st1_fsm_0 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st1_fsm_0 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_53) begin
    if (ap_sig_bdd_53) begin
        ap_sig_cseq_ST_st2_fsm_1 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st2_fsm_1 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_64) begin
    if (ap_sig_bdd_64) begin
        ap_sig_cseq_ST_st3_fsm_2 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st3_fsm_2 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_77) begin
    if (ap_sig_bdd_77) begin
        ap_sig_cseq_ST_st4_fsm_3 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st4_fsm_3 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_86) begin
    if (ap_sig_bdd_86) begin
        ap_sig_cseq_ST_st5_fsm_4 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st5_fsm_4 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_99) begin
    if (ap_sig_bdd_99) begin
        ap_sig_cseq_ST_st6_fsm_5 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st6_fsm_5 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_222) begin
    if (ap_sig_bdd_222) begin
        ap_sig_cseq_ST_st7_fsm_6 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st7_fsm_6 = ap_const_logic_0;
    end
end

always @ (r_V_reg_362 or ap_sig_cseq_ST_st2_fsm_1 or error_out_V_preg) begin
    if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
        error_out_V = r_V_reg_362;
    end else begin
        error_out_V = error_out_V_preg;
    end
end

always @ (ap_sig_cseq_ST_st4_fsm_3 or p_Val2_5_fu_210_p3 or i_term_out_V_preg) begin
    if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
        i_term_out_V = p_Val2_5_fu_210_p3;
    end else begin
        i_term_out_V = i_term_out_V_preg;
    end
end
always @ (ap_start or ap_CS_fsm) begin
    case (ap_CS_fsm)
        ap_ST_st1_fsm_0 : 
        begin
            if (~(ap_start == ap_const_logic_0)) begin
                ap_NS_fsm = ap_ST_st2_fsm_1;
            end else begin
                ap_NS_fsm = ap_ST_st1_fsm_0;
            end
        end
        ap_ST_st2_fsm_1 : 
        begin
            ap_NS_fsm = ap_ST_st3_fsm_2;
        end
        ap_ST_st3_fsm_2 : 
        begin
            ap_NS_fsm = ap_ST_st4_fsm_3;
        end
        ap_ST_st4_fsm_3 : 
        begin
            ap_NS_fsm = ap_ST_st5_fsm_4;
        end
        ap_ST_st5_fsm_4 : 
        begin
            ap_NS_fsm = ap_ST_st6_fsm_5;
        end
        ap_ST_st6_fsm_5 : 
        begin
            ap_NS_fsm = ap_ST_st7_fsm_6;
        end
        ap_ST_st7_fsm_6 : 
        begin
            ap_NS_fsm = ap_ST_st1_fsm_0;
        end
        default : 
        begin
            ap_NS_fsm = 'bx;
        end
    endcase
end


assign OP2_V_fu_132_p1 = r_V_reg_362;

assign ap_return = ((tmp_13_reg_417[0:0] === 1'b1) ? tmp_18_reg_427 : tmp_16_reg_422);


always @ (ap_CS_fsm) begin
    ap_sig_bdd_222 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_6]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_23 = (ap_CS_fsm[ap_const_lv32_0] == ap_const_lv1_1);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_53 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_1]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_64 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_2]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_77 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_3]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_86 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_4]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_99 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_5]);
end

assign grp_fu_347_p0 = grp_fu_347_p00;

assign grp_fu_347_p00 = ki_V;

assign grp_fu_355_p0 = grp_fu_355_p00;

assign grp_fu_355_p00 = kp_V;

assign grp_fu_355_p1 = OP2_V_reg_368;

assign grp_fu_355_p2 = ((sel_tmp2_reg_390[0:0] === 1'b1) ? tmp_6_reg_380 : sel_tmp_reg_385);

assign lhs_V_fu_118_p1 = setpoint_V;

assign p_Val2_5_fu_210_p3 = ((sel_tmp2_reg_390[0:0] === 1'b1) ? tmp_6_reg_380 : sel_tmp_reg_385);

assign p_Val2_7_fu_285_p3 = ((sel_tmp6_reg_412[0:0] === 1'b1) ? tmp_11_reg_402 : sel_tmp4_reg_407);

assign r_V_1_fu_164_p2 = (ap_const_lv17_0 - rhs_V_1_fu_160_p1);

assign r_V_2_fu_243_p2 = (ap_const_lv17_0 - rhs_V_2_fu_239_p1);

assign r_V_fu_126_p2 = (lhs_V_fu_118_p1 - rhs_V_fu_122_p1);

assign rhs_V_1_fu_160_p1 = i_term_limit_V;

assign rhs_V_2_fu_239_p1 = output_limit_V;

assign rhs_V_fu_122_p1 = feedback_V;

assign sel_tmp1_fu_194_p2 = (tmp_s_fu_155_p2 ^ ap_const_lv1_1);

assign sel_tmp2_fu_200_p2 = (tmp_1_fu_182_p2 & sel_tmp1_fu_194_p2);

assign sel_tmp4_fu_266_p3 = ((tmp_2_fu_234_p2[0:0] === 1'b1) ? tmp_7_fu_230_p1 : p_Val2_9_reg_395);

assign sel_tmp5_fu_273_p2 = (tmp_2_fu_234_p2 ^ ap_const_lv1_1);

assign sel_tmp6_fu_279_p2 = (tmp_12_fu_261_p2 & sel_tmp5_fu_273_p2);

assign sel_tmp_fu_187_p3 = ((tmp_s_fu_155_p2[0:0] === 1'b1) ? tmp_9_fu_151_p1 : p_Val2_3_reg_373);

assign tmp_10_fu_249_p3 = {{r_V_2_fu_243_p2}, {ap_const_lv18_0}};

assign tmp_11_fu_257_p1 = $signed(tmp_10_fu_249_p3);

assign tmp_12_fu_261_p2 = ($signed(p_Val2_9_reg_395) < $signed(tmp_11_fu_257_p1)? 1'b1: 1'b0);

assign tmp_14_fu_298_p1 = p_Val2_7_fu_285_p3[17:0];

assign tmp_15_fu_302_p2 = (tmp_14_fu_298_p1 == ap_const_lv18_0? 1'b1: 1'b0);

assign tmp_16_fu_318_p4 = {{p_Val2_7_fu_285_p3[ap_const_lv32_1C : ap_const_lv32_12]}};

assign tmp_17_fu_308_p4 = {{p_Val2_7_fu_285_p3[ap_const_lv32_1C : ap_const_lv32_12]}};

assign tmp_18_fu_334_p3 = ((tmp_15_fu_302_p2[0:0] === 1'b1) ? tmp_16_fu_318_p4 : tmp_19_fu_328_p2);

assign tmp_19_fu_328_p2 = (ap_const_lv11_1 + tmp_17_fu_308_p4);

assign tmp_1_fu_182_p2 = ($signed(p_Val2_3_reg_373) < $signed(tmp_6_fu_178_p1)? 1'b1: 1'b0);

assign tmp_2_fu_234_p2 = ($signed(p_Val2_9_reg_395) > $signed(tmp_7_fu_230_p1)? 1'b1: 1'b0);

assign tmp_3_fu_170_p3 = {{r_V_1_fu_164_p2}, {ap_const_lv18_0}};

assign tmp_5_fu_222_p3 = {{output_limit_V}, {ap_const_lv18_0}};

assign tmp_6_fu_178_p1 = $signed(tmp_3_fu_170_p3);

assign tmp_7_fu_230_p1 = tmp_5_fu_222_p3;

assign tmp_8_fu_143_p3 = {{i_term_limit_V}, {ap_const_lv18_0}};

assign tmp_9_fu_151_p1 = tmp_8_fu_143_p3;

assign tmp_s_fu_155_p2 = ($signed(p_Val2_3_reg_373) > $signed(tmp_9_fu_151_p1)? 1'b1: 1'b0);
always @ (posedge ap_clk) begin
    tmp_6_reg_380[17:0] <= 18'b000000000000000000;
    tmp_11_reg_402[17:0] <= 18'b000000000000000000;
end



endmodule //pi_controller

