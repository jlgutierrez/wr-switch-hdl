`timescale 1ns / 1ps

`define CLK_PERIOD 10

   

module main;

   parameter c_swc_num_ports 		= 11;
   parameter c_swc_packet_mem_size 	= 65536;
   parameter c_swc_packet_mem_multiply 	= 16;
   parameter c_swc_data_width 		= 16;
   parameter c_swc_ctrl_width 		= 4; //16;
   parameter c_swc_page_size 		= 64;


   
   parameter c_swc_packet_mem_num_pages = (c_swc_packet_mem_size / c_swc_page_size);
   parameter c_swc_page_addr_width 	= 10; //$clog2(c_swc_packet_mem_num_pages-1);
   parameter c_swc_usecount_width 	= 4;  //$clog2(c_swc_num_ports-1);
   parameter c_swc_page_offset_width 	= 2; //$clog2(c_swc_page_size / c_swc_packet_mem_multiply);
   parameter c_swc_packet_mem_addr_width= c_swc_page_addr_width + c_swc_page_offset_width;
   parameter c_swc_pump_width 		= c_swc_data_width + c_swc_ctrl_width;

   reg clk 				= 1;
   reg rst 				= 0;


   reg  [c_swc_packet_mem_multiply - 1 : 0]               sync = 1;
 
   reg  [c_swc_num_ports-1 : 0]                           wr_pagereq =0;
   reg  [c_swc_num_ports-1 : 0]                           wr_pckstart =0;
   
   wire [c_swc_num_ports-1 : 0]                           wr_pageend;
   reg  [c_swc_num_ports * c_swc_page_addr_width - 1 : 0] wr_pageaddr =0;

   reg  [c_swc_num_ports-1 : 0]                           rd_pagereq =0;

   
   wire [c_swc_num_ports-1 : 0]                           rd_pageend;
   reg  [c_swc_num_ports * c_swc_page_addr_width - 1 : 0] rd_pageaddr =0;

   
   reg  [c_swc_num_ports * c_swc_ctrl_width - 1 : 0]      wr_ctrl = 0;
   reg  [c_swc_num_ports * c_swc_data_width - 1 : 0]      wr_data = 0;
   
   reg  [c_swc_num_ports-1 : 0]                           wr_drdy  =0;
   
   wire [c_swc_num_ports-1 : 0]                           wr_full  ;
   reg  [c_swc_num_ports-1 : 0]                           wr_flush  =0;

   reg  [c_swc_num_ports-1 : 0]                           rd_dreq =0;
   wire [c_swc_num_ports-1 : 0]                           rd_drdy;
   reg  [c_swc_num_ports-1 : 0]                           rd_sync_read =0;
   wire [c_swc_num_ports * c_swc_ctrl_width - 1 : 0]      rd_ctrl;
   wire [c_swc_num_ports * c_swc_data_width - 1 : 0]      rd_data;
   
   wire [c_swc_num_ports-1 : 0]                           rd_pckend;
   wire [c_swc_num_ports-1 : 0]                           rd_page_end;

  
   swc_packet_mem DUT(

	.clk_i   (clk),
	.rst_n_i (rst),

	.wr_pagereq_i  (wr_pagereq),
	.wr_pageaddr_i (wr_pageaddr),
	.wr_pckstart_i (wr_pckstart),
 	.wr_pageend_o  (wr_pageend),

	.wr_ctrl_i     (wr_ctrl),
	.wr_data_i     (wr_data),

	.wr_drdy_i     (wr_drdy),
	.wr_full_o     (wr_full),
	.wr_flush_i    (wr_flush),
  
  .rd_pagereq_i  (rd_pagereq),
  .rd_pageaddr_i (rd_pageaddr),
  .rd_pageend_o  (rd_page_end),
  .rd_pckend_o   (rd_pckend), 
	.rd_dreq_i     (rd_dreq),
 	.rd_sync_read_i(rd_sync_read),
 	.rd_drdy_o     (rd_drdy),
	.rd_data_o     (rd_data),
	.rd_ctrl_o     (rd_ctrl)
    );
   
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


      
`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];
   

`define wait_cycles(x) for(int iii=0;iii<x;iii++) @(posedge clk);
   
