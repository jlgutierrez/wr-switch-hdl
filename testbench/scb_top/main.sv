`timescale 1ns/1ps

`include "tbi_utils.sv"
`include "simdrv_wrsw_nic.svh"
`include "simdrv_rtu.sv"
`include "simdrv_wr_tru.svh"
`include "simdrv_txtsu.svh"
`include "simdrv_tatsu.svh"
`include "simdrv_hwdu.svh"
`include "endpoint_regs.v"
`include "endpoint_mdio.v"
`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"
`include "scb_top_sim_svwrap.svh"
`include "scb_snake_sim_svwrap.svh"
`include "pfilter.svh"
`include "alloc.svh"
// `define snake_test 1

module main;

   reg clk_ref=0;
   reg clk_sys=0;
   reg clk_swc_mpm_core=0;
   reg rst_n=0;
   parameter g_max_ports = 18;   
   parameter g_num_ports = 18;
   parameter g_mvlan     = 19; //max simulation vlans
   parameter g_max_dist_port_number = 4;
   parameter g_snake_test          = 0;
    typedef enum {
       PAUSE=0,
       BPDU_0,
       MARKER
    } tx_special_pck_t;

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

   typedef struct{
       int               distPortN; //number of entries in the distribution
       int               srcPort;
       int               distr[g_max_dist_port_number];
   } t_sim_port_distr;

   typedef struct {
      CSimDrv_WR_Endpoint ep;
      EthPacketSource send;
      EthPacketSink recv;
   } port_t;
   
   typedef struct{
       int               qmode; 
       int               fix_prio;
       int               prio_val;
       int               pvid;
   } t_vlan_port_config;
   
   int mmu_alloc_cnt[g_num_ports+1];
   int mmu_usecnt_cnt[g_num_ports+1];
   int mmu_free_cnt[g_num_ports+1];
   int mmu_f_free_cnt[g_num_ports+1];
   int tx_done = 0;
   int rx_done = 0;
   reg [g_num_ports-1:0] txrx_done = 0;
   
   port_t ports[$];
   CSimDrv_NIC nic;
   CRTUSimDriver rtu;
   CSimDrv_WR_TRU    tru;
   CSimDrv_TXTSU txtsu;
   CSimDrv_TATSU tatsu;
   CSimDrv_HWDU hwdu;
   EthPacket ptpAnnounce;
   
   reg [g_num_ports-1:0] ep_ctrl;
   reg [15:0]            ep_failure_type = 'h00;
   
   // prameters to create some gaps between pks (not work really well)
   // default settings
   
   /** ***************************   basic conf  ************************************* **/ 
   integer g_enable_pck_gaps                  = 1;   // 1=TRUE, 0=FALSE
   integer g_min_pck_gap                      = 300; // cycles
   integer g_max_pck_gap                      = 300; // cycles
   integer g_force_payload_size               = 0; // if 0, then opt is used
   integer g_payload_range_min                = 63;
   integer g_payload_range_max                = 257;
   integer g_failure_scenario                 = 0;   // no link failure
   integer g_active_port                      = 0;
   integer g_backup_port                      = 1;
   integer g_tru_enable                       = 0;   //TRU disabled
   integer g_is_qvlan                         = 1;  // has vlan header
   integer g_pfilter_enabled                  = 0;
   integer g_limit_config_to_port_num         = g_num_ports;
   integer g_pause_mode                       = 0; //config of endpoints' PAUSE stuff 
                                                   //0:disabled | 1: standard PAUSE | 2: prio-based PAUSE
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
   reg [g_max_ports-1:0] portRtuEnabled       = 18'b111111111111111111; //
   integer repeat_number                      = 20;
   integer tries_number                       = 3;
   integer vid_init_for_inc                   = 0; // with opt 666  and 668
//    reg [31:0] vlan_port_mask                  = 32'hFFFFFFFF;
   reg [31:0] mirror_src_mask                 = 'h00000002;
   reg [31:0] mirror_dst_mask                 = 'h00000080;
   reg [7 :0] hp_prio_mask                    ='b10000001;
   bit mr_rx                                  = 1;
   bit mr_tx                                  = 1;
   bit mr                                     = 0;
   bit mac_ptp                                = 0;
   bit mac_ll                                 = 0;
   bit mac_single                             = 0;
   bit mac_range                              = 0;
   bit mac_br                                 = 0;
   bit hp_fw_cpu                              = 0;
   bit rx_forward_on_fmatch_full              = 0;                 
   bit unrec_fw_cpu                           = 0;
   bit rtu_dbg_f_fast_match                   = 0;
   bit rtu_dbg_f_full_match                   = 0;
   bit g_ignore_rx_test_check                 = 0;
   
   // vlans
//    int prio_map[8]                         = '{7, // Class of Service masked into prioTag 0
//                                                6, // Class of Service masked into prioTag 1
//                                                5, // Class of Service masked into prioTag 2
//                                                4, // Class of Service masked into prioTag 3
//                                                3, // Class of Service masked into prioTag 4
//                                                2, // Class of Service masked into prioTag 5
//                                                1, // Class of Service masked into prioTag 6
//                                                0};// Class of Service masked into prioTag 7 
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
   t_sim_vlan_entry sim_vlan_tab[g_mvlan] = '{'{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b0 },
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b0 }};
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

   byte MARKER_templ[]                    ='{'h01,'h80,'hC2,'h00,'h00,'h02, //0 - 5: dst addr
                                             'h00,'h00,'h00,'h00,'h00,'h00, //6 -11: src addr (to be filled in ?)
                                             'h88,'h09,                     //12-13: Type Field = Marker
                                             'h02,                          //14   : Subtype: Marker Protocol
                                             'h01,                          //15   : Version
                                             'h00,                          //16   : Marker response
                                             'h10,                          //17   : length
                                             //////// there should be more here, but not needed for simulation and I'm too lazy
                                             'h00,'h00,'h00,'h00,'h00,'h00, //18-23: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //24-29: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //30-35: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //36-41: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //42-47: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //48-53: padding
                                             'h00,'h00,'h00,'h00,'h00,'h00, //54-59: padding
                                             'h00,'h00,'h00,'h00};          //60-63: padding
   byte TEST_GEN_templ[]                  ='{'h01,'h80,'hC2,'h00,'h00,'h01, //0 - 5: dst addr
                                             'h00,'h00,'h00,'h00,'h00,'h00, //6 -11: src addr (to be filled in ?)
                                             'hDE,'hED};                    //12-13: EtherType

   byte ANNOUNCE_templ[]                 ='{//PTP header
                                            'h0B, // transport specific | message type
                                            'h02, //           reserved | version type
                                            'h40, //               message length
                                            'h00, //               message length
                                            'h00, //                   domain
                                            'h00, //                  reserved
                                            'h00, //                  flagField
                                            'h00, //                  flagField
                                            'h00, //               correctionField 1
                                            'h00, //               correctionField 2
                                            'h00, //               correctionField 3
                                            'h00, //               correctionField 4
                                            'h00, //               correctionField 5
                                            'h00, //               correctionField 6
                                            'h00, //               correctionField 7
                                            'h00, //               correctionField 8
                                            'h00, //                 reserved 1
                                            'h00, //                 reserved 2
                                            'h00, //                 reserved 3
                                            'h00, //                 reserved 4
                                            'h00, //               sourcPortID 1
                                            'h00, //               sourcPortID 2
                                            'h00, //               sourcPortID 3
                                            'h00, //               sourcPortID 4
                                            'h00, //               sourcPortID 5
                                            'h00, //               sourcPortID 6
                                            'h00, //               sourcPortID 7
                                            'h00, //               sourcPortID 8
                                            'h00, //               sourcPortID 9
                                            'h00, //               sourcPortID 10
                                            'hAB, //               seqID 1
                                            'hCD, //               seqID 2
                                            'h00, //             correctionField 
                                            'h00, //             logMessageInterval
                                            //// PTP Announce
                                            'h00, //             originalTimestamp 1
                                            'h00, //             originalTimestamp 2
                                            'h00, //             originalTimestamp 3
                                            'h00, //             originalTimestamp 4
                                            'h00, //             originalTimestamp 5
                                            'h00, //             originalTimestamp 6
                                            'h00, //             originalTimestamp 7
                                            'h00, //             originalTimestamp 8
                                            'h00, //             originalTimestamp 9
                                            'h00, //             originalTimestamp 10
                                            'h00, //             currentUtcOffset 1
                                            'h00, //             currentUtcOffset 2
                                            'h00, //             reserved
                                            'h00, //             grandmasterPriorit1
                                            'h07, //             gandmasterClockQuality 1 -> clockClass ?
                                            'h00, //             gandmasterClockQuality 2 -> clockAccuracy
                                            'h00, //             gandmasterClockQuality 3 -> offsetScaledLogVariance;
                                            'h00 //             gandmasterClockQuality 4 -> offsetScaledLogVariance;
                                            };
                                            
   integer inj_gen_frame_size            = 225;
   integer inj_gen_if_gap_size           = 10;
   integer inj_gen_mode                  = 0; //0:default | 1: corrupted | 2,3: undefined (yet)
   integer g_test_inj_gen                = 0;
                                           //qmode, fix_prio, prio_val, pvid   
   t_vlan_port_config ep_vlan_conf[]      ='{'{  0,        0,        0,   1 }, //port =  0
                                             '{  0,        0,        0,   1 }, //port =  1
                                             '{  0,        0,        0,   2 }, //port =  2
                                             '{  0,        0,        0,   2 }, //port =  3
                                             '{  0,        0,        0,   3 }, //port =  4
                                             '{  0,        0,        0,   3 }, //port =  5
                                             '{  0,        0,        0,   4 }, //port =  6
                                             '{  0,        0,        0,   4 }, //port =  7
                                             '{  0,        0,        0,   5 }, //port =  8
                                             '{  0,        0,        0,   5 }, //port =  9
                                             '{  0,        0,        0,   6 }, //port =  10
                                             '{  0,        0,        0,   6 }, //port =  11
                                             '{  0,        0,        0,   7 }, //port =  12
                                             '{  0,        0,        0,   7 }, //port =  13
                                             '{  0,        0,        0,   8 }, //port =  14
                                             '{  0,        0,        0,   8 }, //port =  15
                                             '{  0,        0,        0,   9 }, //port =  16
                                             '{  0,        0,        0,   9 }};//port =  17

   integer g_injection_templates_programmed = 0;
   integer g_transition_scenario            = 0;
   integer g_do_vlan_config                 = 1;
//    int vlan_port_mask[]                     ='{32'h00000000,
//                                                32'h00000001,
//                                                32'h00000000,
//                                                32'h00000000,
//                                               }
   t_sim_port_distr LACPdistro              = '{  4,  // distribution port nubmer
                                                  0,  // source port (we send on this
                                                { 4,  // every 4th frame send to port 1
                                                  5,  // every 4th frame send to port 2
                                                  6,  // every 4th frame send to port 3
                                                  7}  // every 4th frame send to port 4
                                               };
   integer g_LACP_scenario                  = 0;
   integer g_traffic_shaper_scenario        = 0;
   integer g_enable_WRtime                  = 0;
   integer g_tatsu_config                   = 0;
   integer g_fw_to_cpu_scenario             = 0;
   integer g_set_untagging                  = 0;
   int lacp_df_hp_id                        = 0;
   int lacp_df_br_id                        = 2;
   int lacp_df_un_id                        = 1;
   int g_simple_allocator_unicast_check     = 0;
   integer g_send_announce_from_NIC         = 0;
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
   /** ***************************   test scenario 21   ********************** **/ 
   /** ***************************     (IMPORTANT)      ********************** **/ 
  /*
   * injection/filtering test => transition test
   * we imitate transition when new (and better) link is added and we change the configuraiton
   * with pausing taffic not to loose anything, so we have
   * ports 0 & 7 - normal = active 
   * ports 1 & 2 - 1 is active and 2 is backup (ingress blocking, egress forwarding)
   * 
   * what we do:
   * 1. send frame to 0,1,2 ports just for test
   * 2. send special "marker" on port 2 to start transition
   * 3. send few frames to port 2 which are counted
   * 4. send "marker" to port 1 to indicate that ports can be changed
   * 5. send few frames to port 1 (the are counted, as soon as the same number as on port 2 is counted
   *    the configuration is swapped and the frames start to be blocked)
   * 6. saend frames to port 2 which now works as active
   */
