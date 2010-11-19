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

   reg [`NUM_PORTS * 10 - 1:0] read_pump_addr = 0;
   reg [`NUM_PORTS * 10 - 1:0] free_pck_addr = 0;
   reg [`NUM_PORTS * 10 - 1:0] write_addr = 0;
   reg [`NUM_PORTS * 10 - 1:0] free_page_addr = 0;
   
   reg [`NUM_PORTS * 10  - 1:0] write_data = 0;


   reg  [`NUM_PORTS-1:0] rq_write=0, rq_free_page_write=0, rq_free_pck_read = 0, rq_read = 0;
 
   wire [`NUM_PORTS-1:0] done_write, done_free,done_free_pck, done_read;
   wire [`PAGE_ADDR_BITS-1:0] data_out;

   task wait_cycles;
    input [31:0] ncycles;
    begin : wait_body
      integer i;

      for(i=0;i<ncycles;i=i+1) @(posedge clk);

    end
   endtask // wait_cycles


   task write_page_addr;
      input [4:0] channel;
      input [`PAGE_ADDR_BITS-1: 0] page_addr;
      input [`PAGE_ADDR_BITS-1: 0] page_data;
      begin : write_page_body
   integer lo, h,k;

   if(rq_write[channel]) begin
      $display("Wait...");
      while(rq_write[channel]) begin @(posedge clk); end
      
      @(posedge clk);
      end

      $display("Write! (ch=%d, p=%d,d=%d)", channel,page_addr,page_data);
   
      for (k=0; k < `PAGE_ADDR_BITS; k=k+1)
         write_addr[channel * `PAGE_ADDR_BITS + k] <= page_addr[k];

      for (k=0; k < `PAGE_ADDR_BITS; k=k+1)
         write_data[channel * `PAGE_ADDR_BITS + k] <= page_data[k];
   
      rq_write[channel] 	<= 1'b1;
      
      @(posedge clk);
   
      end
   endtask // write_page_body
   

   task write_free_page_addr;
      input [4:0] channel;
      input [`PAGE_ADDR_BITS-1: 0] page_addr;
      begin : write_free_page_body
   integer lo, h,k;

   if(rq_free_page_write[channel]) begin
      $display("Wait...");
      while(rq_free_page_write[channel]) begin @(posedge clk); end
      
      @(posedge clk);
      end

      $display("Free! (ch=%d, p=%d)", channel,page_addr);
   
      for (k=0; k < `PAGE_ADDR_BITS; k=k+1)
         free_page_addr[channel * `PAGE_ADDR_BITS + k] <= page_addr[k];
   
      rq_free_page_write[channel] 	<= 1'b1;
      
      @(posedge clk);
   
      end
   endtask // write_page_body
   
   
   task pump_read_page_addr;
      input [4:0] channel;
      input [`PAGE_ADDR_BITS-1: 0] page_addr;
      begin : pump_read_page_body
   integer lo, h,k;

   if(rq_read[channel]) begin
      $display("Wait...");
      while(rq_read[channel]) begin @(posedge clk); end
      
      @(posedge clk);
      end

      $display("Reading page data [by pump]! (ch=%d, p=%d)", channel,page_addr);
   
      for (k=0; k < `PAGE_ADDR_BITS; k=k+1)
         read_pump_addr[channel * `PAGE_ADDR_BITS + k] <= page_addr[k];
   
      rq_read[channel] 	<= 1'b1;
      
      @(posedge clk);
   
      end
   endtask // write_page_body   
  
   task free_pck_read_page_addr;
      input [4:0] channel;
      input [`PAGE_ADDR_BITS-1: 0] page_addr;
      begin : free_pck_read_page_body
   integer lo, h,k;

   if(rq_free_pck_read[channel]) begin
      $display("Wait...");
      while(rq_free_pck_read[channel]) begin @(posedge clk); end
      
      @(posedge clk);
      end

      $display("Reading page data [by pck free modul]! (ch=%d, p=%d)", channel,page_addr);
   
      for (k=0; k < `PAGE_ADDR_BITS; k=k+1)
         free_pck_addr[channel * `PAGE_ADDR_BITS + k] <= page_addr[k];
   
      rq_free_pck_read[channel] 	<= 1'b1;
      
      @(posedge clk);
   
      end
   endtask // write_page_body     
   
   swc_multiport_linked_list 
    DUT (
    
    .rst_n_i               (rst),
    .clk_i                 (clk),
    
     //requests
    .write_i               (rq_write),
    .free_i                (rq_free_page_write),
    .read_pump_read_i      (rq_read),
    .free_pck_read_i       (rq_free_pck_read),
    
     // done strobes
    .write_done_o          (done_write),
    .free_done_o           (done_free),
    .read_pump_read_done_o (done_read),
    .free_pck_read_done_o  (done_free_pck),
     
     //addresses  
    .read_pump_addr_i      (read_pump_addr),
    .free_pck_addr_i       (free_pck_addr),
    .write_addr_i          (write_addr),
    .free_addr_i           (free_page_addr),   
    
    //data
    .write_data_i          (write_data),
    .data_o                (data_out)
    );

     
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


   initial begin
      @(posedge rst);
      #(100);

      @(posedge clk);
      #1;


      
      //for (i=1;i<`NUM_PAGES/2;i=i+1) write_page_addr((i*7123) % `NUM_PORTS,(i*7123) % `NUM_PAGES, (i*7123) % `NUM_PAGES );
      for (i=1;i<`NUM_PAGES/2;i=i+1) write_page_addr((i*7123) % `NUM_PORTS, i , i);
      
      #(1000);

      @(posedge clk);
      #1;

      //for (i=1;i<`NUM_PAGES/2;i=i+1) pump_read_page_addr((i*7123) % `NUM_PORTS,(i*7123) % `NUM_PAGES );
      for (i=1;i<`NUM_PAGES/2;i=i+1) pump_read_page_addr((i*7123) % `NUM_PORTS,i);
      
      #(1000);

      @(posedge clk);
      #1;

      //for (i=1;i<`NUM_PAGES/2;i=i+1) free_pck_read_page_addr((i*7123) % `NUM_PORTS,(i*7123) % `NUM_PAGES );
      for (i=1;i<`NUM_PAGES/2;i=i+1) free_pck_read_page_addr((i*7123) % `NUM_PORTS,i );
      
      #(1000);

      @(posedge clk);
      #1;      
      
      for (i=1;i<`NUM_PAGES/2;i=i+1) 
      begin
        //free_pck_read_page_addr((i*7123) % `NUM_PORTS,(i*7123) % `NUM_PAGES );
        //pump_read_page_addr    ((i*7123) % `NUM_PORTS,(i*7123) % `NUM_PAGES );
        free_pck_read_page_addr((i*7123) % `NUM_PORTS,i);
        pump_read_page_addr    ((i*7123) % `NUM_PORTS,i);

      end
      
      #(1000);

      @(posedge clk);
      #1;       
      
      for (i=1;i<`NUM_PAGES/2;i=i+1) 
      begin
        //free_pck_read_page_addr((i*7123) % `NUM_PORTS,(i*7123) % `NUM_PAGES );
        //pump_read_page_addr    ((i*3456) % `NUM_PORTS,(i*3456) % `NUM_PAGES );
        //write_free_page_addr   ((i*9876) % `NUM_PORTS,(i*9876) % `NUM_PAGES );

        free_pck_read_page_addr((i*7123) % `NUM_PORTS, i);
        pump_read_page_addr    ((i*3456) % `NUM_PORTS, i);
        write_free_page_addr   ((i*9876) % `NUM_PORTS, i);

      end 
      
      #(1000);

      @(posedge clk);
      #1;

      
     
      wait_cycles(1000);

      
   end

   always@(posedge clk) 
     begin
     rq_write                 <= rq_write           & (~done_write);
     rq_free_page_write       <= rq_free_page_write & (~done_free);
     rq_read                  <= rq_read            & (~done_read);
     rq_free_pck_read         <= rq_free_pck_read    & (~done_free_pck);      

      
   end // UNMATCHED !!

endmodule // main