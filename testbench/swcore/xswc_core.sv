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

      WBPacketSource src[];
      WBPacketSink   sink[];
   
   reg clk  = 1'b0;
   reg rst_n = 1'b0;
   // generate clock and reset signals
   always #(`c_clock_period/2) clk <= ~clk;
   initial begin 
      repeat(3) @(posedge clk);
      rst_n <= 1'b1;
   end

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

  task automatic send_random_packets_to_single_port(ref WBPacketSource src[],ref  EthPacket q[$], input integer port, input int n_packets);
      int i, seed = 0;
      integer index;
      EthPacket pkt, tmpl;
      EthPacketGenerator gen  = new;
     
      tmpl                   = new;
      tmpl.src               = '{1,2,3,4,5,6};
      tmpl.dst               = '{10,11,12,13,14,15};
      tmpl.has_smac          = 1;
      tmpl.is_q              = 0;
      
      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD | EthPacketGenerator::ETHERTYPE /*| EthPacketGenerator::RX_OOB*/) ;
      gen.set_template(tmpl);
      gen.set_size(46, 1000);

     for(i=0;i<n_packets;i++)
       begin
          pkt         = gen.gen();
          q.push_back(pkt);
	  //index       = $dist_uniform(seed,0,6);
	  //src[index].send(pkt);
	  
	  set_rtu_rsp(port,1,0 /*drop*/,0/*prio*/,16'b1 /*mask*/); 
	  $display("Send!");
          src[port].send(pkt);
       end
   endtask // send_random_packets
	
	
  task automatic send_random_packets_to_random_port(ref WBPacketSource src[],ref EthPacket q[$], input int n_packets);
      int i, seed = 0;
      integer port;

     for(i=0;i<n_packets;i++)
       begin
          port       = $dist_uniform(seed,0,6);
	  send_random_packets_to_single_port(src,q,port,1);
       end
   endtask // send_random_packets	
	
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
      
      // sending 10 frames to port 0
      send_random_packets_to_single_port(src, txed, 0, 10);
      
      
  end // initial
  
  
   always @(posedge clk) if (sink[0].poll())
     begin
       EthPacket pkt;
       sink[0].recv(pkt);
       $display("Received @ port_%d",0);
     end
   always @(posedge clk) if (sink[1].poll())
     begin
       EthPacket pkt;
       sink[1].recv(pkt);
       $display("Received @ port_%d",1);
     end
   always @(posedge clk) if (sink[2].poll())
     begin
       EthPacket pkt;
       sink[2].recv(pkt);
       $display("Received @ port_%d",2);
     end
   always @(posedge clk) if (sink[3].poll())
     begin
       EthPacket pkt;
       sink[3].recv(pkt);
       $display("Received @ port_%d",3);
     end
   always @(posedge clk) if (sink[4].poll())
     begin
       EthPacket pkt;
       sink[4].recv(pkt);
       $display("Received @ port_%d",4);
     end
   always @(posedge clk) if (sink[5].poll())
     begin
       EthPacket pkt;
       sink[5].recv(pkt);
       $display("Received @ port_%d",5);
     end     
   always @(posedge clk) if (sink[6].poll())
     begin
       EthPacket pkt;
       sink[6].recv(pkt);
       $display("Received @ port_%d",6);
     end      
  
endmodule // main
