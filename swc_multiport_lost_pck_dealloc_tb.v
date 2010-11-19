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

   reg [`NUM_PORTS * `PAGE_ADDR_BITS - 1:0] ib_pgaddr_free = 0;
   reg [`NUM_PORTS * `PAGE_ADDR_BITS - 1:0] ob_pgaddr_free = 0;
   
   reg [`NUM_PORTS-1:0] ib_force_free = 0;
   reg [`NUM_PORTS-1:0] ob_force_free = 0;

   wire [`NUM_PORTS-1:0] ib_done_force_free;
   wire [`NUM_PORTS-1:0] ob_done_force_free;

   
   task wait_cycles;
    input [31:0] ncycles;
    begin : wait_body
      integer i;

      for(i=0;i<ncycles;i=i+1) @(posedge clk);

    end
   endtask // wait_cycles


   
swc_multiport_lost_pck_dealloc
    DUT (
    
    .rst_n_i             (rst),
    .clk_i               (clk),

    .ib_force_free_i     (ib_force_free),
    .ib_force_free_done_o(ib_done_force_free),
    .ib_pgaddr_free_i    (ib_pgaddr_free),

    .ob_force_free_i     (ob_force_free),
    .ob_force_free_done_o(ob_done_force_free),
    .ob_pgaddr_free_i    (ob_pgaddr_free)

    );

     
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


   initial begin
      @(posedge rst);
      #(100);

      @(posedge clk);
      #1;

      ib_pgaddr_free = 14234;
      ob_pgaddr_free = 9764;

      ib_force_free = 7777;
      ob_force_free = 7777;
      
      wait_cycles(1);
      
      ib_force_free = 0;
      ob_force_free = 0;
 
      wait_cycles(100);
      
     
     
   end


endmodule // main
