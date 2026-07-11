################################################################
# create_bd.tcl
# Vivado Block Design for EBAZ4205 NES
#
# Block Design contents:
#   - Zynq-7000 PS (processing_system7)
#       - SDIO0: microSD card (MIO 40-45)
#       - UART0: debug console
#       - AXI Master: M_AXI_GP0 for BRAM access
#       - FCLK_CLK0: 100MHz (PS AXI clock)
#       - FCLK_CLK1: 50MHz (optional)
#   - AXI BRAM Controller 0: PRG ROM (32KB)
#   - AXI BRAM Controller 1: CHR ROM (8KB)
#   - AXI Interconnect (1 master, 2 slaves)
#   - Processor System Reset
#
# AXI Memory Map (PS M_AXI_GP0):
#   0x4000_0000 - 0x4000_7FFF : PRG ROM BRAM (32KB)
#   0x4000_8000 - 0x4000_9FFF : CHR ROM BRAM (8KB)
#   0x4001_0000               : NES control register (GPIO)
################################################################

# Create block design
create_bd_design "zynq_ps_bd"
current_bd_design [get_bd_designs zynq_ps_bd]

################################################################
# Zynq-7000 PS
################################################################
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]

# Apply EBAZ4205 board preset (manual configuration)
set_property -dict [list \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_APU_CLK_RATIO_ENABLE {6:2:1} \
    CONFIG.PCW_CPU_CPU_6X4X_MAX_RANGE {667} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125} \
    CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
    CONFIG.PCW_UIPARAM_DDR_ROW_ADDR_COUNT {14} \
    CONFIG.PCW_UIPARAM_DDR_BANK_ADDR_COUNT {3} \
    CONFIG.PCW_UIPARAM_DDR_CL {7} \
    CONFIG.PCW_UIPARAM_DDR_CWL {6} \
    CONFIG.PCW_UIPARAM_DDR_T_RCD {7} \
    CONFIG.PCW_UIPARAM_DDR_T_RP {7} \
    CONFIG.PCW_UIPARAM_DDR_T_RC {49.5} \
    CONFIG.PCW_UIPARAM_DDR_T_RAS_MIN {36.0} \
    CONFIG.PCW_UIPARAM_DDR_T_FAW {40.0} \
    CONFIG.PCW_UIPARAM_DDR_AL {0} \
    CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_ECC {Disabled} \
    CONFIG.PCW_UIPARAM_DDR_BL {8} \
] $ps7

# Enable SDIO0 for microSD (MIO 40-45)
set_property -dict [list \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_MIO_40_PULLUP {enabled} \
    CONFIG.PCW_MIO_41_PULLUP {enabled} \
    CONFIG.PCW_MIO_42_PULLUP {enabled} \
    CONFIG.PCW_MIO_43_PULLUP {enabled} \
    CONFIG.PCW_MIO_44_PULLUP {enabled} \
    CONFIG.PCW_MIO_45_PULLUP {enabled} \
] $ps7

# Enable UART0 for debug, routed via EMIO to PL pins (H16/H17 UART header
# on the adapter board). MIO 14/15 are not routed to any header on the
# EBAZ4205, so EMIO is the only way to reach the console.
set_property -dict [list \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {EMIO} \
] $ps7

# Enable USB0 (optional, for future controller support)
# set_property -dict [list CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1}] $ps7

# Enable AXI Master GP0 for BRAM access
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {1} \
] $ps7

# FCLK: 100MHz for PS AXI operations
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
] $ps7

# Enable GPIO for NES control (nes_rst_n, nes_ready)
set_property -dict [list \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {4} \
] $ps7

# Make the PS DDR and fixed IO (MIO, clock, resets) external so the
# generated wrapper exposes them (required for a bootable bitstream).
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} \
    $ps7

################################################################
# Processor System Reset
################################################################
set proc_rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]

################################################################
# AXI Interconnect (1 master, 2 slaves)
################################################################
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property -dict [list \
    CONFIG.NUM_MI {2} \
] $axi_ic

