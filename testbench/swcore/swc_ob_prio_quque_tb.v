`timescale 1ns / 1ps

`define NUM_PORTS 11
`define NUM_PAGES 1024
`define PAGE_ADDR_BITS 10
`define USECNT_BITS 4

`define CLK_PERIOD 10

`define wait_cycles(x) for(int iii=0;iii<x;iii++) @(posedge clk);

module main;

   reg clk  = 0;
   reg rst  = 0;
   
   
   integer i, j;
  
   
   integer fail  = 0;

   reg  pq_write = 0;
   reg  pq_read = 0;
   
   wire wr_en;
   wire not_full;
   wire not_empty;
   wire [3:0] wr_addr;
   wire [3:0] rd_addr;

   
   swc_ob_prio_queue 
   DUT (
    
    .rst_n_i             (rst),
    .clk_i               (clk),

    .write_i             (pq_write),
    .read_i              (pq_read),
    
    
    .not_full_o          (not_full),
    .not_empty_o         (not_empty),
       
    .wr_en_o             (wr_en),
    .wr_addr_o           (wr_addr),
    .rd_addr_o           (rd_addr)
    
    );

     
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


   initial begin
     
    `wait_cycles(10); 
    
    pq_write = 1;
    `wait_cycles(1); 
    pq_write = 0;    
    `wait_cycles(10); 

    pq_write = 1;
    `wait_cycles(3); 
    pq_write = 0;    
    `wait_cycles(10); 
   
    pq_read = 1;
    `wait_cycles(3); 
    pq_read = 0;    
    `wait_cycles(10); 
 
     pq_read = 1;
    `wait_cycles(3); 
    pq_read = 0;    
    `wait_cycles(10);
      
    pq_write = 1;
    `wait_cycles(18); 
    pq_write = 0;    
    `wait_cycles(10);
         
   end
   

endmodule // main
