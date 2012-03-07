`timescale 1ns/1ps

/* "shadow" copy of the real F.B. Memory, used for write path verification */
   
interface IShadowFBM
  (
   clk_core_i,
   addr_i,
   data_i,
   we_i
   );
   parameter t_swcore_parameters P = `DEFAULT_SWC_PARAMS; 
   
   localparam int fbm_addr_width = clogb2(P.g_num_pages) + clogb2(P.g_page_size/P.g_ratio) - 2;
   
   input         clk_core_i, we_i;
   input [fbm_addr_width-1 : 0] addr_i;
   input [P.g_data_width * P.g_ratio - 1 : 0] data_i;

   logic [P.g_data_width * P.g_ratio - 1 : 0] mem [P.g_num_pages * P.g_page_size / P.g_ratio] ;
   
   
   always @(posedge clk_core_i)
     if(we_i)
       begin
          mem[addr_i] <= data_i;
       end
   
   
   function automatic u64_array_t read(int pages[$], input int size);
      int                                 page_index = 0;
      u64_array_t rval;

      rval = new[size];
      
      while(size > 0)
        begin
           int i, remaining = (size > P.g_page_size ? P.g_page_size : size);

           for(i=0;i<remaining;i++)
             begin
                rval [ page_index * P.g_page_size + i] = (mem [pages[page_index] * (P.g_page_size / P.g_ratio) + i/P.g_ratio] >> (i%P.g_ratio * P.g_data_width)) & ((1<<P.g_data_width)-1);
             end
           page_index ++;
           size -= remaining;
           
        end
      return rval;
      
   endfunction // read
   
endinterface // IShadowFBM
