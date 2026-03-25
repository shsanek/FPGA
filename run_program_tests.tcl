set src_dir "C:/Users/ssane/Documents/FPGA/riscv"
set tests_dir "$src_dir/tests/programs"

set programs [glob -type d "$tests_dir/*"]

set pass 0
set fail 0

foreach prog_dir $programs {
    set name [file tail $prog_dir]
    set hex "$prog_dir/program.hex"
    set expected "$prog_dir/expected.txt"
    set out_file "C:/Users/ssane/Documents/FPGA/${name}_out.txt"
    
    if {![file exists $hex]} { continue }
    
    puts -nonewline "--- $name --- "
    
    # Run xsim via Vivado's internal TCL
    set cmd "xsim prog_sim -R -testplusarg HEX_FILE=$hex -testplusarg OUT_FILE=$out_file -testplusarg TIMEOUT=500000"
    if {[catch {eval exec $cmd} result]} {
        if {[string match "*PROGRAM_TEST OK*" $result]} {
            # Check output
            if {[file exists $expected]} {
                set f1 [open $out_file r]; set got [read $f1]; close $f1
                set f2 [open $expected r]; set exp [read $f2]; close $f2
                if {$got ne $exp} {
                    puts "OUTPUT MISMATCH"
                    incr fail
                } else {
                    puts "PASSED"
                    incr pass
                }
            } else {
                puts "PASSED (no expected.txt)"
                incr pass
            }
        } elseif {[string match "*TIMEOUT*" $result]} {
            puts "TIMEOUT"
            incr fail
        } else {
            puts "ERROR"
            incr fail
        }
    } else {
        if {[string match "*PROGRAM_TEST OK*" $result]} {
            puts "PASSED"
            incr pass
        } else {
            puts "COMPLETED"
            incr pass
        }
    }
}

puts ""
puts "========================================="
puts "Program tests: $pass passed, $fail failed"
puts "========================================="
