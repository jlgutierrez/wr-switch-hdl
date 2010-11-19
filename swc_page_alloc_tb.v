`timescale 1ns / 1ps

`define NUM_PAGES 2048
`define PAGE_ADDR_BITS 11
`define USE_COUNT_BITS 4

`define CLK_PERIOD 10

module main;
   reg clk    = 0;
   reg rst    = 0;

   reg alloc  = 0;
   reg free   = 0;
   
   wire idle;
   wire nomem;
   
   reg [`USE_COUNT_BITS-1:0] use_cnt;
   wire [`PAGE_ADDR_BITS-1:0] pgaddr_o;
   reg [`PAGE_ADDR_BITS-1:0] pgaddr_i=0;
   wire pgaddr_valid;

   reg force_free = 0;
   
   reg set_usecnt = 0;
   
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   swc_page_allocator #(
    .g_num_pages      (`NUM_PAGES),
    .g_page_addr_bits (`PAGE_ADDR_BITS),
    .g_use_count_bits (`USE_COUNT_BITS))
   dut (
    .clk_i         (clk),
    .rst_n_i       (rst),

    .alloc_i       (alloc),
	  .free_i        (free),
	  .force_free_i  (force_free),
	  .set_usecnt_i  (set_usecnt),
	  .pgaddr_i      (pgaddr_i),
    .usecnt_i      (use_cnt),
    .pgaddr_o      (pgaddr_o),
	  .nomem_o       (nomem),
   	.pgaddr_valid_o(pgaddr_valid),
    .idle_o        (idle)
    );


   task alloc_page;
      input [`USE_COUNT_BITS:0] cnt;
      output[`PAGE_ADDR_BITS:0] pageaddr;
      
      begin
	 if(nomem) begin
	    $display("alloc_page: no more free pages left");
	    $finish;
	    
	 end else begin
	 
	 use_cnt  = cnt;
	 alloc 	 <= 1;

	 @(posedge clk); #1;
	 
	 alloc 	  <= 0;
	 
	   while(idle == 0) begin 
	      if(pgaddr_valid) 	 pageaddr <= pgaddr_o;

	      @(posedge clk); #1; 
	   end

	 end
     
	 
	 
      end
   endtask // allocate_page

   task free_page;
     input[`PAGE_ADDR_BITS:0] pageaddr;    
     begin
	 
   	 pgaddr_i = pageaddr;
   	 free 	 <= 1;

	   @(posedge clk); #1;
	 
   	 free 	  <= 0;
	 
	   while(idle == 0) 
	   begin 
	      @(posedge clk); #1; 
	   end
	 
     end
   endtask 

   task set_usecount;
      input [`USE_COUNT_BITS:0]  cnt;
      input [`PAGE_ADDR_BITS:0] pageaddr;
      begin
	 
      pgaddr_i      = pageaddr;
	    use_cnt       = cnt;
	    set_usecnt 	 <= 1;

    	 @(posedge clk); #1;
	 
    	 set_usecnt 	 <= 0;
	 
	    while(idle == 0) 
	      begin 
	      @(posedge clk); #1; 
    	   end
      end
   endtask 

   task force_free_page;
     input[`PAGE_ADDR_BITS:0] pageaddr;    
     begin
	 
   	 pgaddr_i      = pageaddr;
   	 force_free 	 <= 1;

	   @(posedge clk); #1;
	 
   	 force_free 	  <= 0;
	 
	   while(idle == 0) 
	   begin 
	      @(posedge clk); #1; 
	   end
	 
     end
   endtask 
   
   integer i;
   integer n;
   
    
   initial begin
      @(posedge rst); @(posedge clk);#1;
      
      for (i=0;i<200;i=i+1) begin
	      alloc_page(1,n);
      	 $display(n);
      end

      for(i=0;i<200;i=i+1) free_page(i);

      for (i=0;i<200;i=i+1) begin
      	 alloc_page(1,n);
      	 $display(n);
      end

      //set_usecount(5,5);
      //set_usecount(30,1);
      //set_usecount(55,10);
      //set_usecount(100,2);

      @(posedge clk);#1;

      free_page(10);
      free_page(50);
      free_page(80);

      @(posedge clk);#1;

      alloc_page(1,n);
      set_usecount(3,n);
      free_page(n);
      free_page(n);
      free_page(n);

      alloc_page(1,n);
      set_usecount(3,n);
      force_free_page(n);

      alloc_page(1,n);

      free_page(n);

      
      force_free_page(100);
      force_free_page(90);
      force_free_page(20);

      alloc_page(1, n); $display(n);
      alloc_page(1, n); $display(n);
      alloc_page(1, n); $display(n);
      
      
      
      

      
   end
   

   
   
   

endmodule // main
