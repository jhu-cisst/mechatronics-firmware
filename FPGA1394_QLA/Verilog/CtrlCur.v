/*******************************************************************************
 *
 * Copyright(C) 2011-2021 ERC CISST, Johns Hopkins University.
 *
 * This module incorporates the 4 PID blocks controlling the motor current
 * of one channel of the QLA baord each. It serves as central unit responsible
 * for the distribution of signals to the corresponding channel and for
 * read/write of offset values for commanded and feedback current as well as 
 * controller gains.
 *
 * Revision history
 *     06/20/20    Stefan Kohlgrueber    Initial revision
 */


`include "Constants.v"

module Controller_block(
      input  wire                 clk,          // clk
      input  wire                 val_ready,    // new ADC values available

      //for reading commanded bits --> read out from regs
      input  wire          [31:0] reg_wdata,    // incoming register data
      input  wire          [15:0] reg_waddr,    // register write address
      input  wire                 reg_wen,      // register write enable

      //for reading back the commanded currents
      output wire          [31:0] reg_rdata,    // outgoing register data
      input  wire          [15:0] reg_raddr,    // register read address

      //controller inputs
      input  wire          [15:0] bits_fb1,     // current feedback bits
      input  wire          [15:0] bits_fb2,     // current feedback bits
      input  wire          [15:0] bits_fb3,     // current feedback bits
      input  wire          [15:0] bits_fb4,     // current feedback bits

      input  wire          [24:0] enc_fb1,      // position feedback bits
      input  wire          [24:0] enc_fb2,      // position feedback bits
      input  wire          [24:0] enc_fb3,      // position feedback bits
      input  wire          [24:0] enc_fb4,      // position feedback bits

      input wire           [15:0] bits_cmd1,    // commanded current from host
      input wire           [15:0] bits_cmd2,    // commanded current from host
      input wire           [15:0] bits_cmd3,    // commanded current from host
      input wire           [15:0] bits_cmd4,    // commanded current from host

      //output
      output wire          [15:0] cont_out1,    // controller output in bits
      output wire          [15:0] cont_out2,    // controller output in bits
      output wire          [15:0] cont_out3,    // controller output in bits
      output wire          [15:0] cont_out4,    // controller output in bits

      output wire                 out_ready     // controller output available
    );

// Timing
reg       val_ready_now;      // new state for edge detection
reg       val_ready_last;     // old state for edge detection
reg [7:0] cnt;                // counter for x10 or position control sampling time
reg       pos_val_ready;      // val_ready for position controller --> 10x slower than val_ready

// POSITION CONTROL ENABLED OR ONLY CURRENT CONTROL
reg [1:4] pos_cont_en;

// INTERMEDIATE REGISTERS
reg [24:0] pos_fb[1:4]; //register storing the values until they are updated, every 10th time new current values are available
reg [24:0] pos_cmd[1:4]; //register storing the values until they are updated
reg [24:0] pos_controller_output[1:4]; //for debugging

wire out_ready_x4 [1:4];  //one joint flag, if all 4 PI_controllers have new values at the same time --> should be the case as 4x the same is instantiated.
wire out_pos_ready_x4 [1:4];  //one joint flag, if all 4 PI_controllers have new values at the same time --> should be the case as 4x the same is instantiated --> NOT USED

wire [15:0] wire_cont_out [1:4]; //wire leading from current controller to outputs of the whole module, used for global saturation check
wire [15:0] wire_pos_cont_out [1:4]; //output of position controller, used as reference input of current controller module
wire [15:0] wire_cur_cont_in [1:4]; //input of current control (either commanded current or position controller output)

//parameters
reg [15:0] co_cmd[1:4];
reg [15:0] co_fbBits[1:4];
reg [15:0] Kp_Curr[1:4];
reg [15:0] KiT_Curr[1:4];
reg [15:0] KdT_Curr[1:4];
reg [3:0]  N_shift_Curr_Kp  [1:4];
reg [3:0]  N_shift_Curr_KiT [1:4];
reg [3:0]  N_shift_Curr_KdT [1:4];
reg [15:0] sat_max_Curr[1:4];

reg [15:0] Kp_Pos[1:4];
reg [15:0] KiT_Pos[1:4];
reg [15:0] KdT_Pos[1:4];

reg [3:0]  N_shift_Pos_Kp  [1:4];
reg [3:0]  N_shift_Pos_KiT [1:4];
reg [3:0]  N_shift_Pos_KdT [1:4];
reg [15:0] sat_max_Pos[1:4];
reg [15:0] co_out_Pos;
reg [15:0] cf_out_Pos[1:4];

//ASSIGNMENTS
// outputs for safety check
wire[15:0] cur_cmd[1:4];
assign cur_cmd[1] = bits_cmd1;
assign cur_cmd[2] = bits_cmd2;
assign cur_cmd[3] = bits_cmd3;
assign cur_cmd[4] = bits_cmd4;

//assignments for current controller input
assign wire_cur_cont_in[1] = (pos_cont_en[1]) ? wire_pos_cont_out[1] : cur_cmd[1];
assign wire_cur_cont_in[2] = (pos_cont_en[2]) ? wire_pos_cont_out[2] : cur_cmd[2];
assign wire_cur_cont_in[3] = (pos_cont_en[3]) ? wire_pos_cont_out[3] : cur_cmd[3];
assign wire_cur_cont_in[4] = (pos_cont_en[4]) ? wire_pos_cont_out[4] : cur_cmd[4];

//assignments to CtrlDac via global saturation check to prevent destruction
assign cont_out1 = (wire_cont_out[1] > (co_cmd[1] + 5*sat_max_Curr[1])) ? (co_cmd[1] + 5*sat_max_Curr[1]) : 
                   (wire_cont_out[1] < (co_cmd[1] - 5*sat_max_Curr[1])) ? (co_cmd[1] - 5*sat_max_Curr[1]) :
                   (wire_cont_out[1]);

assign cont_out2 = (wire_cont_out[2] > (co_cmd[2] + 5*sat_max_Curr[2])) ? (co_cmd[2] + 5*sat_max_Curr[2]) : 
                   (wire_cont_out[2] < (co_cmd[2] - 5*sat_max_Curr[2])) ? (co_cmd[2] - 5*sat_max_Curr[2]) :
                   (wire_cont_out[2]);

assign cont_out3 = (wire_cont_out[3] > (co_cmd[3] + 5*sat_max_Curr[3])) ? (co_cmd[3] + 5*sat_max_Curr[3]) : 
                   (wire_cont_out[3] < (co_cmd[3] - 5*sat_max_Curr[3])) ? (co_cmd[3] - 5*sat_max_Curr[3]) :
                   (wire_cont_out[3]);

assign cont_out4 = (wire_cont_out[4] > (co_cmd[4] + 5*sat_max_Curr[4])) ? (co_cmd[4] + 5*sat_max_Curr[4]) : 
                   (wire_cont_out[4] < (co_cmd[4] - 5*sat_max_Curr[4])) ? (co_cmd[4] - 5*sat_max_Curr[4]) :
                   (wire_cont_out[4]);


// output ready signal to trigger DAC: if the controller values of all 4 channels are available
assign out_ready = out_ready_x4[1] & out_ready_x4[2] & out_ready_x4[3] & out_ready_x4[4]; //should get ready at same time (or before at same rising edge clock)


// INITIALIZATION
initial begin
   //parameters

   // R fitted L nom used for controller design (16.06.2020), factor 0.1 to reduce susceptibility to oscillations correct values
   // reduction of Kp to recude susceptibility for oscillations. To avoid overshoot, Ki needs to be reduced as well, Kd set to 0!
   // Rise time of CL current will be slowed down --> compromise triangle of oscillation, overshoot and rise time (only 2 of 3 possible or trade-off)

   //AXIS 0-3 - JHU - Board configuration 89 --> BOARD 8
   co_cmd[1]= 32788; //32837; //axis 0
   co_cmd[2]= 32739; //32837; //axis 1
   co_cmd[3]= 32830; //32898; //axis 2
   co_cmd[4]= 32798; //33025; //axis 3

   co_fbBits[1]= 32781; //32802; //axis 0
   co_fbBits[2]= 32862; //32780; //axis 1
   co_fbBits[3]= 32861; //32818; //axis 2
   co_fbBits[4]= 32692; //32886; //axis 3

   Kp_Curr[1]=349; //axis 0 // Kp_effective = 0.0426
   Kp_Curr[2]=349; //axis 1
   Kp_Curr[3]=561; //axis 2 // Kp_effective = 0.0685
   Kp_Curr[4]=561; //axis 3

   KiT_Curr[1]=59; //axis 0 // Ki_eff = 827
   KiT_Curr[2]=59; //axis 1
   KiT_Curr[3]=76; //axis 2 // Ki_eff = 1069
   KiT_Curr[4]=76; //axis 3

   KdT_Curr[1]=0;
   KdT_Curr[2]=0;
   KdT_Curr[3]=0;
   KdT_Curr[4]=0;

   Kp_Pos[1] = 15904;
   Kp_Pos[2] = 17696;
   Kp_Pos[3] =  6991;
   Kp_Pos[4] = 16000;

   KiT_Pos[1] = 1;
   KiT_Pos[2] = 2;
   KiT_Pos[3] = 3;
   KiT_Pos[4] = 3;

   KdT_Pos[1] = 256;
   KdT_Pos[2] = 276;
   KdT_Pos[3] = 27961;
   KdT_Pos[4] = 16000;

   //unchanged
   //N_shift_Curr = 13; //range of effective values from 0 to 4
   N_shift_Curr_Kp[1]  = 13; //range of effective values from 0 to 4
   N_shift_Curr_Kp[2]  = 13;
   N_shift_Curr_Kp[3]  = 13;
   N_shift_Curr_Kp[4]  = 13;

   N_shift_Curr_KiT[1] = 13; //range of effective values from 0 to 4
   N_shift_Curr_KiT[2] = 13;
   N_shift_Curr_KiT[3] = 13;
   N_shift_Curr_KiT[4] = 13;

   N_shift_Curr_KdT[1] = 13; //range of effective values from 0 to 4
   N_shift_Curr_KdT[2] = 13;
   N_shift_Curr_KdT[3] = 13;
   N_shift_Curr_KdT[4] = 13;

   //N_shift_Pos  = 10; //range of effective values from 0 to 32
   N_shift_Pos_Kp[1]  = 10; //10 //range of effective values from 0 to 32
   N_shift_Pos_Kp[2]  = 10;
   N_shift_Pos_Kp[3]  = 10;
   N_shift_Pos_Kp[4]  = 11;

   N_shift_Pos_KiT[1] = 15; //range of effective values from 0 to 2^16-1
   N_shift_Pos_KiT[2] = 15;
   N_shift_Pos_KiT[3] = 13;
   N_shift_Pos_KiT[4] = 13;

   N_shift_Pos_KdT[1] =  0; //15 //range of effective values from 0 to 2
   N_shift_Pos_KdT[2] =  0;
   N_shift_Pos_KdT[3] =  6;
   N_shift_Pos_KdT[4] = 11;

   sat_max_Curr[1] = 711; // V_motor_max = 5.179V --> 5.179V / 38.2 * (2^15/1.25V) / 5 = 711 bits
   sat_max_Curr[2] = 711;
   sat_max_Curr[3] = 711;
   sat_max_Curr[4] = 711;

   sat_max_Pos[1] = 2621; // 32000;
   sat_max_Pos[2] = 2621; // 32000;
   sat_max_Pos[3] = 1311; // 32000;
   sat_max_Pos[4] = 1311; // 32000;

   co_out_Pos = 32768;

   cf_out_Pos[1] = 1; //   53; //ax0
   cf_out_Pos[2] = 1; //   53; //ax1
   cf_out_Pos[3] = 1; //  155; //ax2
   cf_out_Pos[4] = 1; // 9200; //ax3-6

   //command the current value to cause position controller output to be 0 and prevent movement
   pos_cmd[1] = {enc_fb1[24:0]};
   pos_cmd[2] = {enc_fb2[24:0]};
   pos_cmd[3] = {enc_fb3[24:0]};
   pos_cmd[4] = {enc_fb4[24:0]};

   //timing
   val_ready_now  =  1'b0;    // reset new state for edge detection 
   val_ready_last =  1'b0;    // reset old state for edge detection
   cnt            =  4'b0;    // reset counter for x10 sampling time
   pos_val_ready  =  1'b0;    // val_ready for position controller --> 10x slower than val_ready

   // 1 (by default) ... position control enabled OR 0 ... position control disabled, motor current control only
   pos_cont_en[1] = 0;
   pos_cont_en[2] = 0;
   pos_cont_en[3] = 0;
   pos_cont_en[4] = 0;

end

//POSITION CONTROL SAMPLING TIME HANDLING:
//Ts_pos = 10x Ts_cur

always @(posedge(clk))
begin

   val_ready_now = val_ready; //fetching of ADC status

   if (val_ready_last==0 && val_ready_now==1) begin //edge detection

      if(cnt >= 4'd9) begin
         pos_val_ready <= 1;
         cnt <= 4'b0;
         // update registers
         pos_fb[1] <= {enc_fb1[24:0]};
         pos_fb[2] <= {enc_fb2[24:0]};
         pos_fb[3] <= {enc_fb3[24:0]};
         pos_fb[4] <= {enc_fb4[24:0]};
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


//DEBUG REGISTER UPDATE

always @(posedge(clk))
begin
   pos_controller_output[1] <= wire_pos_cont_out[1];
   pos_controller_output[2] <= wire_pos_cont_out[2];
   pos_controller_output[3] <= wire_pos_cont_out[3];
   pos_controller_output[4] <= wire_pos_cont_out[4];
end



//WRITE
always @(posedge(clk))
begin

   // write selected register with firewire or NOP data source
   if (reg_wen && reg_waddr[15:12]==`ADDR_CTRL) begin //if data available and valid

        if (reg_waddr[3:0]==`OFF_CO_CMD_FB) begin //write conversion offsets for commanded current and feedback current converted to a 16 bit value
            co_cmd[reg_waddr[7:4]] = reg_wdata[31:16];
            co_fbBits[reg_waddr[7:4]] = reg_wdata[15:0];
        end

        if (reg_waddr[3:0]==`OFF_CTRL_CURR_Kp_KiT) begin //write controller gains Kp and Ki*T of CL current controller of chosen channel
            Kp_Curr[reg_waddr[7:4]] = reg_wdata[31:16];
            KiT_Curr[reg_waddr[7:4]] = reg_wdata[15:0];
        end

        if (reg_waddr[3:0]==`OFF_CTRL_CURR_KdT) begin //write controller gain Kd/T of CL current controller of chosen channel
            KdT_Curr[reg_waddr[7:4]] = reg_wdata[31:16];
        end

        if (reg_waddr[3:0]==`OFF_CTRL_POS_Kp_KiT) begin //write controller gains Kp and Ki*T of CL position controller of chosen channel
            Kp_Pos[reg_waddr[7:4]] = reg_wdata[31:16];
            KiT_Pos[reg_waddr[7:4]] = reg_wdata[15:0];
        end

        if (reg_waddr[3:0]==`OFF_CTRL_POS_KdT_CF_OUT) begin //write controller gain Kd/T of CL position controller of chosen channel and conversion offset
            KdT_Pos[reg_waddr[7:4]] = reg_wdata[31:16];
            cf_out_Pos[reg_waddr[7:4]] = reg_wdata[15:0];
        end

        if (reg_waddr[3:0]==`OFF_OUT_POS_CMD) begin //write commanded position
            pos_cmd[reg_waddr[7:4]] = reg_wdata[24:0];
        end

        // not intended to be written to:
