// ==============================================================
// RTL generated by Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC
// Version: 2015.4
// Copyright (C) 2015 Xilinx Inc. All rights reserved.
// 
// ===========================================================

`timescale 1 ns / 1 ps 

(* CORE_GENERATION_INFO="pi_controller,hls_ip_2015_4,{HLS_INPUT_TYPE=cxx,HLS_INPUT_FLOAT=0,HLS_INPUT_FIXED=1,HLS_INPUT_PART=xc7z020clg400-2,HLS_INPUT_CLOCK=6.104000,HLS_INPUT_ARCH=others,HLS_SYN_CLOCK=5.550000,HLS_SYN_LAT=6,HLS_SYN_TPT=none,HLS_SYN_MEM=0,HLS_SYN_DSP=0,HLS_SYN_FF=489,HLS_SYN_LUT=402}" *)

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
        kd_V,
        ff_resistive_V,
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
parameter    ap_const_lv16_8000 = 16'b1000000000000000;
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
parameter    ap_const_lv32_6 = 32'b110;
parameter    ap_const_lv11_1 = 11'b1;
parameter    ap_const_lv1_0 = 1'b0;
parameter    ap_const_lv35_0 = 35'b00000000000000000000000000000000000;
parameter    ap_const_lv16_0 = 16'b0000000000000000;
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
input  [17:0] kd_V;
input  [17:0] ff_resistive_V;
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
reg   [15:0] last_feedback_V = 16'b1000000000000000;
reg   [35:0] i_term_V = 36'b000000000000000000000000000000000000;
wire   [16:0] r_V_1_fu_160_p2;
reg  signed [16:0] r_V_1_reg_434 = 17'b00000000000000000;
wire  signed [34:0] grp_fu_426_p3;
reg  signed [34:0] p_Val2_5_reg_440 = 35'b00000000000000000000000000000000000;
wire   [15:0] setpoint_no_offset_V_fu_170_p2;
reg  signed [15:0] setpoint_no_offset_V_reg_445 = 16'b0000000000000000;
wire  signed [34:0] OP2_V_fu_176_p1;
reg  signed [34:0] OP2_V_reg_450 = 35'b00000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st2_fsm_1;
reg    ap_sig_bdd_61;
wire  signed [35:0] grp_fu_403_p3;
reg  signed [35:0] p_Val2_3_reg_455 = 36'b000000000000000000000000000000000000;
wire  signed [35:0] grp_fu_418_p3;
reg  signed [35:0] tmp2_reg_462 = 36'b000000000000000000000000000000000000;
wire  signed [35:0] tmp_6_fu_232_p1;
reg  signed [35:0] tmp_6_reg_467 = 36'b000000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st3_fsm_2;
reg    ap_sig_bdd_74;
wire   [35:0] sel_tmp_fu_241_p3;
reg   [35:0] sel_tmp_reg_472 = 36'b000000000000000000000000000000000000;
wire   [0:0] sel_tmp2_fu_254_p2;
reg   [0:0] sel_tmp2_reg_477 = 1'b0;
wire  signed [35:0] grp_fu_411_p3;
reg  signed [35:0] tmp1_reg_482 = 36'b000000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st4_fsm_3;
reg    ap_sig_bdd_87;
(* use_dsp48 = "no" *) wire   [35:0] p_Val2_s_4_fu_276_p2;
reg   [35:0] p_Val2_s_4_reg_487 = 36'b000000000000000000000000000000000000;
reg    ap_sig_cseq_ST_st5_fsm_4;
reg    ap_sig_bdd_96;
wire   [35:0] tmp_10_fu_288_p1;
reg   [35:0] tmp_10_reg_493 = 36'b000000000000000000000000000000000000;
wire   [0:0] tmp_11_fu_292_p2;
reg   [0:0] tmp_11_reg_498 = 1'b0;
wire   [16:0] r_V_3_fu_302_p2;
reg   [16:0] r_V_3_reg_504 = 17'b00000000000000000;
reg   [0:0] tmp_15_reg_509 = 1'b0;
reg    ap_sig_cseq_ST_st6_fsm_5;
reg    ap_sig_bdd_111;
wire   [17:0] tmp_16_fu_356_p1;
reg   [17:0] tmp_16_reg_514 = 18'b000000000000000000;
reg   [10:0] tmp_19_reg_519 = 11'b00000000000;
reg   [10:0] tmp_18_reg_524 = 11'b00000000000;
wire   [35:0] p_Val2_7_fu_264_p3;
reg   [16:0] error_out_V_preg = 17'b00000000000000000;
reg   [35:0] i_term_out_V_preg = 36'b000000000000000000000000000000000000;
wire   [16:0] lhs_V_1_fu_156_p1;
wire   [16:0] rhs_V_fu_146_p1;
wire   [33:0] tmp_8_fu_197_p3;
wire   [35:0] tmp_9_fu_205_p1;
wire   [16:0] rhs_V_1_fu_214_p1;
wire   [16:0] r_V_2_fu_218_p2;
wire   [34:0] tmp_3_fu_224_p3;
wire   [0:0] tmp_s_fu_209_p2;
wire   [0:0] tmp_1_fu_236_p2;
wire   [0:0] sel_tmp1_fu_248_p2;
wire   [33:0] tmp_2_fu_280_p3;
wire   [16:0] rhs_V_2_fu_298_p1;
wire   [34:0] tmp_12_fu_308_p3;
wire  signed [35:0] tmp_13_fu_315_p1;
wire   [0:0] tmp_14_fu_319_p2;
wire   [0:0] sel_tmp5_fu_329_p2;
wire   [0:0] sel_tmp6_fu_334_p2;
wire   [35:0] sel_tmp4_fu_324_p3;
wire   [35:0] p_Val2_6_fu_340_p3;
reg    ap_sig_cseq_ST_st7_fsm_6;
reg    ap_sig_bdd_236;
wire   [0:0] tmp_17_fu_380_p2;
wire   [10:0] tmp_21_fu_385_p2;
wire   [10:0] tmp_20_fu_390_p3;
wire   [17:0] grp_fu_403_p0;
wire   [17:0] grp_fu_411_p0;
wire  signed [16:0] grp_fu_411_p1;
wire   [35:0] grp_fu_411_p2;
wire   [17:0] grp_fu_418_p0;
wire   [15:0] grp_fu_426_p0;
wire   [15:0] grp_fu_426_p1;
wire   [17:0] grp_fu_426_p2;
reg   [6:0] ap_NS_fsm;
wire   [34:0] grp_fu_403_p00;
wire   [34:0] grp_fu_411_p00;
wire   [33:0] grp_fu_418_p00;
wire   [16:0] grp_fu_426_p00;
wire   [34:0] grp_fu_426_p20;


pi_controller_mac_muladd_18ns_17s_36ns_36_1 #(
    .ID( 1 ),
    .NUM_STAGE( 1 ),
    .din0_WIDTH( 18 ),
    .din1_WIDTH( 17 ),
    .din2_WIDTH( 36 ),
    .dout_WIDTH( 36 ))
pi_controller_mac_muladd_18ns_17s_36ns_36_1_U1(
    .din0( grp_fu_403_p0 ),
    .din1( r_V_1_reg_434 ),
    .din2( i_term_V ),
    .dout( grp_fu_403_p3 )
);

pi_controller_mac_muladd_18ns_17s_36ns_36_1 #(
    .ID( 1 ),
    .NUM_STAGE( 1 ),
    .din0_WIDTH( 18 ),
    .din1_WIDTH( 17 ),
    .din2_WIDTH( 36 ),
    .dout_WIDTH( 36 ))
pi_controller_mac_muladd_18ns_17s_36ns_36_1_U2(
    .din0( grp_fu_411_p0 ),
    .din1( grp_fu_411_p1 ),
    .din2( grp_fu_411_p2 ),
    .dout( grp_fu_411_p3 )
);

pi_controller_mac_muladd_18ns_16s_35s_36_1 #(
    .ID( 1 ),
    .NUM_STAGE( 1 ),
    .din0_WIDTH( 18 ),
    .din1_WIDTH( 16 ),
    .din2_WIDTH( 35 ),
    .dout_WIDTH( 36 ))
pi_controller_mac_muladd_18ns_16s_35s_36_1_U3(
    .din0( grp_fu_418_p0 ),
    .din1( setpoint_no_offset_V_reg_445 ),
    .din2( p_Val2_5_reg_440 ),
    .dout( grp_fu_418_p3 )
);

pi_controller_am_submul_16ns_16ns_18ns_35_1 #(
    .ID( 1 ),
    .NUM_STAGE( 1 ),
    .din0_WIDTH( 16 ),
    .din1_WIDTH( 16 ),
    .din2_WIDTH( 18 ),
    .dout_WIDTH( 35 ))
pi_controller_am_submul_16ns_16ns_18ns_35_1_U4(
    .din0( grp_fu_426_p0 ),
    .din1( grp_fu_426_p1 ),
    .din2( grp_fu_426_p2 ),
    .dout( grp_fu_426_p3 )
);



always @ (posedge ap_clk) begin : ap_ret_OP2_V_reg_450
    if (ap_rst == 1'b1) begin
        OP2_V_reg_450 <= ap_const_lv35_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
            OP2_V_reg_450 <= OP2_V_fu_176_p1;
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
            error_out_V_preg <= r_V_1_reg_434;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_i_term_V
    if (ap_rst == 1'b1) begin
        i_term_V <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
            i_term_V <= p_Val2_7_fu_264_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_i_term_out_V_preg
    if (ap_rst == 1'b1) begin
        i_term_out_V_preg <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
            i_term_out_V_preg <= p_Val2_7_fu_264_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_last_feedback_V
    if (ap_rst == 1'b1) begin
        last_feedback_V <= ap_const_lv16_8000;
    end else begin
        if (((ap_const_logic_1 == ap_sig_cseq_ST_st1_fsm_0) & ~(ap_start == ap_const_logic_0))) begin
            last_feedback_V <= feedback_V;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_p_Val2_3_reg_455
    if (ap_rst == 1'b1) begin
        p_Val2_3_reg_455 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
            p_Val2_3_reg_455 <= grp_fu_403_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_p_Val2_5_reg_440
    if (ap_rst == 1'b1) begin
        p_Val2_5_reg_440 <= ap_const_lv35_0;
    end else begin
        if (((ap_const_logic_1 == ap_sig_cseq_ST_st1_fsm_0) & ~(ap_start == ap_const_logic_0))) begin
            p_Val2_5_reg_440 <= grp_fu_426_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_p_Val2_s_4_reg_487
    if (ap_rst == 1'b1) begin
        p_Val2_s_4_reg_487 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
            p_Val2_s_4_reg_487 <= p_Val2_s_4_fu_276_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_r_V_1_reg_434
    if (ap_rst == 1'b1) begin
        r_V_1_reg_434 <= ap_const_lv17_0;
    end else begin
        if (((ap_const_logic_1 == ap_sig_cseq_ST_st1_fsm_0) & ~(ap_start == ap_const_logic_0))) begin
            r_V_1_reg_434 <= r_V_1_fu_160_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_r_V_3_reg_504
    if (ap_rst == 1'b1) begin
        r_V_3_reg_504 <= ap_const_lv17_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
            r_V_3_reg_504 <= r_V_3_fu_302_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_sel_tmp2_reg_477
    if (ap_rst == 1'b1) begin
        sel_tmp2_reg_477 <= ap_const_lv1_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st3_fsm_2)) begin
            sel_tmp2_reg_477 <= sel_tmp2_fu_254_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_sel_tmp_reg_472
    if (ap_rst == 1'b1) begin
        sel_tmp_reg_472 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st3_fsm_2)) begin
            sel_tmp_reg_472 <= sel_tmp_fu_241_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_setpoint_no_offset_V_reg_445
    if (ap_rst == 1'b1) begin
        setpoint_no_offset_V_reg_445 <= ap_const_lv16_0;
    end else begin
        if (((ap_const_logic_1 == ap_sig_cseq_ST_st1_fsm_0) & ~(ap_start == ap_const_logic_0))) begin
            setpoint_no_offset_V_reg_445 <= setpoint_no_offset_V_fu_170_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp1_reg_482
    if (ap_rst == 1'b1) begin
        tmp1_reg_482 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
            tmp1_reg_482 <= grp_fu_411_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp2_reg_462
    if (ap_rst == 1'b1) begin
        tmp2_reg_462 <= ap_const_lv36_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
            tmp2_reg_462 <= grp_fu_418_p3;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_10_reg_493
    if (ap_rst == 1'b1) begin
        tmp_10_reg_493[18] <= 1'b0;
        tmp_10_reg_493[19] <= 1'b0;
        tmp_10_reg_493[20] <= 1'b0;
        tmp_10_reg_493[21] <= 1'b0;
        tmp_10_reg_493[22] <= 1'b0;
        tmp_10_reg_493[23] <= 1'b0;
        tmp_10_reg_493[24] <= 1'b0;
        tmp_10_reg_493[25] <= 1'b0;
        tmp_10_reg_493[26] <= 1'b0;
        tmp_10_reg_493[27] <= 1'b0;
        tmp_10_reg_493[28] <= 1'b0;
        tmp_10_reg_493[29] <= 1'b0;
        tmp_10_reg_493[30] <= 1'b0;
        tmp_10_reg_493[31] <= 1'b0;
        tmp_10_reg_493[32] <= 1'b0;
        tmp_10_reg_493[33] <= 1'b0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
                        tmp_10_reg_493[33 : 18] <= tmp_10_fu_288_p1[33 : 18];
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_11_reg_498
    if (ap_rst == 1'b1) begin
        tmp_11_reg_498 <= ap_const_lv1_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st5_fsm_4)) begin
            tmp_11_reg_498 <= tmp_11_fu_292_p2;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_15_reg_509
    if (ap_rst == 1'b1) begin
        tmp_15_reg_509 <= ap_const_lv1_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_15_reg_509 <= p_Val2_6_fu_340_p3[ap_const_lv32_23];
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_16_reg_514
    if (ap_rst == 1'b1) begin
        tmp_16_reg_514 <= ap_const_lv18_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_16_reg_514 <= tmp_16_fu_356_p1;
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_18_reg_524
    if (ap_rst == 1'b1) begin
        tmp_18_reg_524 <= ap_const_lv11_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_18_reg_524 <= {{p_Val2_6_fu_340_p3[ap_const_lv32_1C : ap_const_lv32_12]}};
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_19_reg_519
    if (ap_rst == 1'b1) begin
        tmp_19_reg_519 <= ap_const_lv11_0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st6_fsm_5)) begin
            tmp_19_reg_519 <= {{p_Val2_6_fu_340_p3[ap_const_lv32_1C : ap_const_lv32_12]}};
        end
    end
end

always @ (posedge ap_clk) begin : ap_ret_tmp_6_reg_467
    if (ap_rst == 1'b1) begin
        tmp_6_reg_467[18] <= 1'b0;
        tmp_6_reg_467[19] <= 1'b0;
        tmp_6_reg_467[20] <= 1'b0;
        tmp_6_reg_467[21] <= 1'b0;
        tmp_6_reg_467[22] <= 1'b0;
        tmp_6_reg_467[23] <= 1'b0;
        tmp_6_reg_467[24] <= 1'b0;
        tmp_6_reg_467[25] <= 1'b0;
        tmp_6_reg_467[26] <= 1'b0;
        tmp_6_reg_467[27] <= 1'b0;
        tmp_6_reg_467[28] <= 1'b0;
        tmp_6_reg_467[29] <= 1'b0;
        tmp_6_reg_467[30] <= 1'b0;
        tmp_6_reg_467[31] <= 1'b0;
        tmp_6_reg_467[32] <= 1'b0;
        tmp_6_reg_467[33] <= 1'b0;
        tmp_6_reg_467[34] <= 1'b0;
        tmp_6_reg_467[35] <= 1'b0;
    end else begin
        if ((ap_const_logic_1 == ap_sig_cseq_ST_st3_fsm_2)) begin
                        tmp_6_reg_467[35 : 18] <= tmp_6_fu_232_p1[35 : 18];
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

always @ (ap_sig_bdd_61) begin
    if (ap_sig_bdd_61) begin
        ap_sig_cseq_ST_st2_fsm_1 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st2_fsm_1 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_74) begin
    if (ap_sig_bdd_74) begin
        ap_sig_cseq_ST_st3_fsm_2 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st3_fsm_2 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_87) begin
    if (ap_sig_bdd_87) begin
        ap_sig_cseq_ST_st4_fsm_3 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st4_fsm_3 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_96) begin
    if (ap_sig_bdd_96) begin
        ap_sig_cseq_ST_st5_fsm_4 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st5_fsm_4 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_111) begin
    if (ap_sig_bdd_111) begin
        ap_sig_cseq_ST_st6_fsm_5 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st6_fsm_5 = ap_const_logic_0;
    end
end

always @ (ap_sig_bdd_236) begin
    if (ap_sig_bdd_236) begin
        ap_sig_cseq_ST_st7_fsm_6 = ap_const_logic_1;
    end else begin
        ap_sig_cseq_ST_st7_fsm_6 = ap_const_logic_0;
    end
end

always @ (r_V_1_reg_434 or ap_sig_cseq_ST_st2_fsm_1 or error_out_V_preg) begin
    if ((ap_const_logic_1 == ap_sig_cseq_ST_st2_fsm_1)) begin
        error_out_V = r_V_1_reg_434;
    end else begin
        error_out_V = error_out_V_preg;
    end
end

always @ (ap_sig_cseq_ST_st4_fsm_3 or p_Val2_7_fu_264_p3 or i_term_out_V_preg) begin
    if ((ap_const_logic_1 == ap_sig_cseq_ST_st4_fsm_3)) begin
        i_term_out_V = p_Val2_7_fu_264_p3;
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


assign OP2_V_fu_176_p1 = r_V_1_reg_434;

assign ap_return = ((tmp_15_reg_509[0:0] === 1'b1) ? tmp_20_fu_390_p3 : tmp_18_reg_524);


always @ (ap_CS_fsm) begin
    ap_sig_bdd_111 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_5]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_23 = (ap_CS_fsm[ap_const_lv32_0] == ap_const_lv1_1);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_236 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_6]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_61 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_1]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_74 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_2]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_87 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_3]);
end


always @ (ap_CS_fsm) begin
    ap_sig_bdd_96 = (ap_const_lv1_1 == ap_CS_fsm[ap_const_lv32_4]);
end

assign grp_fu_403_p0 = grp_fu_403_p00;

assign grp_fu_403_p00 = ki_V;

assign grp_fu_411_p0 = grp_fu_411_p00;

assign grp_fu_411_p00 = kp_V;

assign grp_fu_411_p1 = OP2_V_reg_450;

assign grp_fu_411_p2 = ((sel_tmp2_reg_477[0:0] === 1'b1) ? tmp_6_reg_467 : sel_tmp_reg_472);

assign grp_fu_418_p0 = grp_fu_418_p00;

assign grp_fu_418_p00 = ff_resistive_V;

assign grp_fu_426_p0 = grp_fu_426_p00;

assign grp_fu_426_p00 = last_feedback_V;

assign grp_fu_426_p1 = rhs_V_fu_146_p1;

assign grp_fu_426_p2 = grp_fu_426_p20;

assign grp_fu_426_p20 = kd_V;

assign lhs_V_1_fu_156_p1 = setpoint_V;

assign p_Val2_6_fu_340_p3 = ((sel_tmp6_fu_334_p2[0:0] === 1'b1) ? tmp_13_fu_315_p1 : sel_tmp4_fu_324_p3);

assign p_Val2_7_fu_264_p3 = ((sel_tmp2_reg_477[0:0] === 1'b1) ? tmp_6_reg_467 : sel_tmp_reg_472);

assign p_Val2_s_4_fu_276_p2 = ($signed(tmp2_reg_462) + $signed(tmp1_reg_482));

assign r_V_1_fu_160_p2 = (lhs_V_1_fu_156_p1 - rhs_V_fu_146_p1);

assign r_V_2_fu_218_p2 = (ap_const_lv17_0 - rhs_V_1_fu_214_p1);

assign r_V_3_fu_302_p2 = (ap_const_lv17_0 - rhs_V_2_fu_298_p1);

assign rhs_V_1_fu_214_p1 = i_term_limit_V;

assign rhs_V_2_fu_298_p1 = output_limit_V;

assign rhs_V_fu_146_p1 = feedback_V;

assign sel_tmp1_fu_248_p2 = (tmp_s_fu_209_p2 ^ ap_const_lv1_1);

assign sel_tmp2_fu_254_p2 = (tmp_1_fu_236_p2 & sel_tmp1_fu_248_p2);

assign sel_tmp4_fu_324_p3 = ((tmp_11_reg_498[0:0] === 1'b1) ? tmp_10_reg_493 : p_Val2_s_4_reg_487);

assign sel_tmp5_fu_329_p2 = (tmp_11_reg_498 ^ ap_const_lv1_1);

assign sel_tmp6_fu_334_p2 = (tmp_14_fu_319_p2 & sel_tmp5_fu_329_p2);

assign sel_tmp_fu_241_p3 = ((tmp_s_fu_209_p2[0:0] === 1'b1) ? tmp_9_fu_205_p1 : p_Val2_3_reg_455);

assign setpoint_no_offset_V_fu_170_p2 = (setpoint_V ^ ap_const_lv16_8000);

assign tmp_10_fu_288_p1 = tmp_2_fu_280_p3;

assign tmp_11_fu_292_p2 = ($signed(p_Val2_s_4_fu_276_p2) > $signed(tmp_10_fu_288_p1)? 1'b1: 1'b0);

assign tmp_12_fu_308_p3 = {{r_V_3_reg_504}, {ap_const_lv18_0}};

assign tmp_13_fu_315_p1 = $signed(tmp_12_fu_308_p3);

assign tmp_14_fu_319_p2 = ($signed(p_Val2_s_4_reg_487) < $signed(tmp_13_fu_315_p1)? 1'b1: 1'b0);

assign tmp_16_fu_356_p1 = p_Val2_6_fu_340_p3[17:0];

assign tmp_17_fu_380_p2 = (tmp_16_reg_514 == ap_const_lv18_0? 1'b1: 1'b0);

assign tmp_1_fu_236_p2 = ($signed(p_Val2_3_reg_455) < $signed(tmp_6_fu_232_p1)? 1'b1: 1'b0);

assign tmp_20_fu_390_p3 = ((tmp_17_fu_380_p2[0:0] === 1'b1) ? tmp_18_reg_524 : tmp_21_fu_385_p2);

assign tmp_21_fu_385_p2 = (ap_const_lv11_1 + tmp_19_reg_519);

assign tmp_2_fu_280_p3 = {{output_limit_V}, {ap_const_lv18_0}};

assign tmp_3_fu_224_p3 = {{r_V_2_fu_218_p2}, {ap_const_lv18_0}};

assign tmp_6_fu_232_p1 = $signed(tmp_3_fu_224_p3);

assign tmp_8_fu_197_p3 = {{i_term_limit_V}, {ap_const_lv18_0}};

assign tmp_9_fu_205_p1 = tmp_8_fu_197_p3;

assign tmp_s_fu_209_p2 = ($signed(p_Val2_3_reg_455) > $signed(tmp_9_fu_205_p1)? 1'b1: 1'b0);
always @ (posedge ap_clk) begin
    tmp_6_reg_467[17:0] <= 18'b000000000000000000;
    tmp_10_reg_493[17:0] <= 18'b000000000000000000;
    tmp_10_reg_493[35:34] <= 2'b00;
end



endmodule //pi_controller

