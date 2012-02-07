// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        8
`define c_n_pcks_to_send      10
`timescale 1ns / 1ps

`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"

`include "xswcore_wrapper.v2.svh"
`include "swc_param_defs.svh"   // all swcore parameters here

`define DBG_ALLOC //if defined, the allocation debugging is active: we track the number of allocated
                  //and de-allocated pages

typedef struct {
   int cnt;
   int usecnt[`c_num_ports];
   int port[`c_num_ports];

} alloc_info_t;

alloc_info_t alloc_table[1024];
alloc_info_t dealloc_table[1024];

int stack_bastard = 0;
int global_seed = 0;

int pg_alloc_cnt[1024][2*`c_num_ports];
int pg_dealloc_cnt[1024][2*`c_num_ports];

EthPacket swc_matrix[`c_num_ports][`c_n_pcks_to_send];

module main_v2;
  
   reg clk  = 1'b0;
   reg rst_n = 1'b0;
   // generate clock and reset signals
   always #(`c_clock_period/2) clk <= ~clk;
   initial begin 
      repeat(3) @(posedge clk);
      rst_n <= 1'b1;
   end
    
   reg all_pcks_received = 0;
    
   WBPacketSource src[];
   WBPacketSink   sink[];

   IWishboneMaster #(2,16) U_wrf_source[`c_num_ports] (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink[`c_num_ports]   (clk,rst_n);
         
   virtual IWishboneMaster #(2,16) v_wrf_source[`c_num_ports];
   virtual IWishboneSlave  #(2,16) v_wrf_sink[`c_num_ports];
   
   
   reg  [`c_num_ports-1:0]                         rtu_rsp_valid        = 0;     
   wire [`c_num_ports-1:0]                         rtu_rsp_ack;       
   reg  [`c_num_ports * `c_num_ports - 1 : 0] rtu_dst_port_mask    = 0; 
   reg  [`c_num_ports-1:0]                         rtu_drop             = 0;          
   reg  [`c_num_ports * `c_prio_num_width -1 : 0] rtu_prio             = 0;     
 
   //for verification (counting txed and rxed frames)
   int tx_cnt_by_port[`c_num_ports][`c_num_ports];
   int rx_cnt_by_port[`c_num_ports][`c_num_ports];

  integer ports_ready  = 0;
  
  // some settings
  integer n_packets_to_send = `c_n_pcks_to_send;
  integer dbg               = 1;
   
   xswcore_wrapper_v2
    DUT_xswcore_wrapper (
    .clk_i                 (clk),
    .rst_n_i               (rst_n),
    .snk (U_wrf_sink),
    .src(U_wrf_source),
    .rtu_rsp_valid_i       (rtu_rsp_valid),
    .rtu_rsp_ack_o         (rtu_rsp_ack),
    .rtu_dst_port_mask_i   (rtu_dst_port_mask),
    .rtu_drop_i            (rtu_drop),
    .rtu_prio_i            (rtu_prio)
    );

/*
 *  wait ncycles
 */	
    task automatic wait_cycles;
       input [31:0] ncycles;
       begin : wait_body
	  integer i;
 
	  for(i=0;i<ncycles;i=i+1) @(posedge clk);
 
       end
    endtask // wait_cycles
    
/*
 *  set RTU
 */	
    task automatic set_rtu_rsp;
       input [31:0]                    chan;
       input                           valid;
       input                           drop;
       input [`c_prio_num_width - 1:0] prio;
       input [`c_num_ports - 1:0] mask;
       
    begin : wait_body
      
      integer i;
      integer k; // for the macro array_copy()
      if(portNumberCheck(chan) != 0) return;
      `array_copy(rtu_dst_port_mask,(chan+1)*`c_num_ports  - 1, chan*`c_num_ports,  mask ,0); 
      `array_copy(rtu_prio         ,(chan+1)*`c_prio_num_width - 1, chan*`c_prio_num_width, prio, 0); 
    
      rtu_drop         [ chan ]                                                = drop;          
      rtu_rsp_valid    [ chan ]                                                = valid;
 
      end
    endtask // wait_cycles 

/*
 *  send single frame onm a given port with given RTU settings
 */	
  task automatic send_random_packet(
	ref 				WBPacketSource src[],
	ref  				EthPacket q[$], 
	input [31:0]                    port,
	input                           drop,
	input [`c_num_ports - 1:0] prio,
	input [`c_num_ports - 1:0] mask
      );
      
      int i, j, seed = global_seed;
      integer index;
      EthPacket pkt, tmpl;
      EthPacketGenerator gen  = new;
      if(portNumberCheck(port) != 0) return;
      global_seed ++;     
      tmpl                   = new;
      tmpl.src               = '{1,2,3,4,5,6};
      tmpl.dst               = '{10,11,12,13,14,15};
      tmpl.has_smac          = 1;
      tmpl.is_q              = 0;
      tmpl.src[0]            = port;
      
      gen.set_seed(global_seed++);
      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD | EthPacketGenerator::ETHERTYPE /*| EthPacketGenerator::RX_OOB*/) ;
      gen.set_template(tmpl);
      gen.set_size(46, 1000);

      pkt         = gen.gen();
      //pkt.set_size(100);
      
      q.push_back(pkt);
     
      set_rtu_rsp(port,1 /*valid*/,drop /*drop*/,prio /*prio*/,mask /*mask*/); 
      src[port].send(pkt);
      
      if(dbg) $display("Sent     @ port_%1d to mask=0x%x [with prio=%1d, drop=%1d ]!", port, mask, prio, drop);
      
      if(drop == 0 && mask != 0)
       begin
         for(j=0;j<`c_num_ports;j++)
         begin
           if(mask[j]) 
	     begin 
               tx_cnt_by_port[port][j]++;
	       swc_matrix[port][j] = pkt;
	       if(dbg) $display("         > port_%1d to port_%1d [pkt nr=%4d]", port, j, tx_cnt_by_port[port][j]);       
	     end
         end
       end
   endtask // send_random_packets
	
/*
 *  send frames on a given port
 */	
   task automatic load_port;
      ref 			WBPacketSource src[];
      input [31:0]              port;
      input integer             n_packets;
      begin : load_port_body
                
        EthPacket      txed[$];         
        int i,j, seed = global_seed;
        int cnt = 0;
        //bit [10:0] mask ;
	int mask;
        int drop;
	if(portNumberCheck(port) != 0) return;
	global_seed ++;
        if(dbg) $display("Initial waiting: %d cycles",((port*50)%11)*50);
        wait_cycles(((port*50)%11)*50);
        
        for(i=0;i<n_packets;i++)
        begin

	  //mask = ($dist_uniform(seed,0,127) );// 2047;
	  j = $dist_uniform(seed,0,20);
          if(j > 15) drop = 1; else drop = 0;
          
          mask=1<<$dist_uniform(seed,0,`c_num_ports);
          
	  send_random_packet(src,txed, port, drop,$dist_uniform(seed,0,7) , mask);          
          
        end

        if(dbg) $display("==>> FINISHED: %2d  !!!!!",port);
      end
   endtask  //load_port

