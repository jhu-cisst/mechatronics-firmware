`timescale 1ns / 1ps
/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2020 Johns Hopkins University.
 *
 * This module implements a PID Controller
 * (file was originally called PID_Controller_block.v)
 *
 * Revision history
 *      5/20/20     Stefan Kohlgrueber       Initial Revision
 */

`include "Constants.v"

module PID_Controller
      #(pos_ctrl = 0)
      (
      //data inputs
      input  wire                 clk,       // clk
      input  wire                 val_ready, // new ADC values available
      input  wire          [9*pos_ctrl + 15:0] bits_cmd, // commanded bits
      input  wire          [9*pos_ctrl + 15:0] bits_fb,  // feedback bits
      //parameter inputs
      input  wire          [15:0] co_cmd,    // conversion offset from bits to commanded value
      input  wire          [15:0] co_fbBits, // conversion offset from bits to feedback value scaled to bits
      input  wire          [15:0] co_out,    // conversion offset from output value to bits
      input  wire          [15:0] cf_out,    // conversion factor for output multiplication
      input  wire   signed [15:0] Kp,        // proportional controller gain
      input  wire   signed [15:0] KiT,       // integral controller gain combined with sampling time
      input  wire   signed [15:0] KdT,    // differential controller gain combined with sampling time
      input  wire          [ 3:0] N_shift_Kp,   // accounting for parameter transfer factor
      input  wire          [ 3:0] N_shift_KiT,  // accounting for parameter transfer factor
      input  wire          [ 3:0] N_shift_KdT,  // accounting for parameter transfer factor
      input  wire          [15:0] sat_max,   // saturation threshold for controller output in bits
      //output
      // output wire signed   [17:0] bits_diff_out, //for standalone simulation only
      // output wire signed   [21:0] bits_cont_out, //for standalone simulation only
      // output wire signed   [15:0] bits_sat_out,  //for standalone simulation only
      //output wire          [15:0] bits_out //original output name
      output wire          [15:0] cont_out,
      output wire                 out_ready // controller output available
      );

      // PARAMETER DECLARATION
      //----------------------
      //parameter factorI2V = 1;             // 1 for CUR, 0 for POS --> multiplication with factor 5

      // REGISTER DECLARATION
      //---------------------

      // Timing
      reg                 val_ready_now;     // new state for edge detection
      reg                 val_ready_last;    // old state for edge detection

      // Intermediate bits
      reg signed   [9*pos_ctrl + 17:0] e_k;        //bits_diff;   // error including offsets
      reg signed   [9*pos_ctrl + 17:0] e_k1;       // previous error including offsets
      reg signed   [9*pos_ctrl + 35 +4:0] u_k;     //bits_cont;   // controller output (23 bits for max. sum of uKp, uKi, uKd)
      reg signed   [15:0] bits_sat;                // value after saturation check
      reg          [15:0] bits_conv;               // value after converstion to voltage bits
      reg                 conv_done;               // controller output ready for be sent out via DAC

      // Momentary internal controller quantities
      reg signed   [9*pos_ctrl + 17 +4:0] IntE;    // integrated error
      reg signed   [9*pos_ctrl + 33:0] uKp_k;      // proportional controller output
      reg signed   [9*pos_ctrl + 33 +4:0] uKiT_k;  // integral controller output
      reg signed   [9*pos_ctrl + 33 +4:0] uKdT_k;  // differential controller output

      //INITIALISATION
      //--------------

      initial begin
         val_ready_now  = 0;      // reset new state for edge detection 
         val_ready_last = 0;      // reset old state for edge detection
         e_k            = 0;      // reset bits_diff
         e_k1           = 0;      // reset previous error
         u_k            = 0;      // reset bits_cont
         bits_sat       = 0;      // reset value after saturation check
         bits_conv      = co_cmd; // reset value after bit converstion
         conv_done      = 0;      // reset output_ready

         IntE   = 0;
         uKp_k  = 0;
         uKiT_k = 0;
         uKdT_k = 0;
      end

      //BLOCK FUNCTION
      //--------------

      always @ (posedge clk)
      begin
         val_ready_now = val_ready; //fetching of ADC status

         if (val_ready_last==0 && val_ready_now==1) begin //edge detection

            //difference block
            e_k = (bits_cmd - bits_fb - co_cmd + co_fbBits);

            //PI block
            //Forward Euler
            uKp_k  = (Kp  * e_k         ) >>>  N_shift_Kp;
            uKiT_k = (KiT * IntE        ) >>>  N_shift_KiT;
            //uKdT_k = (KdT * (e_k - e_k1)) >>> (N_shift_KdT - 4); //TAKE CARE FOR NEGATIVE SHIFTS INTERPRETED AS 2-complement

            if (N_shift_KdT > 4)
               uKdT_k = (KdT * (e_k - e_k1)) >>> (N_shift_KdT - 4);
            else
               uKdT_k = (KdT * (e_k - e_k1)) <<< (4 - N_shift_KdT);

            u_k    = uKp_k + uKiT_k + uKdT_k;
            IntE   = IntE + e_k; //update after usage, leads effectively to IntE += e_k1
            e_k1   = e_k;        // update value for next cycle

            //saturation check block
            if (u_k > $signed(sat_max)) begin
               bits_sat = sat_max;   //clamping
               if (e_k > 0)
                  IntE = IntE - e_k; //anti-windup
            end
            else if (u_k < $signed(-sat_max)) begin
                  bits_sat = -sat_max;  //clamping
                  if (e_k < 0)
                     IntE = IntE - e_k; //anti-windup
            end else
               bits_sat = u_k;         //no saturation detected

            //conversion block
            bits_conv = (cf_out * bits_sat + co_out);
//          if (factor5 == 1)
//             bits_conv = 5*bits_sat+co_cmd;
//          else
//             bits_conv = bits_sat+co_cmd;

            conv_done = 1;
         end
         else
            conv_done = 0; //reset flag after 1 clock cycle

         val_ready_last = val_ready_now; // update value for next clock cycle
      end

      //OUTPUT ASSIGNMENT
      //-----------------

      //assign bits_diff_out = e_k;
      //assign bits_cont_out = u_k;
      //assign bits_sat_out  = bits_sat;
      //assign bits_out    = bits_conv; //original output name
      assign cont_out = bits_conv;
      assign out_ready = conv_done;

endmodule
