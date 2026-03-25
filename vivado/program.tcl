# Program FPGA with bitstream
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
set bit_file [glob C:/Users/ssane/Documents/FPGA/vivado/project_1/project_1.runs/impl_1/*.bit]
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device

puts "========================================="
puts "FPGA programmed successfully!"
puts "========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
