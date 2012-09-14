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
   
   // prameters to create some gaps between pks (not work really well)
   parameter g_enable_pck_gaps = 0;  //1=TRUE, 0=FALSE
   parameter g_min_pck_gap = 100; // cycles
   parameter g_max_pck_gap = 500; // cycles
   
   // defining which ports send pcks -> forwarding is one-to-one 
   // (port_1 to port_14, port_2 to port_13, etc)
   
   reg [15:0] portUnderTest = 16'b0000000011111111;
   
   
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
   
   task automatic tx_test(ref int seed, input  int n_tries, input int is_q,input int unvid, ref EthPacketSource src, ref EthPacketSink sink, input int srcPort, input int dstPort);
      EthPacketGenerator gen = new;
      EthPacket pkt, tmpl, pkt2;
      EthPacket arr[];
      //int i,j;
      
      arr            = new[n_tries](arr);

      gen.set_seed(seed);
  
      tmpl           = new;
      tmpl.src       = '{srcPort, 2,3,4,5,6};
      tmpl.dst       = '{dstPort, 'h50, 'hca, 'hfe, 'hba, 'hbe};
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
	      $display("rx %d", j);
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
              .clk_swc_mpm_core_i(clk_swc_mpm_core)
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

      tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,   0 /* subentry_addr*/,
                             'h00 /*pattern_mask*/, 'h00 /* pattern_match*/, 'h0 /* pattern_mode */,
                             'hFF /*ports_mask  */, 'h3F /* ports_egress */,'h1D /* ports_ingress   */);

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

        rtu.add_static_rule('{17, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<17 ));
        rtu.add_static_rule('{16, 'h50, 'hca, 'hfe, 'hba, 'hbe}, (1<<16 ));

     // rtu.set_hash_poly();
      
      def_vlan.port_mask      = 32'hffffffff;
      def_vlan.fid        =0;
      def_vlan.drop         = 0;
      def_vlan.has_prio       =0;
      def_vlan.prio_override  = 0;

      rtu.add_vlan_entry(0, def_vlan);

      rtu.enable();
      ///TRU
      tru = new(cpu_acc, 'h57000);      
      init_tru(tru);
      
      ////////////// sending packest on all the ports (16) according to the portUnderTest mask.///////
      fork
//`ifdef none
         begin
         if(portUnderTest[6]) 
            begin 
               for(int g=0;g<20;g++)
                 begin
                    $display("Try f_5:%d", g);
                    tx_test(seed /* seed */, 200 /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[0].send /* src */, ports[16].recv /* sink */,  0 /* srcPort */ , 16 /* dstPort */);
                 end
            end   
         end // fork begin
//`endif //  `ifdef none
         
//         `ifdef none
         begin
         if(portUnderTest[5]) 
            begin 
               for(int g=0;g<20;g++)
                 begin
                    $display("Try f_6:%d", g);
                    tx_test(seed /* seed */, 200 /* n_tries */, 0 /* is_q */, 0 /* unvid */, ports[1].send /* src */, ports[17] .recv /* sink */,  1 /* srcPort */ , 17  /* dstPort */);
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

