target = "xilinx" #  "altera" # 
action = "simulation"
  


files = [ 
         "tru.sv"                
        ]
        
vlog_opt = "+incdir+../../sim +incdir+../../sim/wr-hdl"
        
modules = {"local": 
                [
                 "../../modules/wrsw_tru",
                 "../../ip_cores/wr-cores/ip_cores/general-cores/modules/genrams/"
                ],
             }