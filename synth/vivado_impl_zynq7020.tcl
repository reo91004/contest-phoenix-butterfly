# synth/vivado_impl_zynq7020.tcl
# 핸드오버 §4 — 논문 비교용 Zynq-7020 (xc7z020clg400-1) no-DSP impl + timing.
# 논문 §5: Vivado 2019.1 / Zynq-7020 / critical path 8 ns (125 MHz) target.
# 사용:
#   vivado -mode batch -source synth/vivado_impl_zynq7020.tcl
#   vivado -mode batch -source synth/vivado_impl_zynq7020.tcl -tclargs superbutterfly_sbu 8.000
#   vivado -mode batch -source synth/vivado_impl_zynq7020.tcl -tclargs phoenix_top 30.000
#   vivado -mode batch -source synth/vivado_impl_zynq7020.tcl -tclargs superbutterfly_sbu 8.000 xc7a100tftg256-2

set TOP    [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "superbutterfly_sbu"}]
set PERIOD [expr {[llength $argv] >= 2 ? [lindex $argv 1] : "8.000"}]
set PART   [expr {[llength $argv] >= 3 ? [lindex $argv 2] : "xc7z020clg400-1"}]
file mkdir reports/${TOP}_zynq7020

read_verilog [glob ../rtl/common/*.v]
read_verilog [glob ../rtl/arith/*.v]
read_verilog [glob ../rtl/mul/*.v]
read_verilog [glob ../rtl/reduce/*.v]
read_verilog [glob ../rtl/comp/*.v]
read_verilog [glob ../rtl/sbu/*.v]
if {$TOP eq "phoenix_top"} { read_verilog [glob ../rtl/phoenix/*.v] }
set_property include_dirs [list ../rtl/common] [current_fileset]

synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt -max_dsp 0

set xdc reports/${TOP}_zynq7020/clk.xdc
set fh [open $xdc w]
puts $fh "create_clock -name clk -period $PERIOD \[get_ports {clk_i clk}\]"
close $fh
read_xdc $xdc

report_utilization    -file reports/${TOP}_zynq7020/post_synth_utilization.rpt
opt_design
place_design
route_design
report_utilization    -file reports/${TOP}_zynq7020/post_impl_utilization.rpt
report_timing_summary -file reports/${TOP}_zynq7020/post_impl_timing.rpt
write_checkpoint -force reports/${TOP}_zynq7020/post_impl.dcp

set dsp_n [llength [get_cells -hier -quiet -filter {PRIMITIVE_TYPE =~ DSP*}]]
puts "TOP=$TOP PART=$PART PERIOD=${PERIOD}ns  DSP=$dsp_n"
