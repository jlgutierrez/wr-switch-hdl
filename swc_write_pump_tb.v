`timescale 1ns / 1ps

`define PAGE_ADDR_BITS 10
`define PAGE_SIZE 128
`define INPUT_WIDTH 20
`define MULTIPLY 16

`define CLK_PERIOD 10

module main;
   reg clk    = 0;
   reg rst    = 0;

   reg [`INPUT_WIDTH-1:0] d;

   wire reg_full  ;
   reg flush  = 0;

   reg [15:0] sync = 11'b00010000000;
   
   wire [`INPUT_WIDTH * `MULTIPLY - 1:0] q;
  
   wire we;
   reg drdy =0;
   wire pgend;   
   reg pckstart = 0;
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   reg [`PAGE_ADDR_BITS-1:0] page_addr=0;
   reg page_req  = 0;
   wire page_done;
   
   wire [`PAGE_ADDR_BITS-1:0] current_page_addr;
   wire [`PAGE_ADDR_BITS-1:0] next_page_addr;
   wire  next_page_addr_wr_req;
   reg   next_page_addr_wr_done = 0;
   
   
   swc_packet_mem_write_pump 
   
   
    DUT (
    .clk_i      (clk),
    .rst_n_i    (rst),

    .pgaddr_i   (page_addr), 
    .pgreq_i    (page_req),
    .pgend_o    (pgend),
    .pckstart_i (pckstart),
    .drdy_i     (drdy),
    .full_o     (reg_full),
    .flush_i    (flush),
    .sync_i     (sync[0]),

    .ll_addr_o   (current_page_addr),
    .ll_data_o   (next_page_addr),
    .ll_wr_req_o (next_page_addr_wr_req),
    .ll_wr_done_i(next_page_addr_wr_done),
    
    .d_i        (d),
    .q_o        (q),
    .we_o      (we)
    );

   task wait_cycles;
      input [31:0] ncycles;
      begin : wait_body
	 integer i;

	 for(i=0;i<ncycles;i=i+1) @(posedge clk);

      end
   endtask // wait_cycles
   
      
      

   task write_data;
      input [`INPUT_WIDTH - 1 : 0] in;
      begin : wr_body
	 while(reg_full) wait_cycles(1);

	 d    <= in;
	 drdy <= 1;
	 wait_cycles(1);
	 drdy <= 0;
      

      end
   endtask // write_data



   
   integer i, n;
   
   initial begin
     
//      page_addr <= 3;
      wait_cycles(10);

   	  // write first page number
//      page_req  <= 1;
//      pckstart <=1;
//      wait_cycles(1);
//      page_req <= 0;
//      pckstart <=0;

      for (n  =0; n<17;n=n+1) begin

         wait_cycles(1); 
         
         while(reg_full)  wait_cycles(1);
         
      	  wait_cycles(n);
   
         if(n%5 == 0) begin
        	  page_addr <= page_addr + 4;
 	         page_req  <= 1;
         end    

        pckstart <=1;         

	       for (i=0;i<100;i=i+1) begin
  
            if(n%5 != 0 && i == 5) begin
        	     page_addr <= page_addr + 4;
 	            page_req  <= 1;
            end   
  	         
    	       if(pgend & !page_req) begin
    	         page_req  <= 1;
    	         page_addr <= page_addr + 1;
  	         end
	           write_data(i);
	           page_req <= 0;
	           pckstart <=0;
	       end
	          
       	 flush <= 1;
       	 wait_cycles(1);
       	 flush <= 0;
      end
   end
   
   reg [4:0] r;

   always@(posedge clk) begin
     if(we) begin
    	   $display("write %x",q);
    	end
   end
   
   always@(posedge clk) sync <= {sync[0], sync[15:1]};
   
   //initial begin
   always@(posedge clk) begin
     if(next_page_addr_wr_req) begin
         $display("page write request");
         wait_cycles(4);
         next_page_addr_wr_done <=1;
         wait_cycles(1);
         next_page_addr_wr_done <=0;
     end
   end
   


   
endmodule // main
