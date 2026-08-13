 //*Copyright(C) 2019-2020 ERC CISST, Johns Hopkins University.
 //*
 //* Module:  AD4008.v
 //* The AD4008 module receice AD converter start (CNV) and sck from the the ADC_ctrl module and pass the 16 bit ADC data to TORQUE_CTRL module  
 // 
module AD4008(
                input wire         sck,	            // sck signal to all the ADCs 
                input wire         sdo,             // AD4008 output  
                output wire[15:0]   out             // ADC values captured from the ADC
             );
//TODO: add SDI interface
reg[15:0] adc_data = 0;

// The ADC advances SDO after each falling SCK edge. Capture on the following
// rising edge so the input gets a half-cycle setup window instead of relying
// on the ADC's 1.5 ns minimum hold time at the launch edge.
always @(posedge sck)
    adc_data <= {adc_data[14:0], sdo};


assign out = adc_data;

endmodule
