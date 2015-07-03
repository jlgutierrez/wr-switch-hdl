`timescale 1ns/1ps

`include "tbi_utils.sv"
`include "simdrv_wrsw_nic.svh"
`include "simdrv_rtu.sv"
`include "simdrv_txtsu.svh"
`include "simdrv_hwdu.svh"
`include "simdrv_wdog.svh"
`include "endpoint_regs.v"
`include "endpoint_mdio.v"
`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"
`include "scb_top_sim_svwrap.svh"
`include "pfilter.svh"
`include "alloc.svh"

module main;

   reg clk_ref=0;
   reg clk_sys=0;
   reg clk_swc_mpm_core=0;
   reg rst_n=0;
   parameter g_max_ports = 8;   
   parameter g_num_ports = 8;
   parameter g_mvlan     = 9; //max simulation vlans

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
   int tb_wrd_cnt = 0;
   int tb_forced = 0;
   int tb_got_cyc = 0;
   int tb_rtu_cnt = 0;
   int tb_rtu_fsm = 0;
   
   port_t ports[$];
   CSimDrv_NIC nic;
   CRTUSimDriver rtu;
   CSimDrv_TXTSU txtsu;
   CSimDrv_HWDU hwdu;
   CSimDrv_WDOG wdog;
   
   reg [g_num_ports-1:0] ep_ctrl;
   reg [15:0]            ep_failure_type = 'h00;
   
   /** ***************************   basic conf  ************************************* **/ 
   integer g_enable_pck_gaps                  = 1;   // 1=TRUE, 0=FALSE
   integer g_min_pck_gap                      = 300; // cycles
   integer g_max_pck_gap                      = 300; // cycles
   integer g_force_payload_size               = 0; // if 0, then opt is used
   integer g_payload_range_min                = 63;
   integer g_payload_range_max                = 257;
   integer g_active_port                      = 0;
   integer g_backup_port                      = 1;
   integer g_is_qvlan                         = 1;  // has vlan header
   integer g_pfilter_enabled                  = 0;
   integer g_limit_config_to_port_num         = g_num_ports;

   t_trans_path trans_paths[g_max_ports]      ='{'{0  ,7 , 0 }, // port 0: 
                                                 '{1  ,6 , 0 }, // port 1
                                                 '{2  ,5 , 0 }, // port 2
                                                 '{3  ,4 , 0 }, // port 3
                                                 '{4  ,3 , 0 }, // port 4
                                                 '{5  ,2 , 0 }, // port 5
                                                 '{6  ,1 , 0 }, // port 6
                                                 '{7  ,0 , 0 }}; // port 7
                                         //index: 1,2,3,4,5,6,7,8,9, ....
   integer start_send_init_delay[g_max_ports] = '{0,0,0,0,0,0,0,0};
   //mask with ports we want to use, port number:  18 ...............0
   reg [g_max_ports-1:0] portUnderTest        = 8'b11111111; //
   reg [g_max_ports-1:0] portRtuEnabled       = 8'b11111111; //
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
                                              '{'{32'hFFFFFFFF, 8'h0, 3'h0, 1'b0, 1'b0, 1'b0}, 8,  1'b0 }};
   PFilterMicrocode mc                    = new;


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

   integer g_do_vlan_config                 = 1;

   integer g_set_untagging                  = 0;
   int lacp_df_hp_id                        = 0;
   int lacp_df_br_id                        = 2;
   int lacp_df_un_id                        = 1;
   int g_simple_allocator_unicast_check     = 0;

 /** ***************************   test scenario 62  ************************************* **/ 
  /*
   * test 100% (high) load for 2 streams of small frames
   **/
  //GD
  
  initial begin
    portUnderTest        = 8'b00000001;    
    g_enable_pck_gaps    = 0;
    g_min_pck_gap        = 0; //10;
    g_max_pck_gap        = 0; //10;
    repeat_number        = 20; //1000; //3000; //500000;
    tries_number         = 1;  
    g_force_payload_size = 1517; //696; //1517; //682; //46;  

    g_is_qvlan           = 0;
                         // tx  ,rx ,opt
    trans_paths[0]      = '{0  ,7 ,1};
    trans_paths[7]      = '{7  ,0 ,1};

    trans_paths[1]      = '{1  ,6 ,1};
    trans_paths[6]      = '{6  ,1 ,1};

    trans_paths[2]      = '{2  ,5 ,1};
    trans_paths[5]      = '{5  ,2 ,1};

    trans_paths[3]      = '{3  ,4 ,1};
    trans_paths[4]      = '{4  ,3 ,1};

  end

  /* check state machines of the swcore */
  //always @(posedge clk_sys) begin
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.trans_FSM == 4'h9)
  //    $warning("ll_FSM 0");
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[1].INPUT_BLOCK.trans_FSM == 4'h9)
  //    $warning("ll_FSM 1");
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[6].INPUT_BLOCK.trans_FSM == 4'h9)
  //    $warning("ll_FSM 6");
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[7].INPUT_BLOCK.trans_FSM == 4'h9)
  //    $warning("ll_FSM 7");
  //end

  //always @(negedge clk_sys) begin
  //  if (tb_forced==1) begin
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_stb_int = 0;
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_cyc_int = 0;
  //    //force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_cyc_d0 = 1;
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.in_pck_err = 0;
  //    //tb_forced = 2;
  //  end
  //  //else if (tb_forced==2) begin
  //  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_cyc_d0 = 0;
  //  //end
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.endpoint_src_out[0].cyc == 0 && tb_forced>0) begin
  //    release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_stb_int;
  //    release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_cyc_int;
  //    //release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_cyc_d0;
  //    release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_ack_int;
  //    tb_forced = 0;
  //  end
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_cyc_int == 1'h0 && tb_wrd_cnt==3) begin
  //    tb_wrd_cnt = 0;
  //    release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.in_pck_err;
  //  end
  //  else begin
  //    //we are inside the frame
  //    if(tb_wrd_cnt<3 && DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.page_word_cnt == 64)
  //      tb_wrd_cnt = tb_wrd_cnt + 1;
  //    if(tb_wrd_cnt == 3 && DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.page_word_cnt == 63) begin
  //    //if(tb_wrd_cnt == 3 && DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.page_word_cnt == 53) begin
  //      force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.in_pck_err = 1;
  //      force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.snk_ack_int= 1;
  //      tb_forced = 1;
  //    end
  //  end
  //end

  /////////////////////////////////////////////////////////////////////////

  //always @(negedge clk_sys) begin
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.endpoint_src_out[0].cyc == 1 && tb_got_cyc == 0) begin
  //    tb_got_cyc = 1;
  //    tb_wrd_cnt = 0;
  //  end
  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.endpoint_src_out[0].cyc == 0 && tb_got_cyc==1) begin
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.gen_endpoints_and_phys[0].U_Endpoint_X.U_Wrapped_Endpoint.src_in.stall = 1;
  //    tb_wrd_cnt = tb_wrd_cnt + 1;
  //    if(tb_wrd_cnt == 365) begin
  //      force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.gen_endpoints_and_phys[0].U_Endpoint_X.U_Wrapped_Endpoint.src_in.stall = 0;
  //      release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.gen_endpoints_and_phys[0].U_Endpoint_X.U_Wrapped_Endpoint.src_in.stall;
  //      tb_got_cyc = 2;
  //    end
  //  end


  //  if (tb_rtu_fsm == 3)
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rtu_rsp_valid_i = 0;
  //  if (tb_rtu_fsm == 2) begin
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rtu_rsp_valid_i = 1;
  //    if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rtu_rsp_ack_o == 1)
  //      tb_rtu_fsm = 3;
  //  end
  //  else if (tb_rtu_cnt > 1) begin
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rtu_dst_port_mask_i = 0;
  //    force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rtu_rsp_valid_i = 0;
  //    if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rcv_p_FSM == 1)
  //      tb_rtu_fsm = 1;
  //    if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rcv_p_FSM == 3)
  //      tb_rtu_fsm = 2;
  //  end

  //  if (DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.rtu_rsp_ack)
  //    tb_rtu_cnt = tb_rtu_cnt + 1;
  //end

  //initial begin
  //  //#67608ns
  //  //#66616ns
  //  #66632ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.mmu_page_alloc_done_i = 0;
  //  #944ns
  //  //#1000ns --> check this as well !!
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.mmu_page_alloc_done_i = 1;
  //  #16ns
  //  release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.gen_blocks[0].INPUT_BLOCK.mmu_page_alloc_done_i;
  //end

  //addition
  //initial begin
  //  #125us;
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.PCK_PAGES_FREEEING_MODULE.lpd_gen[0].LPD.dbg_sv_force = 1;
  //  #335us;
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_Swcore.PCK_PAGES_FREEEING_MODULE.lpd_gen[0].LPD.dbg_sv_force = 0;
  //end

  /////////////////////////////////////////////////////////////////////////

  // Trying to reproduce RTU hanging bug
  //initial begin
  //  #1ns  //shift because SV code is executed before VHDL so I need to make sure that whatever I force here
  //        //will be visible for VHDL on next clk cycle.
  //  #51832ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 0;
  //  //RTU req
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rq_i.valid = 1;
  //  #16ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rq_i.valid = 0;
  //  release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rq_i.valid;
  //  #240ns
  //  //#208ns
  //  //RTU req
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rq_i.valid = 1;
  //  #16ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rq_i.valid = 0;
  //  release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rq_i.valid;
  //  //66072
  //  //finally let's ack
  //  #13968ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 1;
  //  #16ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 0;

  //  //ack
  //  #64ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 1;
  //  #16ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 0;

  //  //ack
  //  #64ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 1;
  //  #16ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i = 0;

  //  release DUT.WRS_Top.U_Wrapped_SCBCore.gen_network_stuff.U_RTU.ports[0].U_PortX.rtu_rsp_ack_i;
  //end

  /////////////////////////////////////////////////////////////////////////

  // Trying with the watchdog reset
  //initial begin
  //  //#203247ns
  //  //force DUT.WRS_Top.U_Wrapped_SCBCore.reset_mode = 1;
  //  //force DUT.WRS_Top.U_Wrapped_SCBCore.reset_mode2 = 1;
  //  //#100ns
  //  //force DUT.WRS_Top.U_Wrapped_SCBCore.reset_mode = 0;
  //  //#40us
  //  //force DUT.WRS_Top.U_Wrapped_SCBCore.reset_mode2 = 0;
  //  //release DUT.WRS_Top.U_Wrapped_SCBCore.reset_mode;
  //  //release DUT.WRS_Top.U_Wrapped_SCBCore.reset_mode2;

  //  #203247ns
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gpio_out_1 = 1;
  //  #40us
  //  force DUT.WRS_Top.U_Wrapped_SCBCore.gpio_out_1 = 0;
  //  release DUT.WRS_Top.U_Wrapped_SCBCore.gpio_out_1;
  //end

  initial begin
    #104us;
    //$display("---------------------------");
    //wdog.print_fsms(0);
    //$display("---------------------------");
    //wdog.print_fsms(0);
    //#10us;
    //$display("---------------------------");
    //wdog.print_fsms(0);
    #19us;
    wdog.force_reset();
  end

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
      else
        tmpl.dst       = '{'h00, 'h00, 'h00, 'h00, 'h00, 'h00}; // link-limited

        
      tmpl.has_smac  = 1;
      tmpl.pcp    = 0;  //priority
      tmpl.is_q      = is_q;
      tmpl.vid     = 0;
      tmpl.ethertype = 'h88f7;

      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD  | EthPacketGenerator::SEQ_ID);
      gen.set_template(tmpl);
      if(g_force_payload_size >= 1520) // more than max
        gen.set_size(64, 1500);
      else if(g_force_payload_size < 42)
        gen.set_size(g_payload_range_min, g_payload_range_max);
      else
        gen.set_size(g_force_payload_size, g_force_payload_size+1); // setting the precise size below
      
      fork
        begin // fork 1
          integer vid_cnt=0;
          for(int i=0;i<n_tries;i++) begin
            pkt  = gen.gen();

            if(g_force_payload_size >= 1520) // more than max
              $faltal("wrong g_force_payload_size with wrong opt param");
            else if(g_force_payload_size >= 42) // min size of frame is 64, 
              pkt.set_size(g_force_payload_size);

            pkt.oob = TX_FID;
            $display("|=> TX: port = %2d, pck_i = %4d (opt=%1d, pck_gap=%3d, size=%2d, n=%d)" , srcPort, i,opt,pck_gap,  pkt.payload.size, i);
            src.send(pkt);
            arr[i]  = pkt;
            //if(pck_gap)
            //  wait_cycles(pck_gap); 
          end
          tx_done = 1;
        end   // fork 1

        begin // fork 2
          if(g_ignore_rx_test_check == 0) begin
            //for(int j=0;j<n_tries;j++)
            while(1) begin
              sink.recv(pkt2);
              $display("|<= RX: port = %2d (size=%2d)" , dstPort, pkt2.payload.size);
              //$display("|<= RX: port = %2d, pck_i = %4d (size=%2d)" , dstPort, j,  pkt2.payload.size);
              //if(unvid)
              //  arr[j].is_q  = 0;
              //if((arr[j].payload.size != pkt2.payload.size) || !arr[j].equal(pkt2)) begin
              //  $display("Fault at %d", j);
              //  $display("Should be: ");
              //  arr[j].dump();
              //  $display("Is: ");
              //  pkt2.dump();
              //end
            end // for (i=0;i<n_tries;i++)
            rx_done = 1;
          end
        end // fork 2
      join
      seed = gen.get_seed();
      
   endtask // tx_test

   
  ///////////////////////////////////////////////////////
  ////////////////// DUT  ///////////////////////////////
  ///////////////////////////////////////////////////////
  scb_top_sim_svwrap #(
    .g_num_ports  (g_num_ports),
    .g_with_TRU   (0),
    .g_with_TATSU (0))
    DUT (
    .clk_sys_i(clk_sys),
    .clk_ref_i(clk_ref),
    .rst_n_i(rst_n),
    .cpu_irq(cpu_irq),
    .clk_swc_mpm_core_i(clk_swc_mpm_core),
    .ep_ctrl_i(ep_ctrl),
    .ep_failure_type(ep_failure_type)
  );
  ///////////////////////////////////////////////////////
  ///////////////////////////////////////////////////////
  ///////////////////////////////////////////////////////
  


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
        
      rtu.set_port_config(g_num_ports, 1, 0, 0); // for NIC
      
      rtu.add_static_rule('{'h01, 'h80, 'hc2, 'h00, 'h00, 'h00}, (1<<18));
      rtu.add_static_rule('{'h01, 'h80, 'hc2, 'h00, 'h00, 'h01}, (1<<18));
      rtu.add_static_rule('{'h01, 'h80, 'hc2, 'h00, 'h00, 'h02}, (1<<18));
      
      rtu.add_static_rule('{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF}, 'hFFFFFFFF /*mask*/, 0 /*FID*/);
      
      //GD if(portUnderTest[0])  rtu.add_static_rule('{7, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<7));
      //GD if(portUnderTest[1])  rtu.add_static_rule('{6, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<6));
      if(portUnderTest[2])  rtu.add_static_rule('{5, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<5));
      if(portUnderTest[3])  rtu.add_static_rule('{4, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<4));
      if(portUnderTest[4])  rtu.add_static_rule('{3, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<3));
      if(portUnderTest[5])  rtu.add_static_rule('{2, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<2));
      //GD if(portUnderTest[6])  rtu.add_static_rule('{1, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<1));
      //GD if(portUnderTest[7])  rtu.add_static_rule('{10, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<10));
      //if(portUnderTest[8])  rtu.add_static_rule('{ 9, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<9 ));
      //if(portUnderTest[9])  rtu.add_static_rule('{ 8, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<8 ));
      //if(portUnderTest[10]) rtu.add_static_rule('{ 7, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<7 ));
      //if(portUnderTest[11]) rtu.add_static_rule('{ 6, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<6 ));
      //if(portUnderTest[12]) rtu.add_static_rule('{ 5, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<5 ));
      //if(portUnderTest[13]) rtu.add_static_rule('{ 4, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<4 ));
      //if(portUnderTest[14]) rtu.add_static_rule('{ 3, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<3 ));
      //if(portUnderTest[15]) rtu.add_static_rule('{ 2, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<2 ));
      //if(portUnderTest[16]) rtu.add_static_rule('{ 1, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<1 ));
      //GD if(portUnderTest[17]) rtu.add_static_rule('{ 0, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<0  ));

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

      ///////////////////////////   RTU extension settings:  ////////////////////////////////
      
      rtu.rx_add_ff_mac_single(0/*ID*/,1/*valid*/,'h1150cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_single(1/*ID*/,1/*valid*/,'h111111111111 /*MAC*/);
      rtu.rx_add_ff_mac_single(2/*ID*/,1/*valid*/,'h0150cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_single(3/*ID*/,1/*valid*/,'h0050cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_range (0/*ID*/,1/*valid*/,'h0050cafebabe /*MAC_lower*/,'h0850cafebabe/*MAC_upper*/);
      rtu.rx_set_port_mirror  (mirror_src_mask, mirror_dst_mask,mr_rx, mr_tx);
      rtu.rx_set_hp_prio_mask (hp_prio_mask /*hp prio mask*/);
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
      
      hwdu=new(cpu_acc, 'h59000);
      hwdu.dump_mpm_page_utilization(1);

      wdog = new(cpu_acc, 'h5a000);

      ////////////// sending packest on all the ports (16) according to the portUnderTest mask.///////
      for(q=0; q<g_max_ports; q++)
        fork
          automatic int qq=q;
          begin
          if(portUnderTest[qq]) 
            begin 
              wait_cycles(start_send_init_delay[qq]);
              for(int g=0;g<tries_number;g++)
                begin
                  //$display("Try port_%d:%d", qq, g);
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
            nic.update(DUT.WRS_Top.U_Wrapped_SCBCore.vic_irqs[0]);
            @(posedge clk_sys);
         end
         forever begin
            txtsu.update(DUT.WRS_Top.U_Wrapped_SCBCore.vic_irqs[1]);
            @(posedge clk_sys);
         end
      join_none

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

