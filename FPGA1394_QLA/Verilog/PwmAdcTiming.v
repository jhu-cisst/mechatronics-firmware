`include "Constants.v"

module PwmAdcTiming
#(parameter COUNTER_WIDTH=10)
(
    input wire clk,
    input sysclk,
    output wire adc_sck,
    output reg adc_cnv = 0, // ADC samples at rising edge
    output wire adc_data_ready, // Data valid at rising edge. Stays high until start of next acquisition.
    output wire pwm_cycle_start, // PWM cycle starts at rising edge.
    output wire feedback_calculation_start, // two ADC measurements are ready at rising edge.
    output reg [COUNTER_WIDTH:0] counter_unfolded=0,
    output reg adc_sdi=1,
    input  wire[15:0] reg_waddr,     // register write address
    input  wire[31:0] reg_wdata,    // register write data
    input  wire reg_wen            // write enable from FireWire module
);
reg [15:0] adc_sdi_buffer = 16'hffff;
parameter integer adc_sck_div_ratio = 4;
parameter clk_period = 6.78; // ns
parameter adc_sck_period = clk_period * adc_sck_div_ratio; // ns
parameter integer t_cnv = 360 / adc_sck_period + 1; 
parameter integer t_en = 20 / clk_period + 1; 
// Refer page 7. https://www.analog.com/media/en/technical-documentation/data-sheets/AD4000-4004-4008.pdf
parameter integer n_sck_pulses = 16;

reg [15:0] adc_timing_counter = 16'd0;
reg [10:0] adc_conv_phase = 11'd511;
reg [3:0] current_loop_divider = 4'd0;

reg adc_data_ready_adcclk;

wire adc_sck_div;
wire adc_sck_ce;
// reg adc_sck_gated = 0;

ClkDiv #(.width(2)) adc_clkdiv_instance (.clkin(clk), .clkout(adc_sck_div));
BUFGCE adc_sck_bufg (
    .I(adc_sck_div),
    .O(adc_sck),
    .CE(adc_sck_ce)
);

reg adc_cnv_toggle_pwm_clk = 0;
reg [1:0] sync_cnv_adc_sck = 0;
reg adc_cnv_pulse_adc_sck = 0;
wire conv_start = counter_unfolded == adc_conv_phase;
always @ (posedge clk) begin
    counter_unfolded <= counter_unfolded + 1;

    if (conv_start) begin
            adc_cnv_toggle_pwm_clk <= ~adc_cnv_toggle_pwm_clk;
    end
end

assign adc_sck_ce = state == STATE_SHIFT;

localparam [3:0] STATE_IDLE = 'd0, STATE_CONV = 'd1, STATE_EN = 'd2, STATE_SHIFT = 'd3, STATE_DONE = 'd4;
reg [3:0] state = STATE_IDLE;
always @ (posedge adc_sck_div) begin
    sync_cnv_adc_sck <= {sync_cnv_adc_sck[0], adc_cnv_toggle_pwm_clk};
    adc_cnv_pulse_adc_sck <= sync_cnv_adc_sck[1] ^ sync_cnv_adc_sck[0];

    case (state) 
    STATE_IDLE: begin
        adc_data_ready_adcclk <= 0;
        if (adc_cnv_pulse_adc_sck) begin
            adc_timing_counter <= 16'd0;
            adc_cnv <= 1;
            state <= STATE_CONV;
        end
    end
    STATE_CONV: begin
        if (adc_timing_counter == t_cnv) begin
            adc_timing_counter <= 16'd0;
            adc_cnv <= 0;
            state <= STATE_EN;
        end else adc_timing_counter <= adc_timing_counter + 16'd1;
    end
    STATE_EN: begin
        if (adc_timing_counter == t_en) begin
            adc_timing_counter <= 0;
            state <= STATE_SHIFT;
        end else adc_timing_counter <= adc_timing_counter + 16'd1;
    end
    STATE_SHIFT: begin

        if (adc_timing_counter == n_sck_pulses - 1) begin
            adc_timing_counter <= 0;
            state <= STATE_DONE;
        end else adc_timing_counter <= adc_timing_counter + 16'd1;
    end
    STATE_DONE: begin
        if (adc_timing_counter == 'h4) begin
            adc_data_ready_adcclk <= 1;
            adc_timing_counter <= 0;
            state <= STATE_IDLE;
        end else adc_timing_counter <= adc_timing_counter + 16'd1;
    end
    endcase
end
wire [16:0] adc_sdi_buffer_padded = {adc_sdi_buffer, 1'b1};
always @ (negedge adc_sck_div) begin
    if (state == STATE_SHIFT)
        adc_sdi <= adc_sdi_buffer_padded[16 - adc_timing_counter];
    else
        adc_sdi <= 1'b1;
end

reg [3:0] current_loop_div_counter;
always @(posedge clk) begin
    if (pwm_cycle_start) begin
        if (current_loop_div_counter == current_loop_divider) begin
            current_loop_div_counter <= 4'd0;
        end else begin
            current_loop_div_counter <= current_loop_div_counter + 4'd1;
        end
    end
end

cdc_pulse adc_data_ready_cdc (.clk_a(adc_sck_div), .data_a(adc_data_ready_adcclk), .clk_b(clk), .data_b(adc_data_ready));

assign pwm_cycle_start = counter_unfolded == {{COUNTER_WIDTH + 1'b1}{1'b1}};
assign feedback_calculation_start = (counter_unfolded == {{COUNTER_WIDTH + 1'b1}{1'b1}} - 50) && (current_loop_div_counter == 4'd0);

always @(posedge sysclk)
begin
    if (reg_wen && reg_waddr[15:12]==`ADDR_MOTOR_CONTROL && reg_waddr[7:4]== 4'b0) begin
        case (reg_waddr[3:0])
            4'h1: adc_sdi_buffer <= reg_wdata[15:0];
            4'h2: adc_conv_phase <= reg_wdata[10:0];
            4'h3: current_loop_divider <= reg_wdata[3:0];
        endcase
    end
end

endmodule
