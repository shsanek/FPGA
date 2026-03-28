# Vivado TCL full build: generate IP → synthesis → implementation → bitstream
# Usage: vivado -mode batch -source build_full.tcl

set proj_dir "C:/Users/ssane/Documents/FPGA/vivado/project_1"
set src_dir  "C:/Users/ssane/Documents/FPGA/riscv"

open_project ${proj_dir}/project_1.xpr

# Add peripheral source files (catch if already added)
foreach f {rtl/peripheral/SPI_MASTER.sv rtl/peripheral/OLED_IO_DEVICE.sv rtl/peripheral/SD_IO_DEVICE.sv rtl/peripheral/FLASH_LOADER.sv rtl/core/MULDIV_UNIT.sv rtl/peripheral/TIMER_DEVICE.sv rtl/memory/STREAM_CACHE.sv rtl/memory/SCRATCHPAD.sv} {
    set fpath "${src_dir}/${f}"
    catch {add_files -norecurse -fileset [get_filesets sources_1] $fpath}
    catch {set_property file_type SystemVerilog [get_files $fpath]}
}

# Ensure FPGA_TOP is added and set as top
catch {add_files -norecurse -fileset [get_filesets sources_1] ${src_dir}/rtl/FPGA_TOP.sv}
catch {set_property file_type SystemVerilog [get_files ${src_dir}/rtl/FPGA_TOP.sv]}
set_property top FPGA_TOP [current_fileset]
update_compile_order -fileset sources_1

# =========================================
# 0. GENERATE IP OUTPUT PRODUCTS
# =========================================
puts "========================================="
puts "STEP 0: Generate IP output products"
puts "========================================="
foreach ip [get_ips] {
    generate_target all $ip
    catch { create_ip_run $ip }
}
set ip_runs [get_runs -filter {IS_SYNTHESIS && SRCSET != sources_1}]
foreach r $ip_runs {
    reset_run $r
}
if {[llength $ip_runs] > 0} {
    launch_runs $ip_runs -jobs 4
    foreach r $ip_runs {
        wait_on_run $r
        puts "IP run $r: [get_property STATUS [get_runs $r]]"
    }
}
puts "IP generation done"

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
    puts "ERROR: Synthesis failed. Aborting."
    exit 1
}

# Reports after synthesis
open_run synth_1
report_utilization -file ${proj_dir}/synth_utilization.txt
report_timing_summary -file ${proj_dir}/synth_timing.txt
puts "Synthesis reports saved"

# =========================================
# 2. IMPLEMENTATION (place + route)
# =========================================
puts "========================================="
puts "STEP 2: Implementation"
puts "========================================="
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation: ${impl_status}"

if {[string match "*Complete*" $impl_status] == 0} {
    puts "ERROR: Implementation failed. Aborting."
    exit 1
}

# Reports after implementation
open_run impl_1
report_utilization -file ${proj_dir}/impl_utilization.txt
report_timing_summary -file ${proj_dir}/impl_timing.txt
report_power -file ${proj_dir}/impl_power.txt
puts "Implementation reports saved"

# =========================================
# 3. BITSTREAM
# =========================================
puts "========================================="
puts "STEP 3: Bitstream generation"
puts "========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit_status [get_property STATUS [get_runs impl_1]]
puts "Bitstream: ${bit_status}"

set bit_file [glob -nocomplain ${proj_dir}/project_1.runs/impl_1/*.bit]
if {$bit_file ne ""} {
    puts "Bitstream file: ${bit_file}"
} else {
    puts "WARNING: Bitstream file not found"
}

# =========================================
# 4. BUILD STAGE 1 BOOTLOADER
# =========================================
puts "========================================="
puts "STEP 4: Build Stage 1 bootloader"
puts "========================================="
set boot_dir "C:/Users/ssane/Documents/FPGA/riscv/boot/tools"
set stage1_hdr "${boot_dir}/stage1_with_header.bin"

if {[catch {exec bash -c "cd '${boot_dir}' && make clean && make stage1_hdr"} result]} {
    puts "Stage 1 build output: ${result}"
    # Check if output file was created despite make returning non-zero
    if {![file exists $stage1_hdr]} {
        puts "WARNING: Stage 1 build failed. MCS will contain bitstream only."
        set stage1_ok 0
    } else {
        set stage1_ok 1
    }
} else {
    puts "Stage 1 build output: ${result}"
    set stage1_ok 1
}

# =========================================
# 5. GENERATE MCS (bitstream + Stage 1)
# =========================================
puts "========================================="
puts "STEP 5: Generate MCS file"
puts "========================================="
set mcs_file "${proj_dir}/boot.mcs"

if {$bit_file ne ""} {
    if {$stage1_ok && [file exists $stage1_hdr]} {
        write_cfgmem -format mcs -interface SPIx1 -size 16 \
            -loadbit "up 0x0 ${bit_file}" \
            -loaddata "up 0xF00000 ${stage1_hdr}" \
            -file $mcs_file -force
        puts "MCS file (bitstream + stage1): ${mcs_file}"
    } else {
        write_cfgmem -format mcs -interface SPIx1 -size 16 \
            -loadbit "up 0x0 ${bit_file}" \
            -file $mcs_file -force
        puts "MCS file (bitstream only, no stage1): ${mcs_file}"
    }
} else {
    puts "WARNING: No bitstream — skipping MCS generation"
}

puts ""
puts "========================================="
puts "BUILD COMPLETE"
puts "  Synthesis:      ${synth_status}"
puts "  Implementation: ${impl_status}"
puts "  Bitstream:      ${bit_status}"
if {$bit_file ne ""} {
    puts "  MCS file:       ${mcs_file}"
}
puts "========================================="
