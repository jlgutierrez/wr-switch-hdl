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
   parameter g_scb_number = 3;      // dont' try to change :)
   parameter g_port_bunch_number = 6;  // dont' try to change :)
   reg [g_num_ports-1:0] ep_ctrl;
   
   // prameters to create some gaps between pks (not work really well)
   parameter g_enable_pck_gaps = 1;  //1=TRUE, 0=FALSE
   parameter g_min_pck_gap = 100; // cycles
   parameter g_max_pck_gap = 500; // cycles
   
   reg [18:0] portUnderTest = 18'b000000000000001111; // unicast 

   integer repeat_number = 10;
   integer tries_number = 3;

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
      //int i,j;
      
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
      else if(opt==4)
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
              .cpu_irq(),
              .clk_swc_mpm_core_i(clk_swc_mpm_core),
              .ep_ctrl_i(ep_ctrl)
              );

   typedef struct {
      CSimDrv_WR_Endpoint ep;
      EthPacketSource send;
      EthPacketSink recv;
   } port_t;

   /// simulation endpoints
   port_t          ports[$];
   CSimDrv_NIC     nic[3];
   
   /// Switches
   CRTUSimDriver   rtu[3];
   CSimDrv_WR_TRU  tru[3];
   CSimDrv_TXTSU   txtsu[3];
   
   task automatic init_ports(ref port_t p[$], ref CWishboneAccessor wb, int scp_nr);
      int i;

