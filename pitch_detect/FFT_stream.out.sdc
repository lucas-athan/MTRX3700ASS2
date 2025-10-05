## Generated SDC file "FFT_stream.out.sdc"

## Copyright (C) 2020  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and any partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel FPGA IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Intel and sold by Intel or its authorized distributors.  Please
## refer to the applicable agreement for further details, at
## https://fpgasoftware.intel.com/eula.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 20.1.0 Build 711 06/05/2020 SJ Lite Edition"

## DATE    "Sun Sep 14 23:10:29 2025"

##
## DEVICE  "5CSEMA5F31C6"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {CLOCK_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {CLOCK_50}]
create_clock -name {AUD_BCLK} -period 325.520 -waveform { 0.000 162.760 } [get_ports {AUD_BCLK}]
create_clock -name {adc_clk} -period 54.250 -waveform { 0.000 27.125 } [get_nets {adc_pll_u|altpll_component|auto_generated|wire_generic_pll1_outclk}]
create_clock -name {i2c_clk} -period 50000.000 -waveform { 0.000 25000.000 } [get_nets {i2c_pll_u|altpll_component|auto_generated|wire_generic_pll1_outclk}]


#**************************************************************
# Create Generated Clock
#**************************************************************



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {adc_clk}] -rise_to [get_clocks {adc_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {adc_clk}] -fall_to [get_clocks {adc_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {adc_clk}] -rise_to [get_clocks {AUD_BCLK}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {adc_clk}] -fall_to [get_clocks {AUD_BCLK}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {adc_clk}] -rise_to [get_clocks {adc_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {adc_clk}] -fall_to [get_clocks {adc_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {adc_clk}] -rise_to [get_clocks {AUD_BCLK}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {adc_clk}] -fall_to [get_clocks {AUD_BCLK}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {i2c_clk}] -rise_to [get_clocks {i2c_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {i2c_clk}] -fall_to [get_clocks {i2c_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {i2c_clk}] -rise_to [get_clocks {i2c_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {i2c_clk}] -fall_to [get_clocks {i2c_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {AUD_BCLK}] -rise_to [get_clocks {adc_clk}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {AUD_BCLK}] -fall_to [get_clocks {adc_clk}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {AUD_BCLK}] -rise_to [get_clocks {AUD_BCLK}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {AUD_BCLK}] -rise_to [get_clocks {AUD_BCLK}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {AUD_BCLK}] -fall_to [get_clocks {AUD_BCLK}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {AUD_BCLK}] -fall_to [get_clocks {AUD_BCLK}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {AUD_BCLK}] -rise_to [get_clocks {adc_clk}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {AUD_BCLK}] -fall_to [get_clocks {adc_clk}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {AUD_BCLK}] -rise_to [get_clocks {AUD_BCLK}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {AUD_BCLK}] -rise_to [get_clocks {AUD_BCLK}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {AUD_BCLK}] -fall_to [get_clocks {AUD_BCLK}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {AUD_BCLK}] -fall_to [get_clocks {AUD_BCLK}] -hold 0.060  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_keepers {*rdptr_g*}] -to [get_keepers {*ws_dgrp|dffpipe_re9:dffpipe15|dffe16a*}]
set_false_path -from [get_keepers {*delayed_wrptr_g*}] -to [get_keepers {*rs_dgwp|dffpipe_qe9:dffpipe12|dffe13a*}]


#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

