`timescale 1ns / 1ps

`define CLK_PERIOD 10

`define wait_cycles(x) for(int iii=0;iii<x;iii++) @(posedge clk);

module main;

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
   
   wire                                 ob_transfer_pck ;
   wire [c_swc_page_addr_width - 1 : 0] ob_pageaddr     ;
   wire [c_swc_num_ports - 1       : 0] ob_output_mask  ;
   reg  [c_swc_num_ports - 1       : 0] ob_read_mask     = 0;
   wire [c_swc_prio_width - 1      : 0] ob_prio         ;
   reg                                  pta_transfer_pck = 0;
   reg  [c_swc_page_addr_width - 1 : 0] pta_pageaddr     = 0;
   reg  [c_swc_num_ports - 1       : 0] pta_mask         = 0;
   reg  [c_swc_prio_width - 1      : 0] pta_prio         = 0;
   wire                                 pta_transfer_ack;
   
   swc_pck_transfer_input DUT(

	.clk_i             (clk),
	.rst_n_i           (rst),
  .pto_transfer_pck_o (ob_transfer_pck),
  .pto_pageaddr_o     (ob_pageaddr),
  .pto_output_mask_o  (ob_output_mask),
  .pto_read_mask_i    (ob_read_mask),
  .pto_prio_o         (ob_prio),
  .ib_transfer_pck_i(pta_transfer_pck), 
  .ib_pageaddr_i    (pta_pageaddr),
  .ib_mask_i        (pta_mask),
  .ib_prio_i        (pta_prio),
  .ib_transfer_ack_o(pta_transfer_ack)

    );
   
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   
task pck_transfer_write;
      input [c_swc_page_addr_width - 1 : 0] pageaddr;
      input [c_swc_num_ports - 1       : 0] mask;
      input [c_swc_prio_width - 1      : 0] prio;

      begin : wr_body

	 integer k;
	 

	 $display("Transfering page: addr = %x mask = %x prio = %x ", pta_pageaddr,pta_mask,pta_prio);
	 
   pta_transfer_pck = 1;
   pta_pageaddr     = pageaddr;
   pta_mask         = mask;
   pta_prio         = prio;
   
	 `wait_cycles(1);
	 
   pta_transfer_pck = 0;
   
   end
endtask // pck_transfer_write
      

task pck_transfer_read;
      input [4:0] channel;
  begin : wr_body

   integer k,i;
   
   ob_read_mask <= channel;
   
//   for (i = 0; i < c_swc_num_ports ; i = i + 1) 
//     begin
//       if(i==3) ob_read_mask(i) <= 1 ;
//       if(i != 3) ob_read_mask(i) <= 0 ; 
//     end

   `wait_cycles(1);
   
   ob_read_mask <= 0;   
//   for (i = 0; i < c_swc_num_ports; i = i + 1) begin
//       ob_read_mask(i) <= 0;
//   end

   $display("Transfering page: addr = %x  prio = %x ", ob_pageaddr,ob_prio);
   
   
   end
endtask // pck_transfer_write


   

   integer i;
  
   initial begin
      integer i;
      `wait_cycles(4);
      rst = 1;
      `wait_cycles(10);
      
      pck_transfer_write(123, 5, 2);
      `wait_cycles(10);
      pck_transfer_read(2);

      `wait_cycles(10);
      pck_transfer_read(4);
      
      `wait_cycles(10);
      pck_transfer_read(1);
      
   end

	 
   endmodule // main
