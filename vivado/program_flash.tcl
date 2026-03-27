# Program QSPI flash with boot.mcs (indirect programming)
# Usage: vivado -mode batch -source program_flash.tcl

set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set mcs_file "${proj_dir}/boot.mcs"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

# Create flash memory device (Spansion S25FL128S on Arty A7)
create_hw_cfgmem -hw_device $device \
    -mem_dev [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]

set cfgmem [get_property PROGRAM.HW_CFGMEM $device]

set_property PROGRAM.FILES          [list $mcs_file] $cfgmem
set_property PROGRAM.ADDRESS_RANGE  {use_file} $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BLANK_CHECK    0 $cfgmem
set_property PROGRAM.ERASE          1 $cfgmem
set_property PROGRAM.CFG_PROGRAM    1 $cfgmem
set_property PROGRAM.VERIFY         1 $cfgmem
set_property PROGRAM.CHECKSUM       0 $cfgmem

# Step 1: Create and load indirect programming bitstream (with SPI core)
create_hw_bitstream -hw_device $device [get_property PROGRAM.HW_CFGMEM_BITFILE $device]
program_hw_devices $device
refresh_hw_device $device

# Step 2: Program flash through SPI core
program_hw_cfgmem -hw_cfgmem $cfgmem

puts ""
puts "========================================="
puts "FLASH PROGRAMMED SUCCESSFULLY"
puts "  Ensure JP1 is set, then press PROG or power-cycle"
puts "========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
