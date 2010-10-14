`timescale 1ns / 1ps

`define INPUT_SIZE 22
`define INPUT_SIZE_LOG2 5

`define CLK_PERIOD 10

module main;

   reg clk  = 0;
   reg rst  = 0;
   
   reg [`INPUT_SIZE-1:0] rq = 0;
   wire next;
   wire [`INPUT_SIZE_LOG2-1 : 0] grant;
   wire grant_valid;
   
   integer i, j;
   integer fail  = 0;
   

   swc_rr_arbiter
     #(
       .g_num_ports(`INPUT_SIZE),
       .g_num_ports_log2(`INPUT_SIZE_LOG2))
   dut (
	.rst_n_i     (rst),
	.clk_i       (clk),
	.next_i      (next),
	.request_i   (rq),
	.grant_o     (grant),
	.grant_valid_o (grant_valid)

	);

     
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;


   initial begin
      @(posedge rst);
      #(100);

      @(posedge clk);
      #1;
      
      rq  = 'b00101010011110001001;
      

      $display("RQ?");
      
      
      

   end

   integer idx;
   
   always@(posedge clk) 
     begin
	if(grant_valid) begin
	   $display("Grant: %d", grant);

	   rq[grant] <= 0;

	  	   
	   idx 	      = $random % grant;
	   
	   rq[idx]     <= 1'b1;
	   
	end 
  end

   assign next 	      = grant_valid;
   
   
      

endmodule // main
