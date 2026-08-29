set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set report_dir [file join $project_dir reports]
set output_dir [file join $project_dir output]
file mkdir $report_dir
file mkdir $output_dir

open_project [file join $project_dir ticket_price.xpr]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}

set generated_bitstream [file join $project_dir ticket_price.runs impl_1 ticket_price_top.bit]
file copy -force $generated_bitstream [file join $output_dir ticket_price_top.bit]

open_run impl_1
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization    -file [file join $report_dir utilization.rpt]
report_drc            -file [file join $report_dir drc.rpt]
report_methodology    -file [file join $report_dir methodology.rpt]
close_project
exit
