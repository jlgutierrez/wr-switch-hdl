`timescale 1ns / 1ps

`define CLK_PERIOD 10

`define wait_cycles(x) for(int iii=0;iii<x;iii++) @(posedge clk);

`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];

module main;

   integer start = 0;
   
   
   parameter c_swc_num_ports 		= 11;
   parameter c_swc_packet_mem_size 	= 65536;
   parameter c_swc_packet_mem_multiply 	= 16;
   parameter c_swc_data_width 		= 16;
   parameter c_swc_ctrl_width 		= 16;
   parameter c_swc_page_size 		= 64;
   parameter c_swc_prio_width  = 3; 

   
   parameter c_swc_packet_mem_num_pages = (c_swc_packet_mem_size / c_swc_page_size);
   parameter c_swc_page_addr_width 	= 10; //$clog2(c_swc_packet_mem_num_pages-1);
   parameter c_swc_usecount_width 	= 4;  //$clog2(c_swc_num_ports-1);
   parameter c_swc_page_offset_width 	= 2; //$clog2(c_swc_page_size / c_swc_packet_mem_multiply);
   parameter c_swc_packet_mem_addr_width= c_swc_page_addr_width + c_swc_page_offset_width;
   parameter c_swc_pump_width 		= c_swc_data_width + c_swc_ctrl_width;

   
   reg clk 				= 1;
   reg rst 				= 0;
   
   reg  [c_swc_num_ports -1 : 0]                       ob_data_valid_d1=0;
   
   wire [c_swc_num_ports -1 : 0]                       ob_data_valid;    
   reg  [c_swc_num_ports -1 : 0]                       ob_ack = 0;         
   wire [c_swc_num_ports*c_swc_page_addr_width -1 : 0] ob_pageaddr;    
   wire [c_swc_num_ports * c_swc_prio_width - 1   : 0] ob_prio;        
   reg  [c_swc_num_ports -1 : 0]                       ib_transfer_pck = 0;
   wire [c_swc_num_ports -1 : 0]                       ib_transfer_ack;
   wire [c_swc_num_ports -1 : 0]                       ib_busy;
   reg  [c_swc_num_ports*c_swc_page_addr_width - 1 : 0]ib_pageaddr = 0;
   reg  [c_swc_num_ports*c_swc_num_ports - 1       : 0]ib_mask = 0;
   reg  [c_swc_num_ports * c_swc_prio_width - 1    : 0]ib_prio = 0;


   
   swc_pck_transfer_arbiter DUT(

	.clk_i             (clk),
	.rst_n_i           (rst),
  .ob_data_valid_o   (ob_data_valid),
  .ob_ack_i          (ob_ack),
  .ob_pageaddr_o     (ob_pageaddr),
  .ob_prio_o         (ob_prio),
  .ib_transfer_pck_i (ib_transfer_pck),
  .ib_transfer_ack_o (ib_transfer_ack),
  .ib_busy_o         (ib_busy),
  .ib_pageaddr_i     (ib_pageaddr),
  .ib_mask_i         (ib_mask),
  .ib_prio_i         (ib_prio)
  
    );
   
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   
task pck_transfer_write;
      input [4:0]                           channel;
      input [c_swc_page_addr_width - 1 : 0] pageaddr;
      input [c_swc_num_ports - 1       : 0] mask;
      input [c_swc_prio_width - 1      : 0] prio;

      begin : wr_body

	 integer k,i;
	 
	 while (ib_busy[channel] == 1)  `wait_cycles(1);
	   
	 if(ib_transfer_ack[channel] == 1 ) 	ib_transfer_pck[channel] <= 0; else `wait_cycles(1);

	 $display("Transfering page : input block = %d; addr = %d (0x%x) mask = %x prio = %x \n",channel, pageaddr,pageaddr,mask,prio);
	 
	 `array_copy(ib_pageaddr,    (c_swc_page_addr_width * channel + c_swc_page_addr_width -1), c_swc_page_addr_width * channel, pageaddr, 0);
	 `array_copy(ib_mask,        (c_swc_num_ports       * channel + c_swc_num_ports       -1), c_swc_num_ports       * channel, mask    , 0);
	 `array_copy(ib_prio,        (c_swc_prio_width      * channel + c_swc_prio_width      -1), c_swc_prio_width      * channel, prio    , 0);
	 `wait_cycles(1);
	 ib_transfer_pck[channel] <= 1;
	 `wait_cycles(1);
//   while(ib_transfer_ack[channel] == 0 ) `wait_cycles(1);   
   ib_transfer_pck[channel] <= 0;
   
   end
