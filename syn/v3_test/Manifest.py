target = "xilinx"
action = "synthesis"

fetchto = "../../ip_cores"

syn_device = "xc6vlx130t"
syn_grade = "-1"
syn_package = "ff1156"
syn_top = "test_scb"
syn_project = "test_scb.xise"

modules = { "local" : [ "../../top/scb_test" ] }
