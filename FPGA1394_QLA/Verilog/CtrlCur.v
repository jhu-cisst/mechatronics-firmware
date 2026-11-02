/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2026 ERC CISST, Johns Hopkins University.
 *
 * This module incorporates the PID block controlling the motor current
 * of one channel of the QLA board. It handles the read/write of offset
 * values for commanded and feedback current as well as controller gains.
 * It also includes a position controller.
 *
 * Revision history
 *     06/20/20    Stefan Kohlgrueber    Initial revision
 *     10/30/26    Peter Kazanzides      Revised to support a single channel
 */


`include "Constants.v"

module Controller_block(
    input  wire clk,          // clk
    input  wire val_ready,    // new ADC values available

    // for reading commanded bits --> read out from regs
    input  wire[31:0] reg_wdata,    // incoming register data
    input  wire[3:0]  reg_waddr,    // register write address
    input  wire       ctrl_wen,     // CTRL register write enable

    // for reading back the commanded currents
    output wire[31:0] reg_rdata,    // outgoing register data
    input  wire[3:0]  reg_raddr,    // register read address

    // controller inputs
    input  wire[15:0] bits_fb,     // current feedback bits
    input  wire[24:0] enc_fb,      // position feedback bits
    input  wire[15:0] bits_cmd,    // commanded current from host

    // output
    output wire[15:0] cont_out,    // controller output in bits
    output wire       out_ready    // controller output available
);

// Timing
reg      val_ready_now;      // new state for edge detection
reg      val_ready_last;     // old state for edge detection
reg[7:0] cnt;                // counter for x10 or position control sampling time
reg      pos_val_ready;      // val_ready for position controller --> 10x slower than val_ready

// Position control enabled or only current control
reg pos_cont_en = 1'b0;

// Intermediate registers
reg[24:0] pos_fb;  // register storing the values until they are updated, every 10th time new current values are available
reg[24:0] pos_cmd; // register storing the values until they are updated
reg[24:0] pos_controller_output; // for debugging

wire[15:0] wire_cont_out;     // wire leading from current controller to outputs of the whole module, used for global saturation check
wire[15:0] wire_pos_cont_out; // output of position controller, used as reference input of current controller module
wire[15:0] wire_cur_cont_in;  // input of current control (either commanded current or position controller output)

//parameters
reg[15:0] co_cmd;
reg[15:0] co_fbBits;
reg[15:0] Kp_Curr;
reg[15:0] KiT_Curr;
reg[15:0] KdT_Curr;
reg[3:0]  N_shift_Curr_Kp;
reg[3:0]  N_shift_Curr_KiT;
reg[3:0]  N_shift_Curr_KdT;
reg[15:0] sat_max_Curr;

reg[15:0] Kp_Pos;
reg[15:0] KiT_Pos;
reg[15:0] KdT_Pos;

reg[3:0]  N_shift_Pos_Kp;
reg[3:0]  N_shift_Pos_KiT;
reg[3:0]  N_shift_Pos_KdT;
reg[15:0] sat_max_Pos;
reg[15:0] co_out_Pos;
reg[15:0] cf_out_Pos;

// assignments for current controller input
assign wire_cur_cont_in = pos_cont_en ? wire_pos_cont_out : bits_cmd;

// assignments to CtrlDac via global saturation check to prevent destruction
assign cont_out = (wire_cont_out > (co_cmd + 5*sat_max_Curr)) ? (co_cmd + 5*sat_max_Curr) :
                  (wire_cont_out < (co_cmd - 5*sat_max_Curr)) ? (co_cmd - 5*sat_max_Curr) :
                  wire_cont_out;

// Position control sampling time handling:
// Ts_pos = 10x Ts_cur

always @(posedge(clk))
begin

   val_ready_now = val_ready; //fetching of ADC status

   if (~val_ready_last & val_ready_now) begin //edge detection

      if (cnt >= 4'd9) begin
         pos_val_ready <= 1;
         cnt <= 4'b0;
         // update registers
         pos_fb <= enc_fb;
      end
      else begin
         pos_val_ready <= 0;
         cnt <= cnt + 1;
      end

   end
   else begin // not at rising edge of val_ready, but reset pos_val_ready directly after 1 clk period
      pos_val_ready <= 0;
   end

   val_ready_last = val_ready_now; // update value for next clock cycle
end


// Debug register update

always @(posedge(clk))
begin
   pos_controller_output <= wire_pos_cont_out;
end



// Register write
always @(posedge(clk))
begin

   // Write selected register
   if (ctrl_wen) begin

      case (reg_waddr[3:0])

      `OFF_CO_CMD_FB: begin
         // Write conversion offsets for commanded current and feedback current
         // converted to a 16 bit value
         co_cmd <= reg_wdata[31:16];
         co_fbBits <= reg_wdata[15:0];
      end

      `OFF_CTRL_CURR_Kp_KiT: begin
         // Write controller gains Kp and Ki*T of CL current controller
         Kp_Curr <= reg_wdata[31:16];
         KiT_Curr <= reg_wdata[15:0];
      end

      `OFF_CTRL_CURR_KdT: begin
         // Write controller gain Kd/T of CL current controller
         KdT_Curr <= reg_wdata[31:16];
      end

      `OFF_CTRL_POS_Kp_KiT: begin
         // Write controller gains Kp and Ki*T of CL position controller
         Kp_Pos <= reg_wdata[31:16];
         KiT_Pos <= reg_wdata[15:0];
      end

      `OFF_CTRL_POS_KdT_CF_OUT: begin
         // Write controller gain Kd/T of CL position controller and conversion offset
         KdT_Pos <= reg_wdata[31:16];
         cf_out_Pos <= reg_wdata[15:0];
      end

      `OFF_OUT_POS_CMD: begin
          // Write commanded position
          pos_cmd <= reg_wdata[24:0];
      end

      // not intended to be written to:
      `OFF_OUT_POS_OUT: begin
         // Write controller gain Kd/T of CL position controller and commanded position
         // pos_controller_output <= reg_wdata[24:0];
      end

      `OFF_CTRL_SHIFTS: begin
         // Write shifts and position control enable bits
         pos_cont_en      <= reg_wdata[31];
         N_shift_Curr_Kp  <= reg_wdata[23:20];
         N_shift_Curr_KiT <= reg_wdata[19:16];
         N_shift_Curr_KdT <= reg_wdata[15:12];
         N_shift_Pos_Kp   <= reg_wdata[11: 8];
         N_shift_Pos_KiT  <= reg_wdata[ 7: 4];
         N_shift_Pos_KdT  <= reg_wdata[ 3: 0];
      end

      endcase

      end
end


// Reading back
assign reg_rdata =
   // conversion offsets co_cur_cmd and co_cur_fbBits
   (reg_raddr[3:0]  ==`OFF_CO_CMD_FB)            ? {co_cmd, co_fbBits}   :
   // Kp and Ki*T (already bit-shifted) for motor current controller
   (reg_raddr[3:0]  ==`OFF_CTRL_CURR_Kp_KiT)     ? {Kp_Curr, KiT_Curr}   :
   // Kd/T for motor current controller
   (reg_raddr[3:0]  ==`OFF_CTRL_CURR_KdT)        ? {KdT_Curr, 16'h0}      :
   // Kp and Ki*T (already bit-shifted) for position controller
   (reg_raddr[3:0]  ==`OFF_CTRL_POS_Kp_KiT)      ? {Kp_Pos, KiT_Pos}     :
   // Kd/T and conversion factor depending on joint for position controller
   (reg_raddr[3:0]  ==`OFF_CTRL_POS_KdT_CF_OUT)  ? {KdT_Pos, cf_out_Pos} :
   // Commanded position
   (reg_raddr[3:0]  ==`OFF_OUT_POS_CMD)          ? {7'd0, pos_cmd}       :
   // Output of position PID which is reference input for motor current PID (for debugging)
   (reg_raddr[3:0]  ==`OFF_OUT_POS_OUT)          ? {7'd0, pos_controller_output}  :
   // Position control enable AND N_shifts for the 6 controller gains
   (reg_raddr[3:0]  ==`OFF_CTRL_SHIFTS)          ? {pos_cont_en, 7'h0,
                                                    N_shift_Curr_Kp, N_shift_Curr_KiT, N_shift_Curr_KdT,
                                                    N_shift_Pos_Kp , N_shift_Pos_KiT , N_shift_Pos_KdT}  :
   32'd0;


// Motor current PID controller
PID_Controller #(.pos_ctrl(0))
pid_cur(
   .clk(clk),
   .val_ready(val_ready),
   .bits_cmd(wire_cur_cont_in),
   .bits_fb(bits_fb),
   .co_cmd(co_cmd),
   .co_fbBits(co_fbBits),
   .co_out(co_cmd),
   .cf_out(16'd5),
   .Kp(Kp_Curr),
   .KiT(KiT_Curr),
   .KdT(KdT_Curr),
   .N_shift_Kp(N_shift_Curr_Kp),
   .N_shift_KiT(N_shift_Curr_KiT),
   .N_shift_KdT(N_shift_Curr_KdT),
   .sat_max(sat_max_Curr),
   .cont_out(wire_cont_out),
   .out_ready(out_ready)
);

// Position PID output ready (not used)
wire out_pos_ready;

// Position PID controller
PID_Controller #(.pos_ctrl(1))
pid_pos(
   .clk(clk),
   .val_ready(val_ready),
   .bits_cmd(pos_cmd),
   .bits_fb(pos_fb),
   .co_cmd(16'd0),
   .co_fbBits(16'd0),
   .co_out(co_cmd),
   .cf_out(cf_out_Pos),
   .Kp(Kp_Pos),
   .KiT(KiT_Pos),
   .KdT(KdT_Pos),
   .N_shift_Kp(N_shift_Pos_Kp),
   .N_shift_KiT(N_shift_Pos_KiT),
   .N_shift_KdT(N_shift_Pos_KdT),
   .sat_max(sat_max_Pos),
   .cont_out(wire_pos_cont_out),
   .out_ready(out_pos_ready)
);

endmodule
