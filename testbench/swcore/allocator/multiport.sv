`timescale 1ns/1ns

`include "common.svh"

module main;

   `define c_num_ports 7
   `define c_page_addr_width 10
   `define c_use_count_width 4
   
   reg    clk = 0;
   reg    rst_n = 0;

   IAllocatorPort alloc_port[`c_num_ports] (clk) ;
   VIAllocatorPort valloc_port[`c_num_ports] = alloc_port;


   genvar i;

   wire [`c_num_ports-1:0]  alloc_v, free_v, force_free_v, set_usecnt_v;
   wire [`c_num_ports-1:0]  alloc_done_v, free_done_v, force_free_done_v, set_usecnt_done_v;
   wire [`c_num_ports * `c_page_addr_width - 1 : 0] pgaddr_free_v, pgaddr_force_free_v, pgaddr_usecnt_v;
   wire [`c_num_ports * `c_use_count_width - 1 : 0] usecnt_v;
   wire [`c_page_addr_width-1:0]                    pg_addr_alloc;
   
                                
   generate
      for(i=0;i<`c_num_ports;i++)
        begin
           assign alloc_v[i] = alloc_port[i].alloc;
           assign free_v[i] = alloc_port[i].free;
           assign force_free_v[i] = alloc_port[i].force_free;
           assign set_usecnt_v[i] = alloc_port[i].set_usecnt;
           assign alloc_port[i].done = (alloc_done_v[i] | free_done_v[i] | force_free_done_v[i] | set_usecnt_done_v[i]);
           assign alloc_port[i].pg_addr_alloc = pg_addr_alloc;
           assign pgaddr_free_v[(i+1) * `c_page_addr_width - 1: i * `c_page_addr_width] = alloc_port[i].pg_addr_free;
           assign pgaddr_force_free_v[(i+1) * `c_page_addr_width - 1: i * `c_page_addr_width] = alloc_port[i].pg_addr_force_free;
           assign pgaddr_usecnt_v[(i+1) * `c_page_addr_width - 1: i * `c_page_addr_width] = alloc_port[i].pg_addr_usecnt;
           assign usecnt_v[(i+1) * `c_use_count_width - 1 : i * `c_use_count_width]=alloc_port[i].usecnt;
        end
      
   endgenerate
   

   
   
   swc_multiport_page_allocator
  #(
    .g_page_num (1024),
    .g_page_addr_width (10),
    .g_num_ports      (7),
    .g_usecount_width (4)
    ) DUT (
           .clk_i   (clk),
           .rst_n_i (rst_n),

           .alloc_i (alloc_v),
           .free_i(free_v),
           .force_free_i(force_free_v),
           .set_usecnt_i(set_usecnt_v),

           .alloc_done_o(alloc_done_v),
           .free_done_o(free_done_v),
           .force_free_done_o(force_free_done_v),
           .set_usecnt_done_o(set_usecnt_done_v),

           .pgaddr_free_i(pgaddr_free_v),
           .pgaddr_force_free_i(pgaddr_force_free_v),
           .pgaddr_usecnt_i(pgaddr_usecnt_v),
           .usecnt_i(usecnt_v),

           .pgaddr_alloc_o(pg_addr_alloc)
           );

   const int MAX_USE_COUNT=3;
   int       uniq_id = 0;
   
         
       
   always #5ns clk <= ~clk;
   initial begin
      repeat(3) @(posedge clk);
      rst_n = 1;
   end

   task automatic test_port(VIAllocatorPort port, int initial_seed, int n_seeds, int n_requests);
      
      alloc_request_t rqs[$];
      int seed;

      for(seed = initial_seed; seed < initial_seed + n_seeds; seed++)
        begin
           automatic int init_seed = seed;
           int occupied, peak;
           
           rqs = '{};
           gen_random_requests(rqs, n_requests, init_seed, 100);
           count_occupied_pages(rqs, peak, occupied, rqs.size()-1);
           $display("Peak Page Usage: %d\n", peak);
           
           execute_requests(port, rqs, 0);
        end
     endtask // test_port
      
   initial begin
      int port_idx;
     
      while(!rst_n) @(posedge clk);

      for(port_idx=0;port_idx < 7; port_idx++)
        fork
           automatic int k_idx = port_idx;
           test_port(valloc_port[k_idx], k_idx * 100, 100, 200);
        join_none

      repeat(1000000) @(posedge clk);
      
      $display("AtTheEnd: free_blocks = %-1d", DUT.ALLOC_CORE.free_blocks);
      if(DUT.ALLOC_CORE.free_blocks != 1023)
        $fatal("Pages missing");
      
   end // initial begin

endmodule // main