/*
  initial begin
    portUnderTest        = 18'b000000000000000000; // we send pcks (Markers) in other place
    g_tru_enable         = 1;    
                         // tx  ,rx ,opt
    repeat_number        = 1;
    tries_number         = 1;
    g_injection_templates_programmed = 1;
    tru_config_opt       = 3;
    g_pfilter_enabled    = 1;
    g_transition_scenario= 1;
    g_limit_config_to_port_num = 8; //to speed up the config, don't configure VLANS and stuff 
                                    // in ports above nubmer 7

    mc.nop();
    mc.cmp(0, 'h0180, 'hffff, PFilterMicrocode::MOV, 1);
    mc.cmp(1, 'hc200, 'hffff, PFilterMicrocode::AND, 1);
    mc.cmp(2, 'h0000, 'hffff, PFilterMicrocode::AND, 1);
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(6, 'hbabe, 'hffff, PFilterMicrocode::AND, 1);    
    mc.logic2(25, 1, PFilterMicrocode::MOV, 0);

  end
*/
   /** ***************************   test scenario 22  ************************************* **/ 
  /*
   * Sending Pause the switch: a problem is that switch does not react to PAUSEs -- no 
   * flow control impolemented -- to be FIXED
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000011;
    g_tru_enable         = 1;
//     g_injection_templates_programmed = 1;
    g_transition_scenario= 2;
    tru_config_opt       = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,2 , 4 };
    trans_paths[1]       = '{1  ,3 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
  end
*/
   /** ***************************   test scenario 23  ************************************* **/ 
  /*
   * simple LACP test:
   * - sending frames to port 0
   * - two link aggregations
   *    * ports 3  -  7
   *    * ports 12 & 15
   * - sending frames on port 5 (from aggregated links)
   * - we don't recongize HP traffic, all the kinds of traffic have the same distribbution 
   *   source...
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000100; // no frames this way
    g_tru_enable         = 1;
    tru_config_opt       = 2;
    hp_prio_mask         = 'b10000000;
                         // tx  ,rx ,opt
    trans_paths[2]       = '{5  ,0 , 444 };// not FEC traffic cause etherType is not 0xbabe (the rest is)
    repeat_number        = 30;
    tries_number         = 1;
    g_LACP_scenario      = 1;
    mac_br               = 1;
    g_pfilter_enabled    = 1;
    g_do_vlan_config     = 0; //to make simulation faster, we don't need VLAN config, default is OK
   // limiting with VLAN
                     //      mask     , fid , prio,has_p,overr, drop   , vid, valid
    sim_vlan_tab[0] = '{'{32'h0000F0F1, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    
    mc.nop();                                          
    mc.cmp(0, 'hFFFF, 'hffff, PFilterMicrocode::MOV, 1); //setting bit 1 to HIGH if it 
    mc.cmp(1, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // is righ kind of frame, i.e:
    mc.cmp(2, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // 1. broadcast
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(8, 'hbabe, 'hffff, PFilterMicrocode::AND, 1); // 2. EtherType    
    mc.cmp(9, 'h0000, 'hffff, PFilterMicrocode::MOV, 2); // veryfing info in the frame for aggregation ID
    mc.cmp(9, 'h0001, 'hffff, PFilterMicrocode::MOV, 3); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0002, 'hffff, PFilterMicrocode::MOV, 4); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0003, 'hffff, PFilterMicrocode::MOV, 5); // veryfing info in the frame for aggregation ID   
    mc.logic2(24, 2, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(25, 3, PFilterMicrocode::AND, 1); // recognizing class 1 in correct frame
    mc.logic2(26, 4, PFilterMicrocode::AND, 1); // recognizing class 2 in correct frame
    mc.logic2(27, 5, PFilterMicrocode::AND, 1); // recognizing class 3 in correct frame
  end
 */
   /** ***************************   test scenario 23  ************************************* **/ 
  /*
   * LACP test:
   * - hp/broadcast/unicast distribution functions
   * - sending traffic to two port aggregations groups (4-7 and 13&15 ports)
   * - sending traffic from port on aggregation group
   * - the simulation is a bit simple, so the distribution looks the same for 
   *    hp/broarcast/unicast but each of them is derived differently:
   *    - hp - from plcass detected using packet filter
   *    - br - from source MAC, bits 8 & 9
   *    - un - from destination MAC, bits 8 & 9
   **/
 /*
  initial begin
    g_min_pck_gap        = 50; // cycles
    g_max_pck_gap        = 50; // cycles  
    portUnderTest        = 18'b000000000000000100; // no frames this way
    g_tru_enable         = 1;
    tru_config_opt       = 2;
                         // tx  ,rx ,opt
    trans_paths[2]       = '{5  ,0 , 4 };// 
    repeat_number        = 30;
    tries_number         = 1;
    g_LACP_scenario      = 2;
    mac_br               = 1;
    g_pfilter_enabled    = 1;
    repeat_number        = 20;
                     //      mask     , fid , prio,has_p,overr, drop   , vid, valid
    sim_vlan_tab[0] = '{'{32'h0000F0F1, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    
    mc.nop();                                          
    mc.cmp(0, 'hFFFF, 'hffff, PFilterMicrocode::MOV, 1); //setting bit 1 to HIGH if it 
    mc.cmp(1, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // is righ kind of frame, i.e:
    mc.cmp(2, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // 1. broadcast
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(8, 'hbabe, 'hffff, PFilterMicrocode::AND, 1); // 2. EtherType    
    mc.cmp(9, 'h0000, 'hffff, PFilterMicrocode::MOV, 2); // veryfing info in the frame for aggregation ID
    mc.cmp(9, 'h0001, 'hffff, PFilterMicrocode::MOV, 3); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0002, 'hffff, PFilterMicrocode::MOV, 4); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0003, 'hffff, PFilterMicrocode::MOV, 5); // veryfing info in the frame for aggregation ID   
    mc.logic2(24, 2, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(25, 3, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(26, 4, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(27, 5, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
  end
 */
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

 /** ***************************   test scenario 24  ************************************* **/ 
 /** ***************************     (PROBLEMATIC)   ************************************* **/ 
  /*
   * problematic, packets get merged
   **/
  /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    tru_config_opt       = 4;
    g_failure_scenario   = 1;
    g_injection_templates_programmed = 1;
    mac_single           = 1; // enable single mac entry for fast forward
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 5 };
    trans_paths[1]       = '{1  ,16 , 5 };
    trans_paths[2]       = '{2  ,15 , 5 };
  end
 */

 /** ***************************   test scenario 25  ************************************* **/ 
  /*
   * 
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000011;
    g_tru_enable         = 1;
    tru_config_opt       = 4;
    g_failure_scenario   = 1;
    g_active_port        = 0;
    g_injection_templates_programmed = 1;
    mac_single           = 1; // enable single mac entry for fast forward
                         // tx  ,rx ,opt
   // trans_paths[0]       = '{0  ,17 , 5 };
    trans_paths[0]       = '{0  ,2 , 5 };
    trans_paths[1]       = '{1  ,2 , 5 };
  end
*/


 /** ***************************   test scenario 26  ************************************* **/ 
  /*
   * problem with small frames and min InterFrame Gap: Linked-list is too slow 
   **/
 /*
  initial begin

    portUnderTest        = 18'b000000000000000001;
    g_active_port        = 0;
    g_enable_pck_gaps    = 0;
    repeat_number        = 2000;
    tries_number         = 1;  
    g_force_payload_size = 64;

//     mac_br               = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 203 };
    start_send_init_delay = '{0,20,40,60,80,100,120,140,160,180,200,220,240,260,280,300,320,340};

//     mac_br = 1;
  end
 */

 /** ***************************   test scenario 27  ************************************* **/ 
  /*
   * Sending heavily broadcast (stress-tests)
   **/
  /*
  initial begin
//     portUnderTest        = 18'b000000011111111111;
    portUnderTest        = 18'b000000000000000001;
    g_active_port        = 0;
    g_enable_pck_gaps    = 0;
    repeat_number        = 2000;
    tries_number         = 1;  
    g_force_payload_size = 500;

                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 204 };

    start_send_init_delay = '{0,20,40,60,80,100,120,140,160,180,200,220,240,260,280,300,320,340};

  end
 */
 /** ***************************   test scenario 28  ************************************* **/ 
  /*
   * PAUSE test - simple test of Time Aware Traffic Shaper (TATSU) and output queues
   * - sending PAUSE frames 
   * - making some strange configuration of TATSU
   **/
  /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_active_port        = 0;
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 0;
    g_min_pck_gap        = 800; // cycles
    g_max_pck_gap        = 800; // cycles  
    g_pause_mode         = 2;
    g_enable_WRtime      = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 900 };
    trans_paths[1]       = '{1  ,16 , 901 };
    trans_paths[2]       = '{2  ,15 , 1 };

    g_traffic_shaper_scenario = 1;
  end
 */
 /** ***************************   test scenario 29  ************************************* **/ 
  /*
   * 
   **/
  /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_active_port        = 0;
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 0;
    g_min_pck_gap        = 1000; // cycles
    g_max_pck_gap        = 1000; // cycles  
    g_pause_mode         = 2;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 900 };
    trans_paths[1]       = '{1  ,16 , 901 };
    trans_paths[2]       = '{2  ,15 , 205 };

    g_traffic_shaper_scenario = 2;
    g_enable_WRtime      = 1;

  end
 */
 /** ***************************   test scenario 30  ************************************* **/ 
  /*
   * testing simple RTU forwarding and stuff
   **/
 /*
  initial begin
    portUnderTest        = 18'b010101010101010101;   
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 700;
    g_min_pck_gap        = 100; // cycles
    g_max_pck_gap        = 100; // cycles  
                         // tx  ,rx ,opt

  end
 */
 /** ***************************   test scenario 31  ************************************* **/ 
  /*
   * output drop at HP - testing
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000111;   
    g_enable_pck_gaps    = 0;
    repeat_number        = 20;
    tries_number         = 1;  
    g_force_payload_size = 300;
    g_tatsu_config       = 1;
    mac_br               = 1;
//     g_min_pck_gap        = 100; // cycles
//     g_max_pck_gap        = 100; // cycles  
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 206 };
    trans_paths[1]       = '{1  ,16 , 206 };
    trans_paths[2]       = '{2  ,15 , 206 };

  end
*/
   /** ***************************   test scenario 32  ************************************* **/ 
  /*
   * testing switch over for TRU->eRSTP
   * we port 0 (active) in the middle of frame reception - the rx error should be handled 
   * properly
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 6;
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
   /** ***************************   test scenario 33  ************************************* **/ 
  /*
   * test WR Marker (HP+CPU forward)
   * - forwarding of HP traffic to NIC is disabled, but marker is recognized as link-limited (nf)
   *   so it is forwarded to CPU anyway (not as HP but as NF)
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 6;
    g_active_port        = 0;
    g_backup_port        = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 11 };
    trans_paths[1]       = '{1  ,16 , 11 };
    trans_paths[2]       = '{2  ,15 , 11 };
    repeat_number        = 30;
    tries_number         = 1;
    
    mac_ll               = 1;
    mac_single           = 1;
    hp_fw_cpu            = 0; // 
  end
 */
   /** ***************************   test scenario 34  ************************************* **/ 
  /*
   * HP traffic forwarding to NIC:
   * - by default should not be forwarded: nic_fw =0
   * - should be forwarded if nic_fw=1
   *  
   * we change the config of nic_fw in failure sceonario 7 (out of laziness here)
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 7; // changes hp_fw_cpu to 1
    g_active_port        = 0;
    g_backup_port        = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
    
    mac_ll               = 1;
    mac_single           = 1;
    mac_br               = 1;
    hp_fw_cpu            = 0; // 
  end
 /*/
   /** ***************************   test scenario 35  ************************************* **/ 
  /*
   * Learning - enable/disble forwarding of unrecognized broadcast to CPU
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 12 };
    repeat_number        = 30;
    tries_number         = 1;
    
    mac_ll               = 1;
    mac_single           = 1;
    mac_br               = 1;
    hp_fw_cpu            = 0; // 
    unrec_fw_cpu         = 0;
    g_fw_to_cpu_scenario = 1;
  end
 */
   /** ***************************   test scenario 36  ************************************* **/ 
  /*
   * testing switch over with HW-frame generation 
   * 
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000111;
    g_tru_enable         = 1;
    g_enable_pck_gaps    = 1;   // 1=TRUE, 0=FALSE
    g_min_pck_gap        = 300; // cycles
    g_max_pck_gap        = 300; // cycles
    g_failure_scenario   = 6;
    g_active_port        = 0;
    g_backup_port        = 1;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 4 };
    trans_paths[1]       = '{1  ,16 , 4 };
    trans_paths[2]       = '{2  ,15 , 4 };
    repeat_number        = 30;
    tries_number         = 1;
    tru_config_opt       = 5;
//     g_injection_templates_programmed = 1;
  end
*/
   /** ***************************   test scenario 37  ************************************* **/ 
  /*
   * quick forward/block massage detection and action 
   * 
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000000;
    g_tru_enable         = 1;
    g_transition_scenario= 3;
    g_active_port        = 0;
    g_backup_port        = 1;
    tru_config_opt       = 6;
    g_pfilter_enabled    = 1;
    g_injection_templates_programmed = 1;
    
    mc.nop();
    mc.cmp(0, 'h0180, 'hffff, PFilterMicrocode::MOV, 1);
    mc.cmp(1, 'hc200, 'hffff, PFilterMicrocode::AND, 1);
    mc.cmp(2, 'h0000, 'hffff, PFilterMicrocode::AND, 1);
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(6, 'h2607, 'hffff, PFilterMicrocode::AND, 1);    
    mc.logic2(25, 1, PFilterMicrocode::MOV, 0);    
    mc.logic2(26, 1, PFilterMicrocode::MOV, 0);    
    
  end
*/
 /** ***************************   test scenario 38  ************************************* **/ 
  /*
   * simple tagging/untagging test:
   * 1) send untaggged frames
   * 2) they get tagged at ingress port
   * 3) they get forwarded for pvid VLAN id
   * 4) they get untagged on egress
   **/
 /*
  initial begin
    portUnderTest        = 18'b000000000000000111;   
    
    qmode                = 0;//access
    pvid                 = 1;//tagging vlan
    g_is_qvlan           = 0; //send VLAN-tagged frames
    g_do_vlan_config     = 1; //enable vlan confgi
    g_set_untagging      = 1; // set pre-defined untagging config (untag VIDs:0 - 10)
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 0 };
    trans_paths[1]       = '{1  ,16 , 0 };
    trans_paths[2]       = '{2  ,15 , 0 };

  end
/*/
 /** ***************************   test scenario 39  ************************************* **/ 
  /*
   * tagging+untaggint + HP
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;   
    
    qmode                = 0;//access
    pvid                 = 1;//tagging vlan
    prio_val             = 7;//tag with prio 7 (7 is for HP)
    g_is_qvlan           = 0; //send VLAN-tagged frames
    g_do_vlan_config     = 1; //enable vlan confgi
    g_set_untagging      = 1; // set pre-defined untagging config (untag VIDs:0 - 10)
    
    mac_br               = 1; // fast forward broadcast
    
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 1 };
//     trans_paths[1]       = '{1  ,16 , 0 };
//     trans_paths[2]       = '{2  ,15 , 0 };

  end
*/
 /** ***************************   test scenario 40  ************************************* **/ 
  /*
   * Transparent TRU confgi
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000111;   
    g_tru_enable         = 1; //enable TRU
    tru_config_opt       = 7; //TRUE transparent
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 , 0 };
    trans_paths[1]       = '{1  ,16 , 0 };
    trans_paths[2]       = '{2  ,15 , 0 };

  end
*/
   /** ***************************   test scenario 41  ************************************* **/ 
  /*
   * testing switch over between ports 1,2
   * we broadcast  on ports  1 and 2. One of them is only active.
   * after some time port 0 failes (failure_scenario 7) and we switch to the othter
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000110;
    g_tru_enable         = 1;
    g_failure_scenario   = 8;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,6 , 4 };
    trans_paths[2]       = '{2  ,7 , 4 };
    repeat_number        = 30;
    g_active_port        = 1;
    g_backup_port        = 2;    
    tries_number         = 1;
    tru_config_opt       = 3;
  end
*/
   /** ***************************   test scenario 42  ************************************* **/ 
  /*
   * testing switch over between ports 1,2
   * we broadcast  on ports  1 and 2. One of them is only active.
   * after some time port 0 failes (failure_scenario 7) and we switch to the othter
   * 
   * with much higher laod
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000110;
    g_tru_enable         = 1;
    g_failure_scenario   = 9;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,6 , 4 };
    trans_paths[2]       = '{2  ,7 , 4 };
    repeat_number        = 30;
    g_active_port        = 1;
    g_backup_port        = 2;    
    tries_number         = 1;
    tru_config_opt       = 3;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/

   /** ***************************   test scenario 43  ************************************* **/
   /** ***************************   (PROBLEMATIC)  ************************************* **/  
  /*
   * stress test: 18 ports with packets, no gap - page-allocation too slow...
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b111111111111111111;
    repeat_number        = 30;
    tries_number         = 1;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/
   /** ***************************   test scenario 44  ************************************* **/
   /** ***************************   (PROBLEMATIC)  ************************************* **/  
  /*
   * stress test: 18 ports with packets, no gap - page-allocation too slow...
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b111111111111111111;
    repeat_number        = 30;
    tries_number         = 1;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/
   /** ***************************   test scenario 45  ************************************* **/
  /*
   * test HP detection by prio - works
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    trans_paths[0]       = '{0  ,1 , 207 }; //prio 3, broadcast
    repeat_number        = 30;
    tries_number         = 1;
    mac_br               = 1;
    hp_prio_mask         ='b01000010;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 64;
  end
*/
   /** ***************************   test scenario 46  ************************************* **/
   /** ***************************      (FIXED BUG)    ************************************* **/ 
  /*
   * trying to simulate test setup in the lab to check whether 8 ports binary 09_05_13_00/5
   * does not show RTUful events - 
   * 
   * found and fixed :)
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    trans_paths[0]       = '{0  ,1 ,7}; //fast forward with single entry 11...11
    repeat_number        = 30;
    tries_number         = 1;
    mac_single           = 1;
    mac_br               = 0;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
    hp_prio_mask         = 'b00000000;
  end
*/
   /** ***************************   test scenario 47  ************************************* **/ 
  /*
   * testing switch over between ports 1,2 
   * simulating thrashing of lost physic signal....
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000110;
    g_tru_enable         = 1;
    g_failure_scenario   = 10;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,6 , 4 };
    trans_paths[2]       = '{2  ,7 , 4 };
    repeat_number        = 30;
    g_active_port        = 1;
    g_backup_port        = 2;    
    tries_number         = 1;
    tru_config_opt       = 3;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/
   /** ***************************   test scenario 48  ************************************* **/ 
   /** ***************************      (FIXED BUG)    ************************************* **/ 
  /*
   * testing switch over between ports 1,2
   * trying to simulate situation which happens in hw: stuck at S_WAIT_RTU_VALID,-> simulated and fixed
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000110;
    g_tru_enable         = 1;
    g_failure_scenario   = 11;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,6 , 7 };
    trans_paths[2]       = '{2  ,7 , 7 };
    repeat_number        = 30;
    g_active_port        = 1;
    g_backup_port        = 2;    
    tries_number         = 1;
    tru_config_opt       = 3;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/
   /** ***************************   test scenario 49  ************************************* **/ 
   /** ***************************      (FIXED BUG)    ************************************* **/ 
  /*
   * testing switch over between ports 1,2 on the "upper switch" -> the one which is sending
   * onto two ports 
   * trying to simulate situation which happens in hw: the switch starts to drop frames forward
   * to the rendundant link aggregation
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b0000000000010000000;
    portRtuEnabled       = 18'b0000000000010000110;
    g_tru_enable         = 1;
    g_failure_scenario   = 11;
                         // tx  ,rx ,opt
    trans_paths[7]       = '{7  ,2 , 7 };
    repeat_number        = 30;
    g_active_port        = 1;
    g_backup_port        = 2;    
    tries_number         = 1;
    tru_config_opt       = 3;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/
   /** ***************************   test scenario 50  ************************************* **/ 
  /*
   * testing switch over between ports 1,2 
   * simulating ungraceful loss of physic signal....
   * 
   **/