/*
 *  check statistics of the received frames (vs sent)
 */
  function automatic void transferReport;
    begin
     
      string s,d1,d2;
      int i,j, cnt;
      int sum_rx=0, sum_tx=1, sum_tx_by_port[`c_num_ports],sum_rx_by_port[`c_num_ports];
      for(i=0;i<`c_num_ports;i++)
        begin
        sum_tx_by_port[i] = 0;
        sum_rx_by_port[i] = 0;
      end
  
      sum_tx = 0;
      sum_rx = 0;
  
      for(i=0;i<11;i++)
        begin
          for(j=0;j<`c_num_ports;j++) sum_tx_by_port[i] += tx_cnt_by_port[j][i];
          for(j=0;j<`c_num_ports;j++) sum_rx_by_port[i] += rx_cnt_by_port[i][j];
        end

      for(i=0;i<`c_num_ports;i++) sum_tx += sum_tx_by_port[i];
      for(i=0;i<`c_num_ports;i++) sum_rx += sum_rx_by_port[i];

      s = "";
      d1 = "================";
      d2 = "----------------";
      for(i=0;i<`c_num_ports;i++) s = {s, $psprintf(" P %2d  |",i)};
      for(i=0;i<`c_num_ports;i++) d1 = {d1, "========"};
      for(i=0;i<`c_num_ports;i++) d2 = {d2, "--------"};
      
      $display("%s",d1);
      $display("Rx Ports   :  %s",s);
      $display("%s",d2);
      $display(" (n_pcks sent from Tx to Rx) > (n_pcks received on Tx from Rx) ");
      $display("%s",d2);
      
      for(i=0;i<`c_num_ports;i++)
        begin
          s = $psprintf("",i);
          for(int j=0;j<`c_num_ports;j++) s = {s, $psprintf(" %2d>%2d |",tx_cnt_by_port[i][j],rx_cnt_by_port[i][j])};
          $display("TX Port %2d : %s",i,s);
        end
      
      $display("%s",d1);
      
      $display("SUM    :  sent pcks = %2d, received pcks = %2d", sum_tx,sum_rx);
      $display("%s",d1);


    end
   endfunction // check_transfer	
