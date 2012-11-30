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



module main;

    typedef struct { 
       integer     tx;
       integer     rx;
       integer     op;
    }  t_trans_path;

   reg clk_ref=0;
   reg clk_sys=0;
   reg clk_swc_mpm_core=0;
   reg rst_n=0;
   parameter g_max_ports = 18;   
   parameter g_num_ports = 18;
   
   reg [g_num_ports-1:0] ep_ctrl;
   
   // prameters to create some gaps between pks (not work really well)
   // default settings
   
   /** ***************************   basic conf  ************************************* **/ 
   parameter g_enable_pck_gaps                = 1;   // 1=TRUE, 0=FALSE
   parameter g_min_pck_gap                    = 300; // cycles
   parameter g_max_pck_gap                    = 300; // cycles
   parameter g_failure_scenario               = 0;   // no link failure
   parameter g_tru_enable                     = 0;   //TRU disabled
                                        // tx  ,rx ,opt (send from port tx to rx with option opt
   t_trans_path trans_paths[g_max_ports]      ='{{0  ,17 , 0 }, // port 0: 
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
   integer repeat_number                      = 10;
   integer tries_number                       = 1;
   reg [31:0] vlan_port_mask                  = 32'hFFFFFFFF;
   bit mr                                     = 0;
   bit mac_ptp                                = 0;
   bit mac_ll                                 = 0;
   bit mac_single                             = 0;
   bit mac_range                              = 0;
   bit mac_br                                 = 0;
   
   /** ***************************   test scenarios  ************************************* **/ 
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
   
//   assign clk_ref = clk_sys;
   
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

      if(opt==3 || opt==4)
        tmpl.src       = '{0, 2,3,4,5,6};
      else
        tmpl.src       = '{srcPort, 2,3,4,5,6};

      if(opt==0)
        tmpl.dst       = '{dstPort, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==1)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF};      
      else if(opt==2)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h00};
      else if(opt==3)
        tmpl.dst       = '{17, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==3 | opt==4)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF};      

      tmpl.has_smac  = 1;
      tmpl.is_q      = is_q;
      tmpl.vid       = 100;
      tmpl.ethertype = 'h88f7;
  // 
      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD  | EthPacketGenerator::SEQ_ID);
      gen.set_template(tmpl);
      gen.set_size(63, 257);

      fork
      begin
      for(int i=0;i<n_tries;i++)
           begin
              pkt  = gen.gen();
              pkt.oob = TX_FID;
              
              $display("|=> TX: port = %2d, pck_i = %4d (opt=%1d, pck_gap=%3d)" , srcPort, i,opt,pck_gap);
              
              src.send(pkt);
              arr[i]  = pkt;
              //pkt.dump();
              repeat(60) @(posedge clk_sys);
              wait_cycles(pck_gap);
	  //    $display("Send: %d [dsize %d]", i+1,pkt.payload.size() + 14);
	      
           end
         end 
	begin
         for(int j=0;j<n_tries;j++)
           begin
           sink.recv(pkt2);
              $display("|<= RX: port = %2d, pck_i = %4d" , dstPort, j);
// 	      $display("rx %d at port %d", j,dstPort);
              //pkt2.dump();
           if(unvid)
             arr[j].is_q  = 0;
           
           if(!arr[j].equal(pkt2))
             begin
                $display("Fault at %d", j);
                $display("Should be: ");
                arr[j].dump();
                $display("Is: ");
                pkt2.dump();
                //$fatal("dupa"); //ML
           //sfp     $stop;
             end
           end // for (i=0;i<n_tries;i++)
           end
         join
      seed = gen.get_seed();

//       if(g_enable_pck_gaps == 1) 
//         wait_cycles($dist_uniform(seed,g_min_pck_gap,g_max_pck_gap));
      
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

      tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,    0 /* subentry_addr*/,
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h3FFFF /*ports_mask  */, 32'b111000000010100001 /* ports_egress */,32'b111000000010100001 /* ports_ingress   */);

      tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                             32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0  /* pattern_mode */,
                             32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);