/*

  initial begin
    portUnderTest        = 18'b000000000000000110;
    g_tru_enable         = 1;
    g_failure_scenario   = 11;
                         // tx  ,rx ,opt
    trans_paths[1]       = '{1  ,6 , 4 };
    trans_paths[2]       = '{2  ,7 , 4 };
    repeat_number        = 30;
    g_active_port        = 1;
    g_backup_port        = 2;    
    ep_failure_type      = 'h01;
    tries_number         = 1;
    tru_config_opt       = 3;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 512;
  end
*/
 /** ***************************   test scenario 51  ************************************* **/ 
  /*
   *  VLAN + FF bug
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000010000001;
    
    g_is_qvlan           = 1; //send VLAN-tagged frames
    g_do_vlan_config     = 1; //enable vlan confgi
    qmode                = 2;
    mac_br               = 1; // fast forward broadcast
    hp_prio_mask         = 8'b0;
    sim_vlan_tab[1] = '{'{32'b11        , 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2] = '{'{32'b110       , 8'h2, 3'h0, 1'b0, 1'b0, 1'b0}, 2  , 1'b1 };
    sim_vlan_tab[3] = '{'{32'b1100      , 8'h3, 3'h0, 1'b0, 1'b0, 1'b0}, 3  , 1'b1 };
    sim_vlan_tab[4] = '{'{32'b11000     , 8'h4, 3'h0, 1'b0, 1'b0, 1'b0}, 4  , 1'b1 };
    sim_vlan_tab[5] = '{'{32'b110000    , 8'h5, 3'h0, 1'b0, 1'b0, 1'b0}, 5  , 1'b1 };
    sim_vlan_tab[6] = '{'{32'b1100000   , 8'h6, 3'h0, 1'b0, 1'b0, 1'b0}, 6  , 1'b1 };
    sim_vlan_tab[7] = '{'{32'b11000000  , 8'h7, 3'h0, 1'b0, 1'b0, 1'b0}, 7  , 1'b1 };
    sim_vlan_tab[8] = '{'{32'b110000000 , 8'h8, 3'h0, 1'b0, 1'b0, 1'b0}, 8  , 1'b1 };
    sim_vlan_tab[9] = '{'{32'b1100000000, 8'h9, 3'h0, 1'b0, 1'b0, 1'b0}, 9  , 1'b1 };

                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,2 , 13 }; // send braodcast to VLAN=3
    trans_paths[7]       = '{7  ,0 , 10 };//send broadcast to VLAN=1
//     trans_paths[2]       = '{2  ,15 , 0 };

  end
*/
 /** ***************************   test scenario 51  ************************************* **/ 
  /*
   *  VLAN + FF bug
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000010000000;
    
    g_is_qvlan           = 1; //send VLAN-tagged frames
    g_do_vlan_config     = 1; //enable vlan confgi
    qmode                = 2;
//     mac_br               = 1; // fast forward broadcast
    hp_prio_mask         = 8'b0;
                       //      mask     , fid , prio,has_p,overr, drop   , vid, valid
    sim_vlan_tab[0] = '{'{32'hF         , 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    sim_vlan_tab[1] = '{'{32'hF0        , 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
                         // tx  ,rx ,opt
    
    trans_paths[7]       = '{7  ,4 , 10 };//send broadcast to VLAN=1
//     trans_paths[0]       = '{2  ,15 , 0 };

  end
*/

 /** ***************************   test scenario 52  ************************************* **/ 
  /*
   *  debugging priorities and PSTATS counters for prios
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    
    g_is_qvlan           = 1; //send VLAN-tagged frames
    g_do_vlan_config     = 1; //enable vlan confgi
//     pvid                 = 1; // mapping of priority here
                       //      mask     , fid , prio,has_p,overr, drop , vid, valid
    sim_vlan_tab[0] = '{'{32'h0         , 8'h0, 3'h0, 1'b0, 1'b0, 1'b1}, 0  , 1'b1 }; //disable VID=0
    sim_vlan_tab[1] = '{'{32'hFFFF      , 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
                         // tx  ,rx ,opt
    
    trans_paths[0]       = '{0  ,1 , 205 };//different priorities


  end
/*/
/** ***************************   test scenario 53  ************************************* **/ 
  /*
   *  debugging VLANs -> works on simulation -> seems to be timing problem when reading
   *                     from RAM (VLAN tab)
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    
    g_is_qvlan           = 1; //send VLAN-tagged frames
    g_do_vlan_config     = 1; //enable vlan confgi
                       //      mask     , fid , prio,has_p,overr, drop , vid, valid
    sim_vlan_tab[0] = '{'{32'h0         , 8'h0, 3'h0, 1'b0, 1'b0, 1'b1}, 0  , 1'b1 }; //disable VID=0
    sim_vlan_tab[1] = '{'{32'hFFFF      , 8'h1, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
                         // tx  ,rx ,opt
    
    trans_paths[0]       = '{0  ,1 , 10 }; // vid=1


  end
/*/
/** ***************************   test scenario 53  ************************************* **/ 
  /*
   *  HP-traffic debugging
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;
    mac_br               = 1;
    g_is_qvlan           = 0;
//     hp_prio_mask         = 'b00000000;
    hp_prio_mask         = 'b00000010;
                         // tx  ,rx ,opt    
    trans_paths[0]       = '{0  ,1 , 1 }; // vid=1


  end
/*/
   /** ***************************   test scenario 54  ************************************* **/ 
  /*
   * simple LACP test - marker-based switch between link aggregation config:
   * 1) send frames with first type of distribution function (aggregation between 4-7 and
   *    12 &15 ports)
   * 2) set new type of distribution function (aggregation between 4,5,7 and 12 % 15)
   * 3) set transition config (rep for: "g_transition_scenario == 4") :
   *      tru.transition_config(1 , 4 , 0 , 7 , 1000 ,6 , 7 );
   *    - LACP-> marker (1)
   *    - pfilter class on which to trigger it (4)
   *    - mode of choice which priority should be affected (0)
   *    - protect only high priority (7)
   *    - block output queue for max 1000 quanta
   *    - transition from port 6 to 7 
   * 4) enable transition
   *    - active TRU table bank will be swapped (new config-> new distributin function activated)
   *    - output queue of port 7 will be blocked
   *    - Marker Response will be awated at port 6 (pfilter, if detected at port 6, bit 4 of plcass
   *      will be high
   *    - await max 1000 quanta
   * 5) Marker response frame received, output queue of port 7 unblocked
   * 6) Voila, we have new distribution without loosing frames at prio 7
   * 
   * for this to work, the CPU 
   * @ the distributor switch should send Marker Request frame
   * @ the collector switch should replay (when Marker Request is received) with Marker Response
   * this might turn out to be slow....
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000000; // no frames this way
    g_tru_enable         = 1;
    tru_config_opt       = 2;
    hp_prio_mask         = 'b10000000;
    g_transition_scenario= 4; 
                         // tx  ,rx ,opt
//     trans_paths[2]       = '{5  ,0 , 444 };// not FEC traffic cause etherType is not 0xbabe (the rest is)
    repeat_number        = 50;
    tries_number         = 1;
    g_LACP_scenario      = 3;
    mac_br               = 1;
    g_pfilter_enabled    = 1;
    g_do_vlan_config     = 0; //to make simulation faster, we don't need VLAN config, default is OK
   // limiting with VLAN
                     //      mask     , fid , prio,has_p,overr, drop   , vid, valid
    sim_vlan_tab[0] = '{'{32'h0000F0F1, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    
    mc.nop();                                          
    mc.cmp(0, 'hFFFF, 'hffff, PFilterMicrocode::MOV, 1); //FEC   : setting bit 1 to HIGH if it 
                                                         //FEC   : is righ kind of frame, i.e:    
                                                         //FEC   : broadcast
    mc.cmp(0, 'h0180, 'hffff, PFilterMicrocode::MOV, 6); //Marker: BPDU 

    mc.cmp(1, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); //FEC   : broadcast
    mc.cmp(1, 'hC200, 'hffff, PFilterMicrocode::AND, 6); //Marker: BPDU -> LACP Marker

    mc.cmp(2, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); //FEC   : broadcast
    mc.cmp(2, 'h0002, 'hffff, PFilterMicrocode::AND, 6); //Marker: BPDU 

    mc.nop();
    mc.nop();
    mc.nop();

    mc.cmp(6, 'h8809, 'hffff, PFilterMicrocode::AND, 6); //Marker: EtherType -> Marker       
    mc.cmp(7, 'h0201, 'hffff, PFilterMicrocode::AND, 6); //Marker: subtype+version 

    mc.cmp(8, 'hbabe, 'hffff, PFilterMicrocode::AND, 1); //FEC   : EtherType -> FEC
    mc.cmp(8, 'h0100, 'hff00, PFilterMicrocode::MOV, 7); //Marker: 0x02->Marker request
    mc.cmp(8, 'h0200, 'hff00, PFilterMicrocode::MOV, 8); //Marker: 0x02->Marker response
    
    mc.cmp(9, 'h0000, 'hffff, PFilterMicrocode::MOV, 2); //FEC   : conversation ID
    mc.cmp(9, 'h0001, 'hffff, PFilterMicrocode::MOV, 3); //FEC   : conversation ID
    mc.cmp(9, 'h0002, 'hffff, PFilterMicrocode::MOV, 4); //FEC   : conversation ID
    mc.cmp(9, 'h0003, 'hffff, PFilterMicrocode::MOV, 5); //FEC   : conversation ID

    mc.logic2(24, 2, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(25, 3, PFilterMicrocode::AND, 1); // recognizing class 1 in correct frame
    mc.logic2(26, 4, PFilterMicrocode::AND, 1); // recognizing class 2 in correct frame
    mc.logic2(27, 5, PFilterMicrocode::AND, 1); // recognizing class 3 in correct frame
    mc.logic2(28, 8, PFilterMicrocode::AND, 6); // recognizing recognizing Marker Response Frame
//     mc.logic2(28, 7, PFilterMicrocode::AND, 6); // recognizing recognizing Marker Response Frame
  end
 
*/
   /** ***************************   test scenario 55 (works) ************************************* **/ 
  /*
   * LACP test: using special "LACP mode" in the TRU table - solved the problem of sending
   * a frame received on link aggregation back to the ports of the aggregation (special LACP mode)
   * 
   * TRU table configuraiton for LACP using special LACP-dedicated "mode". For this you need:
   * 1) define "default" entry with "mode"=0x0 (here subentry_addr=0) which allows accepting 
   *    frames all aggregation ports but does not allow forwarding ports to aggregation ports 
   *    (ingres vs. egress)
   * 2) define each link aggregation with "mode"=0x4 (group of ports which define link aggregation
   *    - the ingress mask is used to recognize that frame comes from link aggregation, it is
   *      not used to create final forwarding/accepting mask
   *    - the egress mask is used to define through which port of the link aggregation 
   *      the particular frame (of a given conversation/group identified by pattern_match) should use
   *      
   * see the place where confgi si done (grep for "tru_config_opt == 8")
   **/
/*
  initial begin
    g_min_pck_gap        = 50; // cycles
    g_max_pck_gap        = 50; // cycles  
    portUnderTest        = 18'b000000000000000100; // no frames this way
    g_tru_enable         = 1;
    tru_config_opt       = 8; //SEE description in the place where the config is done !!!!!!!
                         // tx  ,rx ,opt
    trans_paths[2]       = '{5  ,0 , 444 };// 
    hp_prio_mask         = 'b10000000;
    repeat_number        = 30;
    tries_number         = 1;
    g_LACP_scenario      = 2;
    mac_br               = 1;
    g_pfilter_enabled    = 1;
    repeat_number        = 20;
                     //      mask     , fid , prio,has_p,overr, drop   , vid, valid
    sim_vlan_tab[0] = '{'{32'h0000F0F1, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    
    mc.nop();                                          
    mc.cmp(0, 'hFFFF, 'hffff, PFilterMicrocode::MOV, 1); //setting bit 1 to HIGH if it 
    mc.cmp(1, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // is righ kind of frame, i.e:
    mc.cmp(2, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // 1. broadcast
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(8, 'hbabe, 'hffff, PFilterMicrocode::AND, 1); // 2. EtherType    
    mc.cmp(9, 'h0000, 'hffff, PFilterMicrocode::MOV, 2); // veryfing info in the frame for aggregation ID
    mc.cmp(9, 'h0001, 'hffff, PFilterMicrocode::MOV, 3); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0002, 'hffff, PFilterMicrocode::MOV, 4); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0003, 'hffff, PFilterMicrocode::MOV, 5); // veryfing info in the frame for aggregation ID   
    mc.logic2(24, 2, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(25, 3, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(26, 4, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(27, 5, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
  end
*/
   /** ***************************   test scenario 56 (problematic- ToDo) ************************** **/ 
  /*
   * LACP test: - trying different way of solving the problem of forwarding frames back
   * to the link aggregation -> does not work -> need further debugging
   **/
/*
  initial begin
    g_min_pck_gap        = 50; // cycles
    g_max_pck_gap        = 50; // cycles  
    portUnderTest        = 18'b000000000000000100; // no frames this way
    g_tru_enable         = 1;
    tru_config_opt       = 9; //SEE description in the place where the config is done !!!!!!!
                         // tx  ,rx ,opt
    trans_paths[2]       = '{5  ,0 , 444 };// 
    hp_prio_mask         = 'b10000000;
    repeat_number        = 30;
    tries_number         = 1;
    g_LACP_scenario      = 2;
    mac_br               = 1;
    g_pfilter_enabled    = 1;
    repeat_number        = 20;
                     //      mask     , fid , prio,has_p,overr, drop   , vid, valid
    sim_vlan_tab[0] = '{'{32'h0000F0F1, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0  , 1'b1 };
    
    mc.nop();                                          
    mc.cmp(0, 'hFFFF, 'hffff, PFilterMicrocode::MOV, 1); //setting bit 1 to HIGH if it 
    mc.cmp(1, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // is righ kind of frame, i.e:
    mc.cmp(2, 'hFFFF, 'hffff, PFilterMicrocode::AND, 1); // 1. broadcast
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.nop();
    mc.cmp(8, 'hbabe, 'hffff, PFilterMicrocode::AND, 1); // 2. EtherType    
    mc.cmp(9, 'h0000, 'hffff, PFilterMicrocode::MOV, 2); // veryfing info in the frame for aggregation ID
    mc.cmp(9, 'h0001, 'hffff, PFilterMicrocode::MOV, 3); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0002, 'hffff, PFilterMicrocode::MOV, 4); // veryfing info in the frame for aggregation ID   
    mc.cmp(9, 'h0003, 'hffff, PFilterMicrocode::MOV, 5); // veryfing info in the frame for aggregation ID   
    mc.logic2(24, 2, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(25, 3, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(26, 4, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
    mc.logic2(27, 5, PFilterMicrocode::AND, 1); // recognizing class 0 in correct frame
  end
*/
 /** ***************************   test scenario 57  ************************************* **/ 
  /*
   * testing forcing of full_match/fast_match -> for debugging
   **/
/*
  initial begin
    portUnderTest        = 18'b010101010101010101;   
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 700;
    g_min_pck_gap        = 100; // cycles
    g_max_pck_gap        = 100; // cycles  
    mac_single           = 1;
    
                         // tx  ,rx ,opt
   rtu_dbg_f_fast_match                   = 0;
   rtu_dbg_f_full_match                   = 0;
  end
 */
 /** ***************************   test scenario 58  ************************************* **/ 
  /*
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b111111111111111111;   
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 700;
    g_min_pck_gap        = 100; // cycles
    g_max_pck_gap        = 100; // cycles  
    mac_single           = 1;
    vid_init_for_inc     = 1;
    g_is_qvlan           = 1;
    
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,666};
    trans_paths[1]       = '{1  ,16 ,666};
    trans_paths[2]       = '{2  ,15 ,666};  
    trans_paths[3]       = '{3  ,14 ,666};
    trans_paths[4]       = '{4  ,13 ,666};
    trans_paths[5]       = '{5  ,12 ,666};  
    trans_paths[6]       = '{6  ,11 ,666};
    trans_paths[7]       = '{7  ,10 ,666};
    trans_paths[8]       = '{8  ,9  ,666};  
    trans_paths[9]       = '{9  ,8  ,666};
    trans_paths[10]      = '{10 ,7  ,666};
    trans_paths[11]      = '{11 ,6  ,666};  
    trans_paths[12]      = '{12 ,5  ,666};
    trans_paths[13]      = '{13 ,4  ,666};
    trans_paths[14]      = '{14 ,3  ,666};  
    trans_paths[15]      = '{15 ,2  ,666};
    trans_paths[16]      = '{16 ,1  ,666};
    trans_paths[17]      = '{17 ,0  ,666};  

                     //              mask        , fid , prio,has_p,overr, drop , vid, valid
    sim_vlan_tab[0]  = '{'{32'h000000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b1}, 0  , 1'b1 };
    sim_vlan_tab[1]  = '{'{32'b100000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2]  = '{'{32'b010000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 2  , 1'b1 };
    sim_vlan_tab[3]  = '{'{32'b001000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 3  , 1'b1 };
    sim_vlan_tab[4]  = '{'{32'b000100000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 4  , 1'b1 };
    sim_vlan_tab[5]  = '{'{32'b000010000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 5  , 1'b1 };
    sim_vlan_tab[6]  = '{'{32'b000001000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 6  , 1'b1 };
    sim_vlan_tab[7]  = '{'{32'b000000100000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 7  , 1'b1 };
    sim_vlan_tab[8]  = '{'{32'b000000010000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8  , 1'b1 };
    sim_vlan_tab[9]  = '{'{32'b000000001000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 9  , 1'b1 };
    sim_vlan_tab[10] = '{'{32'b000000000100000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 10 , 1'b1 };
    sim_vlan_tab[11] = '{'{32'b000000000010000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 11 , 1'b1 };
    sim_vlan_tab[12] = '{'{32'b000000000001000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 12 , 1'b1 };
    sim_vlan_tab[13] = '{'{32'b000000000000100000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 13 , 1'b1 };
    sim_vlan_tab[14] = '{'{32'b000000000000010000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 14 , 1'b1 };
    sim_vlan_tab[15] = '{'{32'b000000000000001000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 15 , 1'b1 };
    sim_vlan_tab[16] = '{'{32'b000000000000000100, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 16 , 1'b1 };
    sim_vlan_tab[17] = '{'{32'b000000000000000010, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 17 , 1'b1 };
    sim_vlan_tab[18] = '{'{32'b000000000000000001, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 18 , 1'b1 };

   rtu_dbg_f_fast_match                   = 0;
   rtu_dbg_f_full_match                   = 0;
   tru_config_opt                         = 10;
   g_tru_enable                           = 1;
  end
*/
 /** ***************************   test scenario 59  ************************************* **/ 
  /*
   * bug fith FastMatch+prio
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000001;   
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 700;
    g_min_pck_gap        = 100; // cycles
    g_max_pck_gap        = 100; // cycles  
    mac_br               = 1;
    hp_prio_mask         = 'b01001010;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,205};
  end
 */
 /** ***************************   test scenario 60  ************************************* **/ 
  /*
   * 
   **/
