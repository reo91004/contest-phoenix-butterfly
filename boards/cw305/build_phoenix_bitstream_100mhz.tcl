# PHOENIX CW305 100 MHz timing experiment
# Usage (run from boards/cw305/):
#   vivado -mode batch -source build_phoenix_bitstream_100mhz.tcl
#   vivado -mode batch -source build_phoenix_bitstream_100mhz.tcl -tclargs xc7a100tftg256-2 8.000
#
# This is intentionally separate from build_phoenix_bitstream.tcl so the
# 30 ns baseline reports/bitstream are not overwritten.

set TOP_MODULE cw305_phoenix_top
set PART [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "xc7a100tftg256-2"}]
set CLK_PERIOD_NS [expr {[llength $argv] >= 2 ? [lindex $argv 1] : "10.000"}]
set CLK_HALF_NS [format "%.3f" [expr {$CLK_PERIOD_NS / 2.0}]]
set REPORT_TAG [string map {. p} $CLK_PERIOD_NS]

file mkdir reports
file mkdir output

set_property include_dirs {../.. ../../rtl/common .} [current_fileset]

read_verilog cw305_aes_defines.v
read_verilog clog2.v
read_verilog cdc_pulse.v
read_verilog clocks.v
read_verilog cw305_usb_reg_fe.v
read_verilog cw305_reg_aes.v

foreach f [lsort [glob ../../rtl/common/*.v]]  { read_verilog $f }
foreach f [lsort [glob ../../rtl/arith/*.v]]   { read_verilog $f }
foreach f [lsort [glob ../../rtl/mul/*.v]]     { read_verilog $f }
foreach f [lsort [glob ../../rtl/reduce/*.v]]  { read_verilog $f }
foreach f [lsort [glob ../../rtl/comp/*.v]]    { read_verilog $f }
foreach f [lsort [glob ../../rtl/sbu/*.v]]     { read_verilog $f }
foreach f [lsort [glob ../../rtl/phoenix/*.v]] { read_verilog $f }

read_verilog phoenix_cw305_wrapper.v
read_verilog cw305_phoenix_top.v

synth_design -top $TOP_MODULE -part $PART -max_dsp 0

# Reuse board pin/I/O constraints and rewrite the two PHOENIX crypto clocks
# when a non-10 ns experiment is requested. The XDC touches current_design
# properties, so read it after synth_design in this fresh non-project flow.
set active_xdc "constraints/cw305_phoenix_10ns.xdc"
if {$CLK_PERIOD_NS ne "10.000"} {
    set fh [open constraints/cw305_phoenix_10ns.xdc r]
    set xdc_text [read $fh]
    close $fh
    set tio_line "create_clock -period ${CLK_PERIOD_NS} -name tio_clkin -waveform {0.000 ${CLK_HALF_NS}} \[get_nets tio_clkin\]"
    set pll_line "create_clock -period ${CLK_PERIOD_NS} -name pll_clk1 -waveform {0.000 ${CLK_HALF_NS}} \[get_nets pll_clk1\]"
    regsub {create_clock -period 10\.000 -name tio_clkin -waveform \{0\.000 5\.000\} \[get_nets tio_clkin\]} $xdc_text $tio_line xdc_text
    regsub {create_clock -period 10\.000 -name pll_clk1 -waveform \{0\.000 5\.000\} \[get_nets pll_clk1\]} $xdc_text $pll_line xdc_text
    set active_xdc "reports/cw305_phoenix_${REPORT_TAG}ns.xdc"
    set fh [open $active_xdc w]
    puts $fh $xdc_text
    close $fh
}
read_xdc $active_xdc

report_utilization -file reports/phoenix_${REPORT_TAG}ns_synth_util.rpt
report_utilization -hierarchical -file reports/phoenix_${REPORT_TAG}ns_synth_hier_util.rpt
report_timing_summary -file reports/phoenix_${REPORT_TAG}ns_synth_timing.rpt

opt_design
place_design -directive ExtraTimingOpt
route_design -directive NoTimingRelaxation

report_utilization -file reports/phoenix_${REPORT_TAG}ns_impl_util.rpt
report_utilization -hierarchical -file reports/phoenix_${REPORT_TAG}ns_impl_hier_util.rpt
report_timing_summary -file reports/phoenix_${REPORT_TAG}ns_timing.rpt

write_checkpoint -force output/phoenix_cw305_${REPORT_TAG}ns_post_impl.dcp

set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force output/phoenix_cw305_${REPORT_TAG}ns.bit

puts "============================================"
puts "PHOENIX CW305 timing experiment"
puts "Part: $PART"
puts "Crypto clock constraint: ${CLK_PERIOD_NS} ns"
puts "Timing report: reports/phoenix_${REPORT_TAG}ns_timing.rpt"
puts "Bitstream: output/phoenix_cw305_${REPORT_TAG}ns.bit"
puts "============================================"