task pktmem_write;
      input [4:0] channel;
      input [c_swc_data_width-1:0] data;
      input [c_swc_ctrl_width-1:0] ctrl;
      
      begin : wr_body
	 integer k;
	 
	 while(wr_full[channel]) `wait_cycles(1)
	 

	 $display("PKT_write: t %d chan %d data %x ctrl %x", $time, channel, data,ctrl);
	 

	 `array_copy(wr_data, (c_swc_data_width * channel + c_swc_data_width -1), c_swc_data_width * channel, data, 0);
	 `array_copy(wr_ctrl, (c_swc_ctrl_width * channel + c_swc_ctrl_width -1), c_swc_ctrl_width * channel, ctrl, 0);
	 wr_drdy[channel] <= 1'b1;
	 `wait_cycles(1);
	 wr_drdy[channel] <= 1'b0;
      end
   endtask // pktmem_write

   task pktmem_write_flush;
      input [4:0] channel;
      
      begin
	 if(wr_full[channel]) return;
	 
	 wr_flush[channel] <= 1'b1;
	 `wait_cycles(1);
	 wr_flush[channel] <= 1'b0;
	 
	 
      end
      
   endtask // pktmem_write_flush
   
      

   
   task pktmem_read;
      input [4:0] channel;
      input [10:0] count;
      
      input [c_swc_data_width-1:0] data[0:c_swc_page_size -1];
      input [c_swc_ctrl_width-1:0] ctrl[0:c_swc_page_size -1];
      input [c_swc_page_addr_width-1:0] next_page=0;
      
      
      begin : rd_body
	 integer k,n;
	 
	 
	 for (n=0;n<count;n=n+1) begin
	  //  $display("read n=%d", n);
	    
	    while(!rd_drdy[channel]) `wait_cycles(1);
	    rd_dreq[channel] <= rd_drdy[channel];

	    $display("rddata: %x", rd_data);
	    
	    `array_copy(data[k], c_swc_data_width-1, 0, rd_data, c_swc_data_width * channel);
	   `array_copy(ctrl[k], c_swc_ctrl_width-1, 0, rd_ctrl, c_swc_ctrl_width * channel);

	    $display("read data %x", data[k]);
	    
      if(n==0) rd_sync_read<=1;
	    
	    `wait_cycles(1);
      
      rd_sync_read<=0;
	    
	 end
      end
      
   endtask 

   integer i;
  
   
 

   
   integer request_stuff  = 0;

   reg [c_swc_ctrl_width-1:0] cbuf[0:c_swc_page_size-1];
   reg [c_swc_data_width-1:0] dbuf[0:c_swc_page_size-1];

   reg dupa=0, cipa=0;

   initial fork begin `wait_cycles(10); dupa = 1; end
      begin `wait_cycles(50); cipa = 1; end join
      
      
   
   initial begin
      integer i;
      `wait_cycles(10);
      
      
      $display("ML: writing ......");
      wr_pageaddr <= 4;
      wr_pckstart[0] <=1;
      wr_pagereq[0]  <= 1;
      for (i=3;i<200;i=i+1) begin
        
         if(wr_pageend[0] & !wr_pagereq[0]) begin
           wr_pagereq[0]  <= 1;
           wr_pageaddr <= wr_pageaddr + 1;
         end
         
         pktmem_write(0, i, 'hffff);
         
         wr_pckstart[0] <= 0;
         wr_pagereq[0] <= 0;
      end
      
      //for (i=3;i<62;i=i+1) pktmem_write(1, i, 'hffff);
      
      //for (i=3;i<62;i=i+1) pktmem_write(i%16, i, 'hffff);
      
      $display("ML: flusing writing ......");
      pktmem_write_flush(0);
   end

   initial begin
      integer i;
      `wait_cycles(100);
      
      $display("ML: reading ......");
      
      rd_pageaddr <= 4;
      rd_pagereq   <= 11'b11111111111;
      `wait_cycles(1);
      rd_pagereq   <=0;
            
      pktmem_read(0, 60, dbuf,cbuf, 0);    
   end
	 
   endmodule // main
