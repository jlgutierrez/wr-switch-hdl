target = "xilinx" #  "altera" # 
action = "simulation"

fetchto = "../../../ip_cores"

files = [
  "main.sv"
  ]

vlog_opt="+incdir+../../ip_cores/wr-cores/sim +incdir+../../ip_cores/wr-cores/sim/fabric_emu"

modules = {"local":
		[ 
		  "../../../"
		],
	  }
