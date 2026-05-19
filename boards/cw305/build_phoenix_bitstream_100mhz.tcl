# PHOENIX CW305 100 MHz timing experiment
# Usage (run from boards/cw305/):
#   vivado -mode batch -source build_phoenix_bitstream_100mhz.tcl
#
# This is intentionally separate from build_phoenix_bitstream.tcl so the
# 30 ns baseline reports/bitstream are not overwritten.

set TOP_MODULE cw305_phoenix_top
set PART [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "xc7a100tftg256-2"}]
set CLK_PERIOD_NS "10.000"

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

# Reuse board pin/I/O constraints with the two PHOENIX crypto clocks set to
# 10 ns. The XDC touches current_design properties, so read it after
# synth_design in this fresh non-project flow.
read_xdc constraints/cw305_phoenix_10ns.xdc

report_utilization -file reports/phoenix_100mhz_synth_util.rpt
report_utilization -hierarchical -file reports/phoenix_100mhz_synth_hier_util.rpt
report_timing_summary -file reports/phoenix_100mhz_synth_timing.rpt

opt_design
place_design -directive ExtraTimingOpt
route_design -directive NoTimingRelaxation

report_utilization -file reports/phoenix_100mhz_impl_util.rpt
report_utilization -hierarchical -file reports/phoenix_100mhz_impl_hier_util.rpt
report_timing_summary -file reports/phoenix_100mhz_timing.rpt

write_checkpoint -force output/phoenix_cw305_100mhz_post_impl.dcp

set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force output/phoenix_cw305_100mhz.bit

puts "============================================"
puts "PHOENIX CW305 100 MHz timing experiment"
puts "Part: $PART"
puts "Crypto clock constraint: ${CLK_PERIOD_NS} ns"
puts "Timing report: reports/phoenix_100mhz_timing.rpt"
puts "Bitstream: output/phoenix_cw305_100mhz.bit"
puts "============================================"