/*
  initial begin
    portUnderTest        = 18'b111111111111111111;   
    g_enable_pck_gaps    = 1;
    repeat_number        = 200;
    tries_number         = 1;  
    g_force_payload_size = 64;
    g_min_pck_gap        = 100; // cycles
    g_max_pck_gap        = 100; // cycles  
    mac_single           = 1;
    vid_init_for_inc     = 1;
    g_is_qvlan           = 1;
    
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,667};
    trans_paths[1]       = '{1  ,16 ,667};
    trans_paths[2]       = '{2  ,15 ,667};  
    trans_paths[3]       = '{3  ,14 ,667};
    trans_paths[4]       = '{4  ,13 ,667};
    trans_paths[5]       = '{5  ,12 ,667};  
    trans_paths[6]       = '{6  ,11 ,667};
    trans_paths[7]       = '{7  ,10 ,667};
    trans_paths[8]       = '{8  ,9  ,667};  
    trans_paths[9]       = '{9  ,8  ,667};
    trans_paths[10]      = '{10 ,7  ,667};
    trans_paths[11]      = '{11 ,6  ,667};  
    trans_paths[12]      = '{12 ,5  ,667};
    trans_paths[13]      = '{13 ,4  ,667};
    trans_paths[14]      = '{14 ,3  ,667};  
    trans_paths[15]      = '{15 ,2  ,667};
    trans_paths[16]      = '{16 ,1  ,667};
    trans_paths[17]      = '{17 ,0  ,667};  

                     //              mask        , fid , prio,has_p,overr, drop , vid, valid
    sim_vlan_tab[0]  = '{'{32'h000000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b1}, 0  , 1'b1 };
    sim_vlan_tab[1]  = '{'{32'b100000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1  , 1'b1 };
    sim_vlan_tab[2]  = '{'{32'b010000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 2  , 1'b1 };
    sim_vlan_tab[3]  = '{'{32'b001000000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 3  , 1'b1 };
    sim_vlan_tab[4]  = '{'{32'b000100000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 4  , 1'b1 };
    sim_vlan_tab[5]  = '{'{32'b000010000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 5  , 1'b1 };
    sim_vlan_tab[6]  = '{'{32'b000001000000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 6  , 1'b1 };
    sim_vlan_tab[7]  = '{'{32'b000000100000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 7  , 1'b1 };
    sim_vlan_tab[8]  = '{'{32'b000000010000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8  , 1'b1 };
    sim_vlan_tab[9]  = '{'{32'b000000001000000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 9  , 1'b1 };
    sim_vlan_tab[10] = '{'{32'b000000000100000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 10 , 1'b1 };
    sim_vlan_tab[11] = '{'{32'b000000000010000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 11 , 1'b1 };
    sim_vlan_tab[12] = '{'{32'b000000000001000000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 12 , 1'b1 };
    sim_vlan_tab[13] = '{'{32'b000000000000100000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 13 , 1'b1 };
    sim_vlan_tab[14] = '{'{32'b000000000000010000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 14 , 1'b1 };
    sim_vlan_tab[15] = '{'{32'b000000000000001000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 15 , 1'b1 };
    sim_vlan_tab[16] = '{'{32'b000000000000000100, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 16 , 1'b1 };
    sim_vlan_tab[17] = '{'{32'b000000000000000010, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 17 , 1'b1 };
    sim_vlan_tab[18] = '{'{32'b000000000000000001, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 18 , 1'b1 };

   
  end
*/
 /** ***************************   test scenario 61  ************************************* **/ 
  /*
   * test 100% load
   **/
/*
  initial begin
    portUnderTest        = 18'b100000000000000001;   
//     portUnderTest        = 18'b111111111111111111;   
    g_enable_pck_gaps    = 0;
    repeat_number        = 500000;
    tries_number         = 1;  
//     g_force_payload_size = 270; // translates into 288 bytes - size of the entire frame as in 
//                                 // spirent
    g_force_payload_size = 110; // translates into 128 bytes - size of the entire frame as in 
//                                 // spirent

//     g_force_payload_size = 242; // translates into 256 bytes in spirent -> this exactly 2 pages
//     g_force_payload_size = 230; 
//     g_force_payload_size = 1000;

//     g_force_payload_size = 46;  
    g_force_payload_size = 218;   // tranlates into 326 bytes in spirent -> with this we sa the problem


    g_is_qvlan           = 0;
    trans_paths[0]       = '{0  ,17 ,0};
    trans_paths[17]      = '{17  ,0 ,0};
                         // tx  ,rx ,opt
//     trans_paths[0]       = '{0  ,17 ,1000};
//     trans_paths[17]      = '{17  ,0 ,1000};
  end
*/

 /** ***************************   test scenario 62  ************************************* **/ 
  /*
   * test 100% (high) load for 2 streams of small frames
   **/
/*
  initial begin
    portUnderTest        = 18'b110000000000000011;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 500000;
    tries_number         = 1;  
    g_force_payload_size = 46;  

    g_is_qvlan           = 0;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,0};
    trans_paths[17]      = '{17  ,0 ,0};

    trans_paths[1]       = '{1  ,16 ,0};
    trans_paths[16]      = '{16  ,1 ,0};

  end
*/

 /** ***************************   test scenario 63  ************************************* **/ 
  /*
   * test 100% (high) load for tagged frames
   **/
/*
  initial begin
    portUnderTest        = 18'b100000000000000001;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 500000;
    tries_number         = 1;  
    g_force_payload_size = 46;  
    g_is_qvlan           = 1;
  
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,0};
    trans_paths[17]      = '{17  ,0 ,0};

  end
 //*/
 /** ***************************   test scenario 64  ************************************* **/ 
  /*
   * test 100% (high) with tagging/untagging
   **/
/*
  initial begin
    portUnderTest        = 18'b100000000000000001;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 500000;
    tries_number         = 1;  
//     g_force_payload_size = 331;//46;  
    g_force_payload_size = 88;  // it should be 106 of  the entire frame 
//     g_set_untagging      = 1;
//     qmode                = 3;
    g_is_qvlan           = 0;
    
    // strange config -> make some strange wholes.... check this
//     qmode                = 3;
//     g_is_qvlan           = 1;    
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,0};
    trans_paths[17]      = '{17  ,0 ,0};

  end
*/
 /** ***************************   test scenario 65  ************************************* **/ 
  /*
   * test 100% (high) with tagging/untagging
   **/
/*
  initial begin
    portUnderTest        = 18'b100000000000000001;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 500000;
    tries_number         = 1;  
    g_force_payload_size = 128;//46;  
    g_set_untagging      = 1;
//     qmode                = 3;
//     g_is_qvlan           = 0;
//     
    // strange config -> make some strange wholes.... check this
    qmode                = 3;
    g_is_qvlan           = 1;    
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,0};
    trans_paths[17]      = '{17  ,0 ,0};

  end
 */
 /** ***************************   test scenario 66  ************************************* **/ 
  /*
   * test 100% (high) with tagging/untagging
   **/
/*
  initial begin
    portUnderTest        = 18'b100000000000000001;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 500;
    tries_number         = 1;  
    g_force_payload_size = 46;  
    rx_forward_on_fmatch_full = 1; 
    g_is_qvlan           = 0;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,0};
    trans_paths[17]      = '{17  ,0 ,0};

  end
 */
 /** ***************************   test scenario 67  ************************************* **/ 
  /*
   * stress test on all ports with Unicast
   * problem - to be investigated - cuts frames
   **/
/*
  initial begin
    portUnderTest        = 18'b1111111111111111111;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 500000;
    tries_number         = 1;  
    g_force_payload_size = 46*7;  
    
    g_is_qvlan           = 0;
                         // tx  ,rx ,opt
  end
/*/

 /** ***************************   test scenario 68  ************************************* **/ 
  /*
   * stress test on all ports with Unicast
   **/
/*
  initial begin
    portUnderTest        = 18'b1111111111111111111;    
    g_enable_pck_gaps    = 0;
    repeat_number        = 10;
    tries_number         = 1;  
    g_force_payload_size = 300;  
    
    g_is_qvlan           = 0;
                         // tx  ,rx ,opt
  end
*/

 /** ***************************   test scenario 69 (BUG case  *************************** **/ 
  /*
   * stress test on all ports with Braodcast+FastForward
   * FIXME: dropping does not work well - swcore gets lost
   **/
/*
  initial begin
                     //      mask     , fid , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'h00000001, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000002, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h00000004, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000008, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h00000010, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000020, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000040, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00000080, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h00000100, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00000200, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h00000400, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00000800, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00001000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h00002000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h00004000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h00008000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'h00010000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00020000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b1 };
   sim_vlan_tab[18] = '{'{32'h00040000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b1 };

//                   tx  ,rx ,opt (send from port tx to rx with option opt)
    trans_paths[ 0]='{0  ,17 , 668 }; // port 0: 
    trans_paths[ 1]='{1  ,16 , 668 }; // port 1
    trans_paths[ 2]='{2  ,15 , 668 }; // port 2
    trans_paths[ 3]='{3  ,14 , 668 }; // port 3
    trans_paths[ 4]='{4  ,13 , 668 }; // port 4
    trans_paths[ 5]='{5  ,12 , 668 }; // port 5
    trans_paths[ 6]='{6  ,11 , 668 }; // port 6
    trans_paths[ 7]='{7  ,10 , 668 }; // port 7
    trans_paths[ 8]='{8  ,9  , 668 }; // port 8
    trans_paths[ 9]='{9  ,8  , 668 }; // port 9
    trans_paths[10]='{10 ,7  , 668 }; // port 10
    trans_paths[11]='{11 ,6  , 668 }; // port 11
    trans_paths[12]='{12 ,5  , 668 }; // port 12
    trans_paths[13]='{13 ,4  , 668 }; // port 13
    trans_paths[14]='{14 ,3  , 668 }; // port 14
    trans_paths[15]='{15 ,2  , 668 }; // port 15
    trans_paths[16]='{16 ,1  , 668 }; // port 16
    trans_paths[17]='{17 ,0  , 668 }; // port 17

    portUnderTest        = 18'b1111111111111111111;    
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 150;
    g_max_pck_gap        = 150;
    repeat_number        = 20;
    tries_number         = 1;  
    g_force_payload_size = 42; 
    rx_forward_on_fmatch_full = 0; 
//     mac_br               = 1;
    g_is_qvlan           = 1;
                         // tx  ,rx ,opt
  end
/*/
 /** ***************************   test scenario 70  ************************************* **/ 
  /*
   * stress test on all ports with Braodcast+FastForward
   * BUG: s_rcv_pck goes into S_PAUSE -> WHY ??? (important, size: 200)
   * 
   **/
/*
  initial begin
                     //      mask     , fid , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'h00000001, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000002, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h00000004, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000008, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h00000010, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000020, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000040, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00000080, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h00000100, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00000200, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h00000400, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00000800, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00001000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h00002000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h00004000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h00008000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'h00010000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00020000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b1 };
   sim_vlan_tab[18] = '{'{32'h00040000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b1 };

//                   tx  ,rx ,opt (send from port tx to rx with option opt)
    trans_paths[ 0]='{0  ,17 , 668 }; // port 0: 
    trans_paths[ 1]='{1  ,16 , 668 }; // port 1
    trans_paths[ 2]='{2  ,15 , 668 }; // port 2
    trans_paths[ 3]='{3  ,14 , 668 }; // port 3
    trans_paths[ 4]='{4  ,13 , 668 }; // port 4
    trans_paths[ 5]='{5  ,12 , 668 }; // port 5
    trans_paths[ 6]='{6  ,11 , 668 }; // port 6
    trans_paths[ 7]='{7  ,10 , 668 }; // port 7
    trans_paths[ 8]='{8  ,9  , 668 }; // port 8
    trans_paths[ 9]='{9  ,8  , 668 }; // port 9
    trans_paths[10]='{10 ,7  , 668 }; // port 10
    trans_paths[11]='{11 ,6  , 668 }; // port 11
    trans_paths[12]='{12 ,5  , 668 }; // port 12
    trans_paths[13]='{13 ,4  , 668 }; // port 13
    trans_paths[14]='{14 ,3  , 668 }; // port 14
    trans_paths[15]='{15 ,2  , 668 }; // port 15
    trans_paths[16]='{16 ,1  , 668 }; // port 16
    trans_paths[17]='{17 ,0  , 668 }; // port 17

    portUnderTest        = 18'b1111111111111111111;    
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 150;
    g_max_pck_gap        = 150;
    repeat_number        = 20;
    tries_number         = 1;  
    g_force_payload_size = 200;//42; 
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 0;
    g_is_qvlan           = 1;
                         // tx  ,rx ,opt
  end
 */
 /** ***************************   test scenario 71  ************************************* **/ 
  /*
   * stress test on all ports with Braodcast+FastForward
   
   * 
   **/
/*
  initial begin
                     //      mask     , fid , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'h00000001, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000002, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h00000004, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000008, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h00000010, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000020, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000040, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00000080, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h00000100, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00000200, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h00000400, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00000800, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00001000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h00002000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h00004000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h00008000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'h00010000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00020000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b1 };
   sim_vlan_tab[18] = '{'{32'h00040000, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b1 };

//                   tx  ,rx ,opt (send from port tx to rx with option opt)
    trans_paths[ 0]='{0  ,17 , 668 }; // port 0: 
    trans_paths[ 1]='{1  ,16 , 668 }; // port 1
    trans_paths[ 2]='{2  ,15 , 668 }; // port 2
    trans_paths[ 3]='{3  ,14 , 668 }; // port 3
    trans_paths[ 4]='{4  ,13 , 668 }; // port 4
    trans_paths[ 5]='{5  ,12 , 668 }; // port 5
    trans_paths[ 6]='{6  ,11 , 668 }; // port 6
    trans_paths[ 7]='{7  ,10 , 668 }; // port 7
    trans_paths[ 8]='{8  ,9  , 668 }; // port 8
    trans_paths[ 9]='{9  ,8  , 668 }; // port 9
    trans_paths[10]='{10 ,7  , 668 }; // port 10
    trans_paths[11]='{11 ,6  , 668 }; // port 11
    trans_paths[12]='{12 ,5  , 668 }; // port 12
    trans_paths[13]='{13 ,4  , 668 }; // port 13
    trans_paths[14]='{14 ,3  , 668 }; // port 14
    trans_paths[15]='{15 ,2  , 668 }; // port 15
    trans_paths[16]='{16 ,1  , 668 }; // port 16
    trans_paths[17]='{17 ,0  , 668 }; // port 17

//     portUnderTest        = 18'b1111111111111111111;
    portUnderTest        = 18'b111111111111111111;
//     portUnderTest        = 18'b100000000000000001;        
//     portUnderTest        = 18'b000000000000000001;
//     portUnderTest        = 18'b111000000000000111;             
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 150;
    g_max_pck_gap        = 150;
    repeat_number        = 100; //10
    tries_number         = 1;  
    g_force_payload_size = 42; //250;//42; 
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 0;
    g_is_qvlan           = 1;
    g_simple_allocator_unicast_check = 1;
                         // tx  ,rx ,opt
  end
*/
 /** ***************************   test scenario 71  ************************************* **/ 
  /*
   * alloc test for lost pages
   
   * 
   **/
/*
  initial begin

    portUnderTest        = 18'b111111111111111111;
//     portUnderTest        = 18'b000000000000000001;
    g_enable_pck_gaps    = 1;
    g_min_pck_gap        = 0;
    g_max_pck_gap        = 400;
    repeat_number        = 30; //10
    tries_number         = 1;  
    g_force_payload_size = 0;//300;//46;//42; //250;//42; 
    rx_forward_on_fmatch_full = 0; 
    mac_br               = 0;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 1;
    g_simple_allocator_unicast_check = 1;
                         // tx  ,rx ,opt
  end
*/
 /** ***************************   test scenario 72 (bug) ************************************* **/ 
  /*
   * stress-test: broadcast on all ports
   * two problems
   * * swcore->input_block: when nomem receoption of dta from EP is PAUSEd -> not good, should be only 
   *   for HP traffic, otherwise dump
   * * problem on tx-> getting infinitely retry from EP
   
   * 
   **/
/*
  initial begin

                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,17 ,1};
    trans_paths[1]       = '{1  ,16 ,1};
    trans_paths[2]       = '{2  ,15 ,1};  
    trans_paths[3]       = '{3  ,14 ,1};
    trans_paths[4]       = '{4  ,13 ,1};
    trans_paths[5]       = '{5  ,12 ,1};  
    trans_paths[6]       = '{6  ,11 ,1};
    trans_paths[7]       = '{7  ,10 ,1};
    trans_paths[8]       = '{8  ,9  ,1};  
    trans_paths[9]       = '{9  ,8  ,1};
    trans_paths[10]      = '{10 ,7  ,1};
    trans_paths[11]      = '{11 ,6  ,1};  
    trans_paths[12]      = '{12 ,5  ,1};
    trans_paths[13]      = '{13 ,4  ,1};
    trans_paths[14]      = '{14 ,3  ,1};  
    trans_paths[15]      = '{15 ,2  ,1};
    trans_paths[16]      = '{16 ,1  ,1};
    trans_paths[17]      = '{17 ,0  ,1};  

    portUnderTest        = 18'b111111111111111111;
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 0;
    g_max_pck_gap        = 400;
    repeat_number        = 60; //10
    tries_number         = 1;  
    g_force_payload_size = 207; //1500;//300;//46;//42; //250;//42; 
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 1;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 1;
    g_simple_allocator_unicast_check = 1;
                         // tx  ,rx ,opt
  end
 */
 /** ***************************   test scenario 73  ************************************* **/ 
  /*
   * simple
   * 
   **/
/*
  initial begin

  
    portUnderTest        = 18'b100000000000000001;
    trans_paths[ 0]='{0  ,17 , 0 }; // port 0:
    trans_paths[17]='{17 ,0  , 0 }; // port 17
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 100;
    g_max_pck_gap        = 400;
    repeat_number        = 30; //10
    tries_number         = 1;  
    g_force_payload_size = 0;//300;//46;//42; //250;//42; 
    rx_forward_on_fmatch_full = 0; 
    mac_br               = 0;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 0;
    g_simple_allocator_unicast_check = 1;
    
                         // tx  ,rx ,opt
  end
*/

 /** ***************************   test scenario 74  ************************************* **/ 
  /*
   * snake !!!!!!!!!!!!! (need to uncomment/commeent)
   * 
   **/
