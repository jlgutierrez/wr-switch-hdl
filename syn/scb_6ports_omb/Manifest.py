target = "xilinx"
action = "synthesis"

fetchto = "../../ip_cores"

syn_device = "xc6vlx130t"
syn_grade = "-1"
syn_package = "ff1156"
syn_top = "scb_top_synthesis"
syn_project = "scb_6ports_omb.xise"

modules = { "local" : [ "../../top/scb_6ports_omb" ] }
