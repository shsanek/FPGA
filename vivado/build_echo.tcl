# Build UART echo test: synth → impl → bitstream → program
# Usage: vivado -mode batch -source build_echo.tcl

set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"
set xdc_dir  "C:/Users/ssane/Documents/FPGA/vivado"

open_project ${proj_dir}/project_1.xpr

# =========================================
# Save original top and constraints, then swap
# =========================================
set orig_top [get_property top [current_fileset]]
puts "Original top: ${orig_top}"

# Add echo sources
foreach f [list \
    ${src_dir}/UART_ECHO_TOP.sv \
    ${src_dir}/SIMPLE_UART_RX.sv \
    ${src_dir}/I_O/I_O_TIMER_GENERATOR.sv \
    ${src_dir}/I_O/OUTPUT_CONTROLLER/I_O_OUTPUT_CONTROLLER.sv \
] {
    catch {add_files -norecurse -fileset [get_filesets sources_1] $f}
    catch {set_property file_type SystemVerilog [get_files $f]}
}

# Add echo XDC, disable main XDC
set echo_xdc ${xdc_dir}/uart_echo.xdc
catch {add_files -norecurse -fileset [get_filesets constrs_1] $echo_xdc}

# Disable original XDC, enable echo XDC
foreach xdc_file [get_files -of_objects [get_filesets constrs_1] *.xdc] {
    set fname [file tail $xdc_file]
    if {$fname eq "uart_echo.xdc"} {
        set_property IS_ENABLED TRUE [get_files $xdc_file]
    } else {
        set_property IS_ENABLED FALSE [get_files $xdc_file]
    }
}

# Set echo top
set_property top UART_ECHO_TOP [current_fileset]
update_compile_order -fileset sources_1

# =========================================
# Generate clk_wiz IP (needed)
# =========================================
puts "========================================="
puts "STEP 0: Generate clk_wiz IP"
puts "========================================="
foreach ip [get_ips clk_wiz_0] {
    generate_target all $ip
    catch { create_ip_run $ip }
}
set ip_runs [get_runs -filter {IS_SYNTHESIS && NAME =~ "*clk_wiz*"}]
foreach r $ip_runs {
    if {[get_property PROGRESS $r] ne "100%"} {
        reset_run $r
        launch_runs $r -jobs 4
        wait_on_run $r
    }
    puts "IP run $r: [get_property STATUS [get_runs $r]]"
}

# =========================================
# 1. SYNTHESIS
# =========================================
puts "========================================="
puts "STEP 1: Synthesis"
puts "========================================="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis: ${synth_status}"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    # Restore original before exit
    set_property top $orig_top [current_fileset]
    foreach xdc_file [get_files -of_objects [get_filesets constrs_1] *.xdc] {
        set fname [file tail $xdc_file]
        if {$fname eq "uart_echo.xdc"} {
            set_property IS_ENABLED FALSE [get_files $xdc_file]
        } else {
            set_property IS_ENABLED TRUE [get_files $xdc_file]
        }
    }
    exit 1
}

# =========================================
# 2. IMPLEMENTATION
# =========================================
puts "========================================="
puts "STEP 2: Implementation"
puts "========================================="
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation: ${impl_status}"

# =========================================
# 3. BITSTREAM
# =========================================
puts "========================================="
puts "STEP 3: Bitstream"
puts "========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit_status [get_property STATUS [get_runs impl_1]]
puts "Bitstream: ${bit_status}"

# =========================================
# 4. PROGRAM FPGA
# =========================================
puts "========================================="
puts "STEP 4: Program FPGA"
puts "========================================="
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
set bit_file [glob ${proj_dir}/project_1.runs/impl_1/UART_ECHO_TOP.bit]
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device

puts "FPGA programmed with UART echo!"

close_hw_target
disconnect_hw_server
close_hw_manager

# =========================================
# 5. RESTORE original project state
# =========================================
puts "========================================="
puts "Restoring original project..."
puts "========================================="
set_property top $orig_top [current_fileset]
foreach xdc_file [get_files -of_objects [get_filesets constrs_1] *.xdc] {
    set fname [file tail $xdc_file]
    if {$fname eq "uart_echo.xdc"} {
        set_property IS_ENABLED FALSE [get_files $xdc_file]
    } else {
        set_property IS_ENABLED TRUE [get_files $xdc_file]
    }
}
update_compile_order -fileset sources_1
puts "Original top restored to: ${orig_top}"

puts ""
puts "========================================="
puts "UART ECHO TEST COMPLETE"
puts "  Open a terminal at 115200 8N1"
puts "  Type characters — they should echo back"
puts "========================================="