/*
  initial begin

                     //      mask     , fid  , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'hFFFFFFFF, 8'h0 , 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000003, 8'h1 , 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h0000000C, 8'h2 , 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000030, 8'h3 , 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h000000C0, 8'h4 , 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000300, 8'h5 , 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000C00, 8'h6 , 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00003000, 8'h7 , 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h0000C000, 8'h8 , 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00030000, 8'h9 , 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h000C0000, 8'h10, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00300000, 8'h11, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00C00000, 8'h12, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h03000000, 8'h13, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h0C000000, 8'h14, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h30000000, 8'h15, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'hC0000000, 8'h16, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00000000, 8'h17, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b0 };
   sim_vlan_tab[18] = '{'{32'h00000000, 8'h18, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b0 };  

    portUnderTest        = 18'b100000000000000001;
                  // tx  ,rx ,opt
    trans_paths[ 0]='{0  ,17 , 1 }; // port 0:
    trans_paths[17]='{17 ,0  , 1 }; // port 17
    
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 0;
    g_max_pck_gap        = 400;
    repeat_number        = 100;//2700; //10
    tries_number         = 1;  
    g_force_payload_size = 207;//47;// 0;//300;//46;//42; //250;//42; 
//     g_force_payload_size = 482;// should be 500 in spirent
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 1;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 0;
    g_simple_allocator_unicast_check = 1;
    
    g_do_vlan_config    = 2; // snake EP configuration (tagging proper VLANs on ports
    
    g_set_untagging     = 2; // untagging
  end
*/
 /** ***************************   test scenario 75  ************************************* **/ 
  /*
   * stress
   * 
   **/
/*
  initial begin

  
    portUnderTest        = 18'b100000000000000001;
    trans_paths[ 0]='{0  ,17 , 1 }; // port 0:
    trans_paths[17]='{17 ,0  , 1 }; // port 17
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 100;
    g_max_pck_gap        = 400;
    repeat_number        = 300; //10
    tries_number         = 1;  
    g_force_payload_size = 47;//300;//46;//42; //250;//42; 
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 0;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 0;
    g_simple_allocator_unicast_check = 1;
    
                         // tx  ,rx ,opt
  end
*/
 /** ***************************   test scenario 76  ************************************* **/ 
  /*
   * ptpd problems - solved ;-p
   * 
   **/
/*
  initial begin

  
    portUnderTest        = 18'b100000000000000001;
    trans_paths[ 0]='{0  ,17 , 1 }; // port 0:
    trans_paths[17]='{17 ,0  , 1 }; // port 17
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 0;
    g_max_pck_gap        = 400;
    repeat_number        = 100; //10
    tries_number         = 1;  
    g_force_payload_size = 0;//47;//300;//46;//42; //250;//42; 
    rx_forward_on_fmatch_full = 1; 
    g_payload_range_min  = 63;
    g_payload_range_max  = 500;
    mac_br               = 0;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 0;
    g_simple_allocator_unicast_check = 1;
    g_set_untagging      = 3; // untagging
                         // tx  ,rx ,opt
  end
*/
 /** ***************************   test scenario 77  ************************************* **/ 
  /*
   * page-edge-crossing problem
   * 
   **/
/*
  initial begin

  
    portUnderTest        = 18'b100000000000000001;
    trans_paths[ 0]='{0  ,17 , 0 }; // port 0:
    trans_paths[17]='{17 ,0  , 0 }; // port 17
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 0;
    g_max_pck_gap        = 400;
    repeat_number        = 100; //10
    tries_number         = 1;  

                           // 2xpage  = 2x64
                           // payload = { 2x(2x64) [bytes in pages] - 14 [header]  - 4 [crc]}  [bytes]
                           // payload = 238 bytes ->page breaker :238/239
    g_force_payload_size = 239;//47;//300;//46;//42; //250;//42; 
    rx_forward_on_fmatch_full = 1; 
    
    mac_br               = 0;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 0;
    g_simple_allocator_unicast_check = 1;
    g_set_untagging      = 3; // untagging
                         // tx  ,rx ,opt
  end
*/
 /** ***************************   test scenario 78  ************************************* **/ 
  /*
   * snake !!!!!!!!!!!!! (need to uncomment/commeent)
   * 
   **/
/*
  initial begin

                     //      mask     , fid  , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'hFFFFFFFF, 8'h0 , 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000003, 8'h1 , 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h0000000C, 8'h2 , 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000030, 8'h3 , 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h000000C0, 8'h4 , 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000300, 8'h5 , 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000C00, 8'h6 , 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00003000, 8'h7 , 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h0000C000, 8'h8 , 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00030000, 8'h9 , 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h000C0000, 8'h10, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00300000, 8'h11, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00C00000, 8'h12, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h03000000, 8'h13, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h0C000000, 8'h14, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h30000000, 8'h15, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'hC0000000, 8'h16, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00000000, 8'h17, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b0 };
   sim_vlan_tab[18] = '{'{32'h00000000, 8'h18, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b0 };  

    portUnderTest        = 18'b100000000000000001;
                  // tx  ,rx ,opt
    trans_paths[ 0]='{0  ,17 , 1 }; // port 0:
    trans_paths[17]='{17 ,0  , 1 }; // port 17
    
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 0;
    g_max_pck_gap        = 400;
    repeat_number        = 10000;//2700; //10
    tries_number         = 1;  
    g_force_payload_size = 225-18; // header = 14 bytes | CRC = 4 bytes

//     g_force_payload_size = 207;//47;// 0;//300;//46;//42; //250;//42; 
//     g_force_payload_size = 482;// should be 500 in spirent
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 1;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 0;
    g_simple_allocator_unicast_check = 1;
    
    g_do_vlan_config    = 2; // snake EP configuration (tagging proper VLANs on ports
    
    g_set_untagging     = 2; // untagging
  end
*/
   /** ***************************   test scenario 79   ********************** **/   
   /*
    testing hw-supported injectin
   */
/*
  initial begin
    portUnderTest        = 18'b101000000000000101; // we send pcks (Markers) in other place
                         // tx  ,rx ,opt
    trans_paths[ 0]      ='{0  ,17 , 0 }; // port 0:
    trans_paths[17]      ='{17 ,0  , 0 }; // port 17
//     trans_paths[ 2]      ='{2  ,15 , 0 }; // port 2:
//     trans_paths[15]      ='{15 ,2  , 0 }; // port 15
    repeat_number        = 50;
    tries_number         = 1;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 46;// 225-18;    
    g_injection_templates_programmed = 2;
    g_limit_config_to_port_num = 4; //to speed up the config, don't configure VLANS and stuff 
                                    // in ports above nubmer 7
    //g_test_inj_gen       = 1; // inject test-frame scenario
    g_test_inj_gen       = 2; // inject test-frames + enable corruption + disable corrutption
    inj_gen_frame_size   = 64;
    inj_gen_mode         = 1;//0:default | 1: corrupt frames
    inj_gen_if_gap_size  = 100;
    g_ignore_rx_test_check =1;
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 0;
    g_is_qvlan           = 0;
  end
*/
 /** ***************************   test scenario 80  ************************************* **/ 
  /*
   * snake !!!!!!!!!!!!! (need to uncomment/commeent)
   * 
   **/
/*
  initial begin

                     //      mask     , fid  , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'hFFFFFFFF, 8'h0 , 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000003, 8'h1 , 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h0000000C, 8'h2 , 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000030, 8'h3 , 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h000000C0, 8'h4 , 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000300, 8'h5 , 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000C00, 8'h6 , 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00003000, 8'h7 , 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h0000C000, 8'h8 , 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00030000, 8'h9 , 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h000C0000, 8'h10, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00300000, 8'h11, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00C00000, 8'h12, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h03000000, 8'h13, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h0C000000, 8'h14, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h30000000, 8'h15, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'hC0000000, 8'h16, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00000000, 8'h17, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b0 };
   sim_vlan_tab[18] = '{'{32'h00000000, 8'h18, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b0 };  

    portUnderTest        = 18'b100000000000000001;
                  // tx  ,rx ,opt
    trans_paths[ 0]='{0  ,17 , 1 }; // port 0:
    trans_paths[17]='{17 ,0  , 1 }; // port 17
    
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 100;
    g_max_pck_gap        = 120;
    repeat_number        = 10000;//2700; //10
    tries_number         = 1;  
//     g_force_payload_size = 225-18; // header = 14 bytes | CRC = 4 bytes
    g_force_payload_size = 249-18; // header = 14 bytes | CRC = 4 bytes

//     g_force_payload_size = 207;//47;// 0;//300;//46;//42; //250;//42; 
//     g_force_payload_size = 482;// should be 500 in spirent
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 1;
    g_is_qvlan           = 0;
    g_ignore_rx_test_check = 1;
    g_simple_allocator_unicast_check = 1;
    
    g_do_vlan_config    = 2; // snake EP configuration (tagging proper VLANs on ports
    
    g_set_untagging     = 2; // untagging
  end
*/
 /** ***************************   test scenario 81  ************************************* **/ 
  /*
   * snake -> check all sizes of frames
   * 
   **/
/*
  initial begin

                     //      mask     , fid  , prio,has_p,overr, drop , vid, valid
   sim_vlan_tab[ 0] = '{'{32'hFFFFFFFF, 8'h0 , 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
   sim_vlan_tab[ 1] = '{'{32'h00000003, 8'h1 , 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
   sim_vlan_tab[ 2] = '{'{32'h0000000C, 8'h2 , 3'h0, 1'b0, 1'b0, 1'b0}, 2,  1'b1 };
   sim_vlan_tab[ 3] = '{'{32'h00000030, 8'h3 , 3'h0, 1'b0, 1'b0, 1'b0}, 3,  1'b1 };
   sim_vlan_tab[ 4] = '{'{32'h000000C0, 8'h4 , 3'h0, 1'b0, 1'b0, 1'b0}, 4,  1'b1 };
   sim_vlan_tab[ 5] = '{'{32'h00000300, 8'h5 , 3'h0, 1'b0, 1'b0, 1'b0}, 5,  1'b1 };
   sim_vlan_tab[ 6] = '{'{32'h00000C00, 8'h6 , 3'h0, 1'b0, 1'b0, 1'b0}, 6,  1'b1 };
   sim_vlan_tab[ 7] = '{'{32'h00003000, 8'h7 , 3'h0, 1'b0, 1'b0, 1'b0}, 7,  1'b1 };
   sim_vlan_tab[ 8] = '{'{32'h0000C000, 8'h8 , 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b1 };
   sim_vlan_tab[ 9] = '{'{32'h00030000, 8'h9 , 3'h0, 1'b0, 1'b0, 1'b0}, 9,  1'b1 };
   sim_vlan_tab[10] = '{'{32'h000C0000, 8'h10, 3'h0, 1'b0, 1'b0, 1'b0}, 10, 1'b1 };
   sim_vlan_tab[11] = '{'{32'h00300000, 8'h11, 3'h0, 1'b0, 1'b0, 1'b0}, 11, 1'b1 };
   sim_vlan_tab[12] = '{'{32'h00C00000, 8'h12, 3'h0, 1'b0, 1'b0, 1'b0}, 12, 1'b1 };
   sim_vlan_tab[13] = '{'{32'h03000000, 8'h13, 3'h0, 1'b0, 1'b0, 1'b0}, 13, 1'b1 };
   sim_vlan_tab[14] = '{'{32'h0C000000, 8'h14, 3'h0, 1'b0, 1'b0, 1'b0}, 14, 1'b1 };
   sim_vlan_tab[15] = '{'{32'h30000000, 8'h15, 3'h0, 1'b0, 1'b0, 1'b0}, 15, 1'b1 };
   sim_vlan_tab[16] = '{'{32'hC0000000, 8'h16, 3'h0, 1'b0, 1'b0, 1'b0}, 16, 1'b1 };
   sim_vlan_tab[17] = '{'{32'h00000000, 8'h17, 3'h0, 1'b0, 1'b0, 1'b0}, 17, 1'b0 };
   sim_vlan_tab[18] = '{'{32'h00000000, 8'h18, 3'h0, 1'b0, 1'b0, 1'b0}, 18, 1'b0 };  

    portUnderTest        = 18'b100000000000000001;
                  // tx  ,rx ,opt
    trans_paths[ 0]='{0  ,17 , 2000 }; // port 0:
    trans_paths[17]='{17 ,0  , 2000 }; // port 17
    
    g_enable_pck_gaps    = 0;
    repeat_number        = 100000;//2700; //10
    tries_number         = 1;  

    g_force_payload_size = 1600; // goes along with opt=2000 to test different frame sizes
    g_payload_range_min  = 64-18;
    g_payload_range_max  = 1518-18;

    rx_forward_on_fmatch_full = 1; 
    mac_br               = 1;
//     mac_single           = 1;
    g_is_qvlan           = 0;
    
    g_do_vlan_config    = 2; // snake EP configuration (tagging proper VLANs on ports
    
    g_set_untagging     = 2; // untagging
  end
*/
   /** ***************************   test scenario 81  ************************************* **/ 
  /*
    * send frames from port 0 to 1:
    * - vlan on ports 0 & 1
    * - tag/untagg
    * - send broadcast 
    * - enable FastForward for broadcast
    * - 
   **/
/*
  initial begin
    portUnderTest        = 18'b000000000000000011;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,1 , 1 };
    trans_paths[1]       = '{1  ,0 , 1 };
    repeat_number        = 10000;
    tries_number         = 1;
    g_enable_pck_gaps    = 0;
    g_force_payload_size = 249-18; // header = 14 bytes | CRC = 4 bytes
    
    
    sim_vlan_tab[ 0] = '{'{32'hFFFFFFFF, 8'h0 , 3'h0, 1'b0, 1'b0, 1'b0}, 0,  1'b1 };
    sim_vlan_tab[ 1] = '{'{32'h00000003, 8'h1 , 3'h0, 1'b0, 1'b0, 1'b0}, 1,  1'b1 };
    g_do_vlan_config    = 2; // snake EP configuration (tagging proper VLANs on ports
    
    rx_forward_on_fmatch_full = 1; 
    mac_br               = 1;
    mac_single           = 1;
    g_is_qvlan           = 0;
    g_do_vlan_config    = 2; // snake EP configuration (tagging proper VLANs on ports
    g_set_untagging     = 2; // untagging

  end
*/
   /** ***************************   test scenario 82  ************************************* **/ 
  /*
    * send/receive Announce messages to NIC
    * 
   **/
///*
  initial begin

    portUnderTest        = 18'b000000000000000011;
                         // tx  ,rx ,opt
    trans_paths[0]       = '{0  ,1 , 8};
    trans_paths[1]       = '{1  ,0 , 8 };
    repeat_number        = 10;
    tries_number         = 1;
    g_enable_pck_gaps    = 1;
    g_min_pck_gap        = 500;
    g_max_pck_gap        = 520;
    g_force_payload_size = 0; //size per option



    ptpAnnounce           = new(142);
    ptpAnnounce.dst       ='{'h01, 'h1b, 'h19, 'h00, 'h00, 'h00};
    ptpAnnounce.pcp       = 0;
    ptpAnnounce.is_q      = 0;
    ptpAnnounce.ethertype = 'h88f7;
    for(int i=0;i<ANNOUNCE_templ.size();i++)
        ptpAnnounce.payload[i] = ANNOUNCE_templ[i];
    
    g_send_announce_from_NIC = 10; // ten times to all ports
    
  end
//*/
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////

  always #2.66ns clk_swc_mpm_core <=~clk_swc_mpm_core;
//   always #3.11ns clk_swc_mpm_core <=~clk_swc_mpm_core;
//    always #4.2ns clk_swc_mpm_core <=~clk_swc_mpm_core;
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
      integer dmac_dist = 0;
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

      if(opt == 0 || opt == 200 || opt == 201 || opt == 666 || opt == 667 || opt == 1000 || opt == 2000)
        tmpl.src       = '{srcPort, 2,3,4,5,6};
      else if(opt == 101 | opt == 102)
        tmpl.src       = '{0,0,0,0,0,0};
      else if(opt > 2 )
        tmpl.src       = '{0,2,3,4,5,6};
      else
        tmpl.src       = '{srcPort, 2,3,4,5,6};

      if(opt==0 || opt == 200 || opt == 202 || opt == 1000 || opt == 2000)
        tmpl.dst       = '{dstPort, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==1)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF};      
      else if(opt==2 || opt==101)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h00}; //BPDU
      else if(opt==3)
        tmpl.dst       = '{17, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==4 || opt==10 || opt==13 || opt==201 || opt == 203 || opt == 204 || opt == 205 || opt == 206 || opt == 207 || opt == 444 || opt==666|| opt==667 || opt==668)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF}; // broadcast      
      else if(opt==5)
        tmpl.dst       = '{'h11, 'h50, 'hca, 'hfe, 'hba, 'hbe}; // single Fast Forward
      else if(opt==6)
        tmpl.dst       = '{'h11, 'h11, 'h11, 'h11, 'h11, 'h11}; // single Fast Forward
      else if(opt==7)
        tmpl.dst       = '{'h04, 'h50, 'hca, 'hfe, 'hba, 'hbe}; // in the middle of the range
      else if(opt==8)
        tmpl.dst       = '{'h01, 'h1b, 'h19, 'h00, 'h00, 'h00}; // PTP
      else if(opt==9 || opt==900 || opt == 901)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h01}; // PAUSE
      else if(opt==11)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h0F}; // Marker (fast forward + CPU forward)      
      else if(opt==12)
        tmpl.dst       = '{'h01, 'h23, 'h45, 'h67, 'h89, 'h0AB}; // Unknown MAC
      else
        tmpl.dst       = '{'h00, 'h00, 'h00, 'h00, 'h00, 'h00}; // link-limited

        
  
      tmpl.has_smac  = 1;
      if(opt == 204)
        tmpl.pcp     = 3; //priority
      else if(opt == 207)
        tmpl.pcp     = 6; //priority
      else
        tmpl.pcp    = 0;  //priority
      
      if(opt==900 || opt == 901)
        tmpl.is_q      = 0;
      else
        tmpl.is_q      = is_q;


      if(opt==13)
        tmpl.vid     = 3;
      else if(opt==10 )
        tmpl.vid     = 1;
      else
        tmpl.vid     = 0;
      if(opt==900 || opt == 901) 
        tmpl.ethertype = 'h8808;  
      else if(opt == 100 ||  opt == 101 ||  opt == 102)
        tmpl.ethertype = 'hbabe;
      else if(opt == 8) // PTP
        tmpl.ethertype = 'h88f7;
      else
        tmpl.ethertype = 'h1234;
  //  
      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD  | EthPacketGenerator::SEQ_ID);
      gen.set_template(tmpl);
      if(g_force_payload_size >= 1520) // more than max
          gen.set_size(64, 1500);
      else if(g_force_payload_size < 42 || opt == 8 /*PTP*/)
        begin
        if(opt == 101 ||  opt == 102 || opt == 900 || opt == 901)
          gen.set_size(64, 65);
        else if(opt == 201 || opt == 202 || opt == 203 || opt == 204)
          gen.set_size(63, 1001);
        else if(opt == 200)
          gen.set_size(1000, 1001);
        else if(opt == 8) //ptp
          gen.set_size(142, 143);
        else
          gen.set_size(g_payload_range_min, g_payload_range_max);
