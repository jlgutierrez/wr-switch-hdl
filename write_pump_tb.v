`timescale 1ns / 1ps

`define PAGE_ADDR_BITS 10
`define PAGE_SIZE 128
`define INPUT_WIDTH 32
`define MULTIPLY 16

`define CLK_PERIOD 10

module main;
   reg clk    = 0;
   reg rst    = 0;

   reg [`INPUT_WIDTH-1:0] d;

   wire reg_full  ;
   reg flush  = 0;

   reg [15:0] sync = 11'b00010000000;
   
   wire [`INPUT_WIDTH * `MULTIPLY - 1:0] q;
  
   wire we;
   reg drdy =0;
      
   
   
   always #(`CLK_PERIOD/2) clk = ~clk;
   initial #(`CLK_PERIOD*2) rst = 1;

   reg [`PAGE_ADDR_BITS-1:0] page_addr=0;
   reg page_req  = 0;
   wire page_done;
   
   
   swc_packet_mem_write_pump 
   
   
    DUT (
    .clk_i   (clk),
    .rst_n_i (rst),

    .pgaddr_i (page_addr), 
    .pgreq_i  (page_req),
  

    .drdy_i     (drdy),
    .full_o (reg_full),
    .flush_i    (flush),
    .sync_i     (sync[0]),

    .d_i(d),
    .q_o(q),
    .we_o(we)
    );

   task wait_cycles;
      input [31:0] ncycles;
      begin : wait_body
	 integer i;

	 for(i=0;i<ncycles;i=i+1) @(posedge clk);

      end
   endtask // wait_cycles
   
      
      

   task write_data;
      input [`INPUT_WIDTH - 1 : 0] in;
      begin : wr_body
	 while(reg_full) wait_cycles(1);

	 d    <= in;
	 drdy <= 1;
	 wait_cycles(1);
	 drdy <= 0;
      

      end
   endtask // write_data



   
   integer i, n;
   
   initial begin
      wait_cycles(10);



      for (n  =0; n<17;n=n+1) begin
	 wait_cycles(n);
	 
	 for (i=0;i<48;i=i+1) write_data(i);
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
