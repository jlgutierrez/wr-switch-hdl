`timescale 1ns / 1ps

`define PAGE_ADDR_BITS 10
`define PAGE_SIZE 128
`define OUTPUT_WIDTH (16 + 4)//32
`define MULTIPLY 16
`define FBRAM_SIZE 256

`define CLK_PERIOD 10

module main;
   reg clk    = 0;
   reg rst    = 0;

   reg [`PAGE_ADDR_BITS-1:0] page_addr=0;
   reg page_req  = 0;
   wire pgend;
   
   wire drdy;
   reg dreq = 0;

   reg [15:0] sync = 11'b00010000000;
         
   wire [11:0]addr;
   reg [11:0]fb_sram_addr;
   wire [`OUTPUT_WIDTH-1:0] d;
   reg [`OUTPUT_WIDTH * `MULTIPLY - 1:0] q;
  
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   wire page_done;

   wire pckend;
   wire [`PAGE_ADDR_BITS-1 : 0] current_page_addr ;
   reg  [`PAGE_ADDR_BITS-1 : 0] next_page_addr = 0;
   
   reg [`FBRAM_SIZE - 1 : 0][`OUTPUT_WIDTH * `MULTIPLY - 1:0] fbsram ;
   reg [`FBRAM_SIZE - 1 : 0][`PAGE_ADDR_BITS - 1 : 0] llsram ;
   
   wire read_req;
   reg read_data_valid = 0;
   
   
   swc_packet_mem_read_pump 
   
   
    DUT (
    .clk_i     (clk),
    .rst_n_i   (rst),

    .pgaddr_i  (page_addr), 
    .pgreq_i   (page_req),
    .pgend_o   (pgend),
    .pckend_o  (pckend),
     
    .drdy_o    (drdy),
    .dreq_i    (dreq),
    .sync_i    (sync[0]),

    .ll_read_addr_o(current_page_addr),
    .ll_read_data_i(next_page_addr),
    .ll_read_req_o(read_req),
    .ll_read_valid_data_i(read_data_valid),
    .addr_o(addr),
    .d_o(d),
    .q_i(q)

    );

   task wait_cycles;
      input [31:0] ncycles;
      begin : wait_body
	 integer i;

	 for(i=0;i<ncycles;i=i+1) @(posedge clk);

      end
   endtask // wait_cycles
   
   task set_page_addr;
      input [11 : 0] in;
      begin : wr_body
        
        page_req   <= 1;
        page_addr  <= in;
        wait_cycles(1);
        page_req   <= 0;
      
      end
   endtask // write_data   
   
   task read_data;
      output [`OUTPUT_WIDTH - 1 : 0] out;
      begin : wr_body
        
        dreq <= 1;
	      while(!drdy) wait_cycles(1);

      	 out  <= out;
      	 wait_cycles(1);
        dreq <= 0;
      
      end
   endtask // write_data



   
   integer i, n, m,z, cnt = 0;
   integer readout[48];
   integer page = 8;
   initial begin
     
      llsram[0] = `PAGE_ADDR_BITS'h3;
      for (n = 0; n < `FBRAM_SIZE; n = n + 1) begin
        fbsram[n] = 512'h0;
        for (m = 0; m < `MULTIPLY; m = m + 1) begin
          fbsram[n] =  cnt << (m*`OUTPUT_WIDTH) | fbsram[n];
          cnt = cnt + 1;
        end;
        
        if(n != 0) llsram[n] = (llsram[n-1] + 3) % (`FBRAM_SIZE / 4);
 
        $display("cnt = %p; fbsram[%p] =  %x, llsram[%p] =  %x",cnt, n, fbsram[n],n,llsram[n]);
      end;
      
      for(z = 0; z < `PAGE_ADDR_BITS; z++) llsram[30][z] = 1; 
      for(z = 0; z < `PAGE_ADDR_BITS; z++) llsram[4][z] = 1;
      
      for (n = 0; n < `FBRAM_SIZE; n = n + 1) begin
        $display("WTF: llsram[%p] =  %x",n,llsram[n]);
      end;
      
      wait_cycles(10);
      
      set_page_addr(2);
      
      wait_cycles(3);      
      
      for (n  =0; n<20;n=n+1) begin
         
      	  wait_cycles(n);
 	       for (i=0;i<88;i=i+1) begin
	         if(pckend == 1 && (page < 9 || page > 20)) set_page_addr(page++);
           else if(pckend == 1 ) page++;
             
	         read_data(readout[i]);
        end;
	     	 wait_cycles(1);
      end
   end
   
   reg [4:0] r;

   always@(posedge clk) begin
     if(drdy) begin
    	end
   end
   
   
   always@(posedge clk) begin
     if(sync[0])
       fb_sram_addr <= addr;
     else
       fb_sram_addr <= 15;
   end
   
   always@(posedge clk) begin
     if(sync[1])
       q <= fbsram[addr];
     else
       q <= fbsram[15];
   end

//   always@(posedge clk) begin
//     next_page_addr <= llsram[current_page_addr];
//   end
    
    

    
    
   always@(posedge clk) sync <= {sync[0], sync[15:1]};
   

   always@(posedge clk) begin
     if(read_req) begin
         $display("page read request");
         wait_cycles(4);
         read_data_valid <=1;
         next_page_addr <= llsram[current_page_addr];
         wait_cycles(1);
         read_data_valid <=0;
     end
   end


   
endmodule // main