/*
 *  initialize  sources and sinks, we need some clever way to make it configurable (port_number-wise)
 */
   function automatic void initPckSrcAndSink(ref WBPacketSource src[],ref  WBPacketSink   sink[], int port_n) ;
    
      /* no idea how to do it automatically  */
    
      src = new[`c_num_ports];
      sink = new[`c_num_ports];
      src[0]    = new(U_wrf_source[0].get_accessor());
      src[1]    = new(U_wrf_source[1].get_accessor());
      src[2]    = new(U_wrf_source[2].get_accessor());
      src[3]    = new(U_wrf_source[3].get_accessor());
      src[4]    = new(U_wrf_source[4].get_accessor());
      src[5]    = new(U_wrf_source[5].get_accessor());
      src[6]    = new(U_wrf_source[6].get_accessor());
/*     
      src[7]    = new(U_wrf_source[7].get_accessor());
      src[8]    = new(U_wrf_source[8].get_accessor());
      src[9]    = new(U_wrf_source[9].get_accessor());
      src[10]   = new(U_wrf_source[10].get_accessor());
      src[11]   = new(U_wrf_source[11].get_accessor());
      src[12]   = new(U_wrf_source[12].get_accessor());
      src[13]   = new(U_wrf_source[13].get_accessor());
      src[14]   = new(U_wrf_source[14].get_accessor());
      src[15]   = new(U_wrf_source[15].get_accessor());
      src[16]   = new(U_wrf_source[16].get_accessor());
      src[17]   = new(U_wrf_source[17].get_accessor());
      */
      
      sink[0]   = new(U_wrf_sink[0].get_accessor()); 
      sink[1]   = new(U_wrf_sink[1].get_accessor()); 
      sink[2]   = new(U_wrf_sink[2].get_accessor()); 
      sink[3]   = new(U_wrf_sink[3].get_accessor()); 
      sink[4]   = new(U_wrf_sink[4].get_accessor()); 
      sink[5]   = new(U_wrf_sink[5].get_accessor()); 
      sink[6]   = new(U_wrf_sink[6].get_accessor()); 
/*      
      sink[7]   = new(U_wrf_sink[7].get_accessor()); 
      sink[8]   = new(U_wrf_sink[8].get_accessor()); 
      sink[9]   = new(U_wrf_sink[9].get_accessor()); 
      sink[10]  = new(U_wrf_sink[10].get_accessor()); 
      sink[11]  = new(U_wrf_sink[11].get_accessor()); 
      sink[12]  = new(U_wrf_sink[12].get_accessor()); 
      sink[13]  = new(U_wrf_sink[13].get_accessor()); 
      sink[14]  = new(U_wrf_sink[14].get_accessor()); 
      sink[15]  = new(U_wrf_sink[15].get_accessor()); 
      sink[16]  = new(U_wrf_sink[16].get_accessor()); 
      sink[17]  = new(U_wrf_sink[17].get_accessor()); 
      */
      
    endfunction
    
/*
 * Check if the requested action is on a valid port number
 * this way, we don't have to care whether the test is refering
 * to the proper range of ports, if it refers to greater port number
 * then available, it will just inform about this
 */   
   function automatic int portNumberCheck(int port_n);
        if(port_n < `c_num_ports) return 0;
        $display("Accessing port number (%3d) out of the configured range (%3d)",port_n, `c_num_ports);
        return -1;
   endfunction        
        
        
  // and the party starts here....      
  initial begin        
      EthPacket      pkt, tmpl;
      EthPacket      txed[$];
      EthPacketGenerator gen;
      int i;
      int n_ports = `c_num_ports;
      
      // initialization
      initPckSrcAndSink(src, sink, n_ports);
      gen       = new;
      
      //ports_ready  = 1;
      
      @(posedge rst_n);
      @(posedge clk);
      wait_cycles(500);
      
      send_random_packet(src,txed, 0 /*port*/, 0 /*drop*/,7 /*prio*/, 2 /*mask*/);    
  
       for(i=0; i<10; i++) begin  
         send_random_packet(src,txed, i%7, 0,7 , 7);  
         wait_cycles(500);
       end 
  
  wait_cycles(80000); 
  
  transferReport(); // here we wait for all pcks to be received and then make statistics
  memoryLeakageReport();
  
  end // initial
  
   ////////////////////////// sending frames /////////////////////////////////////////
   genvar n;
   generate
   for (n=0;n<`c_num_ports;n++) begin
     initial begin
         int i;
         wait(ports_ready);
         load_port(src, n, n_packets_to_send);
         end //initial
      end //for
    endgenerate

   ////////////////////////// receiving frames ///////////////////////////////////

   generate 
   for (n=0;n<`c_num_ports;n++) begin
     always @(posedge clk) if (sink[n].poll())
       begin
         EthPacket pkt;
         sink[n].recv(pkt);
         rx_cnt_by_port[pkt.src[0]][n]++;
         if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",n, pkt.src[0],rx_cnt_by_port[pkt.src[0]][n]);
       end // always
     end //for
   endgenerate
        

   //////////////////////////  generate faked RTU responses //////////////////////////
  always @(posedge clk) 
     begin
       int i;
       for(i = 0;i<`c_num_ports ;i++)
       begin
         rtu_rsp_valid[i] = rtu_rsp_valid[i] & !rtu_rsp_ack[i];
         rtu_drop[i]      = rtu_drop[i]      & !rtu_rsp_ack[i];
       end
     end	    
        