endtask // pck_transfer_write
      

task pck_transfer_write_set;
      input [4:0]                           channel;
      input [c_swc_page_addr_width - 1 : 0] pageaddr;
      input [c_swc_num_ports - 1       : 0] mask;
      input [c_swc_prio_width - 1      : 0] prio;

      begin : wr_body

   integer k,i;
   

   $display("Transfering page : input block = %d; addr = %d (0x%x) mask = %x prio = %x \n",channel, pageaddr,pageaddr,mask,prio);
   
   `array_copy(ib_pageaddr,    (c_swc_page_addr_width * channel + c_swc_page_addr_width -1), c_swc_page_addr_width * channel, pageaddr, 0);
   `array_copy(ib_mask,        (c_swc_num_ports       * channel + c_swc_num_ports       -1), c_swc_num_ports       * channel, mask    , 0);
   `array_copy(ib_prio,        (c_swc_prio_width      * channel + c_swc_prio_width      -1), c_swc_prio_width      * channel, prio    , 0);
   
   
   end
endtask // pck_transfer_write

  task pck_transfer_read;
      input  [4:0] channel;
      output [c_swc_page_addr_width - 1 : 0] pageaddr;
      output [c_swc_prio_width - 1      : 0] prio;
  begin : wr_body

   integer k,i;
   
   
   if(ob_data_valid[channel] == 1 && ob_ack[channel] == 0 && start == 1)     
     begin
       
     `array_copy(pageaddr, c_swc_page_addr_width - 1 , 0, ob_pageaddr, (c_swc_page_addr_width  * channel ));
     `array_copy(prio    , c_swc_prio_width      - 1 , 0, ob_prio    , (c_swc_prio_width       * channel ));

    // `wait_cycles(3);     
     ob_ack[channel] <= 1;
     `wait_cycles(1);
     ob_ack[channel] <= 0;   

   
     $display("Transfering page: output block = %d addr = %x  prio = %x [prio= %x, addr = %x] (%x) \n",channel, pageaddr,prio, ob_prio, ob_pageaddr,ob_data_valid_d1);
     end
   else 
   begin 
     ob_ack[channel] <= 0;  
   `wait_cycles(1) ;
   end
   
   
   end
endtask // pck_transfer_write


task pck_transfer_read_all_ch;
    output [c_swc_page_addr_width - 1 : 0] pageaddr;
    output [c_swc_prio_width - 1      : 0] prio;
