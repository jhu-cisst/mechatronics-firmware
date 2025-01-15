
if (Vivado_FOUND)

  set (DPRAM_32x1024_sclk_PROPS
       "CONFIG.Assume_Synchronous_Clk true"
       "CONFIG.Memory_Type Simple_Dual_Port_RAM"
       "CONFIG.Operating_Mode_A READ_FIRST"
       "CONFIG.Write_Depth_A 1024"
       "CONFIG.Write_Width_A 32")

  vivado_ip_gen (TARGET_NAME "DPRAM_32x1024_sclk"
                 IP_NAME     "blk_mem_gen"
                 PROPERTIES  ${DPRAM_32x1024_sclk_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (DPRAM_32x512_sclk_PROPS
       "CONFIG.Assume_Synchronous_Clk true"
       "CONFIG.Memory_Type Simple_Dual_Port_RAM"
       "CONFIG.Enable_A Always_Enabled"
       "CONFIG.Enable_B Always_Enabled"
       "CONFIG.Operating_Mode_A READ_FIRST"
       "CONFIG.Write_Depth_A 512"
       "CONFIG.Write_Width_A 32"
       "CONFIG.Fill_Remaining_Memory_Locations true"
       "CONFIG.Register_PortB_Output_of_Memory_Primitives false")

  vivado_ip_gen (TARGET_NAME "DPRAM_32x512_sclk"
                 IP_NAME     "blk_mem_gen"
                 PROPERTIES  ${DPRAM_32x512_sclk_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (DPRAM_32x512_aclk_PROPS
       "CONFIG.Memory_Type Simple_Dual_Port_RAM"
       "CONFIG.Enable_A Always_Enabled"
       "CONFIG.Enable_B Always_Enabled"
       "CONFIG.Operating_Mode_A WRITE_FIRST"
       "CONFIG.Write_Depth_A 512"
       "CONFIG.Write_Width_A 32"
       "CONFIG.Fill_Remaining_Memory_Locations true"
       "CONFIG.Register_PortB_Output_of_Memory_Primitives false")

  vivado_ip_gen (TARGET_NAME "DPRAM_32x512_aclk"
                 IP_NAME     "blk_mem_gen"
                 PROPERTIES  ${DPRAM_32x512_aclk_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (FIFO_10x8192_PROPS
       "CONFIG.Fifo_Implementation Independent_Clocks_Block_RAM"
       "CONFIG.Enable_Safety_Circuit false"
       "CONFIG.Full_Flags_Reset_Value 0"
       "CONFIG.Input_Data_Width 10"
       "CONFIG.Input_Depth 8192"
       "CONFIG.Underflow_Flag true"
       "CONFIG.Valid_Flag true")

  vivado_ip_gen (TARGET_NAME "fifo_10x8192"
                 IP_NAME     "fifo_generator"
                 PROPERTIES  ${FIFO_10x8192_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (FIFO_4x128_PROPS
       "CONFIG.Fifo_Implementation Independent_Clocks_Block_RAM"
       "CONFIG.Enable_Safety_Circuit false"
       "CONFIG.Full_Flags_Reset_Value 0"
       "CONFIG.Input_Data_Width 4"
       "CONFIG.Input_Depth 128"
       "CONFIG.Valid_Flag true")

  vivado_ip_gen (TARGET_NAME "fifo_4x128"
                 IP_NAME     "fifo_generator"
                 PROPERTIES  ${FIFO_4x128_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (GMII_TO_RGMII_1_PROPS
       "CONFIG.SupportLevel Include_Shared_Logic_in_Core")

  vivado_ip_gen (TARGET_NAME "gmii_to_rgmii_1"
                 IP_NAME     "gmii_to_rgmii"
                 PROPERTIES  ${GMII_TO_RGMII_1_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (GMII_TO_RGMII_2_PROPS
       "CONFIG.SupportLevel Include_Shared_Logic_in_Core"
       "CONFIG.C_USE_IDELAY_CTRL false")

  vivado_ip_gen (TARGET_NAME "gmii_to_rgmii_2"
                 IP_NAME     "gmii_to_rgmii"
                 PROPERTIES  ${GMII_TO_RGMII_2_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  set (PWM_CLK_GEN_ZYNQ_PROPS
       "CONFIG.PRIMARY_PORT CLK_IN1"
       "CONFIG.CLK_OUT1_PORT CLK_OUT1"
       "CONFIG.CLKIN1_JITTER_PS 100"
       "CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 147.456"
       "CONFIG.JITTER_OPTIONS PS"
       "CONFIG.PRIM_IN_FREQ 49.152"
       "CONFIG.PRIM_SOURCE No_buffer"
       "CONFIG.USE_LOCKED false"
       "CONFIG.USE_RESET false")

  vivado_ip_gen (TARGET_NAME "pwm_clk_gen_zynq"
                 IP_NAME     "clk_wiz"
                 PROPERTIES  ${PWM_CLK_GEN_ZYNQ_PROPS}
                 IPCORE_DIR  ${CMAKE_CURRENT_BINARY_DIR})

  vivado_block_ip (TARGET_NAME  "processing_system7_0"
                   IP_NAME      "processing_system7"
                   FPGA_PARTNUM ${FPGAV3_PARTNUM}
                   BLOCK_IN     ${BLOCK_DESIGN_IN}
                   IPCORE_DIR   ${CMAKE_CURRENT_BINARY_DIR})
else ()
  ## ISE

  set (IPCORE_DIR "${FPGA1394_QLA_SOURCE_DIR}/ipcore_dir")

  # IP core source files used by all versions of firmware.
  # Using XCP files instead of XCO because project settings
  # (e.g., target device) are set in coregen.cgp.
  set (IPCORE_SOURCE_COMMON "${IPCORE_DIR}/DPRAM_32x512_sclk.xcp"
                            "${IPCORE_DIR}/DPRAM_32x512_aclk.xcp"
                            "${IPCORE_DIR}/DPRAM_32x1024_sclk.xcp"
                            "${IPCORE_DIR}/pwm_clk_gen_zynq.xcp")

  set (IPCORE_SOURCE ${IPCORE_SOURCE_COMMON}
                     "${CMAKE_CURRENT_SOURCE_DIR}/fifo_10x8192.xcp"
                     "${CMAKE_CURRENT_SOURCE_DIR}/fifo_4x128.xcp")

  ise_ipcoregen(TARGET_NAME       "CoreGenV3"
                XCO_SOURCE        ${IPCORE_SOURCE}
                CGP_IN_FILE       "${IPCORE_DIR}/coregen.cgp.in"
                FPGA_FAMILY       ${FPGAV3_FAMILY}
                FPGA_DEVICE       ${FPGAV3_DEVICE}
                FPGA_PACKAGE      ${FPGAV3_PACKAGE}
                FPGA_SPEED        ${FPGAV3_SPEED})

  # For convenience, do not automatically clean this (i.e., do not delete coregen.log)
  # To regenerate IP cores, must manually delete coregen.log
  set_directory_properties(PROPERTIES CLEAN_NO_CUSTOM TRUE)

  # XPS subdirectory for Zynq PS7 core
  add_subdirectory(xps)

endif ()
