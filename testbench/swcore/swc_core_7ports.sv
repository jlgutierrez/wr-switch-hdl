// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        16
`define c_core_clock_period   (`c_clock_period/5)
`define c_wrsw_prio_width     3
`define c_swc_ctrl_width      4
`define c_swc_data_width      16
//`define c_wrsw_num_ports      11
`define c_wrsw_num_ports      7

`define c_n_pcks_to_send      10

`timescale 1ns / 1ps

`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"

`include "xswc_core_wrapper_7ports.svh"


typedef struct {
   int cnt;
   int usecnt[10];
   int port[10];

} alloc_info_t;

alloc_info_t alloc_table[1024];
alloc_info_t dealloc_table[1024];

int stack_bastard = 0;
int global_seed = 0;

int pg_alloc_cnt[1024][20];
int pg_dealloc_cnt[1024][20];



EthPacket swc_matrix[`c_wrsw_num_ports][`c_n_pcks_to_send];

module main_7ports;


   
   reg clk           = 1'b0;
   reg clk_mpm_core  = 1'b0;
   reg rst_n         = 1'b0;
   // generate clock and reset signals
   always #(`c_clock_period/2)     clk <= ~clk;
   always #(`c_core_clock_period/2) clk_mpm_core <= ~clk_mpm_core;
   initial begin 
      repeat(3) @(posedge clk);
      rst_n <= 1'b1;
   end
    
   reg all_pcks_received = 0;
    
   WBPacketSource src[];
   WBPacketSink   sink[];

   IWishboneMaster #(2,16) U_wrf_source_0 (clk,rst_n);
   IWishboneMaster #(2,16) U_wrf_source_1 (clk,rst_n);
   IWishboneMaster #(2,16) U_wrf_source_2 (clk,rst_n);
   IWishboneMaster #(2,16) U_wrf_source_3 (clk,rst_n);
   IWishboneMaster #(2,16) U_wrf_source_4 (clk,rst_n);
   IWishboneMaster #(2,16) U_wrf_source_5 (clk,rst_n);
   IWishboneMaster #(2,16) U_wrf_source_6 (clk,rst_n);
      
   IWishboneSlave #(2,16)  U_wrf_sink_0   (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink_1   (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink_2   (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink_3   (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink_4   (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink_5   (clk,rst_n);
   IWishboneSlave #(2,16)  U_wrf_sink_6   (clk,rst_n);
           
   
   reg  [`c_wrsw_num_ports-1:0]                         rtu_rsp_valid        = 0;     
   wire [`c_wrsw_num_ports-1:0]                         rtu_rsp_ack;       
   reg  [`c_wrsw_num_ports * `c_wrsw_num_ports - 1 : 0] rtu_dst_port_mask    = 0; 
   reg  [`c_wrsw_num_ports-1:0]                         rtu_drop             = 0;          
   reg  [`c_wrsw_num_ports * `c_wrsw_prio_width -1 : 0] rtu_prio             = 0;     
 
   //for verification (counting txed and rxed frames)
   int tx_cnt_by_port[11][11];
   int rx_cnt_by_port[11][11];

  integer ports_ready  = 0;
  
  // some settings
  integer n_packets_to_send = `c_n_pcks_to_send;
  integer dbg               = 1;
   
  
 
  
   xswc_core_wrapper_7ports
    DUT_xswc_core_wrapper(
    .clk_i                 (clk),
    .clk_mpm_core_i        (clk_mpm_core),
    .rst_n_i               (rst_n),
//-------------------------------------------------------------------------------
//-- pWB slave - this is output of the swcore (internally connected to the source)
//-------------------------------------------------------------------------------  

      .snk_0 (U_wrf_sink_0.slave),
      .snk_1 (U_wrf_sink_1.slave), 
      .snk_2 (U_wrf_sink_2.slave), 
      .snk_3 (U_wrf_sink_3.slave), 
      .snk_4 (U_wrf_sink_4.slave), 
      .snk_5 (U_wrf_sink_5.slave), 
      .snk_6 (U_wrf_sink_6.slave), 	 

//-------------------------------------------------------------------------------
//-- pWB master - this is an input of the swcore (internally connected to the sink)
//-------------------------------------------------------------------------------  

      .src_0(U_wrf_source_0.master),
      .src_1(U_wrf_source_1.master),
      .src_2(U_wrf_source_2.master),
      .src_3(U_wrf_source_3.master),
      .src_4(U_wrf_source_4.master),
      .src_5(U_wrf_source_5.master),
      .src_6(U_wrf_source_6.master),	 
       
//-------------------------------------------------------------------------------
//-- I/F with Routing Table Unit (RTU)
//-------------------------------------------------------------------------------      
    
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
       input [`c_wrsw_prio_width - 1:0] prio;
       input [`c_wrsw_num_ports - 1:0] mask;
       
       begin : wait_body
    integer i;
    integer k; // for the macro array_copy()

    `array_copy(rtu_dst_port_mask,(chan+1)*`c_wrsw_num_ports  - 1, chan*`c_wrsw_num_ports,  mask ,0); 
    `array_copy(rtu_prio         ,(chan+1)*`c_wrsw_prio_width - 1, chan*`c_wrsw_prio_width, prio, 0); 
    
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
	input [`c_wrsw_num_ports - 1:0] prio,
	input [`c_wrsw_num_ports - 1:0] mask
      );
      
      int i, j, seed = global_seed;
      integer index;
      EthPacket pkt, tmpl;
      EthPacketGenerator gen  = new;
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
         for(j=0;j<`c_wrsw_num_ports;j++)
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
	global_seed ++;
        if(dbg) $display("Initial waiting: %d cycles",((port*50)%11)*50);
        wait_cycles(((port*50)%11)*50);
        
        for(i=0;i<n_packets;i++)
        begin

	  //mask = ($dist_uniform(seed,0,127) );// 2047;
	  j = $dist_uniform(seed,0,20);
          if(j > 15) drop = 1; else drop = 0;
          
          mask=1<<$dist_uniform(seed,0,`c_wrsw_num_ports);
          
	  send_random_packet(src,txed, port, drop,$dist_uniform(seed,0,7) , mask);          
          
        end

        if(dbg) $display("==>> FINISHED: %2d  !!!!!",port);
      end
   endtask  //load_port

	
	
/*
 *  check statistics of the received frames (vs sent)
 */		
  task automatic check_transfer;
    begin
    
      int i,j, cnt;
      int sum_rx=0, sum_tx=1, sum_tx_by_port[11],sum_rx_by_port[11];
wait_cycles(80000);
//      while(sum_tx != sum_rx)
//	begin 
		for(i=0;i<11;i++)
		  begin
		    sum_tx_by_port[i] = 0;
		    sum_rx_by_port[i] = 0;
		  end
		  
		sum_tx = 0;
		sum_rx = 0;
		  
		for(i=0;i<11;i++)
		  begin
		    for(j=0;j<11;j++) sum_tx_by_port[i] += tx_cnt_by_port[j][i];
		    for(j=0;j<11;j++) sum_rx_by_port[i] += rx_cnt_by_port[i][j];
		  end

		for(i=0;i<11;i++) sum_tx += sum_tx_by_port[i];
		for(i=0;i<11;i++) sum_rx += sum_rx_by_port[i];
	
		wait_cycles(50);
	
//	end
      
      $display("=============================================== DBG =================================================");
      $display("Rx Ports   :  P 0  |  P 1  |  P 2  |  P 3  |  P 4  |  P 5  |  P 6  |  P 7  |  P 8  |  P 9  |  P10  | ");
      $display("-----------------------------------------------------------------------------------------------------");
      $display(" (number of pcks sent from port Rx to port Tx) > (number of pcks received on port Tx from port Rx) | ");
      $display("-----------------------------------------------------------------------------------------------------");
      for(i=0;i<11;i++)

	  $display("TX Port %2d : %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d | %2d>%2d |",i,
	  tx_cnt_by_port[i][0],rx_cnt_by_port[i][0],tx_cnt_by_port[i][1],rx_cnt_by_port[i][1],tx_cnt_by_port[i][2],rx_cnt_by_port[i][2],tx_cnt_by_port[i][3],rx_cnt_by_port[i][3],
	  tx_cnt_by_port[i][4],rx_cnt_by_port[i][4],tx_cnt_by_port[i][5],rx_cnt_by_port[i][5],tx_cnt_by_port[i][6],rx_cnt_by_port[i][6],tx_cnt_by_port[i][7],rx_cnt_by_port[i][7],
	  tx_cnt_by_port[i][8],rx_cnt_by_port[i][8],tx_cnt_by_port[i][9],rx_cnt_by_port[i][9],tx_cnt_by_port[i][10],rx_cnt_by_port[i][10]);
	  
      
      $display("=============================================== DBG =================================================");
      
      $display("=======================================================================");
      $display("SUM    :  sent pcks = %2d, received pcks = %2d", sum_tx,sum_rx);
      $display("=================================== DBG ===============================");

     cnt =0;
     for(i=0;i<1024;i++)
       if(dealloc_table[i].cnt!= alloc_table[i].cnt)
         begin
           $display("Page %4d: alloc = %4d [%2d:%2d|%2d:%2d|%2d:%2d|%2d:%2d|%2d:%2d|%2d:%2d]<=|=>dealloc = %4d [%2d:%11b|%2d:%11b|%2d:%11b|%2d:%11b|%2d:%11b|%2d:%11b]  ",
           i,
           alloc_table[i].cnt,
           alloc_table[i].usecnt[0], alloc_table[i].port[0], 
           alloc_table[i].usecnt[1], alloc_table[i].port[1],
           alloc_table[i].usecnt[2], alloc_table[i].port[2],
           alloc_table[i].usecnt[3], alloc_table[i].port[3],
           alloc_table[i].usecnt[4], alloc_table[i].port[4],
           alloc_table[i].usecnt[5], alloc_table[i].port[5],
           dealloc_table[i].cnt,
           dealloc_table[i].usecnt[0], dealloc_table[i].port[0],
           dealloc_table[i].usecnt[1], dealloc_table[i].port[1],
           dealloc_table[i].usecnt[2], dealloc_table[i].port[2],
           dealloc_table[i].usecnt[3], dealloc_table[i].port[3],
           dealloc_table[i].usecnt[4], dealloc_table[i].port[4],
           dealloc_table[i].usecnt[5], dealloc_table[i].port[5]);
           cnt++;
         end
        
     $display("=======================================================================");
     if(cnt == 22)
       $display("%4d pages allocated in advance (port X start_of_pck + port X pck_internal pages)", cnt);
     else
       $display("MEM LEAKGE Report:  number of lost pages = %2d", (cnt - (2*`c_wrsw_num_ports)));
     $display("=================================== DBG ===============================");


 $fatal("dupa");
      
      
     end
   endtask // check_transfer	
	
	
/*
 *  generate faked RTU responses
 */	
   always @(posedge clk) 
     begin
       int i;
       for(i = 0;i<`c_wrsw_num_ports ;i++)
       begin
         rtu_rsp_valid[i] = rtu_rsp_valid[i] & !rtu_rsp_ack[i];
         rtu_drop[i]      = rtu_drop[i]      & !rtu_rsp_ack[i];
       end
     end	    
        
        
      
  // and the party starts here....      
  initial begin        
      EthPacket      pkt, tmpl;
      EthPacket      txed[$];
      EthPacketGenerator gen;
      int i;
      src = new[7];
      sink = new[7];
      
      src[0]  = new(U_wrf_source_0.get_accessor());
      src[1]  = new(U_wrf_source_1.get_accessor());
      src[2]  = new(U_wrf_source_2.get_accessor());
      src[3]  = new(U_wrf_source_3.get_accessor());
      src[4]  = new(U_wrf_source_4.get_accessor());
      src[5]  = new(U_wrf_source_5.get_accessor());
      src[6]  = new(U_wrf_source_6.get_accessor());
       
//      U_wrf_sink_1.permanent_stall_enable();
 
      sink[0]   = new(U_wrf_sink_0.get_accessor()); 
      sink[1]   = new(U_wrf_sink_1.get_accessor()); 
      sink[2]   = new(U_wrf_sink_2.get_accessor()); 
      sink[3]   = new(U_wrf_sink_3.get_accessor()); 
      sink[4]   = new(U_wrf_sink_4.get_accessor()); 
      sink[5]   = new(U_wrf_sink_5.get_accessor()); 
      sink[6]   = new(U_wrf_sink_6.get_accessor()); 
      
     
      
      gen       = new;
      
//       for(i = 0;i<`c_wrsw_num_ports ;i++)
// 	rtu_rsp_valid[i] = 1;
      
      @(posedge rst_n);
      @(posedge clk);
      wait_cycles(500);
      
//      ports_ready  	= 1; // let now the ports to start sending
      
      //load_port(src, 0, n_packets_to_send);
      send_random_packet(src,txed, 0 /*port*/, 0 /*drop*/,7 /*prio*/, 2 /*mask*/);    
//      send_random_packet(src,txed, 0, 0,7 , 3);    
//      send_random_packet(src,txed, 0, 1,7 , 3);    
//      send_random_packet(src,txed, 0, 0,7 , 3);    
//      send_random_packet(src,txed, 0, 0,7 , 3);    
        for(i=0; i<1000; i++)
 	begin  
 	  send_random_packet(src,txed, i%7, 0,7 , 7);  
//  	  if(! i%10)  U_wrf_source_0.error_on_byte(10);
// 	  else      U_wrf_source_0.error_on_byte(0);
	  wait_cycles(500);
/* 	  if(i==80)
 	    U_wrf_sink_1.permanent_stall_disable();*/
         end 
      
      wait_cycles(500);
      
      check_transfer(); // here we wait for all pcks to be received and then make statistics
      
  end // initial
  
   ////////////////////////// sending frames /////////////////////////////////////////
     
   initial begin
      int i;
      wait(ports_ready);
      load_port(src, 0, n_packets_to_send);
   end
   
   initial begin
      wait(ports_ready);
      load_port(src, 1, n_packets_to_send);
   end
   
   initial begin
      wait(ports_ready);
      load_port(src, 2, n_packets_to_send);
   end

   initial begin
      wait(ports_ready);
      load_port(src, 3, n_packets_to_send);
   end

   initial begin
      wait(ports_ready);
      load_port(src, 4, n_packets_to_send);
   end
   initial begin
     wait(ports_ready);
     load_port(src, 5, n_packets_to_send);
   end
   initial begin
       wait(ports_ready);
      load_port(src, 6, n_packets_to_send);
   end
     
     
   ////////////////////////// receiving frames ///////////////////////////////////
     
   always @(posedge clk) if (sink[0].poll())
     begin
       EthPacket pkt;
       sink[0].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][0]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",0, pkt.src[0],rx_cnt_by_port[pkt.src[0]][0]);
     end
   always @(posedge clk) if(sink[1].poll())
     begin
       EthPacket pkt;
       sink[1].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][1]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",1, pkt.src[0],rx_cnt_by_port[pkt.src[0]][1]);
     end
   always @(posedge clk) if (sink[2].poll())
     begin
       EthPacket pkt;
       sink[2].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][2]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",2, pkt.src[0],rx_cnt_by_port[pkt.src[0]][2]);
     end
   always @(posedge clk) if (sink[3].poll())
     begin
       EthPacket pkt;
       sink[3].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][3]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",3, pkt.src[0],rx_cnt_by_port[pkt.src[0]][3]);
     end
   always @(posedge clk) if (sink[4].poll())
     begin
       EthPacket pkt;
       sink[4].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][4]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",4, pkt.src[0],rx_cnt_by_port[pkt.src[0]][4]);
     end
   always @(posedge clk) if (sink[5].poll())
     begin
       EthPacket pkt;
       sink[5].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][5]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",5, pkt.src[0],rx_cnt_by_port[pkt.src[0]][5]);
     end     
   always @(posedge clk) if (sink[5].poll())
     begin
       EthPacket pkt;
       sink[6].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][6]++;
       if(dbg) $display("Received @ port_%1d from port_%1d [pkt nr=%4d]",6, pkt.src[0],rx_cnt_by_port[pkt.src[0]][6]);
     end      
  
  
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring allocation of pages  /////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//   always @(posedge clk) if(DUT.memory_management_unit.pg_addr_valid)
   always @(posedge clk) if(DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_alloc & DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_done)

     begin
     int address;  
     int usecnt;
     
     usecnt = DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_usecnt;
     
     wait(DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_addr_valid);
     
     address =  DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_addr_alloc;
     pg_alloc_cnt[address][pg_alloc_cnt[address][0]+1]= usecnt;
     pg_alloc_cnt[address][0]++;
     
     alloc_table[address].usecnt[alloc_table[address].cnt]   = usecnt;
     alloc_table[address].port[alloc_table[address].cnt]     = DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.in_sel;
     alloc_table[address].cnt++;


     
	   end   


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring deallocation of pages  /////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
   	   
   always @(posedge clk) if(DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.alloc_core.tmp_dbg_dealloc)
     begin
     int address;  
    
     address =  DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.alloc_core.tmp_page;  

     pg_dealloc_cnt[address][0]++;
       
     dealloc_table[address].cnt++;  
       
     end 	   



///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring freeing of pages  /////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////// 
          
   always @(posedge clk) if(DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_free & DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_done)
     begin
     int address;  
     int port_mask;
     int port;
     
     port      = DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.in_sel;    
     address   = DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_addr;  
     port_mask = dealloc_table[address].port[dealloc_table[address].cnt ] ;
     
     pg_dealloc_cnt[address][pg_dealloc_cnt[address][0] + 1]++;
     
     dealloc_table[address].port[dealloc_table[address].cnt ] = ((1 << port) | port_mask) & 'h7FF;     
     dealloc_table[address].usecnt[dealloc_table[address].cnt ]++;
     
     
       
     end 	      
 
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////// Monitoring setting of pages' usecnt /////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////     
     
   always @(posedge clk) if(DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_set_usecnt & DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_done)
     begin
     int address;  

     address =  DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_addr;  
       
     pg_alloc_cnt[address][pg_alloc_cnt[address][0] + 1] =  DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_usecnt;
     
     alloc_table[address].usecnt[alloc_table[address].cnt - 1]   = DUT_xswc_core_wrapper.DUT_swc_core_7ports_wrapper.U_xswc_core.memory_management_unit.pg_usecnt;;

       
     end 	  
  
endmodule // main
