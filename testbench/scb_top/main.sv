`timescale 1ns/1ps

`include "tbi_utils.sv"
`include "simdrv_wrsw_nic.svh"
`include "simdrv_rtu.sv"
`include "simdrv_wr_tru.svh"
`include "simdrv_txtsu.svh"
`include "endpoint_regs.v"
`include "endpoint_mdio.v"
`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"

`include "scb_top_sim_svwrap.svh"

`include "pfilter.svh"

module main;

    typedef struct { 
       integer     tx;
       integer     rx;
       integer     op;
    }  t_trans_path;

   typedef struct{
       rtu_vlan_entry_t vlan_entry;
       integer          vlan_id;
       bit              valid;
   } t_sim_vlan_entry;

   reg clk_ref=0;
   reg clk_sys=0;
   reg clk_swc_mpm_core=0;
   reg rst_n=0;
   parameter g_max_ports = 18;   
   parameter g_num_ports = 18;
   parameter g_mvlan     = 3; //max simulation vlans
   
   reg [g_num_ports-1:0] ep_ctrl;
   
   // prameters to create some gaps between pks (not work really well)
   // default settings
   
   /** ***************************   basic conf  ************************************* **/ 
   integer g_enable_pck_gaps                  = 1;   // 1=TRUE, 0=FALSE
   integer g_min_pck_gap                      = 300; // cycles
   integer g_max_pck_gap                      = 300; // cycles
   integer g_failure_scenario                 = 0;   // no link failure
   integer g_active_port                      = 0;
   integer g_backup_port                      = 1;
   integer g_tru_enable                       = 0;   //TRU disabled
   integer g_is_qvlan                         = 1;  // has vlan header
   integer g_pfilter_enabled                  = 0;
                                        // tx  ,rx ,opt (send from port tx to rx with option opt
   t_trans_path trans_paths[g_max_ports]      ='{'{0  ,17 , 0 }, // port 0: 
                                                 '{1  ,16 , 0 }, // port 1
                                                 '{2  ,15 , 0 }, // port 2
                                                 '{3  ,14 , 0 }, // port 3
                                                 '{4  ,13 , 0 }, // port 4
                                                 '{5  ,12 , 0 }, // port 5
                                                 '{6  ,11 , 0 }, // port 6
                                                 '{7  ,10 , 0 }, // port 7
                                                 '{8  ,9  , 0 }, // port 8
                                                 '{9  ,8  , 0 }, // port 9
                                                 '{10 ,7  , 0 }, // port 10
                                                 '{11 ,6  , 0 }, // port 11
                                                 '{12 ,5  , 0 }, // port 12
                                                 '{13 ,4  , 0 }, // port 13
                                                 '{14 ,3  , 0 }, // port 14
                                                 '{15 ,2  , 0 }, // port 15
                                                 '{16 ,1  , 0 }, // port 16
                                                 '{17 ,0  , 0 }};// port 17
                                         //index: 1,2,3,4,5,6,7,8,9, ....
   integer start_send_init_delay[g_max_ports] = '{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
   //mask with ports we want to use, port number:  18 ...............0
   reg [g_max_ports-1:0] portUnderTest        = 18'b111111111111111111; //  
   integer repeat_number                      = 20;
   integer tries_number                       = 3;
   reg [31:0] vlan_port_mask                  = 32'hFFFFFFFF;
   reg [31:0] mirror_src_mask                 = 'h00000002;
   reg [31:0] mirror_dst_mask                 = 'h00000080;
   bit mr_rx                                  = 1;
   bit mr_tx                                  = 1;
   bit mr                                     = 0;
   bit mac_ptp                                = 0;
   bit mac_ll                                 = 0;
   bit mac_single                             = 0;
   bit mac_range                              = 0;
   bit mac_br                                 = 0;
   
   // vlans
   int prio_map[8]                         = '{0, // Class of Service masked into prioTag 0
                                               1, // Class of Service masked into prioTag 1
                                               2, // Class of Service masked into prioTag 2
                                               3, // Class of Service masked into prioTag 3
                                               4, // Class of Service masked into prioTag 4
                                               5, // Class of Service masked into prioTag 5
                                               6, // Class of Service masked into prioTag 6
                                               7};// Class of Service masked into prioTag 7 
   int qmode                              = 2; //VLAN tagging/untagging disabled- pass as is
   //0: ACCESS port      - tags untagged received packets with VID from RX_VID field. Drops all tagged packets not belonging to RX_VID VLAN
   //1: TRUNK port       - passes only tagged VLAN packets. Drops all untagged packets.
   //3: unqualified port - passes all traffic regardless of VLAN configuration 
   
   int fix_prio                           = 0;
   int prio_val                           = 0; 
   int pvid                               = 0; 
                                             //      mask     , fid , prio,has_p,overr, drop   , vid, valid
   t_sim_vlan_entry sim_vlan_tab[g_mvlan] = '{'{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 100, 1'b1 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 200, 1'b1 }};
   integer tru_config_opt                 = 0;
   PFilterMicrocode mc                    = new;
   byte BPDU_templ[]                      ='{'h01,'h80,'hC2,'h00,'h00,'h00, //0 - 5: dst addr
                                             'h00,'h00,'h00,'h00,'h00,'h00, //6 -11: src addr (to be filled in ?)
                                             'h26,'h07,'h42,'h42,'h03,      //12-16: rest of the Eth Header
                                             'h00,'h00,                     //17-18: protocol ID
                                             'h00,                          //19   : protocol Version
                                             'h00,                          //20   : BPDU type =>: repleacable
                                             'h00,                          //21   : flags     =>: repleacable      
                                             'h00,'h00,'h00,'h00,'h00,'h00, //22-27: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //28-33: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //34-39: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //40-45: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //46-51: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //52-57: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00}; //58-63: padding

   byte PAUSE_templ[]                     ='{'h01,'h80,'hC2,'h00,'h00,'h01, //0 - 5: dst addr
                                             'h00,'h00,'h00,'h00,'h00,'h00, //6 -11: src addr (to be filled in ?)
                                             'h88,'h08,                     //12-13: Type Field = MAC control Frame
                                             'h00,'h01,                     //14-15: MAC Control Opcode = PAUSE
                                             'h00,'h00,                     //16-17: param: pause time: repleacable
                                             'h00,'h00,'h00,'h00,'h00,'h00, //18-23: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //24-29: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //30-35: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //36-41: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //42-47: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //48-53: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //54-59: padding
                                             'h00,'h00,'h00,'h00};          //60-63: padding
             
   integer g_injection_templates_programmed = 0;
   integer g_transition_scenario            = 0;
   /** ***************************   test scenario 1  ************************************* **/ 
  /*
   * testing switch over between ports 0,1,2
   * we broadcast  on ports 0,1 and 2. One of them is only active.
   * after some time port 0 failes (failure_scenario 1) and we switch to the othter
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_failure_scenario   = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 2  ************************************* **/ 
  /*
   * testing Fast forward of single mac entry
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_failure_scenario   = 1;
    mac_single           = 1; // enable single mac entry for fast forward
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 5 };
    trans_paths[1]       = '{1  ,16 , 5 };
    trans_paths[2]       = '{2  ,15 , 5 };
  end
 */
   /** ***************************   te scenario 3  ************************************* **/ 
  /*
   * test mirroring: simple case: mirroring rx/tx of port 1 into port 7
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000010000010;
    vlan_port_mask       = 32'h00000006; 
    g_tru_enable         = 0;
    mac_br               = 1; // enable fast forward for broadcast
    mr                   = 1; // enable mirror
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,2  , 5 };
    trans_paths[7]       = '{7  ,7  , 5 };  // this is the mirror port
    
  end
*/
   /** ***************************   te scenario 4  ************************************* **/ 
  /*
   * test mirroring: simple case: mirroring rx/tx of port 1 into port 7
   * when we broadcast traffic on port 1 and we want only egress traffic on this port, we should
   * not receive the sent traffic
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000010000110;
    vlan_port_mask       = 32'h00000006; 
    g_tru_enable         = 0;
    mac_br               = 1; // enable fast forward for broadcast
    mr                   = 1; // enable mirror
    mr_rx                = 0; // mirror only traffic sent on port 1 (egress)
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,2  , 4 };
    trans_paths[2]       = '{2  ,1  , 4 };
    trans_paths[7]       = '{7  ,7  , 4 };  // this is the mirror port
    
  end
*/
   /** ***************************   te scenario 5  ************************************* **/ 
  /*
   * test mirroring: mirroring received traffic on port 1 - sending from 1 , so should
   * go to mirror port
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000010000010;
    vlan_port_mask       = 32'h00000086; 
    g_tru_enable         = 0;
    mac_br               = 1; // enable fast forward for broadcast
    mr                   = 1; // enable mirror
    mr_tx                = 0; // mirror only traffic received on port
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,2  , 4 };
    trans_paths[7]       = '{7  ,7  , 4 };  // this is the mirror port
    
  end
 */
   /** ***************************   te scenario 6  ************************************* **/ 
  /*
   * test mirroring: mirroring received traffic on port 1 - sending on 2, so it should not go
   * to mirror port
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000010000100;
    vlan_port_mask       = 32'h00000086; 
    g_tru_enable         = 0;
    mac_br               = 1; // enable fast forward for broadcast
    mr                   = 1; // enable mirror
    mr_tx                = 0; // mirror only traffic received on port
                         // tx  ,rx ,opt
    trans_paths[2]       = '{2  ,1  , 4 };
    trans_paths[7]       = '{7  ,7  , 4 };  // this is the mirror port
    
  end
 */
   /** ***************************   te scenario 7  ************************************* **/ 
  /*
   * test mirroring: simple case: mirroring rx/tx of port 1 into port 7
   * when we broadcast traffic on port 1 and we want only egress traffic on this port, we should
   * not receive the sent traffic
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000010000110;
    vlan_port_mask       = 32'h00000086; 
    g_tru_enable         = 0;
    mac_br               = 1; // enable fast forward for broadcast
    mr                   = 1; // enable mirror
    mr_rx                = 0; // mirror only traffic sent on port 1 (egress)
                         // tx  ,rx ,opt
    trans_paths[2]       = '{1  ,2  , 4 };
    trans_paths[7]       = '{7  ,7  , 4 };  // this is the mirror port
    
  end
*/
   /** ***************************   te scenario 8  ************************************* **/ 
  /*
   * checking single MAC : checking if fast forward works for singe entries
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000010;
    vlan_port_mask       = 32'h000000FF; 
    g_tru_enable         = 0;
    mac_br               = 1; // enable fast forward for broadcast
    mac_single           = 1;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,2  , 6 };
    trans_paths[7]       = '{7  ,7  , 6 };  
    
  end
*/
   /** ***************************   te scenario 9  ************************************* **/ 
  /*
   * checking range MAC : 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000010;
    vlan_port_mask       = 32'h000000FF; 
    g_tru_enable         = 0;
    mac_range            = 1;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,2  , 7 };
    trans_paths[7]       = '{7  ,7  , 7 };  
    
  end
*/
   
   /** ***************************   test scenario 10  ************************************* **/ 
  /*
   * testing no-mirroring: verifying bug which makes the dst_mirror port disabled even if
   * mirroring is not enabled (but the dst_mirror mask is set)
   **/
/*
  initial begin
   mirror_src_mask                 = 'h00000002;
   mirror_dst_mask                 = 'h00000080;
   mr_rx                           = 1;
   mr_tx                           = 1;
   mr                              = 0;
  end
*/
   /** ***************************   test scenario 11  ************************************* **/ 
   /** ***************************     (problematic)   ************************************* **/ 
  /*
   * testing switch over for TRU->eRSTP
   * 1) we put port 1 (backup) down and up again (nothing should happen and  nothing happens)
   * 2) we put port 0 (active) down and the switch over works, we take packets from port 1 
   *    (so far this port was dropping ingress packets)
   * 
   * here, the switchover takes place during pck reception
   * 
   * PROBLEM: we receive the previous packet (somehow)
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps                  = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap                      = 300; // cycles
    g_max_pck_gap                      = 300; // cycles
    g_failure_scenario   = 2;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 12  ************************************* **/ 
   /** ***************************     (problematic)   ************************************* **/ 
  /*
   * testing switch over for TRU->eRSTP
   * 1) we put port 1 (backup) down and up again (nothing should happen and  nothing happens)
   * 2) we put port 0 (active) down and the switch over works, we take packets from port 1 
   *    (so far this port was dropping ingress packets)
   * 
   * here, the switchover takes place between pck receptions
   * 
   * PROBLEM: we receive the previous packet (somehow)
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps                  = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap                      = 300; // cycles
    g_max_pck_gap                      = 300; // cycles
    g_failure_scenario                         = 3;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 13  ************************************* **/ 
  /*
   * testing switch over for TRU->eRSTP
   * we kill port 0, works
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 1;
    g_active_port        = 0;
    g_backup_port        = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 14  ************************************* **/ 
  /*
   * testing switch over for TRU->eRSTP
   * we kill port 1 (backup) (DOWN) and then revivie it (UP) and then kill port 0 (active)
   * the killing of port 1 happens between frames being sent... OK
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 4;
    g_active_port        = 0;
    g_backup_port        = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 15  ************************************* **/ 
   /** ***************************     (problematic)   ************************************* **/ 
  /*
   * testing switch over for TRU->eRSTP
   * we kill port 1 (backup) (DOWN) and then revivie it (UP) and then kill port 0 (active)
   * the killing of port 1 happens during reception of frame... problem
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 2;
    g_active_port        = 0;
    g_backup_port        = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 16  ************************************* **/ 
  /*
   * simple VLAN tests: sending pckts on VLAN =100, we have no entries in hashTable for these,
   * so unrecongizes entries are broadcast
   **/
/*
  initial begin
    sim_vlan_tab[0] = '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    sim_vlan_tab[1] = '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 200, 1'b1 };
    sim_vlan_tab[2] = '{'{32'hFFFFFFFF, 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 100, 1'b1 };

  end
*/
   /** ***************************   test scenario 17  ************************************* **/ 
  /*
   * test of TRU+VLANs:
   * we have two VLANs with different active/backup ports
   * VLAN_0: 0-3 ports: 0-active, 1-backup, 2 & 3 - receive broadcast from 0 & 1
   * VLAN_1: 4-7 ports: 4-active, 5-backup, 6 & 7 - receive broadcast from 4 & 5
   * 
   * at some point we kill both active ports -> change to backup ports
   **/
/*
  initial begin
    sim_vlan_tab[0] = '{'{32'h0000000F, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    sim_vlan_tab[1] = '{'{32'h000000F0, 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2] = '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b0 };

    portUnderTest        = 18'b000000000000110011;
    g_tru_enable         = 1;
    g_failure_scenario   = 5;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,2 , 4 };
    trans_paths[1]       = '{1  ,3 , 4 };
    trans_paths[4]       = '{4  ,6 , 10};
    trans_paths[5]       = '{5  ,7 , 10};
    repeat_number        = 30;
    tries_number         = 1;
    g_is_qvlan           = 1;
    tru_config_opt       = 1;
    
  end
*/
   /** ***************************   test scenario 18  ************************************* **/ 
  /*
   * simle VLAN tagging test:
   * we send untagged frame and it should (acccording to the table with which I don't agree)
   * tagged (simulation errors appear)
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    g_tru_enable         = 0;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,2 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
    g_is_qvlan           = 0;
    qmode                = 3;
    
  end
*/
   /** ***************************   test scenario 19  ************************************* **/ 
  /*
   * simle VLAN test
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000010001;
    g_tru_enable         = 0;
    sim_vlan_tab[0] = '{'{32'h0000000F, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    sim_vlan_tab[1] = '{'{32'h000000F0, 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2] = '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b0 };
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,1 , 4 };
    trans_paths[4]       = '{4  ,5 , 10 };
    repeat_number        = 30;
    tries_number         = 1;
    g_is_qvlan           = 1;
   
  end
*/
   /** ***************************   test scenario 19  ************************************* **/ 
  /*
   * simple pfilter test: sets class=1 for each packet sent
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    g_tru_enable         = 0;
    sim_vlan_tab[0] = '{'{32'h0000000F, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    sim_vlan_tab[1] = '{'{32'h000000F0, 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2] = '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b0 };
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,1 , 4 };
    trans_paths[5]       = '{5  ,6 , 10 };
    repeat_number        = 30;
    tries_number         = 1;
    g_is_qvlan           = 1;
    g_pfilter_enabled    = 1;

    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(6, 'h8100, 'hffff, PFilterMicrocode::MOV, 1);
    mc.nop();
    mc.cmp(8, 'h88f7, 'hffff, PFilterMicrocode::AND, 1);    
    mc.logic2(24, 1, PFilterMicrocode::MOV, 0);
    
  end
*/   
   /** ***************************   test scenario 20  ************************************* **/ 
  /*
   * Testing pFilter:
   * detecting different classes of incoming packets using pFilter
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000010001;
    g_tru_enable         = 0;
    sim_vlan_tab[0] = '{'{32'h0000000F, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    sim_vlan_tab[1] = '{'{32'h000000F0, 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2] = '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b0 };
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,1 , 100 };
    trans_paths[4]       = '{4  ,5 , 10 };
    repeat_number        = 30;
    tries_number         = 1;
    g_is_qvlan           = 1;
    g_pfilter_enabled    = 1;

    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(6, 'h8100, 'hffff, PFilterMicrocode::MOV, 1);
    mc.nop();
    mc.cmp(8, 'hbabe, 'hffff, PFilterMicrocode::AND, 1);
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(16, 'h0001, 'hffff, PFilterMicrocode::MOV, 2);
    mc.cmp(16, 'h0010, 'hffff, PFilterMicrocode::MOV, 3);
    mc.cmp(16, 'h0100, 'hffff, PFilterMicrocode::MOV, 4);
    mc.cmp(16, 'h1000, 'hffff, PFilterMicrocode::MOV, 5);
    
    mc.logic2(24, 1, PFilterMicrocode::AND, 2);
    mc.logic2(25, 1, PFilterMicrocode::AND, 3);
    mc.logic2(26, 1, PFilterMicrocode::AND, 4);
    mc.logic2(27, 1, PFilterMicrocode::AND, 5);
    
  end
*/   
   /** ***************************   test scenario 21  ************************************* **/ 
  /*
   * injection/filtering test => transition test
   * we imitate transition when new (and better) link is added and we change the configuraiton
   * with pausing taffic not to loose anything
   */
/*
  initial begin
    portUnderTest        = 18'b000000000000000000; // we send pcks (Markers) in other place
    g_tru_enable         = 1;    
                         // tx  ,rx ,opt
    repeat_number        = 1;
    tries_number         = 1;
    g_injection_templates_programmed = 1;
    tru_config_opt       = 2;
    g_pfilter_enabled    = 1;
    g_transition_scenario= 1;

    mc.nop();
    mc.cmp(0, 'h0180, 'hffff, PFilterMicrocode::MOV, 1);
    mc.cmp(1, 'hc200, 'hffff, PFilterMicrocode::MOV, 1);
    mc.cmp(2, 'h0000, 'hffff, PFilterMicrocode::MOV, 1);
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(6, 'hbabe, 'hffff, PFilterMicrocode::MOV, 1);    
    mc.logic2(25, 1, PFilterMicrocode::MOV, 0);

  end
*/
   /** ***************************   test scenario 22  ************************************* **/ 
  /*
   * 
   **/
// /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_failure_scenario   = 1;
    g_injection_templates_programmed = 1;
    g_transition_scenario= 1;
    tru_config_opt       = 2;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
// */
  /*****************************************************************************************/
 
// defining which ports send pcks -> forwarding is one-to-one 
// (port_1 to port_14, port_2 to port_13, etc)
//     reg [18:0] portUnderTest = 18'b000000000000000011; // unicast -- port 0 disabled by VLAN config
//    reg [18:0] portUnderTest = 18'b111000000000000111; // unicast
//    reg [18:0] portUnderTest = 18'b000000000000001111; // unicast - switch over
//       reg [18:0] portUnderTest = 18'b100000000000000001; // unicast 
//     reg [18:0] portUnderTest = 18'b000000000000001000; // broadcast
//   reg [18:0] portUnderTest = 18'b100000000000000101;
//   reg [18:0] portUnderTest = 18'b111111111111111111;
//    integer tx_option[18]             = {4,4,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
//    integer repeat_number = 10;
//    integer tries_number = 3;

   /** *********************************************************************************** **/
   always #2.5ns clk_swc_mpm_core <=~clk_swc_mpm_core;
   always #8ns clk_sys <= ~clk_sys;
   always #8ns clk_ref <= ~clk_ref;
   
   initial begin
      repeat(100) @(posedge clk_sys);
      rst_n <= 1;
   end
/*
 *  wait ncycles
 */
    task automatic wait_cycles;
       input [31:0] ncycles;
       begin : wait_body
	  integer i;
 
	  for(i=0;i<ncycles;i=i+1) @(posedge clk_sys);
 
       end
    endtask // wait_cycles   
    
   task automatic tx_test(ref int seed, input  int n_tries, input int is_q,input int unvid, ref EthPacketSource src, ref EthPacketSink sink, input int srcPort, input int dstPort, input int opt=0);
      EthPacketGenerator gen = new;
      EthPacket pkt, tmpl, pkt2;
      EthPacket arr[];
      integer pck_gap = 0;
      //int i,j;
      
      if(g_enable_pck_gaps == 1) 
        if(g_min_pck_gap == g_max_pck_gap)
          pck_gap = g_min_pck_gap;
        else
          pck_gap = $dist_uniform(seed,g_min_pck_gap,g_max_pck_gap);

      arr            = new[n_tries](arr);
      if(opt !=3 && opt != 4)
        gen.set_seed(seed);
  
      tmpl           = new;

      if(opt > 2 )
        tmpl.src       = '{0,2,3,4,5,6};
      else if(opt == 101)
        tmpl.src       = '{0,0,0,0,0,0};
      else
        tmpl.src       = '{srcPort, 2,3,4,5,6};

      if(opt==0)
        tmpl.dst       = '{dstPort, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==1)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF};      
      else if(opt==2 || opt==101)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h00}; //BPDU
      else if(opt==3)
        tmpl.dst       = '{17, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==4 | opt==10)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF}; // broadcast      
      else if(opt==5)
        tmpl.dst       = '{'h11, 'h50, 'hca, 'hfe, 'hba, 'hbe}; // single Fast Forward
      else if(opt==6)
        tmpl.dst       = '{'h11, 'h11, 'h11, 'h11, 'h11, 'h11}; // single Fast Forward
      else if(opt==7)
        tmpl.dst       = '{'h04, 'h50, 'hca, 'hfe, 'hba, 'hbe}; // in the middle of the range
      else if(opt==8)
        tmpl.dst       = '{'h01, 'h1b, 'h19, 'h00, 'h00, 'h00}; // PTP
      else if(opt==9)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h01}; // link-limited

  
      tmpl.has_smac  = 1;
      tmpl.is_q      = is_q;
      if(opt==10)
        tmpl.vid     = 1;
      else
        tmpl.vid     = 0;
      if(opt == 100 ||  opt == 101)
        tmpl.ethertype = 'hbabe;
      else
        tmpl.ethertype = 'h88f7;
  // 
      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD  | EthPacketGenerator::SEQ_ID);
      gen.set_template(tmpl);
      if(opt == 101)
        gen.set_size(63, 64);
      else
        gen.set_size(63, 257);

      fork
        begin // fork 1
        for(int i=0;i<n_tries;i++)
           begin
              pkt  = gen.gen();
              pkt.oob = TX_FID;
              $display("|=> TX: port = %2d, pck_i = %4d (opt=%1d, pck_gap=%3d)" , srcPort, i,opt,pck_gap);
              if(opt == 100)
              begin
                pkt.payload[14] = 'h00;
                pkt.payload[15] = 'h01;
              end
              else if(opt == 101)
              begin
                pkt.payload[0] = 'hba;
                pkt.payload[1] = 'hbe;
              end
              
              src.send(pkt);
              arr[i]  = pkt;
              repeat(60) @(posedge clk_sys);
              wait_cycles(pck_gap); 
           end
        end   // fork 1
        begin // fork 2
        if(opt != 101)
          for(int j=0;j<n_tries;j++)
            begin
              sink.recv(pkt2);
              $display("|<= RX: port = %2d, pck_i = %4d" , dstPort, j);
              if(unvid)
                arr[j].is_q  = 0;
              if(!arr[j].equal(pkt2))
                begin
                  $display("Fault at %d", j);
                  $display("Should be: ");
                  arr[j].dump();
                  $display("Is: ");
                  pkt2.dump();
                end
            end // for (i=0;i<n_tries;i++)
        end // fork 2
      join
      seed = gen.get_seed();
      
   endtask // tx_test

   scb_top_sim_svwrap
     #(
       .g_num_ports(g_num_ports)
       ) DUT (
              .clk_sys_i(clk_sys),
              .clk_ref_i(clk_ref),
              .rst_n_i(rst_n),
              .cpu_irq(cpu_irq),
              .clk_swc_mpm_core_i(clk_swc_mpm_core),
              .ep_ctrl_i(ep_ctrl)
              );

   typedef struct {
      CSimDrv_WR_Endpoint ep;
      EthPacketSource send;
      EthPacketSink recv;
   } port_t;

   port_t ports[$];
   CSimDrv_NIC nic;
   CRTUSimDriver rtu;
   CSimDrv_WR_TRU    tru;
   CSimDrv_TXTSU txtsu;
   
   

   task automatic init_ports(ref port_t p[$], ref CWishboneAccessor wb);
      int i;
      
      for(i=0;i<g_num_ports;i++)
        begin
           port_t tmp;
           CSimDrv_WR_Endpoint ep;
           ep = new(wb, 'h30000 + i * 'h400);
           ep.init(i);
           ep.vlan_config(qmode, fix_prio, prio_val, pvid, prio_map);
           if(g_pfilter_enabled == 1)
           begin
             ep.pfilter_load_microcode(mc.assemble());
             ep.pfilter_enable(1);             
           end
           if(g_injection_templates_programmed == 1)
           begin
             ep.write_template(0, PAUSE_templ, 8);
             ep.write_template(1, BPDU_templ,  10);
           end

           tmp.ep = ep;
           tmp.send = EthPacketSource'(DUT.to_port[i]);
           tmp.recv = EthPacketSink'(DUT.from_port[i]);
           p.push_back(tmp);
        end
   endtask // init_endpoints
   
   task automatic init_nic(ref port_t p[$],ref CWishboneAccessor wb);
      NICPacketSource nic_src;
      NICPacketSink nic_snk;
      port_t tmp;
      
      nic = new(wb, 'h20000);
      $display("NICInit");
      nic.init();
      $display("Done");
      
      nic_src = new (nic);
      nic_snk = new (nic);
      $display("Src: %x\n",nic_src);
      
      tmp.send = EthPacketSource'(nic_src);
      tmp.recv = EthPacketSink'(nic_snk);
      p.push_back(tmp);
      
   endtask // init_nic
   
   task automatic init_tru(input CSimDrv_WR_TRU tru_drv);

      $display(">>>>>>>>>>>>>>>>>>> TRU initialization  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
      tru_drv.pattern_config(1 /*replacement*/, 0 /*addition*/);
//       tru_drv.rt_reconf_config(4 /*tx_frame_id*/, 4/*rx_frame_id*/, 1 /*mode*/);
//       tru_drv.rt_reconf_enable();
        
      /*
       * transition
       **/
//       tru_drv.transition_config(0 /*mode */,     4 /*rx_id*/, 0 /*prio*/, 20 /*time_diff*/, 
//                                 3 /*port_a_id*/, 4 /*port_b_id*/);



      /*
       * | port  | ingress | egress |
       * |--------------------------|
       * |   0   |   1     |   1    |   
       * |   1   |   0     |   1    |   
       * |   2   |   1     |   1    |   
       * |   3   |   1     |   1    |   
       * |   4   |   1     |   1    |   
       * |   5   |   0     |   1    |   
       * |--------------------------|
       * 
       *      5 -> 1 -> 0 
       *    ----------------
       *  port 1 is backup for 0
       *  port 5 is backup ofr 1
       * 
       **/

      if(tru_config_opt == 1)
        begin
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                               32'h3FFFF /*ports_mask  */, 32'b000000000000001101 /* ports_egress */,32'b000000000000001101 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0  /* pattern_mode */,
                               32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);    

        tru_drv.write_tru_tab(  1   /* valid     */,     1 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                               32'h3FFFF /*ports_mask  */, 32'b000000000011010000 /* ports_egress */,32'b000000000011010000 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   1  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00110000 /*pattern_mask*/, 32'b00010000 /* pattern_match*/,'h0  /* pattern_mode */,
                               32'b00110000 /*ports_mask  */, 32'b00100000 /* ports_egress */,32'b00100000 /* ports_ingress   */);    
        end
      else // default config == 0
        begin
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                               32'h3FFFF /*ports_mask  */, 32'b111000000010100001 /* ports_egress */,32'b111000000010100001 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0  /* pattern_mode */,
                               32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
        end


      
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    2 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    3 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    4 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    5 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    6 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    7 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);


//       tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
//                              32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0  /* pattern_mode */,
//                              32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
//  
//       tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
//                              32'b00000011 /*pattern_mask*/, 32'b00000011 /* pattern_match*/,'h0  /* pattern_mode */,
//                              32'b00000111 /*ports_mask  */, 32'b00000100 /* ports_egress */,32'b00000100 /* ports_ingress   */);
// 
//       tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
//                              'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
//                              'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);
 
      if(tru_config_opt == 2)
        tru_drv.transition_config(0 /*mode */,     1 /*rx_id*/, 0 /*prio*/, 20 /*time_diff*/, 
                                  0 /*port_a_id*/, 1 /*port_b_id*/);

      tru_drv.tru_swap_bank();  
      if(g_tru_enable)
         tru_drv.tru_enable();
      tru_drv.tru_port_config(0);
      $display("TRU configured and enabled");
      $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
   endtask; //init_tru
   
   initial begin
      uint64_t msr;
      int seed;
      rtu_vlan_entry_t def_vlan;
      int q;
      
      CWishboneAccessor cpu_acc = DUT.cpu.get_accessor();
      
      for(int gg=0;gg<g_num_ports;gg++) 
      begin 
        ep_ctrl[gg] = 'b1; 
      end
      repeat(200) @(posedge clk_sys);

      $display("Startup!");
      
      cpu_acc.set_mode(PIPELINED);
      cpu_acc.write('h10304, (1<<3));

      
      init_ports(ports, cpu_acc);
      $display("InitNIC");
      
      init_nic(ports, cpu_acc);

      $display("InitTXTS");

      txtsu = new (cpu_acc, 'h51000);
      txtsu.init();
      
      
      $display("Initialization done");

      rtu = new;
      rtu.set_bus(cpu_acc, 'h60000);
      for (int dd=0;dd<g_num_ports;dd++)
        begin
        rtu.set_port_config(dd, 1, 0, 1);
      end
        
        //
      rtu.set_port_config(g_num_ports, 1, 0, 0); // for NIC
        
      if(portUnderTest[0])  rtu.add_static_rule('{17, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<17));
      if(portUnderTest[1])  rtu.add_static_rule('{16, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<16));
      if(portUnderTest[2])  rtu.add_static_rule('{15, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<15));
      if(portUnderTest[3])  rtu.add_static_rule('{14, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<14));
      if(portUnderTest[4])  rtu.add_static_rule('{13, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<13));
      if(portUnderTest[5])  rtu.add_static_rule('{12, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<12));
      if(portUnderTest[6])  rtu.add_static_rule('{11, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<11));
      if(portUnderTest[7])  rtu.add_static_rule('{10, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<10));
      if(portUnderTest[8])  rtu.add_static_rule('{ 9, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<9 ));
      if(portUnderTest[9])  rtu.add_static_rule('{ 8, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<8 ));
      if(portUnderTest[10]) rtu.add_static_rule('{ 7, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<7 ));
      if(portUnderTest[11]) rtu.add_static_rule('{ 6, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<6 ));
      if(portUnderTest[12]) rtu.add_static_rule('{ 5, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<5 ));
      if(portUnderTest[13]) rtu.add_static_rule('{ 4, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<4 ));
      if(portUnderTest[14]) rtu.add_static_rule('{ 3, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<3 ));
      if(portUnderTest[15]) rtu.add_static_rule('{ 2, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<2 ));
      if(portUnderTest[16]) rtu.add_static_rule('{ 1, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<1 ));
      if(portUnderTest[17]) rtu.add_static_rule('{ 0, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<0  ));

     // rtu.set_hash_poly();
      $display(">>>>>>>>>>>>>>>>>>> RTU initialization  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
      for(int dd=0;dd<g_mvlan;dd++)
        begin
        def_vlan.port_mask      = sim_vlan_tab[dd].vlan_entry.port_mask;
        def_vlan.fid            = sim_vlan_tab[dd].vlan_entry.fid;
        def_vlan.drop           = sim_vlan_tab[dd].vlan_entry.drop;
        def_vlan.prio           = sim_vlan_tab[dd].vlan_entry.prio;
        def_vlan.has_prio       = sim_vlan_tab[dd].vlan_entry.has_prio;
        def_vlan.prio_override  = sim_vlan_tab[dd].vlan_entry.prio_override;
        if(sim_vlan_tab[dd].valid == 1)
          rtu.add_vlan_entry(sim_vlan_tab[dd].vlan_id, def_vlan);
      end

//       def_vlan.port_mask      = vlan_port_mask;
//       def_vlan.fid            = 0;
//       def_vlan.drop           = 0;
//       def_vlan.prio           = 0;
//       def_vlan.has_prio       = 0;
//       def_vlan.prio_override  = 0;
//       rtu.add_vlan_entry(0, def_vlan);
      ///////////////////////////   RTU extension settings:  ////////////////////////////////
      
      rtu.rx_add_ff_mac_single(0/*ID*/,1/*valid*/,'h1150cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_single(1/*ID*/,1/*valid*/,'h111111111111/*MAC*/);
      rtu.rx_add_ff_mac_range (0/*ID*/,1/*valid*/,'h0050cafebabe/*MAC_lower*/,'h0850cafebabe/*MAC_upper*/);
//       rtu.rx_set_port_mirror  ('h00000002 /*mirror_src_mask*/,'h00000080 /*mirror_dst_mask*/,1/*rx*/,1/*tx*/);
      rtu.rx_set_port_mirror  (mirror_src_mask, mirror_dst_mask,mr_rx, mr_tx);
      rtu.rx_set_hp_prio_mask ('b10000001 /*hp prio mask*/); //HP traffic set to 7th priority
      rtu.rx_set_cpu_port     ((1<<g_num_ports)/*mask: virtual port of CPU*/);
      rtu.rx_drop_on_fmatch_full();
      rtu.rx_feature_ctrl(mr, mac_ptp , mac_ll, mac_single, mac_range, mac_br);
      ////////////////////////////////////////////////////////////////////////////////////////

      rtu.enable();
      $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
      ///TRU
      tru = new(cpu_acc, 'h57000,g_num_ports,1);      
      init_tru(tru);
      
      
      ////////////// sending packest on all the ports (16) according to the portUnderTest mask.///////
      fork
         begin
           if(g_failure_scenario == 1)
           begin 
             wait_cycles(2000);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
           end
           else if(g_failure_scenario == 2 | g_failure_scenario == 3 | g_failure_scenario == 4)
           begin
             if(g_failure_scenario == 4)
               wait_cycles(400);
             else
               wait_cycles(500);
             ep_ctrl[g_backup_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 1 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(200);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(200);
             ep_ctrl[g_backup_port] = 'b1;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 1 up <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(400);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             if( g_failure_scenario == 3) 
               wait_cycles(350);
             else
               wait_cycles(500);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
           end
           if(g_failure_scenario == 5)
           begin 
             wait_cycles(2000);
             ep_ctrl[0] = 'b0;
             ep_ctrl[4] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> links 0 & 4 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
           end           
         end 
      join_none; //


      fork
         begin
           if(g_transition_scenario == 1)
           begin 
             wait_cycles(200);
             //program other bank with alternate config
             tru.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                               32'h3FFFF /*ports_mask  */, 32'b111000000010100010 /* ports_egress */,32'b111000000010100010 /* ports_ingress   */);

             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                            32'b00000011 /*pattern_mask*/, 32'b00000010 /* pattern_match*/,'h0  /* pattern_mode */,
                            32'b00000011 /*ports_mask  */, 32'b00000001 /* ports_egress */,32'b00000001 /* ports_ingress   */);
             // enable transition
             tru.transition_enable();
             wait_cycles(200);
             //sent marker to port 1
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     101             /*option=4 */);             
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> transition 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(200);
             //sent marker to port 1
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[0].send /* src     */, 
                     ports[0].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     101             /*option=4 */);               
           end
         end 
      join_none; //
      
      for(q=0; q<g_max_ports; q++)
        fork
          automatic int qq=q;
          begin
          if(portUnderTest[qq]) 
            begin 
              wait_cycles(start_send_init_delay[q]);
              for(int g=0;g<tries_number;g++)
                begin
                  $display("Try port_0:%d",  g);
                  tx_test(seed                          /* seed    */, 
                          repeat_number                 /* n_tries */, 
                          g_is_qvlan                    /* is_q    */, 
                          0                             /* unvid   */, 
                          ports[trans_paths[qq].tx].send /* src     */, 
                          ports[trans_paths[qq].rx].recv /* sink    */,  
                          trans_paths[qq].tx             /* srcPort */ , 
                          trans_paths[qq].rx             /* dstPort */, 
                          trans_paths[qq].op             /*option=4 */);
                end  //for
             end   //if
          end  //thread
       join_none;//fork
   
      fork
         forever begin
            nic.update(DUT.U_Top.U_Wrapped_SCBCore.vic_irqs[0]);
            @(posedge clk_sys);
         end
         forever begin
            txtsu.update(DUT.U_Top.U_Wrapped_SCBCore.vic_irqs[1]);
            @(posedge clk_sys);
         end
      join_none
      

   end 

endmodule // main