//      if (reg_waddr[3:0]==`OFF_OUT_POS_OUT) begin //write controller gain Kd/T of CL position controller of chosen channel and commanded position
//       pos_controller_output[reg_waddr[7:4]] = reg_wdata[24:0];
//      end

        if (reg_waddr[3:0]==`OFF_CTRL_SHIFTS) begin //write shifts and position control enable bits
            pos_cont_en[reg_waddr[7:4]]      = reg_wdata[31];
            N_shift_Curr_Kp[reg_waddr[7:4]]  = reg_wdata[23:20];
            N_shift_Curr_KiT[reg_waddr[7:4]] = reg_wdata[19:16];
            N_shift_Curr_KdT[reg_waddr[7:4]] = reg_wdata[15:12];
            N_shift_Pos_Kp[reg_waddr[7:4]]   = reg_wdata[11: 8];
            N_shift_Pos_KiT[reg_waddr[7:4]]  = reg_wdata[ 7: 4];
            N_shift_Pos_KdT[reg_waddr[7:4]]  = reg_wdata[ 3: 0];
        end  

   end
end


//READING BACK
assign reg_rdata = (reg_raddr[15:12]==`ADDR_CTRL) ?
          (reg_raddr[3:0]  ==`OFF_CO_CMD_FB)            ? {co_cmd[reg_waddr[7:4]], co_fbBits[reg_waddr[7:4]]}   :   // conversion offsets co_cur_cmd and co_cur_fbBits
          (reg_raddr[3:0]  ==`OFF_CTRL_CURR_Kp_KiT)     ? {Kp_Curr[reg_raddr[7:4]], KiT_Curr[reg_raddr[7:4]]}   :   // Kp and Ki*T (already bit-shifted) for motor current controller
          (reg_raddr[3:0]  ==`OFF_CTRL_CURR_KdT)        ? {KdT_Curr[reg_raddr[7:4]],16'h0}                      :   // Kd/T for motor current controller
          (reg_raddr[3:0]  ==`OFF_CTRL_POS_Kp_KiT)      ? {Kp_Pos[reg_raddr[7:4]], KiT_Pos[reg_raddr[7:4]]}     :   // Kp and Ki*T (already bit-shifted) for position controller
          (reg_raddr[3:0]  ==`OFF_CTRL_POS_KdT_CF_OUT)  ? {KdT_Pos[reg_raddr[7:4]], cf_out_Pos[reg_raddr[7:4]]} :   // Kd/T and conversion factor depending on joint for position controller
          (reg_raddr[3:0]  ==`OFF_OUT_POS_CMD)          ? {7'd0, pos_cmd[reg_raddr[7:4]]}                       :   // commanded position
          (reg_raddr[3:0]  ==`OFF_OUT_POS_OUT)          ? {7'd0, pos_controller_output[reg_raddr[7:4]]}         :   // output of position PID which is reference input for motor current PID (for debugging)
          (reg_raddr[3:0]  ==`OFF_CTRL_SHIFTS)          ? {pos_cont_en[reg_raddr[7:4]],7'h0, N_shift_Curr_Kp[reg_waddr[7:4]], N_shift_Curr_KiT[reg_waddr[7:4]], N_shift_Curr_KdT[reg_waddr[7:4]], N_shift_Pos_Kp [reg_waddr[7:4]], N_shift_Pos_KiT [reg_waddr[7:4]], N_shift_Pos_KdT[reg_waddr[7:4]]}        : 32'h0     // POS CONT ENABLE AND N_shifts for the 6 controller gains
       : 32'd0;


// INSTANTIATION:
//CH1
PID_Controller #(.pos_ctrl(0))
PID_Controller1(
   .clk(clk),
   .val_ready(val_ready),
   //.bits_cmd(wire_pos_cont_out[1]),
   .bits_cmd(wire_cur_cont_in[1]),
   .bits_fb(bits_fb1),
   .co_cmd(co_cmd[1]),
   .co_fbBits(co_fbBits[1]),
   .co_out(co_cmd[1]),
   .cf_out(16'd5),
   .Kp(Kp_Curr[1]),
   .KiT(KiT_Curr[1]),
   .KdT(KdT_Curr[1]),
   .N_shift_Kp(N_shift_Curr_Kp[1]),
   .N_shift_KiT(N_shift_Curr_KiT[1]),
   .N_shift_KdT(N_shift_Curr_KdT[1]),
   .sat_max(sat_max_Curr[1]),
   //.cont_out(cont_out4),
   .cont_out(wire_cont_out[1]),
   .out_ready(out_ready_x4[1])
);

//CH2
PID_Controller #(.pos_ctrl(0))
PID_Controller2(
   .clk(clk),
   .val_ready(val_ready),
   //.bits_cmd(wire_pos_cont_out[2]),
   .bits_cmd(wire_cur_cont_in[2]),
   .bits_fb(bits_fb2),
   .co_cmd(co_cmd[2]),
   .co_fbBits(co_fbBits[2]),
   .co_out(co_cmd[2]),
   .cf_out(16'd5),
   .Kp(Kp_Curr[2]),
   .KiT(KiT_Curr[2]),
   .KdT(KdT_Curr[2]),
   .N_shift_Kp(N_shift_Curr_Kp[2]),
   .N_shift_KiT(N_shift_Curr_KiT[2]),
   .N_shift_KdT(N_shift_Curr_KdT[2]),
   .sat_max(sat_max_Curr[2]),
   //.cont_out(cont_out4),
   .cont_out(wire_cont_out[2]),
   .out_ready(out_ready_x4[2])
);

//CH3
PID_Controller #(.pos_ctrl(0))
PID_Controller3(
   .clk(clk),
   .val_ready(val_ready),
   //.bits_cmd(wire_pos_cont_out[3]),
   .bits_cmd(wire_cur_cont_in[3]),
   .bits_fb(bits_fb3),
   .co_cmd(co_cmd[3]),
   .co_fbBits(co_fbBits[3]),
   .co_out(co_cmd[3]),
   .cf_out(16'd5),
   .Kp(Kp_Curr[3]),
   .KiT(KiT_Curr[3]),
   .KdT(KdT_Curr[3]),
   .N_shift_Kp(N_shift_Curr_Kp[3]),
   .N_shift_KiT(N_shift_Curr_KiT[3]),
   .N_shift_KdT(N_shift_Curr_KdT[3]),
   .sat_max(sat_max_Curr[3]),
   //.cont_out(cont_out4),
   .cont_out(wire_cont_out[3]),
   .out_ready(out_ready_x4[3])
);

//CH4
PID_Controller #(.pos_ctrl(0))
PID_Controller4(
   .clk(clk),
   .val_ready(val_ready),
   //.bits_cmd(wire_pos_cont_out[4]),
   .bits_cmd(wire_cur_cont_in[4]),
   .bits_fb(bits_fb4),
   .co_cmd(co_cmd[4]),
   .co_fbBits(co_fbBits[4]),
   .co_out(co_cmd[4]),
   .cf_out(16'd5),
   .Kp(Kp_Curr[4]),
   .KiT(KiT_Curr[4]),
   .KdT(KdT_Curr[4]),
   .N_shift_Kp(N_shift_Curr_Kp[4]),
   .N_shift_KiT(N_shift_Curr_KiT[4]),
   .N_shift_KdT(N_shift_Curr_KdT[4]),
   .sat_max(sat_max_Curr[4]),
   //.cont_out(cont_out4),
   .cont_out(wire_cont_out[4]),
   .out_ready(out_ready_x4[4])
);


// POSITION CH1
PID_Controller #(.pos_ctrl(1))
PID_POS1(
   .clk(clk),
   //.val_ready(pos_val_ready),
   .val_ready(val_ready),
   .bits_cmd(pos_cmd[1]),
   .bits_fb(pos_fb[1]),
   .co_cmd(16'd0),
   .co_fbBits(16'd0),
   .co_out(co_cmd[1]),
   .cf_out(cf_out_Pos[1]),
   .Kp(Kp_Pos[1]),
   .KiT(KiT_Pos[1]),
   .KdT(KdT_Pos[1]),
   .N_shift_Kp(N_shift_Pos_Kp[1]),
   .N_shift_KiT(N_shift_Pos_KiT[1]),
   .N_shift_KdT(N_shift_Pos_KdT[1]),
   .sat_max(sat_max_Pos[1]),
   .cont_out(wire_pos_cont_out[1]),
   .out_ready(out_pos_ready_x4[1])
);
//defparam PID_POS1.factorI2V = 0;

// POSITION CH2
PID_Controller #(.pos_ctrl(1))
PID_POS2(
   .clk(clk),
   //.val_ready(pos_val_ready),
   .val_ready(val_ready),
   .bits_cmd(pos_cmd[2]),
   .bits_fb(pos_fb[2]),
   .co_cmd(16'd0),
   .co_fbBits(16'd0),
   .co_out(co_cmd[2]),
   .cf_out(cf_out_Pos[2]),
   .Kp(Kp_Pos[2]),
   .KiT(KiT_Pos[2]),
   .KdT(KdT_Pos[2]),
   .N_shift_Kp(N_shift_Pos_Kp[2]),
   .N_shift_KiT(N_shift_Pos_KiT[2]),
   .N_shift_KdT(N_shift_Pos_KdT[2]),
   .sat_max(sat_max_Pos[2]),
   .cont_out(wire_pos_cont_out[2]),
   .out_ready(out_pos_ready_x4[2])
);
//defparam PID_POS2.factorI2V = 0;

// POSITION CH3
PID_Controller #(.pos_ctrl(1))
PID_POS3(
   .clk(clk),
   //.val_ready(pos_val_ready),
   .val_ready(val_ready),
   .bits_cmd(pos_cmd[3]),
   .bits_fb(pos_fb[3]),
   .co_cmd(16'd0),
   .co_fbBits(16'd0),
   .co_out(co_cmd[3]),
   .cf_out(cf_out_Pos[3]),
   .Kp(Kp_Pos[3]),
   .KiT(KiT_Pos[3]),
   .KdT(KdT_Pos[3]),
   .N_shift_Kp(N_shift_Pos_Kp[3]),
   .N_shift_KiT(N_shift_Pos_KiT[3]),
   .N_shift_KdT(N_shift_Pos_KdT[3]),
   .sat_max(sat_max_Pos[3]),
   .cont_out(wire_pos_cont_out[3]),
   .out_ready(out_pos_ready_x4[3])
);
//defparam PID_POS3.factorI2V = 0;

// POSITION CH4
PID_Controller #(.pos_ctrl(1))
PID_POS4(
   .clk(clk),
   //.val_ready(pos_val_ready),
   .val_ready(val_ready),
   .bits_cmd(pos_cmd[4]),
   .bits_fb(pos_fb[4]),
   .co_cmd(16'd0),
   .co_fbBits(16'd0),
   .co_out(co_cmd[4]),
   .cf_out(cf_out_Pos[4]),
   .Kp(Kp_Pos[4]),
   .KiT(KiT_Pos[4]),
   .KdT(KdT_Pos[4]),
   .N_shift_Kp(N_shift_Pos_Kp[4]),
   .N_shift_KiT(N_shift_Pos_KiT[4]),
   .N_shift_KdT(N_shift_Pos_KdT[4]),
   .sat_max(sat_max_Pos[4]),
   .cont_out(wire_pos_cont_out[4]),
   .out_ready(out_pos_ready_x4[1])
);
//defparam PID_POS4.factorI2V = 0;


endmodule
