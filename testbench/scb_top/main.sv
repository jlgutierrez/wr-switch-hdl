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

   reg clk_ref=0;
   reg clk_sys=0;
   reg clk_swc_mpm_core=0;
   reg rst_n=0;
      
   parameter g_num_ports = 18;
   
   reg [g_num_ports-1:0] ep_ctrl;
   
   // prameters to create some gaps between pks (not work really well)
   parameter g_enable_pck_gaps = 1;  //1=TRUE, 0=FALSE
   parameter g_min_pck_gap = 100; // cycles
   parameter g_max_pck_gap = 500; // cycles
   
   // defining which ports send pcks -> forwarding is one-to-one 
   // (port_1 to port_14, port_2 to port_13, etc)
  //     reg [18:0] portUnderTest = 18'b000000000000000011; // unicast -- port 0 disabled by VLAN config
  //    reg [18:0] portUnderTest = 18'b111000000000000111; // unicast
      reg [18:0] portUnderTest = 18'b000000000000000111; // unicast 
 //     reg [18:0] portUnderTest = 18'b000000000000001000; // broadcast
 //   reg [18:0] portUnderTest = 18'b100000000000000101;
 //   reg [18:0] portUnderTest = 18'b111111111111111111;
   integer repeat_number = 10;
   integer tries_number = 3;
/* -----\/----- EXCLUDED -----\/-----
   tbi_clock_rst_gen
     #(
       .g_rbclk_period(8002))
   clkgen(
	  .clk_sys_o(clk_sys),
          .clk_ref_o(clk_ref),
	  .rst_n_o(rst_n)
	  );
 -----/\----- EXCLUDED -----/\----- */

   always #2.5ns clk_swc_mpm_core <=~clk_swc_mpm_core;
   //always #5ns clk_swc_mpm_core <=~clk_swc_mpm_core;
   always #8ns clk_sys <= ~clk_sys;
   always #8ns clk_ref <= ~clk_ref;
   
//   always #8ns clk_sys <= ~clk_sys;
//   always #8ns clk_ref <= ~clk_ref;

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
      //int i,j;
      
      arr            = new[n_tries](arr);

      gen.set_seed(seed);
  
      tmpl           = new;
      tmpl.src       = '{srcPort, 2,3,4,5,6};
      if(opt==0)
        tmpl.dst       = '{dstPort, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      else if(opt==1)
        tmpl.dst       = '{'hFF, 'hFF, 'hFF, 'hFF, 'hFF, 'hFF};      
      else if(opt==2)
        tmpl.dst       = '{'h01, 'h80, 'hC2, 'h00, 'h00, 'h00};


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
              
              $display("[port %d] tx %d", srcPort, i);
              
              src.send(pkt);
              arr[i]  = pkt;
              //pkt.dump();
            //  repeat(3000) @(posedge clk_sys);
              
	  //    $display("Send: %d [dsize %d]", i+1,pkt.payload.size() + 14);
	      
           end
         end 
	begin
         for(int j=0;j<n_tries;j++)
           begin
           sink.recv(pkt2);
	      $display("rx %d at port %d", j,dstPort);
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

      if(g_enable_pck_gaps == 1) 
        wait_cycles($dist_uniform(seed,g_min_pck_gap,g_max_pck_gap));
      
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

      tru_drv.pattern_config(1 /*replacement*/ ,2 /*addition*/);
      tru_drv.rt_reconf_config(4 /*tx_frame_id*/, 4/*rx_frame_id*/, 1 /*mode*/);
      tru_drv.rt_reconf_enable();
        
      /*
       * transition
       **/
      tru_drv.transition_config(0 /*mode */,     4 /*rx_id*/, 0 /*prio*/, 20 /*time_diff*/, 
                                3 /*port_a_id*/, 4 /*port_b_id*/);

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
                             'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,   'h0 /* pattern_mode */,
                             'hFFFFF /*ports_mask  */, 'hFFFFF /* ports_egress */,'hFFFFF /* ports_ingress   */);

      tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                             'h03 /*pattern_mask*/, 'h01 /* pattern_match*/,'h0  /* pattern_mode */,
                             'hFF /*ports_mask  */, 'h3E /* ports_egress */,'h1E /* ports_ingress   */);
 
      tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                             'h03 /*pattern_mask*/, 'h03 /* pattern_match*/,'h0  /* pattern_mode */,
                             'hFF /*ports_mask  */, 'h3C /* ports_egress */,'h3C /* ports_ingress   */);

      tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                             'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                             'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);
 
      tru_drv.tru_swap_bank();  
      tru_drv.tru_enable();
      $display("TRU configured and enabled");
   endtask; //init_tru
   
   initial begin
      uint64_t msr;
      int seed;
      rtu_vlan_entry_t def_vlan;
      
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
      
      def_vlan.port_mask      = 32'hffffFFFF;
      def_vlan.fid            = 0;
      def_vlan.drop           = 0;
      def_vlan.prio           = 0;
      def_vlan.has_prio       = 0;
      def_vlan.prio_override  = 0;

      rtu.add_vlan_entry(0, def_vlan);

