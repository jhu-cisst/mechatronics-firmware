HOW TO BUILD EXAMPLE DESIGN:

Example design module is placed in example_design directory during core generation.To implement the example design, follow any of the below methods. 


Method 1 : If Core is generated from CoreGen, to run implementation on the example design through ISE:
	  
           Step 1: Launch a ISE Design Suite Command Line
	   Step 2: Change directory to the implement folder
           Step 3: ./ise_implement.sh or ise_implement.bat

Method 2 : If Core is generated from PlanAhead, to run implementation on example design either through ISE using PlanAhead:
           Execute the below commands in the PlanAhead tcl console:

           Step 1: change directory to the implement folder
           Step 2: source pa_ise_implement.tcl

When this example design is run on analyzer, the following scenarios can be tested.

1) Shift operation is observed on each trigger port. Each trigger port can be distinguished from other trigger ports with pulse width. 

For example, consider if two trigger ports are selected of width 2, shift operation observed on each trigger port is shown below:

For TRIG0:
	           __    __    __    __    __    __    __    
TRIG0[0]:	     |__|  |__|	 |__|  |__|  |__|  |__|  |__	
                      __    __    __    __    __    __    __
TRIG0[1]:          __|  |__|  |__|  |__|  |__|  |__|  |__|   

FOR TRIG1:
                         _____       _____       _____       _____
TRIG1[0]:           ____|     |_____|     |_____|     |_____|     |_____
                    ____       _____       _____       _____       _____
TRIG1[1]:               |_____|     |_____|     |_____|     |_____|

2) If Data port is selected, Johnson Counter operation can be observed on Data port. 
3) If TRIG_OUT port is selected, shift operation is observed on VIO console. To observe walking one pattern on VIO console, enable trig_out while setting trigger condition.The option is set to DISABLED by default.