################################################################
# AXI BRAM Controller 0: PRG ROM (32KB)
################################################################
set bram_ctrl_prg [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_prg]
set_property -dict [list \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.SINGLE_PORT_BRAM {0} \
    CONFIG.ECC_TYPE {0} \
    CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.READ_LATENCY {1} \
] $bram_ctrl_prg

################################################################
# AXI BRAM Controller 1: CHR ROM (8KB)
################################################################
set bram_ctrl_chr [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_chr]
set_property -dict [list \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.SINGLE_PORT_BRAM {0} \
    CONFIG.ECC_TYPE {0} \
    CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.READ_LATENCY {1} \
] $bram_ctrl_chr

################################################################
# Create external ports for PL interface
################################################################

# PRG ROM BRAM Port B (to PL top)
create_bd_port -dir O -type clk bram_prg_clk
create_bd_port -dir O bram_prg_en
create_bd_port -dir O -from 3 -to 0 bram_prg_we
create_bd_port -dir O -from 14 -to 0 bram_prg_addr
create_bd_port -dir O -from 31 -to 0 bram_prg_din
create_bd_port -dir I -from 31 -to 0 bram_prg_dout

# CHR ROM BRAM Port B (to PL top)
create_bd_port -dir O -type clk bram_chr_clk
create_bd_port -dir O bram_chr_en
create_bd_port -dir O -from 3 -to 0 bram_chr_we
create_bd_port -dir O -from 12 -to 0 bram_chr_addr
create_bd_port -dir O -from 31 -to 0 bram_chr_din
create_bd_port -dir I -from 31 -to 0 bram_chr_dout

# NES control (GPIO EMIO)
create_bd_port -dir O nes_rst_n
create_bd_port -dir I nes_ready

# UART0 console (EMIO)
create_bd_port -dir O UART0_TX
create_bd_port -dir I UART0_RX

################################################################
# Connections
################################################################

# PS7 clock and reset
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] \
    [get_bd_pins $axi_ic/ACLK] \
    [get_bd_pins $ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins $bram_ctrl_prg/s_axi_aclk] \
    [get_bd_pins $bram_ctrl_chr/s_axi_aclk] \
    [get_bd_pins $proc_rst/slowest_sync_clk]

connect_bd_net [get_bd_pins $ps7/FCLK_RESET0_N] \
    [get_bd_pins $proc_rst/ext_reset_in]

connect_bd_net [get_bd_pins $proc_rst/peripheral_aresetn] \
    [get_bd_pins $axi_ic/ARESETN] \
    [get_bd_pins $axi_ic/S00_ARESETN] \
    [get_bd_pins $axi_ic/M00_ARESETN] \
    [get_bd_pins $axi_ic/M01_ARESETN] \
    [get_bd_pins $bram_ctrl_prg/s_axi_aresetn] \
    [get_bd_pins $bram_ctrl_chr/s_axi_aresetn]

# AXI interconnect clocks
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] \
    [get_bd_pins $axi_ic/S00_ACLK] \
    [get_bd_pins $axi_ic/M00_ACLK] \
    [get_bd_pins $axi_ic/M01_ACLK]

# PS7 M_AXI_GP0 -> AXI Interconnect
connect_bd_intf_net [get_bd_intf_pins $ps7/M_AXI_GP0] \
    [get_bd_intf_pins $axi_ic/S00_AXI]

# AXI Interconnect -> BRAM Controllers
connect_bd_intf_net [get_bd_intf_pins $axi_ic/M00_AXI] \
    [get_bd_intf_pins $bram_ctrl_prg/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_ic/M01_AXI] \
    [get_bd_intf_pins $bram_ctrl_chr/S_AXI]

# BRAM Controller PRG -> external ports (Port A signals to PL top)
connect_bd_net [get_bd_pins $bram_ctrl_prg/bram_clk_a]  [get_bd_ports bram_prg_clk]
connect_bd_net [get_bd_pins $bram_ctrl_prg/bram_en_a]   [get_bd_ports bram_prg_en]
connect_bd_net [get_bd_pins $bram_ctrl_prg/bram_we_a]   [get_bd_ports bram_prg_we]
connect_bd_net [get_bd_pins $bram_ctrl_prg/bram_addr_a] [get_bd_ports bram_prg_addr]
connect_bd_net [get_bd_pins $bram_ctrl_prg/bram_wrdata_a] [get_bd_ports bram_prg_din]
connect_bd_net [get_bd_ports bram_prg_dout] [get_bd_pins $bram_ctrl_prg/bram_rddata_a]

