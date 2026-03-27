set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set boot_dir "C:/Users/ssane/Documents/FPGA/riscv/boot/tools"

set bit_file [glob ${proj_dir}/project_1.runs/impl_1/*.bit]
set stage1_hdr "${boot_dir}/stage1_with_header.bin"
set mcs_file "${proj_dir}/boot.mcs"

puts "Bitstream: ${bit_file}"
puts "Stage1:    ${stage1_hdr}"

write_cfgmem -format mcs -interface SPIx1 -size 16 \
    -loadbit "up 0x0 ${bit_file}" \
    -loaddata "up 0xF00000 ${stage1_hdr}" \
    -file $mcs_file -force

puts "MCS generated: ${mcs_file}"

# Program FPGA + flash
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Program bitstream
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
puts "FPGA programmed with bitstream"

# Program flash
set flash [lindex [get_hw_cfgmems] 0]
if {$flash eq ""} {
    create_hw_cfgmem -hw_device $device -mem_dev [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]
    set flash [lindex [get_hw_cfgmems] 0]
}
set_property PROGRAM.FILES $mcs_file $flash
set_property PROGRAM.ADDRESS_RANGE {use_file} $flash
set_property PROGRAM.BLANK_CHECK 0 $flash
set_property PROGRAM.ERASE 1 $flash
set_property PROGRAM.CFG_PROGRAM 1 $flash
set_property PROGRAM.VERIFY 1 $flash
program_hw_cfgmem $flash

puts "========================================="
puts "Flash programmed and verified!"
puts "========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
