# Update Vivado project: add all sources, set top, configure
set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"

open_project ${proj_dir}/project_1.xpr

# Add all synthesizable SV files
set sv_files [list \
    ${src_dir}/BASE_TYPE.sv \
    ${src_dir}/FPGA_TOP.sv \
    ${src_dir}/TOP.sv \
    ${src_dir}/Register/REGISTER_32_BLOCK_32.sv \
    ${src_dir}/ALU/OP_0110011/OP_0110011.sv \
    ${src_dir}/ALU/OP_0010011/OP_0010011.sv \
    ${src_dir}/BRANCH_UNIT/BRANCH_UNIT.sv \
    ${src_dir}/IMMEDIATE_GENERATOR/IMMEDIATE_GENERATOR.sv \
    ${src_dir}/LOAD_UNIT/LOAD_UNIT.sv \
    ${src_dir}/STORE_UNIT/STORE_UNIT.sv \
    ${src_dir}/I_O/I_O_TIMER_GENERATOR.sv \
    ${src_dir}/I_O/INPUT_CONTROLLER/I_O_INPUT_CONTROLLER.sv \
    ${src_dir}/I_O/OUTPUT_CONTROLLER/I_O_OUTPUT_CONTROLLER.sv \
    ${src_dir}/I_O/VALUE_STORAGE/VALUE_STORAGE.sv \
    ${src_dir}/MEMORY/CHUNK_STORAGE/CHUNK_STORAGE.sv \
    ${src_dir}/MEMORY/CHUNK_STORAGE_4_POOL/CHUNK_STORAGE_4_POOL.sv \
    ${src_dir}/MEMORY/RAM_CONTROLLER/RAM_CONTROLLER.sv \
    ${src_dir}/MEMORY/MEMORY_CONTROLLER.sv \
    ${src_dir}/CPU/CPU_ALU.sv \
    ${src_dir}/CPU/CPU_DATA_ADAPTER.sv \
    ${src_dir}/CPU/CPU_SINGLE_CYCLE.sv \
    ${src_dir}/CPU/PERIPHERAL_BUS.sv \
    ${src_dir}/CPU/UART_IO_DEVICE.sv \
    ${src_dir}/CPU/DEBUG_CONTROLLER.sv \
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
