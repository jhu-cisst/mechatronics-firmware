CHANGE LOG for Xilinx LogiCORE FIR Compiler 6.3

Release Date:  October 2, 2013 
--------------------------------------------------------------------------------

Table of Contents

1.   INTRODUCTION 
2.   DEVICE SUPPORT    
3.   NEW FEATURE HISTORY   
4.   RESOLVED ISSUES 
5.   KNOWN ISSUES & LIMITATIONS 
6.   TECHNICAL SUPPORT & FEEDBACK 
7.   CORE RELEASE HISTORY 
8.   LEGAL DISCLAIMER 

--------------------------------------------------------------------------------


1. INTRODUCTION

  This file contains the change log for all released versions of the Xilinx 
  LogiCORE IP FIR Compiler. 

  For the latest core updates, see the product page at:

    http://www.xilinx.com/products/ipcenter/FIR_Compiler.htm

  For installation instructions for this release, please go to:

    http://www.xilinx.com/ipcenter/coregen/ip_update_install_instructions.htm

  For system requirements:

    http://www.xilinx.com/ipcenter/coregen/ip_update_system_requirements.htm


2. DEVICE SUPPORT 

  2.1. ISE

    The following device families are supported by the core for this release:

    All Series 7 devices
    All Virtex-6 devices
    All Spartan-6 devices


3. NEW FEATURE HISTORY

  3.1 ISE
 
  v6.3
    - Ongoing new device support.
    - Advanced Interleaved Channels (Configurable Bandwidth support)
    - Multi-column support for symmetric filter implementations
    - Re-introduction of Hilbert Transform, Single Rate Half-Band and Interpolated filters
    - C Model added


4. RESOLVED ISSUES 

  4.1 ISE

    - FIR Compiler v6.x - GUI may crash when Maximize_Dynamic_Range is selected
      - CR 627620
      
    - FIR Compiler v6.x - Reload port allows boolean type in System Generator
      - CR 640607
      
    - FIR Compiler v6.x - Custom column lengths ignored in System Generator for some core configurations
      - CR 630639
      
    - FIR Compiler v6.x - Latency information in the GUI doesn't match the core
      - AR 40200
      - CR 591161
     
    - FIR Compiler v6.x : Multi-column filters will not map/place
      - AR 40769
      - CR 594220
      
    - FIR Compiler v6.2 - The output for a Fractional Rate is in bursts rather than at regular intervals
      - AR 41707
      - CR 605099
  
    - FIR Compiler v6.x : Event I/F mismatches between model and core
      - AR 42305
      - CR 592301
    
    - FIR Compiler v6.2 - Multi-Channel core data comes out on the wrong channel
      - The output shift channels when using a multi-channel, interpolate by 2, odd number of symetrical coefficients, 
        with oversample rate of 3 with Block RAM selected for memory implementation
      - AR 42727
      - CR 614460
      - N/A


5. KNOWN ISSUES & LIMITATIONS 

  The following are known issues for this core at time of release:

  5.1 ISE
    1. Unsupported v5.0 features - The following features are not supported by v6.3:
      - Distributed Arithmetic
      - Polyphase filter bank
      
    2. Memory collision errors - Netlist or UniSim structural model simulation may 
        report Block RAM memory collision errors. These errors are issued by the Block RAM 
        primitive when a write occurs and the read and write addresses match. However, a 
        read or write event is qualified by read enable or write enable respectively. 
        In operation, read and write events never occur to the same address at the same 
        time so functionality is not affected by these apparent collisions.

  For a comprehensive listing of Known Issues for this core, please see the IP 
  Release Notes Guide,  
    
    www.xilinx.com/support/documentation/user_guides/xtp025.pdf


6. TECHNICAL SUPPORT & FEEDBACK

  To obtain technical support, create a WebCase at www.xilinx.com/support.
  Questions are routed to a team with expertise using this product.
  Please feel free to leave feedback on this IP under the "Leave Feedback"
  menu item in Vivado/PlanAhead.

  Xilinx provides technical support for use of this product when used
  according to the guidelines described in the core documentation, and
  cannot guarantee timing, functionality, or support of this product for
  designs that do not follow specified guidelines.


7. CORE RELEASE HISTORY

Date        By            Version      Description
================================================================================
10/02/2013  Xilinx, Inc.  6.3          ISE 14.7 support and Production support for Series 7
06/19/2012  Xilinx, Inc.  6.3          ISE 14.6 support
03/20/2012  Xilinx, Inc.  6.3          ISE 14.5 support. 
12/18/2012  Xilinx, Inc.  6.3          ISE 14.4 and Vivado 2012.4 support
10/16/2012  Xilinx, Inc.  6.3          ISE 14.3 and Vivado 2012.3 support
07/25/2012  Xilinx, Inc.  6.3          ISE 14.2 and Vivado 2012.2 support
04/24/2012  Xilinx, Inc.  6.3          ISE 14.1 and Vivado 2012.1 support
01/11/2012  Xilinx, Inc.  6.3          ISE 13.4 support
10/19/2011  Xilinx, Inc.  6.3          ISE 13.3 support.
06/22/2011  Xilinx, Inc.  6.2          ISE 13.2 support, Artix-7 support
03/01/2011  Xilinx, Inc.  6.2          IDS 13.1 support.
12/14/2010  Xilinx, Inc.  6.1          IDS 12.4 support.
09/21/2010  Xilinx, Inc.  6.0          IDS 12.3 support. AXI4-Stream Interfaces
12/02/2009  Xilinx, Inc.  5.0          11.4 support, Spartan-6L support
                                       and Automotive Spartan6 support
09/16/2009  Xilinx, Inc.  5.0          11.3 support, Virtex-6L support
06/24/2009  Xilinx, Inc.  5.0          11.2 support, Virtex-6 and Spartan-6 support
05/30/2008  Xilinx, Inc.  4.0          Scheduled Release
10/10/2007  Xilinx, Inc.  3.2          Patch Release
================================================================================


8. LEGAL DISCLAIMER

  (c) Copyright 2002 - 2013 Xilinx, Inc. All rights reserved.
  
  This file contains confidential and proprietary information
  of Xilinx, Inc. and is protected under U.S. and
  international copyright and other intellectual property
  laws.
  
  DISCLAIMER
  This disclaimer is not a license and does not grant any
  rights to the materials distributed herewith. Except as
  otherwise provided in a valid license issued to you by
  Xilinx, and to the maximum extent permitted by applicable
  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
  WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
  (2) Xilinx shall not be liable (whether in contract or tort,
  including negligence, or under any other theory of
  liability) for any loss or damage of any kind or nature
  related to, arising under or in connection with these
  materials, including for any direct, or any indirect,
  special, incidental, or consequential loss or damage
  (including loss of data, profits, goodwill, or any type of
  loss or damage suffered as a result of any action brought
  by a third party) even if such damage or loss was
  reasonably foreseeable or Xilinx had been advised of the
  possibility of the same.
  
  CRITICAL APPLICATIONS
  Xilinx products are not designed or intended to be fail-
  safe, or for use in any application requiring fail-safe
  performance, such as life-support or safety devices or
  systems, Class III medical devices, nuclear facilities,
  applications related to the deployment of airbags, or any
  other applications that could lead to death, personal
  injury, or severe property or environmental damage
  (individually and collectively, "Critical
  Applications"). Customer assumes the sole risk and
  liability of any use of Xilinx products in Critical
  Applications, subject only to applicable laws and
  regulations governing limitations on product liability.
  
  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
  PART OF THIS FILE AT ALL TIMES.
  
