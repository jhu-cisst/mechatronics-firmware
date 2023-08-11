 //*Copyright(C) 2019-2020 ERC CISST, Johns Hopkins University.
 //*
 //* Module:  AD4008.v
 //* The AD4008 module receice AD converter start (CNV) and sck from the the ADC_ctrl module and pass the 16 bit ADC data to TORQUE_CTRL module  
 // 
module AD4008(
                input wire         sck,	            // sck signal to all the ADCs 
                input wire         sdo,             // AD4008 output  
                input wire         data_ready,          // latch ADC data for Torque Control Module to process
                output wire[31:0]   out             // ADC values captured from the  ADC
             );
//TODO: add SDI interface
reg[31:0] adc_data = 0; 

always @(negedge sck)
    adc_data <= {adc_data[30:0], sdo};


assign out = adc_data;

endmodule
