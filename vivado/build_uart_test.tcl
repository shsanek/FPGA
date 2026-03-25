set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"

open_project ${proj_dir}/project_1.xpr

foreach f [list \
    ${src_dir}/SIMPLE_UART_RX.sv \
    ${src_dir}/UART_FIFO.sv \
    ${src_dir}/CPU/CPU_PIPELINE_ADAPTER.sv \
] {
    catch {add_files -norecurse -fileset [get_filesets sources_1] $f}
    catch {set_property file_type SystemVerilog [get_files $f]}
}

set_property top FPGA_TOP [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "Synthesis: [get_property STATUS [get_runs synth_1]]"

launch_runs impl_1 -jobs 4
wait_on_run impl_1
puts "Implementation: [get_property STATUS [get_runs impl_1]]"

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "Bitstream: [get_property STATUS [get_runs impl_1]]"
puts "DONE"
