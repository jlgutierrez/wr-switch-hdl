target = "xilinx"
action = "synthesis"

fetchto = "../../ip_cores"

syn_device = "xc6vlx240t"
syn_grade = "-1"
syn_package = "ff1156"
syn_top = "scb_top_synthesis"
syn_project = "test_scb.xise"

modules = { "local" : [ "../../top/scb_18ports" ] }
