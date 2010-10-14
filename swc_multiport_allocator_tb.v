`timescale 1ns / 1ps

`define NUM_PORTS 11
`define NUM_PAGES 1024
`define PAGE_ADDR_BITS 10
`define USECNT_BITS 4

`define CLK_PERIOD 10

module main;

   reg clk  = 0;
   reg rst  = 0;
   
   
   integer i, j;
  
   
   integer fail  = 0;

   reg [`NUM_PORTS * 10 - 1:0] pgaddr_free = 0;
   
   reg [`NUM_PORTS * 4 - 1:0] usecnt_alloc = 0;
   wire [`PAGE_ADDR_BITS-1:0] pgaddr_alloc;

   reg [`NUM_PORTS-1:0] rq_alloc=0, rq_free=0;
   wire [`NUM_PORTS-1:0] done_alloc, done_free;

   reg [`PAGE_ADDR_BITS-1:0] pgaddr_alloc_tab [`NUM_PORTS-1:0];
   reg [`PAGE_ADDR_BITS-1:0] usecnt_alloc_tab [`NUM_PORTS-1:0];

   integer alloced_pages_map [0:`NUM_PAGES-1];
   integer alloced_pages_count 	= 0;
   
   

   task alloc_page_multi;
      input [4:0] channel;
      begin : alloc_body
	 integer lo, hi;

	 if(rq_alloc[channel]) begin
	    $display("Wait...");
	    while(!done_alloc[channel]) begin @(posedge clk); end
	    
	    @(posedge clk);
	    end

	 $display("Alloc! (ch %d)", channel);
	 
	    rq_alloc[channel] 	<= 1'b1;
	    
	    lo 			= channel * `USECNT_BITS;
	    
	 usecnt_alloc[lo]   <= 1'b0;
	    usecnt_alloc[lo+1] <= 1'b1;
	    usecnt_alloc[lo+2] <= 1'b0;
	    usecnt_alloc[lo+3] <= 1'b0;
	    
	 @(posedge clk);
	 
	 
      end
   endtask // alloc_page_multi

     task free_page_multi;
      input [4:0] channel;
	input [`PAGE_ADDR_BITS-1: 0] pageaddr;
	
      begin : free_body
	 integer k,n;

	 if(rq_free[channel]) begin
	    $display("Wait...");
	    while(!done_free[channel]) begin @(posedge clk); end
	    
	    @(posedge clk);
	    end

	 $display("Free! (ch %d, page %d)", channel, pageaddr);
	 
	 rq_free[channel] 			      <= 1'b1;
	 
	 for (k=0; k < `PAGE_ADDR_BITS; k=k+1)
	   pgaddr_free[channel * `PAGE_ADDR_BITS + k] <= pageaddr[k];
	 
    
	 @(posedge clk);
	 
	 
      end
   endtask
        
   
swc_multiport_page_allocator #(
    .g_num_ports      (`NUM_PORTS),
    .g_num_pages      (`NUM_PAGES),
    .g_page_addr_bits (`PAGE_ADDR_BITS),
    .g_use_count_bits (`USECNT_BITS)
) DUT (
    .rst_n_i (rst),
    .clk_i  (clk),

    .alloc_i (rq_alloc),
       .free_i (rq_free),
    .alloc_done_o  (done_alloc),
    .free_done_o (done_free),
       
    .pgaddr_free_i  (pgaddr_free),
    .usecnt_i       (usecnt_alloc),
    .pgaddr_alloc_o (pgaddr_alloc)
       
  
    );

     
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


   initial begin
      @(posedge rst);
      #(100);

      @(posedge clk);
      #1;

      for (i=0;i<`NUM_PAGES;i=i+1) alloced_pages_map[i] = 0;
      
      for (i=0;i<`NUM_PAGES/2;i=i+1) alloc_page_multi((i*7123) % `NUM_PORTS);
      
      #(1000);

      @(posedge clk);
      #1;

      for(i=0;i<`NUM_PAGES/2;i=i+1) free_page_multi((i*23) % `NUM_PORTS, i);
      for(i=0;i<`NUM_PAGES/2;i=i+1) free_page_multi((i*23) % `NUM_PORTS, i);

        #(1000);

      @(posedge clk);
      #1;

      alloc_page_multi(5);
      

      
   end

   always@(posedge clk) 
     begin
	rq_alloc <= rq_alloc & (~done_alloc);
	rq_free  <= rq_free & (~done_free);
      
      
      for (j=0;j<`NUM_PORTS;j=j+1) begin
	if(done_alloc[j]) begin
	   $display("Allocated: ch %d page %d", j, pgaddr_alloc);
	   
	end

      if(done_free[j]) begin
	 $display("freed page ch %d", j);
      end

	 end
      
   end // UNMATCHED !!
	    
 
      

endmodule // main