//       tru_drv.write_tru_tab(  0   /* valid     */,     0 /* entry_addr   */,    1 /* subentry_addr*/,
//                              32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
//                              32'h00000 /*ports_mask  */, 32'h00000 /* ports_egress */, 32'h00000 /* ports_ingress   */);
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
      def_vlan.port_mask      = vlan_port_mask;
      def_vlan.fid            = 0;
      def_vlan.drop           = 0;
      def_vlan.prio           = 0;
      def_vlan.has_prio       = 0;
      def_vlan.prio_override  = 0;

      rtu.add_vlan_entry(0, def_vlan);

      ///////////////////////////   RTU extension settings:  ////////////////////////////////
      
      rtu.rx_add_ff_mac_single(0/*ID*/,1/*valid*/,'h1150cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_single(1/*ID*/,1/*valid*/,'h111111111111/*MAC*/);
      rtu.rx_add_ff_mac_range (0/*ID*/,1/*valid*/,'h0050cafebabe/*MAC_lower*/,'h0850cafebabe/*MAC_upper*/);
      rtu.rx_set_port_mirror  ('h00020000 /*mirror_src_mask*/,'h00000008 /*mirror_dst_mask*/,0/*rx*/,1/*tx*/);
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
             wait_cycles(5000);
             ep_ctrl[0] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
           end
           else if(g_failure_scenario == 2)
           begin
             wait_cycles(500);
             ep_ctrl[1] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 1 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(200);
             rtu.set_port_config(1, 0, 0, 1); // disable port 1
             wait_cycles(200);
             ep_ctrl[1] = 'b1;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 1 up <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
             wait_cycles(400);
             rtu.set_port_config(1, 1, 0, 1); // enable port 1
             wait_cycles(500);
             ep_ctrl[0] = 'b0;
             $display("");
             $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>> link 0 down <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
             $display("");
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
                          0                             /* is_q    */, 
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
   
