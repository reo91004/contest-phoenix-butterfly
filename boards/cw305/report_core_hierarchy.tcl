# Project-run report hook for slide-friendly PHOENIX utilization.
#
# This hook is attached to the CW305 Vivado project implementation run. After
# route_design finishes, it writes hierarchical utilization/timing reports in
# boards/cw305/reports/. For PPT resource numbers, use the row:
#   u_phoenix/u_core  phoenix_top

set script_dir [file dirname [file normalize [info script]]]
set report_dir [file join $script_dir reports]
file mkdir $report_dir

set core_cell [get_cells -hier -quiet u_phoenix/u_core]
if {[llength $core_cell] == 0} {
    puts "WARNING: PHOENIX core instance u_phoenix/u_core was not found."
} else {
    puts "PHOENIX PPT utilization instance: u_phoenix/u_core (phoenix_top)"
}

report_utilization -hierarchical \
    -file [file join $report_dir phoenix_project_impl_hier_util.rpt]

report_timing_summary \
    -file [file join $report_dir phoenix_project_timing.rpt]

puts "PHOENIX project reports written to $report_dir"
