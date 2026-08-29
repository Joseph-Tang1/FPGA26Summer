set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set report_dir [file join $project_dir reports]
file mkdir $report_dir

open_project [file join $project_dir ticket_price.xpr]
set_property top tb_ticket_price_top [get_filesets sim_1]
launch_simulation
run all
close_sim

set simulation_log [file join $project_dir ticket_price.sim sim_1 behav xsim simulate.log]
if {[file exists $simulation_log]} {
    file copy -force $simulation_log [file join $report_dir simulation.log]
}

close_project
exit
