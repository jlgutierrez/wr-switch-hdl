`timescale 1ns/1ps

/* Fake Page Linked List. */

interface ILinkedList
  (
   clk_io_i,
   rst_n_i
   );
   parameter t_swcore_parameters P = `DEFAULT_SWC_PARAMS;
   
   
   input      clk_io_i, rst_n_i;

   localparam int c_ll_entry_size = P.g_page_address_width + 2;
   localparam int c_page_size_width = clogb2(P.g_page_size + 1);
   
   logic [P.g_page_address_width-1:0] ll_addr;
   logic [c_ll_entry_size-1:0]        ll_data;

   modport at_mpm (
                output  ll_addr,
                input ll_data
                );
   
   typedef struct      {
      int              next; // pointer to the next page in chain
      bit              valid; // page contains valid data
      bit              eof; // page is the last in the current chain
      bit              allocated; // is the page allocated or free?
      int              size; // size of the data stored in the page
      int              dsel; // partial select
      int              use_count; // number of output blocks the page is allocated for
   } ll_entry_t;
   
   
   ll_entry_t list [P.g_num_pages]; // the list itself

   semaphore           af_mutex; // allocation lock

/* MPM LL output driver */
   reg [c_ll_entry_size-1:0] data_packed;

  
   always @(*) begin
      /* pack the ll_entry to a format accepted by the MPM */
      
      data_packed[P.g_page_address_width] <= list[ll_addr].eof;
      data_packed[P.g_page_address_width + 1] <= list[ll_addr].valid;
      
      if(list[ll_addr].eof)
        begin
           data_packed[c_page_size_width-1:0] <= list[ll_addr].size;
           data_packed[P.g_page_address_width-1 : P.g_page_address_width-P.g_partial_select_width] <= list[ll_addr].dsel;
        end else
          data_packed[P.g_page_address_width-1:0] <= list[ll_addr].next;
      end
   
   
   always@(posedge clk_io_i)
     ll_data <= data_packed;



   /* Initializes and clears the list */
   task automatic init();
      int i;

      af_mutex = new(1);
      
      for(i=0;i<P.g_num_pages;i++)
        begin
           list[i].valid = 0;
           list[i].allocated = 0;
        end   
   endtask // init
   
   

   task automatic free_chain(int start_page, int force_free = 0);
      int page;

      page  = start_page;
      
      af_mutex.get(1);

      list[page].use_count--;
      if(!list[page].use_count || force_free)
      forever begin
         list[page].allocated = 0;
         list[page].valid = 0;

         if(list[page].eof) break;

         page = list[page].next;
      end

      af_mutex.put(1);
   endtask // free_chain

   task automatic alloc_page(ref int page);
      int i, n_allocated = 0;

      af_mutex.get(1);
      
      foreach (list[i])
        if(! list[i].allocated)
          begin
             

             list[i].eof = 0;
             list[i].allocated = 1;
             //             list[i].use_count = use_count;
             if(page >= 0)
               list[page].next=  i;
             
             page = i;
             af_mutex.put(1);
             return;
             
          end // if (! list[i].allocated)

      af_mutex.put(1);
      
      $error("Fatal: alloc_page(): no pages left");
      $stop();

   endtask

   task automatic set_valid(int page);
      list[page].valid = 1;
   endtask // int


   task automatic set_last(int page, int size, int dsel);
      list[page].eof = 1;
      list[page].dsel = dsel;
      
      list[page].size = (size % P.g_page_size == 0 ? P.g_page_size : size % P.g_page_size);
   endtask // set_eof

   task automatic set_use_count(int start_page, int use_count);
      list[start_page].use_count = use_count;
   endtask // set_use_count

   function automatic string dump_chain(int start_page);
      int page = start_page;
      
      string str = "";
      while(!list[page].eof)
        begin
           $sformat(str, "%s %4x", str, page);
           page=list[page].next;
        end

      $sformat(str, "%s %4x [size %d, dsel %1x, usecount %d]", str, page, list[page].size, list[page].dsel, list[start_page].use_count);
            return str;


      
   endfunction // dump_chain
   
   
   initial init();
endinterface // ILinkedList
