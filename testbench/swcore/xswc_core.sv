// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        8
`define c_swc_page_addr_width 10
`define c_swc_usecount_width  4 
`define c_wrsw_prio_width     3
`define c_swc_ctrl_width      4
`define c_swc_data_width      16
//`define c_wrsw_num_ports      11
`define c_wrsw_num_ports      7


`timescale 1ns / 1ps

`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"

`include "xswcore_wrapper.svh"

`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];


typedef struct {
   int cnt;
   int usecnt[10];
   int port[10];

} alloc_info_t;

alloc_info_t alloc_table[1024];
alloc_info_t dealloc_table[1024];

int stack_bastard = 0;

int pg_alloc_cnt[1024][20];
int pg_dealloc_cnt[1024][20];

module main;


   
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

   
   xswcore_wrapper
    DUT_xswcore_wrapper (
    .clk_i                 (clk),
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
    
    task automatic wait_cycles;
       input [31:0] ncycles;
       begin : wait_body
	  integer i;
 
	  for(i=0;i<ncycles;i=i+1) @(posedge clk);
 
       end
    endtask // wait_cycles
    

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

  task automatic send_random_packet(
	ref 				WBPacketSource src[],
	ref  				EthPacket q[$], 
	input [31:0]                    port,
	input                           drop,
	input [`c_wrsw_num_ports - 1:0] prio,
	input [`c_wrsw_num_ports - 1:0] mask
      );
      
      int i, j, seed = 0;
      integer index;
      EthPacket pkt, tmpl;
      EthPacketGenerator gen  = new;
     
      tmpl                   = new;
      tmpl.src               = '{1,2,3,4,5,6};
      tmpl.dst               = '{10,11,12,13,14,15};
      tmpl.has_smac          = 1;
      tmpl.is_q              = 0;
      tmpl.src[0]            = port;
      
      
      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD | EthPacketGenerator::ETHERTYPE /*| EthPacketGenerator::RX_OOB*/) ;
      gen.set_template(tmpl);
      gen.set_size(46, 1000);

      pkt         = gen.gen();
      q.push_back(pkt);
     
      set_rtu_rsp(port,1,drop /*drop*/,prio /*prio*/,mask /*mask*/); 
      src[port].send(pkt);
      if(drop == 0 && mask != 0)
       begin
         for(j=0;j<`c_wrsw_num_ports;j++)
         begin
           if(mask[j]) 
             tx_cnt_by_port[port][j]++; 
         end
       end
      $display("Sent:[@port_%1d, to mask=0x%x, with prio=%1d]!", port, mask, prio);
      
      
   endtask // send_random_packets
	
	
  task automatic check_transfer;
    begin
    
      int i,j, cnt;
      int sum_rx=0, sum_tx=1, sum_tx_by_port[11],sum_rx_by_port[11];

      
      
      while(sum_tx != sum_rx)
	begin 
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
	
		//$display("sum_tx = %3d  <-> sum_rx = %3d", sum_tx, sum_rx);
		wait_cycles(50);
	
	end
      
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
      
//       for(i=0;i<11;i++)
// 	begin
// 	  for(j=0;j<11;j++) sum_tx_by_port[i] += tx_cnt_by_port[j][i];
// 	  for(j=0;j<11;j++) sum_rx_by_port[i] += rx_cnt_by_port[i][j];
// 	  $display("Tx Port %2d : pcks sent to P%2d = %2d, pcks received on P%2d = %2d",i,i, sum_tx_by_port[i],i ,sum_rx_by_port[i]);
// 	end
// 
//       for(i=0;i<11;i++) sum_tx += sum_tx_by_port[i];
//       for(i=0;i<11;i++) sum_rx += sum_rx_by_port[i];

      $display("=======================================================================");
      $display("SUM    :  sent pcks = %2d, received pcks = %2d", sum_tx,sum_rx);
      $display("=================================== DBG ===============================");

      
      
     end
   endtask // check_transfer	
	
