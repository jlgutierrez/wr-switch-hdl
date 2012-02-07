target = "altera" # "xilinx" # 
action = "simulation"

#fetchto = "../../ip_cores"

#files = "swc_core.v4.sv"

files = [
  "swc_core_wrapper_7ports.vhd",
  "xswc_core_wrapper_7ports.svh",
  "swc_core_7ports.sv",
  "swc_core_wrapper_generic.svh",
  "swc_core_generic.sv"
  ]

#vlog_opt="+incdir+../../../sim "
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