`ifdef DBG_ALLOC   // alloc debugging not yet 
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring allocation of pages  /////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//   always @(posedge clk) if(DUT.memory_management_unit.pg_addr_valid)
   always @(posedge clk) if(DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_alloc & DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_done)

     begin
     int address;  
     int usecnt;
     
     usecnt = DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_usecnt;
     
     wait(DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_addr_valid);
     
     address =  DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_addr_alloc;
     pg_alloc_cnt[address][pg_alloc_cnt[address][0]+1]= usecnt;
     pg_alloc_cnt[address][0]++;
     
     alloc_table[address].usecnt[alloc_table[address].cnt]   = usecnt;
     alloc_table[address].port[alloc_table[address].cnt]     = DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.in_sel;
     alloc_table[address].cnt++;
     
   end   

///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring deallocation of pages  /////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
   	   
   always @(posedge clk) if(DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.alloc_core.tmp_dbg_dealloc)
     begin
     int address;  
    
     address =  DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.alloc_core.tmp_page;  
     pg_dealloc_cnt[address][0]++;
     dealloc_table[address].cnt++;  
       
     end 	   

///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring freeing of pages  /////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////// 
          
   always @(posedge clk) if(DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_free & DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_done)
     begin
     int address;  
     int port_mask;
     int port;
     
     port      = DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.in_sel;    
     address   = DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_addr;  
     port_mask = dealloc_table[address].port[dealloc_table[address].cnt ] ;
     
     pg_dealloc_cnt[address][pg_dealloc_cnt[address][0] + 1]++;
     
     dealloc_table[address].port[dealloc_table[address].cnt ] = ((1 << port) | port_mask) & 'h7FF;     
     dealloc_table[address].usecnt[dealloc_table[address].cnt ]++;
       
     end 	      
 
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring setting of pages' usecnt /////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////     
     
   always @(posedge clk) if(DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_set_usecnt & DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_done)
     begin
     int address;  

     address =  DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_addr;  
     pg_alloc_cnt[address][pg_alloc_cnt[address][0] + 1] =  DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_usecnt;
     alloc_table[address].usecnt[alloc_table[address].cnt - 1]   = DUT_xswcore_wrapper.DUT_swc_core.xswcore.memory_management_unit.pg_usecnt;;
       
     end 	
`endif
   
   function automatic void memoryLeakageReport;
   
`ifdef DBG_ALLOC
        string s;
        int i,j, cnt;
        cnt =0;
        for(i=0;i<1024;i++)
          if(dealloc_table[i].cnt!= alloc_table[i].cnt)
            begin
              s = "";
              for(j=0;j<`c_num_ports;j++)  s = {s, $psprintf("%2d:%2d|",alloc_table[i].usecnt[j],alloc_table[i].port[j])};
              $display("Page %4d: alloc = %4d [%s]",i,alloc_table[i].cnt,s);
             
             //$display("Page %4d: alloc = %4d [%2d:%2d|%2d:%2d|%2d:%2d|%2d:%2d|%2d:%2d|%2d:%2d]<=|=>dealloc = %4d [%2d:%11b|%2d:%11b|%2d:%11b|%2d:%11b|%2d:%11b|%2d:%11b]  ",
//               i,
//               alloc_table[i].cnt,
//               alloc_table[i].usecnt[0], alloc_table[i].port[0], 
//               alloc_table[i].usecnt[1], alloc_table[i].port[1],
//               alloc_table[i].usecnt[2], alloc_table[i].port[2],
//               alloc_table[i].usecnt[3], alloc_table[i].port[3],
//               alloc_table[i].usecnt[4], alloc_table[i].port[4],
//               alloc_table[i].usecnt[5], alloc_table[i].port[5],
//               dealloc_table[i].cnt,
//               dealloc_table[i].usecnt[0], dealloc_table[i].port[0],
//               dealloc_table[i].usecnt[1], dealloc_table[i].port[1],
//               dealloc_table[i].usecnt[2], dealloc_table[i].port[2],
//               dealloc_table[i].usecnt[3], dealloc_table[i].port[3],
//               dealloc_table[i].usecnt[4], dealloc_table[i].port[4],
//               dealloc_table[i].usecnt[5], dealloc_table[i].port[5]);
              cnt++;
            end
        
        $display("=======================================================================");
        $display("MEM LEAKGE Report:  number of lost pages = %2d", (cnt - (2*`c_num_ports)));
        $display("=================================== DBG ===============================");
 `endif
   
   endfunction

endmodule // main
