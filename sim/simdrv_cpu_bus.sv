`include "simdrv_defs.svh"


interface ICPUBus;
   
   
/* I/O */  
   logic[18:0] a = 0;
   wire[31:0] d ;
   logic cs 	 = 1;
   logic rd 	 = 1;
   logic wr 	 = 1;
   wire nwait;

   
   bit data_hiz  = 1;
   logic[31:0]  dr = 32'h0000000;
   
   assign d 	 =data_hiz ? 32'bz:dr;

   parameter g_setup_delay  = 300ns;
   parameter g_write_delay  = 300ns;
   parameter g_hold_delay   = 300ns;
   
   
   task write32(input [20:0] addr,
		input [31:0] data);
      
      data_hiz  = 0;
      cs        =0;
      a         = addr >> 2;            
      dr        = data;
      
      #(g_setup_delay) wr = 0;  
      #(g_write_delay) 

      if(!nwait) @(posedge nwait);
      
      wr = 1; 
      #(g_hold_delay) wr = 1;
      cs        =1;
      data_hiz  = 1;
   endtask // write32

   task read32 (input [20:0] addr,
		output [31:0] data);

      integer i;
      
      data_hiz  = 1;            
      a         = addr >> 2;            

      cs        =0;
      
      #(g_setup_delay) rd = 0;  
      #(g_write_delay) 
      if(!nwait) @(posedge nwait);
      
      rd = 1;
      data 	= d;
      
      #(g_hold_delay) rd = 1;
      cs        =1;
      
      data_hiz  = 1;

   endtask // read32

   modport master
     (
      output a,
      inout d,
      output cs,
      output rd,
      output wr,
      input nwait
      );
   
class CAsyncCPUBusAccessor extends CBusAccessor;
   
    task writem(uint64_t addr[], uint64_t data[], input int size, ref int result);
       int i;
       
       if(size != 4)
	 $error("ICPUBus: we currently support only 32-bit transfers");
       for(i=0; i<addr.size(); i++)
	 write32(addr[i], data[i]);

       result = 0;
    endtask // writem
   
   task readm(uint64_t addr[], ref uint64_t data[], input int size, ref int result);
      int i;
      
       if(size != 4)
	 $error("ICPUBus: we currently support only 32-bit transfers");

      
      for(i=0; i<addr.size(); i++)
	begin
	   reg[31:0] rdata;
	   read32(addr[i], rdata);
	   data[i] = rdata;
	end
      result = 0;
   endtask // readm
   
		
endclass // CAsyncCPUBusAccessor

   
   function automatic CBusAccessor get_accessor();
      CAsyncCPUBusAccessor acc = new;
      return CBusAccessor'(acc);
   endfunction // get_accessor
   
   
endinterface // ICPUBus