//       def_vlan.port_mask      = 32'hfffff0Ff;
//       def_vlan.fid            = 0;
//       def_vlan.drop           = 0;
//       def_vlan.prio           = 7;
//       def_vlan.has_prio       = 1;
//       def_vlan.prio_override  = 0;
// 
//       rtu.add_vlan_entry(100, def_vlan);

      ///////////////////////////   RTU extension settings:  ////////////////////////////////
      
      rtu.rx_add_ff_mac_single(0/*ID*/,1/*valid*/,'h1150cafebabe /*MAC*/);
      rtu.rx_add_ff_mac_single(1/*ID*/,1/*valid*/,'h111111111111/*MAC*/);
      rtu.rx_add_ff_mac_range (0/*ID*/,1/*valid*/,'h0050cafebabe/*MAC_lower*/,'h0850cafebabe/*MAC_upper*/);
      rtu.rx_set_port_mirror  ('h00000001 /*mirror_src_mask*/,'h00000002 /*mirror_dst_mask*/,1/*rx*/,1/*tx*/);
      rtu.rx_set_hp_prio_mask ('b10000001 /*hp prio mask*/); //HP traffic set to 7th priority
      rtu.rx_set_cpu_port     ((1<<g_num_ports)/*mask: virtual port of CPU*/);
//       rtu.rx_forward_on_fmatch_full();
      rtu.rx_drop_on_fmatch_full();
      rtu.rx_feature_ctrl(0 /*mr*/, 0 /*mac_ptp*/, 0/*mac_ll*/, 0/*mac_single*/, 0/*mac_range*/, 1/*mac_br*/);
      ////////////////////////////////////////////////////////////////////////////////////////

      rtu.enable();
      ///TRU
      tru = new(cpu_acc, 'h57000);      
      init_tru(tru);
      
      
      ////////////// sending packest on all the ports (16) according to the portUnderTest mask.///////
      fork
         begin
           wait_cycles(500);
           ep_ctrl[0] = 'b0;
         end 
//`ifdef none
         begin
         if(portUnderTest[0]) 
            begin 
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_0:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[0].send /* src */, ports[17].recv /* sink */,  0 /* srcPort */ , 17 /* dstPort */, 0 /*option*/);
                 end
            end   
         end // fork begin
//`endif //  `ifdef none
         
//         `ifdef none
         begin
         if(portUnderTest[1]) 
            begin 
//                wait_cycles(5);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_1:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[1].send /* src */, ports[16] .recv /* sink */,  1 /* srcPort */ , 16  /* dstPort */);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[2]) 
            begin 
//                wait_cycles(5);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_2:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[2].send /* src */, ports[15] .recv /* sink */,  2 /* srcPort */ , 15  /* dstPort */, 0 /*option*/);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[3]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_3:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[3].send /* src */, ports[14] .recv /* sink */,  3 /* srcPort */ , 14  /* dstPort */,1 /*option*/);
                 end
            end   
         end
//         `endif

//         `ifdef none
         begin
         if(portUnderTest[4]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_4:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[4].send /* src */, ports[13] .recv /* sink */,  4 /* srcPort */ , 13  /* dstPort */);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[5]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_5:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[5].send /* src */, ports[12] .recv /* sink */,  5 /* srcPort */ , 12  /* dstPort */);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[6]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_6:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[6].send /* src */, ports[11] .recv /* sink */,  6 /* srcPort */ , 11  /* dstPort */);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[7]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_7:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[7].send /* src */, ports[10] .recv /* sink */,  7 /* srcPort */ , 10  /* dstPort */);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[8]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_8:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[8].send /* src */, ports[9] .recv /* sink */,  8 /* srcPort */ , 9  /* dstPort */);
                 end
            end   
         end
//         `endif


//         `ifdef none
         begin
         if(portUnderTest[9]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_9:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[9].send /* src */, ports[8] .recv /* sink */, 9 /* srcPort */ , 8  /* dstPort */);
                 end
            end   
         end
//         `endif

//         `ifdef none
         begin
         if(portUnderTest[10]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_10:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[10].send /* src */, ports[7] .recv /* sink */, 10 /* srcPort */ , 7  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[11]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_11:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[11].send /* src */, ports[6] .recv /* sink */,  11 /* srcPort */ , 6  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[12]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_12:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[12].send /* src */, ports[5] .recv /* sink */,  12 /* srcPort */ , 5  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[13]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_13:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[13].send /* src */, ports[4] .recv /* sink */,  13 /* srcPort */ , 4  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[14]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_14:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[14].send /* src */, ports[3] .recv /* sink */,  14 /* srcPort */ , 3  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[15]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_15:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[15].send /* src */, ports[2] .recv /* sink */,  15 /* srcPort */ , 2  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[16]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_16:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[16].send /* src */, ports[1] .recv /* sink */,  16 /* srcPort */ , 1  /* dstPort */);
                 end
            end   
         end
//         `endif
//         `ifdef none
         begin
         if(portUnderTest[17]) 
            begin 
//                 wait_cycles(20);
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_17:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[17].send /* src */, ports[0] .recv /* sink */,  17 /* srcPort */ , 0  /* dstPort */);
                 end
            end   
         end
//         `endif

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

