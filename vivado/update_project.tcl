# Update Vivado project: add all sources, set top, configure
set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"

open_project ${proj_dir}/project_1.xpr

# Remove old source files that no longer exist at old paths
foreach f [get_files -of_objects [get_filesets sources_1] *.sv] {
    if {![file exists $f]} {
        puts "Removing stale file: $f"
        remove_files -fileset [get_filesets sources_1] $f
    }
}

# Add all synthesizable SV files (new rtl/ structure)
set sv_files [list \
    ${src_dir}/rtl/BASE_TYPE.sv \
    ${src_dir}/rtl/FPGA_TOP.sv \
    ${src_dir}/rtl/TOP.sv \
    ${src_dir}/rtl/core/REGISTER_32_BLOCK_32.sv \
    ${src_dir}/rtl/core/OP_0110011.sv \
    ${src_dir}/rtl/core/OP_0010011.sv \
    ${src_dir}/rtl/core/BRANCH_UNIT.sv \
    ${src_dir}/rtl/core/IMMEDIATE_GENERATOR.sv \
    ${src_dir}/rtl/core/LOAD_UNIT.sv \
    ${src_dir}/rtl/core/STORE_UNIT.sv \
    ${src_dir}/rtl/core/CPU_ALU.sv \
    ${src_dir}/rtl/core/CPU_DATA_ADAPTER.sv \
    ${src_dir}/rtl/core/CPU_SINGLE_CYCLE.sv \
    ${src_dir}/rtl/core/CPU_PIPELINE_ADAPTER.sv \
    ${src_dir}/rtl/memory/CHUNK_STORAGE.sv \
    ${src_dir}/rtl/memory/CHUNK_STORAGE_4_POOL.sv \
    ${src_dir}/rtl/memory/RAM_CONTROLLER.sv \
    ${src_dir}/rtl/memory/MEMORY_CONTROLLER.sv \
    ${src_dir}/rtl/peripheral/PERIPHERAL_BUS.sv \
    ${src_dir}/rtl/peripheral/UART_IO_DEVICE.sv \
    ${src_dir}/rtl/peripheral/SPI_MASTER.sv \
    ${src_dir}/rtl/peripheral/OLED_IO_DEVICE.sv \
    ${src_dir}/rtl/peripheral/SD_IO_DEVICE.sv \
    ${src_dir}/rtl/peripheral/FLASH_LOADER.sv \
    ${src_dir}/rtl/uart/I_O_TIMER_GENERATOR.sv \
    ${src_dir}/rtl/uart/I_O_INPUT_CONTROLLER.sv \
    ${src_dir}/rtl/uart/I_O_OUTPUT_CONTROLLER.sv \
    ${src_dir}/rtl/uart/VALUE_STORAGE.sv \
    ${src_dir}/rtl/uart/SIMPLE_UART_RX.sv \
    ${src_dir}/rtl/uart/UART_FIFO.sv \
    ${src_dir}/rtl/debug/DEBUG_CONTROLLER.sv \
]

foreach f $sv_files {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -norecurse -fileset [get_filesets sources_1] $f
    }
    set_property file_type SystemVerilog [get_files $f]
}

# Add constraints
set xdc_file "C:/Users/ssane/Documents/FPGA/vivado/Arty-A7-100-Master.xdc"
if {[llength [get_files -quiet $xdc_file]] == 0} {
    add_files -fileset [get_filesets constrs_1] $xdc_file
}

# Set top module
set_property top FPGA_TOP [current_fileset]
update_compile_order -fileset sources_1

# Save
close_project
open_project ${proj_dir}/project_1.xpr
close_project

puts "========================================="
puts "Project updated successfully"
puts "Top module: FPGA_TOP"
puts "========================================="
