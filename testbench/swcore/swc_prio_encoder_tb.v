`timescale 1ns / 1ps

`define INPUT_SIZE 36
`define OUTPUT_BITS 6

module main;

   reg [`INPUT_SIZE-1:0] a = 0;
   wire [`OUTPUT_BITS-1:0] q ;
   integer i, j;
   integer fail  = 0;
   
   
   swc_prio_encoder #( 
		   .g_num_inputs(`INPUT_SIZE), 
		   .g_output_bits(`OUTPUT_BITS)) 
   dut ( 
	 .in_i(a), 
	 .out_o(q)
	 );
   

   initial begin

      for(i=0;i<`INPUT_SIZE;i=i+1) begin
	 a[i]  = 1'b1;

	 if(i>0) for (j=0;j<=i-1;j=j+1) a[j] = 1'b0;
	 if(i<`INPUT_SIZE-1) for(j=i+1; j<`INPUT_SIZE; j=j+1) a[j] = $random;

      #200;
	 
	 if(i!=q) begin
	 $display(i,"!=",q);
	    fail  = 1;
	 end
      end  

      
      if(!fail) 
	$display("test passed");
      else 
	$display("test failed");
      
      
      
   end
   
   
   

endmodule // main
