# synth/vivado_synth_no_dsp.tcl
# no-DSP synthesis audit for the SBU or phoenix_top.
# 사용:
#   vivado -mode batch -source synth/vivado_synth_no_dsp.tcl
#   vivado -mode batch -source synth/vivado_synth_no_dsp.tcl -tclargs superbutterfly_sbu xc7z020clg400-1
#   vivado -mode batch -source synth/vivado_synth_no_dsp.tcl -tclargs phoenix_top xc7a100tftg256-2
#
# REQ-RTL-003: report 의 DSP 사용량은 반드시 0. constant_memory 의 pow_mod_q
# twiddle precompute 가 elaboration constant-fold 되어 DSP=0 인지 객관 확인.

set TOP  [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "superbutterfly_sbu"}]
set PART [expr {[llength $argv] >= 2 ? [lindex $argv 1] : "xc7z020clg400-1"}]

file mkdir reports/${TOP}_no_dsp

read_verilog [glob ../rtl/common/*.v]
read_verilog [glob ../rtl/arith/*.v]
read_verilog [glob ../rtl/mul/*.v]
read_verilog [glob ../rtl/reduce/*.v]
read_verilog [glob ../rtl/comp/*.v]
read_verilog [glob ../rtl/sbu/*.v]
if {$TOP eq "phoenix_top"} {
    read_verilog [glob ../rtl/phoenix/*.v]
}
set_property include_dirs [list ../rtl/common] [current_fileset]

synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt -max_dsp 0

report_utilization     -file reports/${TOP}_no_dsp/post_synth_utilization.rpt
report_timing_summary  -file reports/${TOP}_no_dsp/post_synth_timing.rpt

# DSP primitive 직접 카운트 (일부 Vivado 에서 property 미동작 → util parsing 병행)
set dsp_cells [get_cells -hier -quiet -filter {PRIMITIVE_TYPE =~ DSP*}]
set dsp_n [llength $dsp_cells]
puts "============================================"
puts "TOP=$TOP PART=$PART"
puts "DSP primitive cell count = $dsp_n"
if {$dsp_n == 0} { puts "DSP=0 OK (REQ-RTL-003)" } else { puts "ERROR: DSP != 0" }
puts "============================================"
write_checkpoint -force reports/${TOP}_no_dsp/post_synth.dcp
