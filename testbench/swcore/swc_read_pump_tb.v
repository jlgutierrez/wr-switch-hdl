`timescale 1ns / 1ps

`define PAGE_ADDR_BITS 10
`define PAGE_SIZE 128
`define OUTPUT_WIDTH 32
`define MULTIPLY 16
`define FBRAM_SIZE 16

`define CLK_PERIOD 10

module main;
   reg clk    = 0;
   reg rst    = 0;

   reg [`PAGE_ADDR_BITS-1:0] page_addr=0;
   reg page_req  = 0;
   wire pgend;
   
   wire drdy;

   reg [15:0] sync = 11'b00010000000;
         
   wire [`OUTPUT_WIDTH-1:0] d;
   reg [`OUTPUT_WIDTH * `MULTIPLY - 1:0] q;
  
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   wire page_done;
   
   
   swc_packet_mem_read_pump 
   
   
    DUT (
    .clk_i     (clk),
    .rst_n_i   (rst),

    .pgaddr_i  (page_addr), 
    .pgreq_i   (page_req),
    .pgend_o   (pgend),

    .drdy_o    (drdy),
    .dreq_i    (dreq),
    .sync_i    (sync[0]),

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



   
   integer i, n, m, cnt = 0;
   integer readout[48];
   initial begin
      
      wait_cycles(10);
      q <= 512'h000000000000000100000002000000030000000400000005000000060000000700000008000000090000000a0000000b0000000c0000000d0000000e;
      
//      for (n = 0; n < FBRAM_SIZE; n = n + 1) begin
//        for (m = 0; m < FBRAM_SIZE * MULTIPLY; m = m + 1) begin
//           q[n] = (cnt << m) || q[n];
//           cnt = cnt + 1;
//        end;
//      end;

      for (n  =0; n<17;n=n+1) begin
      	  wait_cycles(n);
 	 
	       for (i=0;i<48;i=i+1) 
	          read_data(readout[i]);
	          
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
   



   
endmodule // main
