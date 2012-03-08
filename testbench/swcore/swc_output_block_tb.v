`timescale 1ns / 1ps

`define NUM_PORTS 11
`define NUM_PAGES 1024
`define PAGE_ADDR_BITS 10
`define USECNT_BITS 4

`define CLK_PERIOD 10

`define wait_cycles(x) for(int iii=0;iii<x;iii++) @(posedge clk);

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
   parameter c_wrsw_prio_width  =   3;
   parameter c_swc_max_pck_size_width = 14;
   
   reg clk  = 0;
   reg rst  = 0;
   
   
   integer i, j;
  
   
   integer fail  = 0;

   reg                                     pta_transfer_data_valid = 0;
   reg  [c_swc_page_addr_width    - 1 : 0] pta_pageaddr            = 0;
   reg  [c_wrsw_prio_width        - 1 : 0] pta_prio                = 0;
   reg  [c_swc_max_pck_size_width - 1 : 0] pta_pck_size            = 0;
   wire                                    pta_transfer_data_ack;
   
   wire                                    mpm_pgreq;
   wire [c_swc_page_addr_width    - 1 : 0] mpm_pgaddr;
   reg                                     mpm_pckend = 0;
   reg                                     mpm_pgend  = 0;
   reg                                     mpm_drdy   = 0;
   wire                                    mpm_dreq;
   reg  [c_swc_data_width - 1 : 0]         mpm_data   = 0;
   reg  [c_swc_ctrl_width - 1 : 0]         mpm_ctrl   = 0;
   
   wire                                 rx_sof_p1;
   wire                                 rx_eof_p1;         
   reg                                  rx_dreq = 0;   
   wire [c_swc_ctrl_width - 1 : 0]      rx_ctrl;   
   wire [c_swc_data_width - 1 : 0]      rx_data;
   wire                                 rx_valid;
   wire                                 rx_bytesel;
   wire                                 rx_idle;
   wire                                 rx_rerror_p1;

   
   swc_output_block
   DUT (
    
    .rst_n_i                    (rst),
    .clk_i                      (clk),

    .pta_transfer_data_valid_i  (pta_transfer_data_valid),
    .pta_pageaddr_i             (pta_pageaddr),
    .pta_prio_i                 (pta_prio),
    .pta_pck_size_i             (pta_pck_size),
    .pta_transfer_data_ack_o    (pta_transfer_data_ack),

    .mpm_pgreq_o                (mpm_pgreq),
    .mpm_pgaddr_o               (mpm_pgaddr),
    .mpm_pckend_i               (mpm_pckend),
    .mpm_pgend_i                (mpm_pgend),
    .mpm_drdy_i                 (mpm_drdy),
    .mpm_dreq_o                 (mpm_dreq),
    .mpm_data_i                 (mpm_data),
    .mpm_ctrl_i                 (mpm_ctrl),

    .rx_sof_p1_o                (rx_sof_p1),
    .rx_eof_p1_o                (rx_eof_p1),
    .rx_dreq_i                  (rx_dreq),
    .rx_ctrl_o                  (rx_ctrl),
    .rx_data_o                  (rx_data),
    .rx_valid_o                 (rx_valid),
    .rx_bytesel_o               (rx_bytesel),
    .rx_idle_o                  (rx_idle),
    .rx_rerror_p1_o             (rx_rerror_p1)
    
    );

     
     task write;
        input [c_swc_page_addr_width    - 1 : 0] pageaddr;
        input [c_wrsw_prio_width        - 1 : 0] prio    ;
        input [c_swc_max_pck_size_width - 1 : 0] pck_size;
        begin : wait_body
     integer i;
  
        pta_pageaddr = pageaddr;
        pta_prio     = prio;
        pta_pck_size = pck_size;
        pta_transfer_data_valid = 1;
        `wait_cycles(1);
        pta_transfer_data_valid = 0;
  
        end
     endtask // wait_cycles 
     
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


   initial begin
   integer i;
 
   `wait_cycles(10);

   for(i=0;i<10; i=i+1)
    write(i,7,10);
 
   for(i=0;i<10; i=i+1)
    write(i,0,20);
 
   for(i=0;i<10; i=i+1)
    write(i,1,20);

   for(i=0;i<10; i=i+1)
    write(i,2,30);


   `wait_cycles(10)
   rx_dreq = 1;
   mpm_drdy = 1;
   `wait_cycles(10)
   mpm_drdy = 0;
   `wait_cycles(2);
   mpm_drdy = 1;
   `wait_cycles(50)
   mpm_drdy = 0;   
   
   `wait_cycles(10)
   
   end
   

endmodule // main