# BRAM Controller CHR -> external ports (Port A signals to PL top)
connect_bd_net [get_bd_pins $bram_ctrl_chr/bram_clk_a]  [get_bd_ports bram_chr_clk]
connect_bd_net [get_bd_pins $bram_ctrl_chr/bram_en_a]   [get_bd_ports bram_chr_en]
connect_bd_net [get_bd_pins $bram_ctrl_chr/bram_we_a]   [get_bd_ports bram_chr_we]
connect_bd_net [get_bd_pins $bram_ctrl_chr/bram_addr_a] [get_bd_ports bram_chr_addr]
connect_bd_net [get_bd_pins $bram_ctrl_chr/bram_wrdata_a] [get_bd_ports bram_chr_din]
connect_bd_net [get_bd_ports bram_chr_dout] [get_bd_pins $bram_ctrl_chr/bram_rddata_a]

# GPIO EMIO for NES control
# GPIO[0]: nes_rst_n (output from PS, active-low)
# GPIO[1]: nes_ready (input to PS)
# EMIO GPIO is 4-bit [3:0]; slice/concat to match the 1-bit external ports.
set slice_rst [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_nes_rst]
set_property -dict [list \
    CONFIG.DIN_WIDTH {4} \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
] $slice_rst
connect_bd_net [get_bd_pins $ps7/GPIO_O]        [get_bd_pins $slice_rst/Din]
connect_bd_net [get_bd_pins $slice_rst/Dout]    [get_bd_ports nes_rst_n]

set const_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_zero]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $const_zero

set concat_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_gpio_i]
set_property -dict [list CONFIG.NUM_PORTS {4}] $concat_gpio
connect_bd_net [get_bd_pins $const_zero/dout]   [get_bd_pins $concat_gpio/In0]
connect_bd_net [get_bd_ports nes_ready]         [get_bd_pins $concat_gpio/In1]
connect_bd_net [get_bd_pins $const_zero/dout]   [get_bd_pins $concat_gpio/In2]
connect_bd_net [get_bd_pins $const_zero/dout]   [get_bd_pins $concat_gpio/In3]
connect_bd_net [get_bd_pins $concat_gpio/dout]  [get_bd_pins $ps7/GPIO_I]

# UART0 EMIO -> external ports
connect_bd_net [get_bd_pins $ps7/UART0_TX] [get_bd_ports UART0_TX]
connect_bd_net [get_bd_ports UART0_RX]     [get_bd_pins $ps7/UART0_RX]

################################################################
# Address assignment
################################################################
assign_bd_address [get_bd_addr_segs $bram_ctrl_prg/S_AXI/Mem0]
set_property offset 0x40000000 [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_prg_Mem0}]
set_property range 32K [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_prg_Mem0}]

assign_bd_address [get_bd_addr_segs $bram_ctrl_chr/S_AXI/Mem0]
set_property offset 0x40008000 [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_chr_Mem0}]
set_property range 8K [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_bram_ctrl_chr_Mem0}]

################################################################
# Validate and save
################################################################
validate_bd_design
save_bd_design

# Generate wrapper (instantiated by rtl/system_top.v, which is the real top)
make_wrapper -files [get_files zynq_ps_bd.bd] -top
add_files -norecurse [glob $origin_dir/vivado/$project_name.srcs/sources_1/bd/zynq_ps_bd/hdl/zynq_ps_bd_wrapper.v]
set_property top system_top [get_filesets sources_1]

puts "Block Design created successfully."
puts ""
puts "AXI Memory Map:"
puts "  PRG ROM: 0x4000_0000 - 0x4000_7FFF (32KB)"
puts "  CHR ROM: 0x4000_8000 - 0x4000_9FFF (8KB)"
