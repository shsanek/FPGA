# Vivado TCL build script for FPGA_TOP
# Usage: vivado -mode batch -source build.tcl

set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"

# Open project
open_project ${proj_dir}/project_1.xpr

# Add FPGA_TOP (may already exist, catch error)
catch {add_files -norecurse -fileset [get_filesets sources_1] ${src_dir}/FPGA_TOP.sv}
catch {set_property file_type SystemVerilog [get_files ${src_dir}/FPGA_TOP.sv]}

# Set FPGA_TOP as top module
set_property top FPGA_TOP [current_fileset]
update_compile_order -fileset sources_1

# Run synthesis
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Report results
set synth_status [get_property STATUS [get_runs synth_1]]
puts "========================================="
puts "Synthesis status: ${synth_status}"
puts "========================================="

# If synthesis succeeded, show utilization
if {$synth_status eq "synth_design Complete!"} {
    open_run synth_1
    report_utilization -file ${proj_dir}/utilization_report.txt
    report_timing_summary -file ${proj_dir}/timing_report.txt
    puts "Reports saved to project directory"
}
