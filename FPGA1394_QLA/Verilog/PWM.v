module PWM
#(parameter COUNTER_WIDTH=10)
(
input clk,
input wire signed [COUNTER_WIDTH:0] duty_cycle,
input wire [COUNTER_WIDTH:0] counter_unfolded,
input wire pwm_cycle_start,
output reg pwm_p = 0,  
output reg pwm_n = 0  
);

wire counter_down = ~counter_unfolded[COUNTER_WIDTH];
wire [COUNTER_WIDTH - 1:0] counter = counter_down ? {{COUNTER_WIDTH}{1'b1}} - counter_unfolded[COUNTER_WIDTH - 1:0]  : counter_unfolded[COUNTER_WIDTH - 1:0];

reg signed [COUNTER_WIDTH:0] duty_cycle_this_period = 0;
wire forward = duty_cycle_this_period > 0;
wire [COUNTER_WIDTH-1:0] duty_cycle_abs = forward ? duty_cycle_this_period : -duty_cycle_this_period;
wire pwm = counter < duty_cycle_abs; 


always @(posedge clk)
begin
    if (pwm_cycle_start) 
    begin
        duty_cycle_this_period <= duty_cycle == 11'sh400 ? 11'sh401 : duty_cycle;
    end
    pwm_p <= pwm & forward;
    pwm_n <= pwm & (~forward);
end

endmodule