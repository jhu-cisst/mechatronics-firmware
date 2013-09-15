module HubReg(
    input  wire sysclk,            // system clk
    input  wire reset,             // system reset
    input  wire hub_rx_active,     // hub rx active
    input  wire[7:0] hub_addr,     // hub reg addr
    input  wire[31:0] hub_wdata,   // hub incoming write data
    output wire[31:0] hub_rdata    // hub outgoing read data 
);

reg[31:0] hub_mem[15:0][15:0];    // memory for storing FPGA boards data

assign hub_rdata = hub_mem[hub_addr[7:4]][hub_addr[3:0]];


// handle register write
always @(posedge(sysclk) or negedge(reset))
begin
    if (reset==0) begin
        hub_mem[0][0] <= 5;
        hub_mem[9][12] <= 32'h9C;
    end
    else begin
        if (hub_rx_active) begin
             hub_mem[hub_addr[7:4]][hub_addr[3:0]] <= hub_wdata;
        end
    end
end


endmodule