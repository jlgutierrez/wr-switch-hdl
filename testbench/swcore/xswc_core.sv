// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        8
`define c_swc_page_addr_width 10
`define c_swc_usecount_width  4 
`define c_wrsw_prio_width     3
`define c_swc_ctrl_width      4
`define c_swc_data_width      16
`define c_wrsw_num_ports      11
//`define c_wrsw_num_ports      7


`timescale 1ns / 1ps

`include "if_wb_master.svh"
`include "if_wb_slave.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"

`include "swcore_wrapper.svh"

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

   
   reg clk 		       = 0;
   reg rst_n 		     = 0;


   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_0
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_1
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_2
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );
      
   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_3
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );
      
   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_4
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

      
   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_5
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

      
   IWishboneMaster 
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_source_6
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

      
      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_0
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );
            
      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_1
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_2
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );
      
      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_3
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );
   
      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_4
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_5
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );

      IWishboneSlave
     #(
       .g_data_width(16),
       .g_addr_width(2))
   U_wrf_sink_6
     (
      .clk_i(clk_sys),
      .rst_n_i(rst_n)
      );


      
   reg  [`c_wrsw_num_ports-1:0]                         rtu_rsp_valid        = 0;     
   wire [`c_wrsw_num_ports-1:0]                         rtu_rsp_ack;       
   reg  [`c_wrsw_num_ports * `c_wrsw_num_ports - 1 : 0] rtu_dst_port_mask    = 0; 
   reg  [`c_wrsw_num_ports-1:0]                         rtu_drop             = 0;          
   reg  [`c_wrsw_num_ports * `c_wrsw_prio_width -1 : 0] rtu_prio             = 0;     

   // generate clock and reset signals
   always #(`c_clock_period/2) clk <= ~clk;
   
   initial begin 
      repeat(3) @(posedge clk);
      rst_n  = 1;
   end
 
   int tx_cnt_0[11];
   int tx_cnt_1[11];
   int tx_cnt_2[11];
   int tx_cnt_3[11];
   int tx_cnt_4[11];
   int tx_cnt_5[11];
   int tx_cnt_6[11];
   int tx_cnt_7[11];
   int tx_cnt_8[11];
   int tx_cnt_9[11];
   int tx_cnt_10[11];

   int rx_cnt[11];
   
   int tx_cnt_by_port[11][11];
   int rx_cnt_by_port[11][11];
   
   int rx_cnt_0[11];
   int rx_cnt_1[11];
   int rx_cnt_2[11];
   int rx_cnt_3[11];
   int rx_cnt_4[11];
   int rx_cnt_5[11];
   int rx_cnt_6[11];
   int rx_cnt_7[11];
   int rx_cnt_8[11];
   int rx_cnt_9[11];
   int rx_cnt_10[11];
 
 
   bit [10:0] tx_port_finished = 0;//{0,0,0,0,0,0,0,0,0,0,0};
 
   integer ports_read = 0;

   
   swcore_wrapper
    DUT (
    .clk_i                 (clk),
    .rst_n_i               (rst_n),
//-------------------------------------------------------------------------------
//-- Fabric I/F  
//-------------------------------------------------------------------------------  

      .snk_0 (U_wrf_sink_0.slave),
      .snk_1 (U_wrf_sink_1.slave), 
      .snk_2 (U_wrf_sink_2.slave), 
      .snk_3 (U_wrf_sink_3.slave), 
      .snk_4 (U_wrf_sink_4.slave), 
      .snk_5 (U_wrf_sink_5.slave), 
      .snk_6 (U_wrf_sink_6.slave), 	 

//-------------------------------------------------------------------------------
//-- Fabric I/F : output (goes to the Endpoint)
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
    


	      
        
endmodule // main