//           gen.set_size(63, 257);
        end
      else
        gen.set_size(g_force_payload_size, g_force_payload_size+1); // setting the precise size below
      
      fork
        begin // fork 1
           integer vid_cnt=0;
        for(int i=0;i<n_tries;i++)
           begin
              
              pkt  = gen.gen();

              if(g_force_payload_size >= 1520) // more than max
                if(opt == 2000)
                  pkt.set_size(g_payload_range_min + i%(g_payload_range_max-g_payload_range_min));
                else
                  $faltal("wrong g_force_payload_size with wrong opt param");
              else if(g_force_payload_size >= 42) // min size of frame is 64, 
                if(opt == 1000)
                  pkt.set_size(g_force_payload_size + i%2);
                else
                  pkt.set_size(g_force_payload_size);

              pkt.oob = TX_FID;
              $display("|=> TX: port = %2d, pck_i = %4d (opt=%1d, pck_gap=%3d, size=%2d, n=%d)" , srcPort, i,opt,pck_gap,  pkt.payload.size, i);
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
              else if(opt == 900) // "normal pause
              begin
                pkt.payload[0] = 'h00;
                pkt.payload[1] = 'h01;
                pkt.payload[2] = 'h00;
                pkt.payload[3] = 'h01;                
              end
              else if(opt == 901) // "per-prio pause
              begin
                pkt.payload[0] = 'h01;
                pkt.payload[1] = 'h01;
                
                // prio vector
                pkt.payload[2] = 'h00;
                pkt.payload[3] = 'h81;  
                
                //Quanta of prio 0                
                pkt.payload[4] = 'h00;
                pkt.payload[5] = 'h0A;                  

                //Quanta of prio 7            
                pkt.payload[18]= 'h00;
                pkt.payload[19]= 'h14;
              end
              else if(opt == 8) // PTP over raw Ethernet
              begin
                // PTP 
                pkt.set_size(142);
                for(int i=0;i<ANNOUNCE_templ.size();i++)
		    pkt.payload[i] = ANNOUNCE_templ[i];
              end
              if(opt == 444)
                pkt.src[4]    = dmac_dist++;
              
              if(opt == 205 || opt == 206)
                pkt.pcp = i%8;
                
              if(opt == 666)
                pkt.vid = vid_init_for_inc+srcPort;
              else if(opt== 667)
                pkt.vid = (vid_init_for_inc+srcPort+i)%18;
              else if(opt == 668)
                pkt.vid = vid_init_for_inc+dstPort;                
              src.send(pkt);
              arr[i]  = pkt;
//               repeat(60) @(posedge clk_sys);
//              repeat(6) @(posedge clk_sys); //minimum interframe gap : 96 bits = 12 bytes = 6 words
//               repeat(2) @(posedge clk_sys); //it seems that in reality it's less
//               wait_cycles(pck_gap); 
              if(pck_gap)
                wait_cycles(pck_gap); 
           end
           tx_done = 1;
        end   // fork 1
        begin // fork 2
        if(opt != 101 && opt != 201 && opt != 900 && opt != 901 && opt != 206 && opt != 666 && opt != 667 && opt!=8 && g_ignore_rx_test_check == 0)
          for(int j=0;j<n_tries;j++)
            begin
              sink.recv(pkt2);
              $display("|<= RX: port = %2d, pck_i = %4d (size=%2d)" , dstPort, j,  pkt2.payload.size);
              if(unvid)
                arr[j].is_q  = 0;
              if((arr[j].payload.size != pkt2.payload.size) || !arr[j].equal(pkt2))
                begin
                  $display("Fault at %d", j);
                  $display("Should be: ");
                  arr[j].dump();
                  $display("Is: ");
                  pkt2.dump();
                end
            end // for (i=0;i<n_tries;i++)
            rx_done = 1;
        end // fork 2
      join
      seed = gen.get_seed();
      
   endtask // tx_test

  task automatic tx_distrib_test(ref int seed, input int n_tries, input int is_q, input int unvid, ref port_t p[$], input t_sim_port_distr portDist, input int opt=0);
      /*
       * options:
       * 0: high priority, distribution/class in the first word
       * 1: boradcast, distribution by looking at src MAC, bits 6 & 7
       * 2: unicast, distribution by looking at dst MAC, bits 6 & 7
       **/
      EthPacketGenerator gen = new;
      EthPacket pkt, tmpl;
      EthPacket arr[4][];
      int n_dist_tries[];

      integer pck_gap = 0;
      //int i,j;
      
      if(g_enable_pck_gaps == 1) 
        if(g_min_pck_gap == g_max_pck_gap)
          pck_gap = g_min_pck_gap;
        else
          pck_gap = $dist_uniform(seed,g_min_pck_gap,g_max_pck_gap);

      arr[0]            = new[n_tries](arr[0]);
      arr[1]            = new[n_tries](arr[1]);
      arr[2]            = new[n_tries](arr[2]);
      arr[3]            = new[n_tries](arr[3]);
      
      if(opt !=3 && opt != 4)
        gen.set_seed(seed);
  
      tmpl           = new;

      tmpl.src       = '{1,2,3,4,5,6};
      if(opt == 2)
        tmpl.dst       = '{1,2,3,4,5,6};
      else
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF};      
  
      tmpl.has_smac  = 1;
      tmpl.is_q      = is_q;
      tmpl.vid       = 0;
      tmpl.pcp       = 7;
      if(opt == 1) 
        tmpl.pcp       = 5;
      else
        tmpl.pcp       = 7;
      tmpl.ethertype = 'hbabe;

      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD  | EthPacketGenerator::SEQ_ID);
      gen.set_template(tmpl);
      gen.set_size(63, 257);

      fork
        begin // fork 1
        for(int i=0;i<n_tries;i++)
           begin
              automatic int srcPort, dstID, dstPort;
              
              pkt  = gen.gen();
              pkt.oob = TX_FID;
              dstID   = (i % portDist.distPortN);
              dstPort = portDist.distr[dstID];
              srcPort = portDist.srcPort;
              $display("|=> TX: srcPort = %2d,dstPort = %2d [dstId=%2d], pck_i = %2d (opt=%1d, pck_gap=%3d)", 
                         srcPort, dstPort, dstID, i,opt,pck_gap);
              
              if(opt == 1)
                pkt.src[4] = dstID;
              else if(opt == 2)
                pkt.dst[4] = dstID;
              else
                begin
                pkt.payload[0] = 'h00;
                pkt.payload[1] = 'h00FF & dstID;
                end
              
              p[srcPort].send.send(pkt);
              arr[dstID][ n_dist_tries[dstID]]=pkt;
//               n_dist_tries[dstPort]++;
              if(opt != 5)
              fork
                begin
                  automatic EthPacket pkt2;
                  automatic int rxDstID = dstID;
                  automatic int j = n_dist_tries[dstID];
                  p[portDist.distr[rxDstID]].recv.recv(pkt2);
                  $display("|<= RX: port = %2d [dstID=%2d], pck_i = %4d" , portDist.distr[rxDstID], rxDstID, j);
                  if(unvid)
                    arr[rxDstID][j].is_q  = 0;
                  if(!arr[rxDstID][j].equal(pkt2))
                    begin
                      $display("Fault at %d", j);
                      $display("Should be: ");
                      arr[rxDstID][j].dump();
                      $display("Is: ");
                      pkt2.dump();
                    end
                  end // fork
                join
                n_dist_tries[dstID]++;
              repeat(60) @(posedge clk_sys);
//               repeat(6) @(posedge clk_sys);
//               wait_cycles(pck_gap); 
           end
        end   // fork 1
//         begin // fork 2
//           for(int j=0;j<n_tries/portDist.distPortN;j++)
//             begin
//               automatic EthPacket pkt2;
//               automatic int dstID = 0;
//               p[portDist.distr[dstID]].recv.recv(pkt2);
//               $display("|<= RX: port = %2d [dstID=%2d], pck_i = %4d" , portDist.distr[dstID], dstID, j);
//               if(unvid)
//                 arr[dstID][j].is_q  = 0;
//               if(!arr[dstID][j].equal(pkt2))
//                 begin
//                   $display("Fault at %d", j);
//                   $display("Should be: ");
//                   arr[dstID][j].dump();
//                   $display("Is: ");
//                   pkt2.dump();
//                 end
// 
//             end // for (i=0;i<n_tries;i++)
//         end // fork 2

      join
      seed = gen.get_seed();
      
   endtask // tx_distrib_test

   task automatic tx_special_pck(ref EthPacketSource src, input tx_special_pck_t opt=PAUSE,input integer user_value=0);
      EthPacket pkt;

      int i;
      pkt           = new(64);
      case(opt)
      PAUSE:   
        begin
        pkt.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h01};
        pkt.ethertype = 'h8808;        
        for(i=14;i<64;i++)
          pkt.payload[i-14]=PAUSE_templ[i];
        pkt.payload[2]= user_value>>8;
        pkt.payload[3]= user_value;
        end
      BPDU_0:
        begin
        pkt.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h00};
        pkt.ethertype = 'h2607;        
        for(i=14;i<64;i++)
          pkt.payload[i-14]=BPDU_templ[i];
        pkt.payload[6]= user_value>>8;
        pkt.payload[7]= user_value;
        end
      MARKER:
        begin
        pkt.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h02};
        pkt.ethertype = 'h8809;        
        for(i=14;i<64;i++)
          pkt.payload[i-14]=MARKER_templ[i];
        pkt.payload[2]= user_value;
        end
      endcase;
        
      pkt.has_smac  = 0;
      pkt.is_q      = 0;
      pkt.vid       = 0;
      pkt.oob       = TX_FID;
      src.send(pkt);
      repeat(60) @(posedge clk_sys);
      
   endtask // tx_special_pck

   
//    `ifdef `snake_test
//      scb_snake_sim_svwrap
//        #(
//          .g_num_ports(g_num_ports)
//          ) DUT (
//               .clk_sys_i(clk_sys),
//               .clk_ref_i(clk_ref),
//               .rst_n_i(rst_n),
//               .cpu_irq(cpu_irq),
//               .clk_swc_mpm_core_i(clk_swc_mpm_core),
//               .ep_ctrl_i(ep_ctrl),
//               .ep_failure_type(ep_failure_type)
//               );
//    `else
     scb_top_sim_svwrap
       #(
         .g_num_ports(g_num_ports)
         ) DUT (
              .clk_sys_i(clk_sys),
              .clk_ref_i(clk_ref),
              .rst_n_i(rst_n),
              .cpu_irq(cpu_irq),
              .clk_swc_mpm_core_i(clk_swc_mpm_core),
              .ep_ctrl_i(ep_ctrl),
              .ep_failure_type(ep_failure_type)
              );
//    `endif
     


   task automatic init_ports(ref port_t p[$], ref CWishboneAccessor wb);
      int i,j;
      
      for(i=0;i<g_num_ports;i++)
        begin
           port_t tmp;
           CSimDrv_WR_Endpoint ep;
           ep = new(wb, 'h30000 + i * 'h400);
           ep.init(i);
           if(g_do_vlan_config == 2 & i < g_limit_config_to_port_num )
             ep.vlan_config(ep_vlan_conf[i].qmode, ep_vlan_conf[i].fix_prio, ep_vlan_conf[i].prio_val, ep_vlan_conf[i].pvid, prio_map);
           else if(g_do_vlan_config == 1 & i < g_limit_config_to_port_num )
             ep.vlan_config(qmode, fix_prio, prio_val, pvid, prio_map);
           else
             ep.vlan_config(2, 0, 0, 0, '{0,1,2,3,4,5,6,7});//default

           if(g_pfilter_enabled == 1 & i < g_limit_config_to_port_num )
           begin
             ep.pfilter_load_microcode(mc.assemble());
             ep.pfilter_enable(1);             
           end
           if(g_injection_templates_programmed == 1 & i < g_limit_config_to_port_num)
           begin
             ep.write_template(0, PAUSE_templ, 16);
             ep.write_template(1, BPDU_templ,  20);
           end
           else if(g_injection_templates_programmed == 2 & i < g_limit_config_to_port_num)
           begin
             ep.inject_gen_ctrl_config(inj_gen_if_gap_size /*interframe gap*/,0 /*template sel id*/, inj_gen_mode /*mode of injection*/);
             ep.write_inj_gen_frame(TEST_GEN_templ /*header template*/,inj_gen_frame_size /*frame gap*/);
//              ep.inject_gen_ctrl_enable();
           end
           if(g_pause_mode == 1)
             ep.pause_config( 1/*txpause_802_3*/, 1/*rxpause_802_3*/, 0/*txpause_802_1q*/, 0/*rxpause_802_1q*/);
           else if(g_pause_mode == 2)
             ep.pause_config( 1/*txpause_802_3*/, 1/*rxpause_802_3*/, 1/*txpause_802_1q*/, 1/*rxpause_802_1q*/);
           
           if(g_set_untagging == 1)
           begin
             for(j=0;j<g_limit_config_to_port_num; j++)
               ep.vlan_egress_untag(j /*vlan*/ ,1);
           end
           else if(g_set_untagging == 2)
           begin
             for(j=0;j<g_limit_config_to_port_num; j++)
               ep.vlan_egress_untag(ep_vlan_conf[j].pvid /*vlan*/ ,1);
           end
           else if(g_set_untagging == 3)
           begin
               ep.vlan_egress_untag_direct('hFFFF /*vlan*/ ,0);
               ep.vlan_egress_untag_direct('hFFFF /*vlan*/ ,1);
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
      tru_drv.pattern_config(1 /*replacement*/, 0 /*addition*/, 0 /*subtraction*/);

      /*define distribution functions for hp, broadcast, unicast straffic*/
      tru_drv.lacp_config(lacp_df_hp_id,lacp_df_br_id,lacp_df_un_id); 

      tru_drv.hw_frame_config(1/*tx_fwd_id*/, 1/*rx_fwd_id*/, 1/*tx_blk_id*/, 2 /*rx_blk_id*/);
//       tru_drv.rt_reconf_config(4 /*tx_frame_id*/, 4/*rx_frame_id*/, 1 /*mode*/);
//       tru_drv.rt_reconf_enable();
        
      /*
       * transition
       **/
//       tru_drv.transition_config(0 /*mode */,     4 /*rx_id*/, 1, /*prio mode*/, 0 /*prio*/, 20 /*time_diff*/, 
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
      // initial clean
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    1 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);      
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    2 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/, 'h000 /* mode */,
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    3 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    4 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    5 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    6 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
      tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    7 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                             32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);

      if(tru_config_opt == 1 || tru_config_opt == 4)
        begin
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b000000000000001101 /* ports_egress */,32'b000000000000001101 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h000 /* mode */, 
                               32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);    

        tru_drv.write_tru_tab(  1   /* valid     */,     1 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b000000000011010000 /* ports_egress */,32'b000000000011010000 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   1  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00110000 /*pattern_mask*/, 32'b00010000 /* pattern_match*/,'h000 /* mode */,
                               32'b00110000 /*ports_mask  */, 32'b00100000 /* ports_egress */,32'b00100000 /* ports_ingress   */);    
        end
      else if(tru_config_opt == 2) // LACP (link aggregation of ports 4-1)
        begin
        
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  0  /* subentry_addr*/,
                               32'b0000_0000_0000_0000 /*pattern_mask*/,32'b0000_0000_0000_0000 /* pattern_match*/,'h0 /* mode */, 
                               32'b0000_1111_0000_1111 /*ports_mask */, 32'b0000_1111_0000_1111 /* ports_egress */,32'b0000_1111_0000_1111 /* ports_ingress   */); 

        // a bunch of link aggregation ports (ports 4 to 7 and 12&15)
        // received FEC msg of class 0 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0001 /* pattern_match*/,'h0 /* mode */, 
                               32'b1001_0000_1111_0000 /*ports_mask  */, 32'b1000_0000_0001_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */);    
        // received FEC msg of class 1
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0010 /* pattern_match*/,'h0 /* mode */, 
                               32'b1001_0000_1111_0000 /*ports_mask  */, 32'b1000_0000_0010_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 
        // received FEC msg of class 2 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0100 /* pattern_match*/,'h0 /* mode */, 
                               32'b1001_0000_1111_0000  /*ports_mask */, 32'b0001_0000_0100_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 
        // received FEC msg of class 3
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  4  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_1000 /* pattern_match*/,'h0 /* mode */, 
                               32'b1001_0000_1111_0000 /*ports_mask  */, 32'b0001_0000_1000_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */);        

