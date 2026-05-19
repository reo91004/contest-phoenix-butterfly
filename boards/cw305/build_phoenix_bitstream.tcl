# PHOENIX CW305 bitstream build
# Usage (run from boards/cw305/):
#   vivado -mode batch -source build_phoenix_bitstream.tcl
#   vivado -mode batch -source build_phoenix_bitstream.tcl -tclargs xc7a100tftg256-2
#
# Paths are relative to boards/cw305/ (repo root = ../..). CW305 USB/clock/reg
# glue is flattened into this directory. PHOENIX RTL uses
# rtl/{common,arith,mul,reduce,comp,sbu,phoenix}.
# Top cw305_phoenix_top → phoenix_cw305_wrapper → phoenix_top.

set TOP_MODULE cw305_phoenix_top
set PART [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "xc7a100tftg256-2"}]
set CLK_PERIOD_NS "30.000"

file mkdir reports
file mkdir output

set_property include_dirs {../.. ../../rtl/common .} [current_fileset]

# CW305 USB/register/clock infrastructure (flattened into boards/cw305/)
read_verilog cw305_aes_defines.v
read_verilog clog2.v
read_verilog cdc_pulse.v
read_verilog clocks.v
read_verilog cw305_usb_reg_fe.v
read_verilog cw305_reg_aes.v

# PHOENIX RTL
foreach f [lsort [glob ../../rtl/common/*.v]]  { read_verilog $f }
foreach f [lsort [glob ../../rtl/arith/*.v]]   { read_verilog $f }
foreach f [lsort [glob ../../rtl/mul/*.v]]     { read_verilog $f }
foreach f [lsort [glob ../../rtl/reduce/*.v]]  { read_verilog $f }
foreach f [lsort [glob ../../rtl/comp/*.v]]    { read_verilog $f }
foreach f [lsort [glob ../../rtl/sbu/*.v]]     { read_verilog $f }
foreach f [lsort [glob ../../rtl/phoenix/*.v]] { read_verilog $f }

# CW305 PHOENIX wrapper/top
read_verilog phoenix_cw305_wrapper.v
read_verilog cw305_phoenix_top.v

read_xdc constraints/cw305_phoenix_30ns.xdc

synth_design -top $TOP_MODULE -part $PART -max_dsp 0
report_utilization -file reports/phoenix_synth_util.rpt
report_utilization -hierarchical -file reports/phoenix_synth_hier_util.rpt
report_timing_summary -file reports/phoenix_synth_timing.rpt

opt_design
place_design -directive ExtraTimingOpt
route_design -directive NoTimingRelaxation

report_utilization -file reports/phoenix_impl_util.rpt
report_utilization -hierarchical -file reports/phoenix_impl_hier_util.rpt
report_timing_summary -file reports/phoenix_timing.rpt

write_checkpoint -force output/phoenix_cw305_post_impl.dcp

set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force output/phoenix_cw305.bit

puts "============================================"
puts "PHOENIX CW305 bitstream"
puts "Part: $PART"
puts "Crypto clock constraint: ${CLK_PERIOD_NS} ns"
puts "Bitstream: output/phoenix_cw305.bit"
puts "============================================"
