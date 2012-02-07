target = "altera" # "xilinx" # 
action = "simulation"

#fetchto = "../../ip_cores"

files = [
  # simulation for 7 ports (hard-coded)
  "swc_core_wrapper_7ports.vhd",
  "xswc_core_wrapper_7ports.svh",
  "swc_core_7ports.sv",
  # simulation for generic number of ports (set in swc_param_defs.svh for DUT and simulation)
  "swc_core_wrapper_generic.svh",
  "swc_core_generic.sv"
  ]

vlog_opt="+incdir+../../ip_cores/wr-cores/sim +incdir+../../ip_cores/wr-cores/sim/fabric_emu"

modules = {"local":
		[ 
		  "../../ip_cores/wr-cores",
		  "../../ip_cores/general-cores/modules/genrams/",
		  "../../modules/wrsw_swcore",
		],
	    #"git" :
		#[
		  #"git://ohwr.org/hdl-core-lib/general-cores.git",
		#],
	  }