//       for(i=0;i<g_port_bunch_number;i++)
      for(i=0;i<g_num_ports;i++)
        begin
           port_t tmp;
           CSimDrv_WR_Endpoint ep;
           ep = new(wb, 'h30000 + i * 'h400);
           ep.init(i);
           if(i<g_port_bunch_number) begin
             tmp.ep = ep;
             tmp.send = EthPacketSource'(DUT.to_port[i+g_port_bunch_number*scp_nr]);
             tmp.recv = EthPacketSink'(DUT.from_port[i+g_port_bunch_number*scp_nr]);
             p.push_back(tmp);
           end
        end
   endtask // init_endpoints
   
   task automatic init_nic(ref port_t p[$],ref CWishboneAccessor wb, int scp_nr);
      NICPacketSource nic_src;
      NICPacketSink nic_snk;
      port_t tmp;
      
      nic[scp_nr] = new(wb, 'h20000);
      $display("NICInit");
      nic[scp_nr].init();
      $display("Done");
      
      nic_src = new (nic[scp_nr]);
      nic_snk = new (nic[scp_nr]);
      $display("Src: %x\n",nic_src);
      
      tmp.send = EthPacketSource'(nic_src);
      tmp.recv = EthPacketSink'(nic_snk);
      p.push_back(tmp);
      
   endtask // init_nic
   
   task automatic init_tru(input CSimDrv_WR_TRU tru_drv);

      $display(">>>>>>>>>>>>>>>>>>> TRU initialization  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
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
                             32'h00000 /*pattern_mask*/, 32'h00000 /* pattern_match*/,   'h000 /* pattern_mode */,
                             32'h3FFFF /*ports_mask  */, 32'b111000000010100001 /* ports_egress */,32'b111000000010100001 /* ports_ingress   */);

      tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                             32'b00000011 /*pattern_mask*/, 32'b00000001 /* pattern_match*/,'h0  /* pattern_mode */,
                             32'b00000011 /*ports_mask  */, 32'b00000010 /* ports_egress */,32'b00000010 /* ports_ingress   */);
 
      tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                             32'b00000011 /*pattern_mask*/, 32'b00000011 /* pattern_match*/,'h0  /* pattern_mode */,
                             32'b00000111 /*ports_mask  */, 32'b00000100 /* ports_egress */,32'b00000100 /* ports_ingress   */);

      tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                             'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                             'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);
 
      tru_drv.tru_swap_bank();  
      tru_drv.tru_enable();
      tru_drv.tru_port_config(0);
      $display("TRU configured and enabled");
      $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
   endtask; //init_tru
   task automatic init_rtu(input CRTUSimDriver rtu, bit[31:0] vlanMask, bit[17:0] staticEntries = 0, bit RTUeX=0);
      rtu_vlan_entry_t def_vlan;
      $display(">>>>>>>>>>>>>>>>>>> RTU initialization  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
      for (int dd=0;dd<g_num_ports;dd++)
      begin
        rtu.set_port_config(dd, 1, 0, 1);
      end
 
      rtu.set_port_config(g_num_ports, 1, 0, 0); // for NIC
        
      if(staticEntries[0])  rtu.add_static_rule('{17, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<17));
      if(staticEntries[1])  rtu.add_static_rule('{16, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<16));
      if(staticEntries[2])  rtu.add_static_rule('{15, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<15));
      if(staticEntries[3])  rtu.add_static_rule('{14, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<14));
      if(staticEntries[4])  rtu.add_static_rule('{13, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<13));
      if(staticEntries[5])  rtu.add_static_rule('{12, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<12));
      if(staticEntries[6])  rtu.add_static_rule('{11, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<11));
      if(staticEntries[7])  rtu.add_static_rule('{10, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<10));
      if(staticEntries[8])  rtu.add_static_rule('{ 9, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<9 ));
      if(staticEntries[9])  rtu.add_static_rule('{ 8, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<8 ));
      if(staticEntries[10]) rtu.add_static_rule('{ 7, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<7 ));
      if(staticEntries[11]) rtu.add_static_rule('{ 6, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<6 ));
      if(staticEntries[12]) rtu.add_static_rule('{ 5, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<5 ));
      if(staticEntries[13]) rtu.add_static_rule('{ 4, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<4 ));
      if(staticEntries[14]) rtu.add_static_rule('{ 3, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<3 ));
      if(staticEntries[15]) rtu.add_static_rule('{ 2, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<2 ));
      if(staticEntries[16]) rtu.add_static_rule('{ 1, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<1 ));
      if(staticEntries[17]) rtu.add_static_rule('{ 0, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<0  ));

      def_vlan.port_mask      = vlanMask;
      def_vlan.fid            = 0;
      def_vlan.drop           = 0;
      def_vlan.prio           = 0;
      def_vlan.has_prio       = 0;
      def_vlan.prio_override  = 0;

      rtu.add_vlan_entry(0, def_vlan);
      if(RTUeX) begin
//        rtu.rx_add_ff_mac_single(0/*ID*/,1/*valid*/,'h1150cafebabe /*MAC*/);
//        rtu.rx_add_ff_mac_single(1/*ID*/,1/*valid*/,'h111111111111/*MAC*/);
//        rtu.rx_add_ff_mac_range (0/*ID*/,1/*valid*/,'h0050cafebabe/*MAC_lower*/,'h0850cafebabe/*MAC_upper*/);
//        rtu.rx_set_port_mirror  ('h00020000 /*mirror_src_mask*/,'h00000008 /*mirror_dst_mask*/,0/*rx*/,1/*tx*/);
//        rtu.rx_set_hp_prio_mask ('b10000001 /*hp prio mask*/); //HP traffic set to 7th priority
//        rtu.rx_set_cpu_port     ((1<<g_num_ports)/*mask: virtual port of CPU*/);
// //       rtu.rx_forward_on_fmatch_full();
//        rtu.rx_drop_on_fmatch_full();
       rtu.rx_feature_ctrl(0 /*mr*/, 0 /*mac_ptp*/, 0/*mac_ll*/, 0/*mac_single*/, 0/*mac_range*/, 1/*mac_br*/);
      end
      ////////////////////////////////////////////////////////////////////////////////////////

      rtu.enable();
      $display(">>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
   endtask; //init_tru   
  /// ========================================= main stuff =================================//
   initial begin
      uint64_t msr;
      int seed;
      bit [31:0] vlanMasks[3];            

      CWishboneAccessor cpu_acc[3]; //= DUT.cpu.get_accessor();
      cpu_acc[0] = DUT.cpu_0.get_accessor();
      cpu_acc[1] = DUT.cpu_1.get_accessor();
      cpu_acc[2] = DUT.cpu_2.get_accessor();

      for(int gg=0;gg<g_num_ports;gg++) 
      begin 
        ep_ctrl[gg] = 'b1; 
      end
      repeat(200) @(posedge clk_sys);

      $display("Startup!");
      
      for(int i=0;i<g_scb_number;i++) begin
        cpu_acc[i].set_mode(PIPELINED);
        cpu_acc[i].write('h10304, (1<<3));
        init_ports(ports, cpu_acc[i],i);
      end

      vlanMasks[0] = 32'h00011F1;
      vlanMasks[1] = 32'h0001111;
      vlanMasks[2] = 32'h0001011;

      for(int i=0;i<g_scb_number;i++) begin

        $display("Switch_%1d: InitNIC",i);     
        init_nic(ports, cpu_acc[i],i);

        $display("Switch_%1d: InitTXTS",i);

        txtsu[i] = new (cpu_acc[i], 'h51000);
        txtsu[i].init();
      
        $display("Switch_%1d: Initialization done",i);

        rtu[i] = new;
        rtu[i].set_bus(cpu_acc[i], 'h60000); 
         
        init_rtu(rtu[i], vlanMasks[i] /* VLAN */, 32'h00000000 /* static entries */, 1 /* RTUeX*/);  
      end
      fork
//          begin
//            wait_cycles(500);
//            ep_ctrl[0] = 'b0;
//            wait_cycles(500);
//            ep_ctrl[1] = 'b0;
//          end 
         begin
         if(portUnderTest[0]) 
            begin 
               for(int g=0;g<tries_number;g++)
                 begin
                    $display("Try port_0:%d",  g);
                    tx_test(seed /* seed */, repeat_number /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[0].send /* src */, ports[12].recv /* sink */,  0 /* srcPort */ , 12 /* dstPort */, 4 /*option*/);
                 end
            end   
         end // fork begin

         /// Switch 0
         forever begin
            nic[0].update(DUT.U_SW_0.U_Wrapped_SCBCore.vic_irqs[0]);
            @(posedge clk_sys);
         end
         forever begin
            txtsu[0].update(DUT.U_SW_0.U_Wrapped_SCBCore.vic_irqs[1]);
            @(posedge clk_sys);
         end
         /// Switch 1
         forever begin
            nic[0].update(DUT.U_SW_1.U_Wrapped_SCBCore.vic_irqs[0]);
            @(posedge clk_sys);
         end
         forever begin
            txtsu[0].update(DUT.U_SW_1.U_Wrapped_SCBCore.vic_irqs[1]);
            @(posedge clk_sys);
         end
         /// Switch 2
         forever begin
            nic[0].update(DUT.U_SW_2.U_Wrapped_SCBCore.vic_irqs[0]);
            @(posedge clk_sys);
         end
         forever begin
            txtsu[0].update(DUT.U_SW_2.U_Wrapped_SCBCore.vic_irqs[1]);
            @(posedge clk_sys);
         end
      join_none

   end // initial begin

endmodule // main

