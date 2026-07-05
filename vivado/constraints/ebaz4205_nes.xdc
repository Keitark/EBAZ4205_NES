################################################################################
# ebaz4205_nes.xdc
# Constraints for EBAZ4205 NES (tarunes port)
################################################################################

#===============================================================================
# System Clock
#===============================================================================
set_property PACKAGE_PIN N18 [get_ports CLK]
set_property IOSTANDARD LVCMOS33 [get_ports CLK]
create_clock -period 30.000 -name sys_clk_pin -waveform {0.000 15.000} [get_ports CLK]

#===============================================================================
# HDMI TMDS Output (Adapter board)
#===============================================================================
# HDMI Clock
set_property PACKAGE_PIN F19 [get_ports HDMI_CLK_P]
set_property IOSTANDARD TMDS_33 [get_ports HDMI_CLK_P]
# set_property PACKAGE_PIN F20 [get_ports HDMI_CLK_N]
# set_property IOSTANDARD TMDS_33 [get_ports HDMI_CLK_N]

# HDMI Data 0 (Blue)
set_property PACKAGE_PIN D19 [get_ports {HDMI_P[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {HDMI_P[0]}]
# set_property PACKAGE_PIN D20 [get_ports {HDMI_N[0]}]
# set_property IOSTANDARD TMDS_33 [get_ports {HDMI_N[0]}]

# HDMI Data 1 (Green)
set_property PACKAGE_PIN C20 [get_ports {HDMI_P[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {HDMI_P[1]}]
# set_property PACKAGE_PIN B20 [get_ports {HDMI_N[1]}]
# set_property IOSTANDARD TMDS_33 [get_ports {HDMI_N[1]}]

# HDMI Data 2 (Red)
set_property PACKAGE_PIN B19 [get_ports {HDMI_P[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {HDMI_P[2]}]
# set_property PACKAGE_PIN A20 [get_ports {HDMI_N[2]}]
# set_property IOSTANDARD TMDS_33 [get_ports {HDMI_N[2]}]

#===============================================================================
# Buttons (Adapter board)
#===============================================================================
set_property PACKAGE_PIN T19 [get_ports {BTN[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[0]}]

set_property PACKAGE_PIN P19 [get_ports {BTN[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[1]}]

set_property PACKAGE_PIN U20 [get_ports {BTN[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[2]}]

set_property PACKAGE_PIN U19 [get_ports {BTN[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[3]}]

set_property PACKAGE_PIN V20 [get_ports {BTN[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[4]}]

#===============================================================================
# NTSC Composite Video (3-bit resistor DAC) + PWM Audio
# User GPIO header on the adapter board. GPIO index -> package pin mapping
# assumed: GPIO0=T20, GPIO1=R18, GPIO2=N17, GPIO3=R19 (GPIO4=P20 spare).
# Verify against your adapter board wiring and adjust if needed.
#
# External circuit:
#   GPIO0 (COMP_DAC[0], LSB) -- 910 ohm --+
#   GPIO1 (COMP_DAC[1])      -- 470 ohm --+-- RCA video center
#   GPIO2 (COMP_DAC[2], MSB) -- 220 ohm --+
#   GPIO3 (AUDIO_PWM) -- 1k + 100nF LPF -- 10uF -- RCA audio center
#===============================================================================
set_property PACKAGE_PIN T20 [get_ports {COMP_DAC[0]}]
set_property PACKAGE_PIN R18 [get_ports {COMP_DAC[1]}]
set_property PACKAGE_PIN N17 [get_ports {COMP_DAC[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {COMP_DAC[*]}]
# Low output impedance and fast edges keep the resistor DAC accurate
set_property DRIVE 16 [get_ports {COMP_DAC[*]}]
set_property SLEW FAST [get_ports {COMP_DAC[*]}]
# Register the DAC bits in the IOB so all three switch simultaneously
set_property IOB TRUE [get_ports {COMP_DAC[*]}]

set_property PACKAGE_PIN R19 [get_ports AUDIO_PWM]
set_property IOSTANDARD LVCMOS33 [get_ports AUDIO_PWM]

#===============================================================================
# RGB LED (Adapter board)
#===============================================================================
set_property PACKAGE_PIN E19 [get_ports {LED_RGB[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED_RGB[0]}]

set_property PACKAGE_PIN K17 [get_ports {LED_RGB[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED_RGB[1]}]

set_property PACKAGE_PIN H18 [get_ports {LED_RGB[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED_RGB[2]}]

#===============================================================================
# Timing Exceptions
#===============================================================================
# Asynchronous paths between PS AXI clock (100MHz) and PL pixel clock (27MHz)
# BRAM ports are dual-port, crossing is handled by the BRAM primitive.
set_false_path -from [get_clocks clk_fpga_0] -to [get_clocks -of_objects [get_pins u_pl/mmcm_inst/CLKOUT0]]
set_false_path -from [get_clocks -of_objects [get_pins u_pl/mmcm_inst/CLKOUT0]] -to [get_clocks clk_fpga_0]

# NES core clock (27MHz) and NTSC sample clock (42.954545MHz) are
# asynchronous; the only crossing is the dual-clock framebuffer BRAM
# inside ntsc_encoder plus the reset synchronizer.
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins u_pl/mmcm_inst/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins u_pl/pll_ntsc_inst/CLKOUT0]]