//         // collector: receiving frames  on the aggregation ports, forwarding to "normal" (others)
//         tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  5  /* subentry_addr*/,
//                                32'b1001_0000_1111_0000 /*pattern_mask*/, 32'b1001_0000_1111_0000 /* pattern_match*/,'h2 /* mode */, 
//                                32'b1001_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_0000_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 

        tru_drv.pattern_config(4 /*replacement : use distributioon funciton defined by aggr_df_id */, 
                               5 /*addition    : simple mask reflecting on which port frame was rx-ed*/, 
                               5 /*subtraction*/); 
        end
      else if(tru_config_opt == 3) 
        begin
        /* port 2 is backup for port 1*/
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b1100_0111 /* ports_egress */,32'b1100_0011 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000110 /*pattern_mask*/, 32'b00000010 /* pattern_match*/,'h000 /* mode */, 
                               32'b00000110 /*ports_mask  */, 32'b00000110 /* ports_egress */,32'b00000100 /* ports_ingress   */);    

        tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    2 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/, 'h000 /* mode */,
                               32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    3 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                               32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);  
        end
        else if(tru_config_opt == 5)
        begin
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h0 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b111000000010100001 /* ports_egress */,32'b111000000010100001 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0 /* mode */,
                               32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
        end
        else if(tru_config_opt == 6)
        begin
        tru_drv.pattern_config(1 /*replacement*/, 2 /*addition*/, 3 /*subtraction*/); 
        // basic config
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h0 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b111000000010100001 /* ports_egress */,32'b111000000010100001 /* ports_ingress   */);
        // backup if link down
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0 /* mode */,
                               32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
        // quick forward
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               32'b00000010 /*pattern_mask*/, 32'b00000010 /* pattern_match*/,'h2 /* mode */,
                               32'b00000010 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
        // quick block
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               32'b00000001 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h3 /* mode */,
                               32'b00000001 /*ports_mask  */, 32'b00000001 /* ports_egress */,32'b00000001 /* ports_ingress   */);

        end
        else if(tru_config_opt == 7) // TRU transparent but is there
        begin
        // basic config
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h0 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'h3FFFF /* ports_egress */, 32'h3FFFF /* ports_ingress   */);
        end
      else if(tru_config_opt == 8) // LACP : using special LACP-dedicated
        begin
        
        // TRU table configuraiton for LACP using special LACP-dedicated "mode". For this you need:
        // 1) define "default" entry with "mode"=0x0 (here subentry_addr=0) which allows accepting 
        //    frames all aggregation ports but does not allow forwarding ports to aggregation ports 
        //    (ingres vs. egress)
        // 2) define each link aggregation with "mode"=0x4 (group of ports which define link aggregation
        //    - the ingress mask is used to recognize that frame comes from link aggregation, it is
        //      not used to create final forwarding/accepting mask
        //    - the egress mask is used to define through which port of the link aggregation 
        //      the particular frame (of a given conversation/group identified by pattern_match) should use
        
        // default configuraion
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  0  /* subentry_addr*/,
                               32'b0000_0000_0000_0000 /*pattern_mask*/,32'b0000_0000_0000_0000 /* pattern_match*/,'h0 /* mode */, 
                               32'b1001_1111_1111_1111 /*ports_mask */, 32'b0000_1111_0000_1111 /* ports_egress */,32'b1001_1111_1111_1111 /* ports_ingress   */); 

        // first link aggregation of ports 4-7
        // received FEC msg of class 0 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0001 /* pattern_match*/,'h4 /* mode */, 
                               32'b0000_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_0001_0000 /* ports_egress */,32'b0000_0000_1111_0000 /* ports_ingress   */);    
        // received FEC msg of class 1
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0010 /* pattern_match*/,'h4 /* mode */, 
                               32'b0000_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_0010_0000 /* ports_egress */,32'b0000_0000_1111_0000 /* ports_ingress   */); 
        // received FEC msg of class 2 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0100 /* pattern_match*/,'h4 /* mode */, 
                               32'b0000_0000_1111_0000  /*ports_mask */, 32'b0000_0000_0100_0000 /* ports_egress */,32'b0000_0000_1111_0000 /* ports_ingress   */); 
        // received FEC msg of class 3
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  4  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_1000 /* pattern_match*/,'h4 /* mode */, 
                               32'b0000_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_1000_0000 /* ports_egress */,32'b0000_0000_1111_0000 /* ports_ingress   */);        

        // second link aggregation of ports 12 & 15
        // received FEC msg of class 0 & 1
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  5  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0011 /* pattern_match*/,'h4 /* mode */, 
                               32'b1001_0000_0000_0000 /*ports_mask  */, 32'b1000_0000_0000_0000 /* ports_egress */,32'b1001_0000_0000_0000 /* ports_ingress   */);    
        // received FEC msg of class 2 & 3 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  6  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_1100 /* pattern_match*/,'h4 /* mode */, 
                               32'b1001_0000_0000_0000  /*ports_mask */, 32'b0001_0000_0000_0000 /* ports_egress */,32'b1001_0000_0000_0000 /* ports_ingress   */); 

        tru_drv.pattern_config(4 /*replacement : use distributioon funciton defined by aggr_df_id */, 
                               5 /*addition    : simple mask reflecting on which port frame was rx-ed*/, 
                               5 /*subtraction*/); 
        end
      else if(tru_config_opt == 9) // LACP -> problematic - does not work - to be debugged
        begin
        
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  0  /* subentry_addr*/,
                               32'b0000_0000_0000_0000 /*pattern_mask*/,32'b0000_0000_0000_0000 /* pattern_match*/,'h0 /* mode */, 
                               32'b1001_1111_1111_1111  /*ports_mask */, 32'b0000_1111_0000_1111  /* ports_egress */,32'b1001_1111_1111_1111 /* ports_ingress   */); 

        // a bunch of link aggregation ports (ports 4 to 7 and 12&15)
        // received FEC msg of class 0 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0001 /* pattern_match*/,'h0 /* mode */, 
                               32'b0001_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_0001_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */);    
        // received FEC msg of class 1
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0010 /* pattern_match*/,'h0 /* mode */, 
                               32'b0001_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_0010_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 
        // received FEC msg of class 2 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0100 /* pattern_match*/,'h0 /* mode */, 
                               32'b1000_0000_1111_0000  /*ports_mask */, 32'b0000_0000_0100_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 
        // received FEC msg of class 3
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  4  /* subentry_addr*/,
                               32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_1000 /* pattern_match*/,'h0 /* mode */, 
                               32'b1000_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_1000_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */);        

        // a bunch of link aggregation ports (ports 4 to 7 and 12&15)
        // received FEC msg of class 0 & 1
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  5  /* subentry_addr*/,
                               32'b0000_0000_1111_0000 /*pattern_mask*/, 32'b0000_0000_1111_0000 /* pattern_match*/,'h5 /* mode */, 
                               32'b0000_0000_1111_0000 /*ports_mask  */, 32'b0000_0000_1111_0000 /* ports_egress */,32'b0000_0000_0000_0000 /* ports_ingress   */);    
        // received FEC msg of class 2 & 3 
        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  6  /* subentry_addr*/,
                               32'b1001_0000_0000_0000 /*pattern_mask*/, 32'b1001_0000_0000_0000 /* pattern_match*/,'h5 /* mode */, 
                               32'b1001_0000_0000_0000  /*ports_mask */, 32'b1001_0000_0000_0000 /* ports_egress */,32'b0000_0000_0000_0000 /* ports_ingress   */); 

        tru_drv.pattern_config(4 /*replacement : use distributioon funciton defined by aggr_df_id */, 
                               5 /*addition    : simple mask reflecting on which port frame was rx-ed*/, 
                               5 /*subtraction*/); 
        end
      else if(tru_config_opt == 10) // test VID bug
        begin
        int i =0;
        for(i=0;i<18;i++)
          tru_drv.write_tru_tab(  1   /* valid     */,   i  /* entry_addr   */,  0  /* subentry_addr*/,
                                 32'h00000000 /*pattern_mask*/, 32'h00000000 /* pattern_match*/,'h0 /* mode */, 
                                 32'hFFFFFFFF  /*ports_mask */, 32'hFFFFFFFF /* ports_egress */, 32'hFFFFFFFF /* ports_ingress*/); 
        end
      else // default config == 0
        begin
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h0 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b111000000010100001 /* ports_egress */,32'b111000000010100001 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0 /* mode */,
                               32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
        end



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
        tru_drv.transition_config(0 /*mode */,     1 /*rx_id*/,     1 /*prio mode*/, 0 /*prio*/, 
                                 20 /*time_diff*/, 0 /*port_a_id*/, 1 /*port_b_id*/);
      else if(tru_config_opt == 3)
        tru_drv.transition_config(0 /*mode */,     1 /*rx_id*/,     0 /*prio mode*/, 0 /*prio*/, 
                                  100 /*time_diff*/,1 /*port_a_id*/, 2 /*port_b_id*/);
      
      if(tru_config_opt == 4 || tru_config_opt == 5)
        begin 
          tru_drv.rt_reconf_config(1 /*tx_frame_id*/, 1/*rx_frame_id*/, 1 /*mode*/);
          tru_drv.hw_frame_config(1/*tx_fwd_id*/, 1/*rx_fwd_id*/, 1/*tx_blk_id*/, 2 /*rx_blk_id*/);
          tru_drv.rt_reconf_enable();        
        end       
      if(tru_config_opt == 6)
        begin 
          tru_drv.rt_reconf_config(1 /*tx_frame_id*/, 1/*rx_frame_id*/, 1 /*mode*/);
          tru_drv.hw_frame_config(1/*tx_fwd_id*/, 1/*rx_fwd_id*/, 1/*tx_blk_id*/, 2 /*rx_blk_id*/);
          tru_drv.rt_reconf_enable();        
        end 

      tru_drv.tru_swap_bank();  
      
      if(g_tru_enable)
         tru_drv.tru_enable();
//       tru_drv.tru_port_config(0);
      $display("TRU configured and enabled");
      $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
   endtask; //init_tru
   
   initial begin
      uint64_t msr;
      int seed;
      rtu_vlan_entry_t def_vlan;
      int q;
      int z;
      
      CWishboneAccessor cpu_acc = DUT.cpu.get_accessor();
      
      for(int gg=0;gg<g_num_ports;gg++) 
      begin 
        ep_ctrl[gg] = 'b1; 
      end
      
      repeat(200) @(posedge clk_sys);

      $display("Startup!");
      
      cpu_acc.set_mode(PIPELINED);
      cpu_acc.write('h10304, (1<<3));
      
      // pps_gen for time code for Time-Aware Traffic Shaper
      if(g_enable_WRtime == 1)
      begin
        cpu_acc.write('h10500, (1<<1)); // enable pps_gen counter
        cpu_acc.write('h1051c, (1<<2)); // tm_valid HIGH
      end
      
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
        rtu.set_port_config(dd /*port ID*/, portRtuEnabled[dd] /*pass_all*/, 0 /*pass_bpdu*/, 1 /*learn_en*/);
      end
        
        //
      rtu.set_port_config(g_num_ports, 1, 0, 0); // for NIC
      
      rtu.add_static_rule('{'h01, 'h80, 'hc2, 'h00, 'h00, 'h00}, (1<<18));
      rtu.add_static_rule('{'h01, 'h80, 'hc2, 'h00, 'h00, 'h01}, (1<<18));
      rtu.add_static_rule('{'h01, 'h80, 'hc2, 'h00, 'h00, 'h02}, (1<<18));
      rtu.add_static_rule('{'h01, 'h1b, 'h19, 'h00, 'h00, 'h00}, (1<<18)); // PTP
      
      rtu.add_static_rule('{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF}, 'hFFFFFFFF /*mask*/, 0 /*FID*/);
      
      if(g_LACP_scenario == 2)
        begin
          for(int i = 0;i<LACPdistro.distPortN;i++)
            rtu.add_static_rule('{0,2,i,4,5,6}, (1<<LACPdistro.distr[i]));
        end
      else
        begin  
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
        end

      
      

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
      rtu.rx_add_ff_mac_single(1/*ID*/,1/*valid*/,'h111111111111 /*MAC*/);
      rtu.rx_add_ff_mac_single(2/*ID*/,1/*valid*/,'h0150cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_single(3/*ID*/,1/*valid*/,'h0050cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_range (0/*ID*/,1/*valid*/,'h0050cafebabe /*MAC_lower*/,'h0850cafebabe/*MAC_upper*/);
//       rtu.rx_set_port_mirror  ('h00000002 /*mirror_src_mask*/,'h00000080 /*mirror_dst_mask*/,1/*rx*/,1/*tx*/);
      rtu.rx_set_port_mirror  (mirror_src_mask, mirror_dst_mask,mr_rx, mr_tx);
      rtu.rx_set_hp_prio_mask (hp_prio_mask /*hp prio mask*/);
//       rtu.rx_set_hp_prio_mask ('b10000001 /*hp prio mask*/); //HP traffic set to 7th priority
//       rtu.rx_set_cpu_port     ((1<<g_num_ports)/*mask: virtual port of CPU*/);
      rtu.rx_read_cpu_port(); 
      if(rx_forward_on_fmatch_full)
        rtu.rx_forward_on_fmatch_full();
      else
        rtu.rx_drop_on_fmatch_full();
      rtu.rx_feature_ctrl(mr, mac_ptp , mac_ll, mac_single, mac_range, mac_br);
      rtu.rx_fw_to_CPU(hp_fw_cpu,unrec_fw_cpu);
      rtu.rx_feature_dbg(rtu_dbg_f_fast_match, rtu_dbg_f_full_match);
      
      ////////////////////////////////////////////////////////////////////////////////////////

      rtu.enable();
      $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
      ///TRU
      tru = new(cpu_acc, 'h56000,g_num_ports,1 /*enable debugging*/);      
      init_tru(tru);
      
      tatsu=new(cpu_acc, 'h57000);
      if(g_tatsu_config == 1)
        tatsu.drop_at_HP_enable();
      
      hwdu=new(cpu_acc, 'h59000);
      hwdu.dump_mpm_page_utilization(1);

      fork
        begin
          if(g_fw_to_cpu_scenario == 1)
          begin
            wait_cycles(1000);
            unrec_fw_cpu         = 1; // 
            rtu.rx_fw_to_CPU(hp_fw_cpu,unrec_fw_cpu);
          end
        end
      join_none
      
      fork
        begin
          if(g_traffic_shaper_scenario == 1)
          begin
            // initial settings
            tatsu.set_tatsu(8 /*pause quanta*/, 1 /*tm_tai*/, 1000 /*tm_cycles*/, 1/*prio_mask*/, 
                            3 /*port_mask   */,  100     /*repeat_cycles*/);
            tatsu.print_status();
             
            // wait for  it to start 
            wait_cycles(10000);
            
            // wrong settings - we should be at tai >=1, so tai=0 is wrong setting for sure
            tatsu.set_tatsu(8 /*pause quanta*/, 0 /*tm_tai*/, 1000 /*tm_cycles*/, 1/*prio_mask*/, 
                            3 /*port_mask   */,  100     /*repeat_cycles*/);
            // check that it says error
            tatsu.print_status();
             
            // set tm_valid LOW
            cpu_acc.write('h1051c, (0<<2)); // tm_valid LOW
            
            // new settings 
            wait_cycles(10);
            tatsu.set_tatsu(8 /*pause quanta*/, 2 /*tm_tai*/, 1000 /*tm_cycles*/, 'b10000000/*prio_mask*/, 
                            32'b1010100 /*port_mask   */,  100     /*repeat_cycles*/);
            tatsu.print_status();
             
            wait_cycles(15000); // we should be already after the time specifid
            // set tm_valid HIGH again
            cpu_acc.write('h1051c, (1<<2)); // tm_valid HIGH
            
            wait_cycles(5000); 
            // test re-sync
            cpu_acc.write('h1051c, (0<<2)); // tm_valid HIGH
            wait_cycles(15000); 
            cpu_acc.write('h1051c, (1<<2)); // tm_valid HIGH
            wait_cycles(500); 
            cpu_acc.write('h1051c, (0<<2)); // tm_valid HIGH
            wait_cycles(50000); 
          end
          if(g_traffic_shaper_scenario == 2)
          begin          
          
            tatsu.set_tatsu(50                     /* pause quanta                  */,
                            0 , 7000               /* start time: tm_tai, tm_cycles */ ,
                            8'b10000000            /* prio_mask                     */, 
                            32'b111111111111111111 /* port_mask                     */,  
                            8000                   /* repeat_cycles                 */);
            tatsu.print_status();          
          
          end
        end
      join_none
      
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
             wait_cycles(600);
             tru.tru_swap_bank();  
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
           if(g_failure_scenario == 6 || g_failure_scenario == 7)
           begin 
             wait_cycles(500);
             ep_ctrl[0] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> links 0 <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             if(g_failure_scenario == 7)
             begin
               wait_cycles(500);
               hp_fw_cpu = 1;
               rtu.rx_fw_to_CPU(hp_fw_cpu,unrec_fw_cpu);
             end
           end   
           if(g_failure_scenario == 8)
           begin 
             wait_cycles(2010);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(600);
             /* port 1 is backup for port 2*/
             tru.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,'h000 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b1100_0111 /* ports_egress */,32'b1100_0101 /* ports_ingress   */);

             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               32'b00000110 /*pattern_mask*/, 32'b00000100 /* pattern_match*/,'h000 /* mode */, 
                               32'b00000110 /*ports_mask  */, 32'b00000110 /* ports_egress */,32'b00000010 /* ports_ingress   */); 
             tru.tru_swap_bank();  
             wait_cycles(600);
             ep_ctrl[g_active_port] = 'b1;
           end       
           if(g_failure_scenario == 9)
           begin 
             wait_cycles(2030);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(50);
             ep_ctrl[g_active_port] = 'b1;
             wait_cycles(50);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             wait_cycles(100);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(50);
             ep_ctrl[g_active_port] = 'b1;
             wait_cycles(50);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             wait_cycles(100);
             hwdu.dump_mpm_page_utilization(1);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(50);
             ep_ctrl[g_active_port] = 'b1;
             wait_cycles(50);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             wait_cycles(100);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(50);
             ep_ctrl[g_active_port] = 'b1;
             wait_cycles(50);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             wait_cycles(100);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(50);
             ep_ctrl[g_active_port] = 'b1;
             wait_cycles(50);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             wait_cycles(100);
             hwdu.dump_mpm_page_utilization(1);
           end  
           if(g_failure_scenario == 10)
           begin 
             int thrash_cnt = 1;
             wait_cycles(2030);
             
             for(thrash_cnt=1;thrash_cnt<40;thrash_cnt++)
             begin
               ep_ctrl[g_active_port] = 'b0;  
               wait_cycles(thrash_cnt);
               ep_ctrl[g_active_port] = 'b1;  
               wait_cycles(thrash_cnt);
             end
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             hwdu.dump_mpm_page_utilization(1);

           end        
           if(g_failure_scenario == 11)
           begin 
             int thrash_cnt = 1;
             wait_cycles(2015);
             ep_ctrl[g_active_port] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(100);
             hwdu.dump_mpm_page_utilization(1);
             wait_cycles(1000);
             hwdu.dump_mpm_page_utilization(1);
             wait_cycles(1000);
             hwdu.dump_mpm_page_utilization(1);

           end  
         end 
      join_none; //


      fork
         begin
           if(g_LACP_scenario == 1 )
           begin 
             wait_cycles(200);
              $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> Link Aggregation for HP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             tx_distrib_test(seed,           /* seed    */
                             repeat_number,  /* n_tries */
                             1,              /* is_q    */
                             0,              /* unvid   */
                             ports,          /*  */
                             LACPdistro,       /* port distribution */ 
                             0);             /* option */
                                       

           end
           if(g_LACP_scenario == 3 )
           begin 
             wait_cycles(200);
              $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> Link Aggregation for HP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             tx_distrib_test(seed,           /* seed    */
                             repeat_number,  /* n_tries */
                             1,              /* is_q    */
                             0,              /* unvid   */
                             ports,          /*  */
                             LACPdistro,       /* port distribution */ 
                             5);             /* option */
                                       

           end
           else if(g_LACP_scenario == 2)
           begin
             wait_cycles(200);
              $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> Link Aggregation for HP <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             tx_distrib_test(seed,           /* seed    */
                             repeat_number,  /* n_tries */
                             1,              /* is_q    */
                             0,              /* unvid   */
                             ports,          /*  */
                             LACPdistro,       /* port distribution */ 
                             0);             /* option */
                             
             wait_cycles(200);                
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> Link Aggregation for Broadcast <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             tx_distrib_test(seed,           /* seed    */
                             repeat_number,  /* n_tries */
                             1,              /* is_q    */
                             0,              /* unvid   */
                             ports,          /*  */
                             LACPdistro,       /* port distribution */ 
                             1);             /* option */                

             wait_cycles(200);                
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> Link Aggregation for Unicast <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             tx_distrib_test(seed,           /* seed    */
                             repeat_number,  /* n_tries */
                             1,              /* is_q    */
                             0,              /* unvid   */
                             ports,          /*  */
                             LACPdistro,       /* port distribution */ 
                             2);             /* option */                



           end
         end 
      join_none; //

      fork
         begin
           int dd;
           if(g_transition_scenario == 1)
           begin 
             wait_cycles(200);
             //program other bank with alternate config
             tru.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                               32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,  'h0 /* mode */, 
                               32'h3FFFF /*ports_mask  */, 32'b1000_0111 /* ports_egress */,32'b1000_0101 /* ports_ingress   */);

             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                            32'b00000110 /*pattern_mask*/, 32'b0100 /* pattern_match*/,'h0 /* mode */,
                            32'b00000110 /*ports_mask  */, 32'b1000_0111 /* ports_egress */,32'b1000_0011 /* ports_ingress   */);
             // enable transition
             tru.transition_enable();
             wait_cycles(200);

             // send normal stuff
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[0].send /* src     */, 
                     ports[7].recv /* sink    */,  
                     0             /* srcPort */ , 
                     7             /* dstPort */, 
                     4             /*option=4 */);  
             wait_cycles(200);
             //send some crap - is to be blocked by the port and counted
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);     
             wait_cycles(200);
             //send some crap - is to be blocked by the port and counted
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[2].send /* src     */, 
                     ports[2].recv /* sink    */,  
                     2             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);     
             wait_cycles(200);
             //sent marker to port 1
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[2].send /* src     */, 
                     ports[2].recv /* sink    */,  
                     2             /* srcPort */ , 
                     0             /* dstPort */, 
                     101             /*option=4 */);     
             //send some crap - is to be blocked by the port and counted
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[2].send /* src     */, 
                     ports[2].recv /* sink    */,  
                     2             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);     

              //send some crap - is to be blocked by the port and counted
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[2].send /* src     */, 
                     ports[2].recv /* sink    */,  
                     2             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);             

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
             wait_cycles(200);
             
             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);     

             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);    


             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     201             /*non-blocking => does not wait for reception */);     

             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     201    /*non-blocking => does not wait for reception */); 
             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[2].send /* src     */, 
                     ports[2].recv /* sink    */,  
                     2             /* srcPort */ , 
                     0             /* dstPort */, 
                     201    /*non-blocking => does not wait for reception */); 
             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[1].send /* src     */, 
                     ports[1].recv /* sink    */,  
                     1             /* srcPort */ , 
                     0             /* dstPort */, 
                     201    /*non-blocking => does not wait for reception */); 
             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[2].send /* src     */, 
                     ports[2].recv /* sink    */,  
                     2             /* srcPort */ , 
                     0             /* dstPort */, 
                     201    /*non-blocking => does not wait for reception */); 
             //send some crap - it should be forwarded/counted before transition
             tx_test(seed                         /* seed    */, 
                     1                 /* n_tries */, 
                     0                    /* is_q    */, 
                     0                             /* unvid   */, 
                     ports[0].send /* src     */, 
                     ports[0].recv /* sink    */,  
                     0             /* srcPort */ , 
                     0             /* dstPort */, 
                     201    /*non-blocking => does not wait for reception */); 
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> transition 0  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");

             for(dd=0;dd<8;dd++)
               tru.ep_debug_read_pfilter(dd);

             wait_cycles(10);
             tru.ep_debug_clear_pfilter(1);
             wait_cycles(10);
             tru.ep_debug_read_pfilter(1);
             wait_cycles(10);
             tru.ep_debug_inject_packet(3,'h1234,1);
             wait_cycles(10);
             tru.ep_debug_inject_packet(4,'h1234,0);
             wait_cycles(100);
             tru.ep_debug_inject_packet(4,'hFFFF,1);
             wait_cycles(100);
             tru.ep_debug_inject_packet(4,'h1234,0);
             wait_cycles(10);
             tru.ep_debug_inject_packet(3,'h4321,0);
             wait_cycles(10);

           end
           
           if(g_transition_scenario == 2)
           begin 
             wait_cycles(200);
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> PAUSE  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             //program other bank with alternate config
             tx_special_pck(ports[3].send,PAUSE /*opt*/,14/*pause time*/);     
                    
           end
           if(g_transition_scenario == 3)
           begin 
             // send normal stuff
             fork
               begin 
                 tx_test(seed                         /* seed    */, 
                         5                 /* n_tries */, 
                         0                    /* is_q    */, 
                         0                             /* unvid   */, 
                         ports[0].send /* src     */, 
                         ports[7].recv /* sink    */,  
                         0             /* srcPort */ , 
                         7             /* dstPort */, 
                         4             /*option=4 */);             
                 end 
               begin 
                 tx_test(seed                         /* seed    */, 
                         5                 /* n_tries */, 
                         0                    /* is_q    */, 
                         0                             /* unvid   */, 
                         ports[1].send /* src     */, 
                         ports[5].recv /* sink    */,  
                         0             /* srcPort */ , 
                         5             /* dstPort */, 
                         4             /*option=4 */);             
               end 
             join
             fork
               begin 
                 $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLOSE / OPEN  port 0<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
                 tx_special_pck(ports[0].send,BPDU_0 /*opt*/);  
               end
               begin
                 wait_cycles(20);
                 $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> CLOSE / OPEN  port 1<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
                 tx_special_pck(ports[1].send,BPDU_0 /*opt*/);  
               end
             join  
             fork
               begin 
                 tx_test(seed                         /* seed    */, 
                         5                 /* n_tries */, 
                         0                    /* is_q    */, 
                         0                             /* unvid   */, 
                         ports[0].send /* src     */, 
                         ports[7].recv /* sink    */,  
                         0             /* srcPort */ , 
                         7             /* dstPort */, 
                         4             /*option=4 */);             
                 end 
               begin 
                 tx_test(seed                         /* seed    */, 
                         5                 /* n_tries */, 
                         0                    /* is_q    */, 
                         0                             /* unvid   */, 
                         ports[1].send /* src     */, 
                         ports[5].recv /* sink    */,  
                         0             /* srcPort */ , 
                         5             /* dstPort */, 
                         4             /*option=4 */);             
               end 
             join
                  
           end
           if(g_transition_scenario == 4)
           begin 
             wait_cycles(9000);
             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  0  /* subentry_addr*/,
                                   32'b0000_0000_0000_0000 /*pattern_mask*/,32'b0000_0000_0000_0000 /* pattern_match*/,'h0 /* mode */, 
                                   32'b0000_1111_0000_1111 /*ports_mask */, 32'b0000_1111_0000_1111 /* ports_egress */,32'b0000_1111_0000_1111 /* ports_ingress   */); 
     
             // a bunch of link aggregation ports (ports 4 to 7 and 12&15)
             // received FEC msg of class 0 
             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                                   32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0001 /* pattern_match*/,'h0 /* mode */, 
                                   32'b1001_0000_1111_0000 /*ports_mask  */, 32'b1000_0000_0001_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */);    
             // received FEC msg of class 1
             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                                   32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0010 /* pattern_match*/,'h0 /* mode */, 
                                   32'b1001_0000_1111_0000 /*ports_mask  */, 32'b1000_0000_0010_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 
             // received FEC msg of class 2 
             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                                   32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_0100 /* pattern_match*/,'h0 /* mode */, 
                                   32'b1001_0000_1111_0000  /*ports_mask */, 32'b0001_0000_1000_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */); 
             // received FEC msg of class 3
             tru.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  4  /* subentry_addr*/,
                                   32'b0000_0000_0000_1111 /*pattern_mask*/, 32'b0000_0000_0000_1000 /* pattern_match*/,'h0 /* mode */, 
                                   32'b1001_0000_1111_0000 /*ports_mask  */, 32'b0001_0000_1000_0000 /* ports_egress */,32'b1001_0000_1111_0000 /* ports_ingress   */);        

             tru.transition_config(1 /*mode */,     4 /*rx_id*/,     0 /*prio mode*/, 7 /*prio*/, 
                                  1000 /*time_diff*/,6 /*port_a_id*/, 7 /*port_b_id*/);
             
             tru.transition_enable();

             wait_cycles(4000);

             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> MARKER  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             
             tx_special_pck(ports[6].send,MARKER /*opt*/,2/*response*/);     
                    
           end
         end 
      join_none; //

      fork
         begin
           if(g_test_inj_gen == 1)
           begin 
             wait_cycles(400);
             ports[2].ep.inject_gen_ctrl_enable();
             wait_cycles(4000);
             ports[2].ep.inject_gen_ctrl_disable();
             wait_cycles(4000);
             ports[2].ep.inject_gen_ctrl_enable();
             wait_cycles(4000);
             ports[2].ep.inject_gen_ctrl_disable();
           end
           if(g_test_inj_gen == 2)
           begin 
             wait_cycles(400);
             ports[2].ep.inject_gen_ctrl_enable();
             wait_cycles(500);
             ports[2].ep.inject_gen_ctrl_mode(1);
             wait_cycles(500);
             ports[2].ep.inject_gen_ctrl_mode(0);
             wait_cycles(500);
             ports[2].ep.inject_gen_ctrl_disable();
             wait_cycles(1000);
             ports[2].ep.inject_gen_ctrl_enable();
             wait_cycles(1000);
             ports[2].ep.inject_gen_ctrl_disable();
           end
         end 
      join_none; //


      for(q=0; q<g_max_ports; q++)
        fork
          automatic int qq=q;
          begin
          if(portUnderTest[qq]) 
            begin 
              wait_cycles(start_send_init_delay[qq]);
              for(int g=0;g<tries_number;g++)
                begin
                  $display("Try port_%d:%d", qq, g);
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
                txrx_done[qq]=1;
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

      fork // sending of PTP announce messages from NIC
         begin
           if(g_send_announce_from_NIC > 0)
           begin 
             ptpAnnounce.tx_wr_port = 0;
             wait_cycles(400);
             for (int i =0;i<g_send_announce_from_NIC;i++)
             begin
                 for(int j = 0;j<g_num_ports;j++)
                 begin
                    wait_cycles(400);
                    ptpAnnounce.tx_wr_port = j;         // port to send
                    ptpAnnounce.payload[30]=  i % 'hFF; // seqID 1
                    ptpAnnounce.payload[31]= 'h00;      // seqID 2
                    ports[18].send.send(ptpAnnounce); //nic
                 end
             end

           end
         end 
      join_none; //

   end 

  /* ***************************************************************************************
   *           Page allocator and resource manager debugging
   * ***************************************************************************************
   * this stuff is used to debug allocator and resource manager - it is very slow and has 
   * static tables which causes simulation to crash if we run it tooo long 
   * uncomment only if debugging allocator
   * ***************************************************************************************
     
   initial begin
     int q =0;
     while(!rst_n) @(posedge clk_sys);
     
     if(g_simple_allocator_unicast_check) 
     forever begin      
       for(q=0;q<g_max_ports;q++) begin
         if(portUnderTest[q]) begin 
           if(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.alloc_done_o[q])
             mmu_alloc_cnt[q]++;
           if(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.set_usecnt_done_o[q])
             mmu_usecnt_cnt[q]++;              
           if(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.free_done_o[q])
             mmu_free_cnt[q]++; 
           if(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.force_free_done_o[q])
             mmu_f_free_cnt[q]++;
         end //if
       end // for
       @(posedge clk_sys);
     end //forever
   end //initial begin
        

   initial begin 
     int l = 0;
     int pg_cnt =0;
     while(!rst_n) @(posedge clk_sys);
     while(txrx_done != portUnderTest || g_transition_scenario != 0) @(posedge clk_sys);
     wait_cycles(100);
     while(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.free_pages < 985) @(posedge clk_sys);
     $display("free pages: %4d",DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.free_pages);
     if(!g_simple_allocator_unicast_check) 
     begin
       wait_cycles(2000);// wait so we can do other stuff (i.e. display the other alloc check
       $stop; //$finish; // finish sim
     end
     if(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.g_with_RESOURCE_MGR) begin
       $display("unknown: %4d",DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.dbg_o[9 : 0]);
       $display("special: %4d",DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.dbg_o[19:10]);
       $display("normal : %4d",DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.dbg_o[29:20]);
     end
     $display("------------------- this check works only for unicast traffic ------------------------");
     for(l=0;l<g_max_ports+1;l++) 
       begin
         pg_cnt = mmu_alloc_cnt[trans_paths[l].tx]-mmu_f_free_cnt[trans_paths[l].tx]-mmu_free_cnt[trans_paths[l].rx];
         if(pg_cnt == 2) // very simple sanity check
           $display("CNT: tx_port=%2d: alloc=%3d; usecnt=%3d; force free=%3d | rx_port=%2d: free=%3d [OK]",trans_paths[l].tx, mmu_alloc_cnt[trans_paths[l].tx], mmu_usecnt_cnt[trans_paths[l].tx],mmu_f_free_cnt[trans_paths[l].tx], trans_paths[l].rx, mmu_free_cnt[trans_paths[l].rx]);         
         else
           $display("CNT: tx_port=%2d: alloc=%3d; usecnt=%3d; force free=%3d | rx_port=%2d: free=%3d [--]",trans_paths[l].tx, mmu_alloc_cnt[trans_paths[l].tx], mmu_usecnt_cnt[trans_paths[l].tx],mmu_f_free_cnt[trans_paths[l].tx], trans_paths[l].rx, mmu_free_cnt[trans_paths[l].rx]);         
       end//if
     $display("------------------- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ------------------------");
   end //initla begin


   initial begin 
     int l = 0;
     int pg_cnt =0;
     init_alloc_tab();
     while(!rst_n) @(posedge clk_sys);    
     forever begin
     alloc_check(
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.done_alloc_o,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.done_usecnt_o,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.done_free_o,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.done_force_free_o,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.alloc_req_d1.usecnt_alloc,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.alloc_req_d1.usecnt_set,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.alloc_req_d1.pgaddr_free,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.alloc_req_d1.pgaddr_usecnt,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.pgaddr_o,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.rsp_vec_o
                );
     @(posedge clk_sys);    
     end
   end //initla begin

   initial begin 
     int l = 0;
     int pg_cnt =0;
     init_alloc_tab();
     while(!rst_n) @(posedge clk_sys);    
     while(txrx_done != portUnderTest || g_transition_scenario != 0) @(posedge clk_sys);
     wait_cycles(1000);
     while(DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.MEMORY_MANAGEMENT_UNIT.ALLOC_CORE.free_pages < 985) @(posedge clk_sys);
     wait_cycles(1000);
     dump_results(
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.dbg_pckstart_pageaddr,
                DUT.U_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.dbg_pckinter_pageaddr);     

     $stop;  
   end //initla begin
   */

endmodule // main

