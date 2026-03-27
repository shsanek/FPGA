set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set bit_file [glob ${proj_dir}/project_1.runs/impl_1/FPGA_TOP.bit]
set stage1   "C:/Users/ssane/Documents/FPGA/riscv/boot/tools/stage1_with_header.bin"
set mcs_file "${proj_dir}/boot.mcs"

write_cfgmem -format mcs -interface SPIx1 -size 16 \
    -loadbit "up 0x0 ${bit_file}" \
    -loaddata "up 0xF00000 ${stage1}" \
    -file $mcs_file -force

puts ""
puts "========================================="
puts "MCS GENERATED (bitstream + stage1)"
puts "  Bitstream: ${bit_file}"
puts "  Stage 1:   ${stage1}"
puts "  Output:    ${mcs_file}"
puts "========================================="