/*  task automatic send_random_packets_to_random_port(ref WBPacketSource src[],ref EthPacket q[$], input int n_packets);
      int i, seed = 0;
      integer port;

     for(i=0;i<n_packets;i++)
       begin
          port       = $dist_uniform(seed,0,6);
	  send_random_packets_to_single_port(src,q,port,1);
       end
   endtask // send_random_packets*/	
	
   // generate RTUs' acks (fake RTU)
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
      //WBPacketSource src[];
      //WBPacketSink   sink[];
      EthPacket      pkt, tmpl;
      EthPacket      txed[$];
      EthPacketGenerator gen;
      
      src = new[7];
      sink = new[7];
      
      src[0]  = new(U_wrf_source_0.get_accessor());
      src[1]  = new(U_wrf_source_1.get_accessor());
      src[2]  = new(U_wrf_source_2.get_accessor());
      src[3]  = new(U_wrf_source_3.get_accessor());
      src[4]  = new(U_wrf_source_4.get_accessor());
      src[5]  = new(U_wrf_source_5.get_accessor());
      src[6]  = new(U_wrf_source_6.get_accessor());
      
 
      sink[0]   = new(U_wrf_sink_0.get_accessor()); 
      sink[1]   = new(U_wrf_sink_1.get_accessor()); 
      sink[2]   = new(U_wrf_sink_2.get_accessor()); 
      sink[3]   = new(U_wrf_sink_3.get_accessor()); 
      sink[4]   = new(U_wrf_sink_4.get_accessor()); 
      sink[5]   = new(U_wrf_sink_5.get_accessor()); 
      sink[6]   = new(U_wrf_sink_6.get_accessor()); 
      
      gen       = new;
        
      @(posedge rst_n);
      @(posedge clk);
      wait_cycles(50);
      

      send_random_packet(src,txed, 0 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      send_random_packet(src,txed, 1 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      send_random_packet(src,txed, 2 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      send_random_packet(src,txed, 3 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      send_random_packet(src,txed, 4 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      send_random_packet(src,txed, 5 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      send_random_packet(src,txed, 6 /*port*/,0 /*drop*/ , 0 /*prio*/, 7 /*mask*/ );
      
      wait_cycles(500);
      
      check_transfer();
      
  end // initial
  
     
   always @(posedge clk) if (sink[0].poll())
     begin
       EthPacket pkt;
       sink[0].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][0]++;
       $display("Received @ port_%1d from port_%1d",0, pkt.src[0]);
     end
   always @(posedge clk) if (sink[1].poll())
     begin
       EthPacket pkt;
       sink[1].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][1]++;
       $display("Received @ port_%1d from port_%1d",1, pkt.src[0]);
     end
   always @(posedge clk) if (sink[2].poll())
     begin
       EthPacket pkt;
       sink[2].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][2]++;
       $display("Received @ port_%1d from port_%1d",2, pkt.src[0]);
     end
   always @(posedge clk) if (sink[3].poll())
     begin
       EthPacket pkt;
       sink[3].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][3]++;
       $display("Received @ port_%1d from port_%1d",3, pkt.src[0]);
     end
   always @(posedge clk) if (sink[4].poll())
     begin
       EthPacket pkt;
       sink[4].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][4]++;
       $display("Received @ port_%1d from port_%1d",4, pkt.src[0]);
     end
   always @(posedge clk) if (sink[5].poll())
     begin
       EthPacket pkt;
       sink[5].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][5]++;
       $display("Received @ port_%1d from port_%1d",5, pkt.src[0]);
     end     
   always @(posedge clk) if (sink[5].poll())
     begin
       EthPacket pkt;
       sink[6].recv(pkt);
       rx_cnt_by_port[pkt.src[0]][6]++;
       $display("Received @ port_%1d from port_%1d",6, pkt.src[0]);
     end      
  
endmodule // main