begin : wr_body

 integer k,i;
 
   $display("------------------------------------------------------------------------------------ \n",);
   for (i=0;i<11;i=i+1)
     ob_ack[i] <= 1;
  
  
  
   for (i=0;i<11;i=i+1)
   begin
  
     `array_copy(pageaddr, c_swc_page_addr_width - 1 , 0, ob_pageaddr, (c_swc_page_addr_width  * i ));
     `array_copy(prio    , c_swc_prio_width      - 1 , 0, ob_prio    , (c_swc_prio_width       * i ));
     $display("Transfering page: output block = %d addr = %d  prio = %x [prio= %x, addr = %x] \n",i, pageaddr,prio, ob_prio, ob_pageaddr);
  
   end
   
   `wait_cycles(1);
  
  
   for (i=0;i<11;i=i+1)
     ob_ack[i] <= 0;   
 
  $display("------------------------------------------------------------------------------------ \n",);
 
 end
endtask // pck_transfer_write
   
   
   integer i;
   integer x,y;
   initial begin
      integer i;
      `wait_cycles(4);
      rst = 1;
      `wait_cycles(10);
      
/*
task pck_transfer_write;
      input [4:0]                           channel;
      input [c_swc_page_addr_width - 1 : 0] pageaddr;
      input [c_swc_num_ports - 1       : 0] mask;
      input [c_swc_prio_width - 1      : 0] prio;

*/      
      start = 1; 
/*      
      ib_transfer_pck[0] <= 1;
      ib_transfer_pck[1] <= 1;
      ib_transfer_pck[2] <= 1; 

      ib_transfer_pck[4] <= 1;
      ib_transfer_pck[5] <= 1;
      ib_transfer_pck[6] <= 1; 
      
      pck_transfer_write(0,11, 1, 1);
      pck_transfer_write(1,11, 1, 2);
      pck_transfer_write(2,11, 1, 3);
      pck_transfer_write(4,11, 1, 3);
      pck_transfer_write(5,11, 1, 3);
      pck_transfer_write(6,11, 1, 3);
      
      `wait_cycles(1);
      
      ib_transfer_pck[0] <= 0;
      ib_transfer_pck[1] <= 0;
      ib_transfer_pck[2] <= 0;

      ib_transfer_pck[4] <= 0;
      ib_transfer_pck[5] <= 0;
      ib_transfer_pck[6] <= 0;      
   */   
    //  pck_transfer_write(0,11, 2047, 7);

      pck_transfer_write(0, 10, 2047, 3);
      pck_transfer_write(1, 11, 2047, 1);
      pck_transfer_write(2, 12, 2047, 2);
      pck_transfer_write(3, 13, 2047, 3);
      pck_transfer_write(4, 14, 2047, 4);
      pck_transfer_write(5, 15, 2047, 5);
      pck_transfer_write(6, 16, 2047, 6);
      pck_transfer_write(7, 17, 2047, 7);
      pck_transfer_write(8, 18, 2047, 1);
      pck_transfer_write(9, 19, 2047, 2);
      pck_transfer_write(10,20, 2047, 3);
      
      `wait_cycles(20);
      
    //  start = 1;
      


      `wait_cycles(100);
/*      
      pck_transfer_read(0,x ,y );
      pck_transfer_read(1,x ,y );
      pck_transfer_read(2,x ,y );
      pck_transfer_read(3,x ,y );
      pck_transfer_read(4,x ,y );
      pck_transfer_read(5,x ,y );
      pck_transfer_read(6,x ,y );
      pck_transfer_read(7,x ,y );
      pck_transfer_read(8,x ,y );
      pck_transfer_read(9,x ,y );
      pck_transfer_read(10,x ,y );
*/     

      pck_transfer_read_all_ch(x,y);
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);      
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);      
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);      
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
   //   `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
   //   `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
   //   `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
   //   `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
     // `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
    //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
      //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);
      //  `wait_cycles(1);
      pck_transfer_read_all_ch(x,y);      
      `wait_cycles(100);
   end

/*  
	 always begin
	   integer x,y;
	   pck_transfer_read(0,x ,y );
	 end
   always begin
     integer x,y;
     pck_transfer_read(1,x ,y );
   end
	 always begin
	   integer x,y;
	   pck_transfer_read(2,x ,y );
	 end
   always begin
     integer x,y;
     pck_transfer_read(3,x ,y );
   end
   always begin
     integer x,y;
     pck_transfer_read(4,x ,y );
   end
   always begin
	   integer x,y;
	   pck_transfer_read(5,x ,y );
	 end
   always begin
     integer x,y;
     pck_transfer_read(6,x ,y );
   end
	 always begin
	   integer x,y;
	   pck_transfer_read(7,x ,y );
	 end
   always begin
     integer x,y;
     pck_transfer_read(8,x ,y );
   end
   always begin
     integer x,y;
     pck_transfer_read(9,x ,y );
   end	   
   always begin
	 	 integer x,y;
	   pck_transfer_read(10,x ,y );
	 end
*/
   endmodule // main
