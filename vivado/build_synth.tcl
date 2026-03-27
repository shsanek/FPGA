# Vivado TCL: add new files + synthesis only (no impl/bitstream)
# Usage: vivado -mode batch -source build_synth.tcl

set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"

open_project ${proj_dir}/project_1.xpr

# Add peripheral/new source files (catch if already added)
foreach f {rtl/peripheral/SPI_MASTER.sv rtl/peripheral/OLED_IO_DEVICE.sv rtl/peripheral/SD_IO_DEVICE.sv rtl/peripheral/FLASH_LOADER.sv rtl/core/MULDIV_UNIT.sv rtl/peripheral/TIMER_DEVICE.sv} {
    set fpath "${src_dir}/${f}"
    catch {add_files -norecurse -fileset [get_filesets sources_1] $fpath}
    catch {set_property file_type SystemVerilog [get_files $fpath]}
    puts "Added: $f"
}

# Ensure FPGA_TOP is top
catch {add_files -norecurse -fileset [get_filesets sources_1] ${src_dir}/rtl/FPGA_TOP.sv}
set_property top FPGA_TOP [current_fileset]
update_compile_order -fileset sources_1

# =========================================
# SYNTHESIS
# =========================================
puts "========================================="
puts "Running synthesis..."
puts "========================================="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis: ${synth_status}"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed."
    exit 1
}

open_run synth_1
report_utilization -file ${proj_dir}/synth_utilization.txt
report_timing_summary -file ${proj_dir}/synth_timing.txt
puts "Reports saved."

puts ""
puts "========================================="
puts "SYNTHESIS COMPLETE: ${synth_status}"
puts "========================================="