`ifdef  0
         begin
         if(portUnderTest[0]) 
            begin 
               wait_cycles(start_send_init_delay[0]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_0:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[0].send /* src */, ports[17] .recv /* sink */,  0 /* srcPort */ , 11  /* dstPort */,tx_option[0]/*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[0].tx].send /* src     */, 
                            ports[trans_paths[0].rx].recv /* sink    */,  
                            trans_paths[0].tx             /* srcPort */ , 
                            trans_paths[0].rx             /* dstPort */, 
                            trans_paths[0].op             /*option=4 */);
                 end
            end   
         end // fork begin
         begin
         if(portUnderTest[1]) 
            begin 
//                wait_cycles(5);
               wait_cycles(start_send_init_delay[1]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_1:%d",  g);
                    // hacked
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[1].send /* src */, ports[16] .recv /* sink */,  1 /* srcPort */ , 16  /* dstPort */,tx_option[1]/*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[1].tx].send /* src     */, 
                            ports[trans_paths[1].rx].recv /* sink    */,  
                            trans_paths[1].tx             /* srcPort */ , 
                            trans_paths[1].rx             /* dstPort */, 
                            trans_paths[1].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[2]) 
            begin 
//                wait_cycles(5);
               wait_cycles(start_send_init_delay[2]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_2:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[2].send /* src */, ports[15] .recv /* sink */,  2 /* srcPort */ , 15  /* dstPort */,tx_option[2]  /*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[2].tx].send /* src     */, 
                            ports[trans_paths[2].rx].recv /* sink    */,  
                            trans_paths[2].tx             /* srcPort */ , 
                            trans_paths[2].rx             /* dstPort */, 
                            trans_paths[2].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[3]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[3]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_3:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[3].send /* src */, ports[14] .recv /* sink */,  3 /* srcPort */ , 14  /* dstPort */,tx_option[3] /*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[3].tx].send /* src     */, 
                            ports[trans_paths[3].rx].recv /* sink    */,  
                            trans_paths[3].tx             /* srcPort */ , 
                            trans_paths[3].rx             /* dstPort */, 
                            trans_paths[3].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[4]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[4]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_4:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[4].send /* src */, ports[13] .recv /* sink */,  4 /* srcPort */ , 13  /* dstPort */,tx_option[4] /*option*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[4].tx].send /* src     */, 
                            ports[trans_paths[4].rx].recv /* sink    */,  
                            trans_paths[4].tx             /* srcPort */ , 
                            trans_paths[4].rx             /* dstPort */, 
                            trans_paths[4].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[5]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[5]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_5:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[5].send /* src */, ports[12] .recv /* sink */,  5 /* srcPort */ , 12  /* dstPort */,tx_option[5] /*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[5].tx].send /* src     */, 
                            ports[trans_paths[5].rx].recv /* sink    */,  
                            trans_paths[5].tx             /* srcPort */ , 
                            trans_paths[5].rx             /* dstPort */, 
                            trans_paths[5].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[6]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[6]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_6:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[trans_paths[0].tx_port_id].send /* src */, ports[11] .recv /* sink */,  6 /* srcPort */ , 11  /* dstPort */,tx_option[6] /*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[6].tx].send /* src     */, 
                            ports[trans_paths[6].rx].recv /* sink    */,  
                            trans_paths[6].tx             /* srcPort */ , 
                            trans_paths[6].rx             /* dstPort */, 
                            trans_paths[6].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[7]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[7]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_7:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[7].send /* src */, ports[10] .recv /* sink */,  7 /* srcPort */ , 10  /* dstPort */,tx_option[7] /*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[7].tx].send /* src     */, 
                            ports[trans_paths[7].rx].recv /* sink    */,  
                            trans_paths[7].tx             /* srcPort */ , 
                            trans_paths[7].rx             /* dstPort */, 
                            trans_paths[7].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[8]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[8]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_8:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[8].send /* src */, ports[9] .recv /* sink */,  8 /* srcPort */ , 9  /* dstPort */,tx_option[8] /*option=4*/);                    tx_test(seed                          /* seed    */, 
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[8].tx].send /* src     */, 
                            ports[trans_paths[8].rx].recv /* sink    */,  
                            trans_paths[8].tx             /* srcPort */ , 
                            trans_paths[8].rx             /* dstPort */, 
                            trans_paths[8].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[9]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[9]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_9:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[9].send /* src */, ports[8] .recv /* sink */, 9 /* srcPort */ , 8  /* dstPort */,tx_option[9] /*option=4*/);                    tx_test(seed                          /* seed    */, 
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[9].tx].send /* src     */, 
                            ports[trans_paths[9].rx].recv /* sink    */,  
                            trans_paths[9].tx             /* srcPort */ , 
                            trans_paths[9].rx             /* dstPort */, 
                            trans_paths[9].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[10]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[10]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_10:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[10].send /* src */, ports[7] .recv /* sink */, 10 /* srcPort */ , 7  /* dstPort */,tx_option[10] /*option=4*/);                    tx_test(seed                          /* seed    */, 
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[10].tx].send /* src     */, 
                            ports[trans_paths[10].rx].recv /* sink    */,  
                            trans_paths[10].tx             /* srcPort */ , 
                            trans_paths[10].rx             /* dstPort */, 
                            trans_paths[10].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[11]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[11]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_11:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[11].send /* src */, ports[6] .recv /* sink */,  11 /* srcPort */ , 6  /* dstPort */,tx_option[11] /*option=4*/);                    tx_test(seed                          /* seed    */, 
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[11].tx].send /* src     */, 
                            ports[trans_paths[11].rx].recv /* sink    */,  
                            trans_paths[11].tx             /* srcPort */ , 
                            trans_paths[11].rx             /* dstPort */, 
                            trans_paths[11].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[12]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[12]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_12:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[12].send /* src */, ports[5] .recv /* sink */,  12 /* srcPort */ , 5  /* dstPort */,tx_option[12] /*option=4*/);                    tx_test(seed                          /* seed    */, 
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[12].tx].send /* src     */, 
                            ports[trans_paths[12].rx].recv /* sink    */,  
                            trans_paths[12].tx             /* srcPort */ , 
                            trans_paths[12].rx             /* dstPort */, 
                            trans_paths[12].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[13]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[13]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_13:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[13].send /* src */, ports[4] .recv /* sink */,  13 /* srcPort */ , 4  /* dstPort */,tx_option[13] /*option=4*/);
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[13].tx].send /* src     */, 
                            ports[trans_paths[13].rx].recv /* sink    */,  
                            trans_paths[13].tx             /* srcPort */ , 
                            trans_paths[13].rx             /* dstPort */, 
                            trans_paths[13].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[14]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[14]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_14:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[14].send /* src */, ports[3] .recv /* sink */,  14 /* srcPort */ , 3  /* dstPort */,tx_option[14] /*option=4*/);
                    tx_test(seed                          /* seed    */, 
                            repeat_number                 /* n_tries */, 
                            0                             /* is_q    */, 
                            0                             /* unvid   */, 
                            ports[trans_paths[14].tx].send /* src     */, 
                            ports[trans_paths[14].rx].recv /* sink    */,  
                            trans_paths[14].tx             /* srcPort */ , 
                            trans_paths[14].rx             /* dstPort */, 
                            trans_paths[14].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[15]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[15]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_15:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[15].send /* src */, ports[2] .recv /* sink */,  15 /* srcPort */ , 2  /* dstPort */,tx_option[15] /*option=4*/);
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[15].tx].send /* src     */, 
                            ports[trans_paths[15].rx].recv /* sink    */,  
                            trans_paths[15].tx             /* srcPort */ , 
                            trans_paths[15].rx             /* dstPort */, 
                            trans_paths[15].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[16]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[16]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_16:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[16].send /* src */, ports[1] .recv /* sink */,  16 /* srcPort */ , 1  /* dstPort */,tx_option[16] /*option=4*/);
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[16].tx].send /* src     */, 
                            ports[trans_paths[16].rx].recv /* sink    */,  
                            trans_paths[16].tx             /* srcPort */ , 
                            trans_paths[16].rx             /* dstPort */, 
                            trans_paths[16].op             /*option=4 */);
                 end
            end   
         end
         begin
         if(portUnderTest[17]) 
            begin 
//                 wait_cycles(20);
               wait_cycles(start_send_init_delay[17]);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_17:%d",  g);
//                     tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[17].send /* src */, ports[0] .recv /* sink */,  17 /* srcPort */ , 0  /* dstPort */,tx_option[17] /*option=4*/);                    tx_test(seed                          /* seed    */, 
                    tx_test(seed                           /* seed    */, 
                            repeat_number                  /* n_tries */, 
                            0                              /* is_q    */, 
                            0                              /* unvid   */, 
                            ports[trans_paths[17].tx].send /* src     */, 
                            ports[trans_paths[17].rx].recv /* sink    */,  
                            trans_paths[17].tx             /* srcPort */ , 
                            trans_paths[17].rx             /* dstPort */, 
                            trans_paths[17].op             /*option=4 */);
                 end
            end   
         end
`endif  
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
   
/* -----\/----- EXCLUDED -----\/-----
      
      

      #3us;

      $display("Startup");
      acc.write('h10304, (1<<3));

      for (i=0;i<18;i++)
        begin
           acc.read('h30034 + i*'h400, msr);
           $display("IDCODE [%d]: %x", i, msr);
        end
      
      
      ep = new (acc, 'h31000);
      ep.init();

      nic = new (acc, 'h20000);
      nic.init();
      
      $display("waiting for link");

 
     
      fork
	 
	 begin
	    tx_test(3, 0, 0, nic_src, nic_snk);
	 end
	 begin
	    forever begin 
	       nic.update(!cpu_irq_n);
	       @(posedge clk_sys);
	    end
	    
	 end

      join

   end // initial begin
 -----/\----- EXCLUDED -----/\----- */
   
  

endmodule // main

