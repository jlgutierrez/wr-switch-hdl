
typedef enum 
             {
              ALLOC,
              FREE,
              FORCE_FREE,
              SET_USECOUNT
              } alloc_req_type_t ;

typedef struct {
   alloc_req_type_t t;
   int         use_count;
   int         id, origin;
   int         page;
   time        t_event;
} alloc_request_t;

function automatic int first_free(int tab[]);
   int         i;
   
   for(i=0;i<tab.size;i++)
     if(tab[i] < 0)
       return i;
endfunction // first_free



function automatic int lookup_origin_page(ref alloc_request_t rqs[$], int id);
   foreach(rqs[i])
     begin
        if(rqs[i].id == id)
          begin
             //      $display("Found t%d page %d\n", rqs[i].t, rqs[i].page);
             
             return rqs[i].page;
          end
        
     end
   $fatal("ID Not found: %i", id);
endfunction // lookup_origin_page


task automatic count_occupied_pages(ref alloc_request_t rqs[$], ref int peak, output int occupied, input int up_to=0, int verbose=0, int reserve_pages=1);
   int         i, n =0;
   int         page_table[1024]; /* fixme: this is ugly */
   int         pages_allocated = 0;
   string      s = "";
   
   
   peak = 0;
   
   if(!up_to)
     up_to = rqs.size() - 1;
   
   for(i=0;i<1024;i++) page_table[i] = -1;
  // $display("----\n");
   
   for(i=0;i<=up_to;i++)
     begin
        case(rqs[i].t)
          ALLOC:begin
             int page = reserve_pages?first_free(page_table) : rqs[i].page;
             rqs[i].page = page;
             page_table[page] = rqs[i].use_count; 
             pages_allocated++;
             if(verbose) $display("%d : alloc %d [cnt=%d, used=%d]",i, rqs[i].page, rqs[i].use_count, pages_allocated);

          end
          SET_USECOUNT: begin
             int page = reserve_pages?lookup_origin_page(rqs, rqs[i].origin):rqs[i].page;
            if(verbose)             $display("%d : set_ucnt %d [cnt=%d]", i, page, rqs[i].use_count);
             page_table[page] = rqs[i].use_count;
             end
          FREE: begin
             int page = reserve_pages?lookup_origin_page(rqs, rqs[i].origin):rqs[i].page;
             
             if(page_table[page] < 0)
               $fatal("attempt to free a free page\n");
             
             page_table[page]--; 
             if(!page_table[page])
               begin
                  page_table[page] = -1;
                  pages_allocated--;
               end

             if(verbose)             $display("%d : free %d, used = %d", i, page, pages_allocated);

             end
 
          FORCE_FREE:begin
             int page = reserve_pages?lookup_origin_page(rqs, rqs[i].origin):rqs[i].page;
             
             page_table[page] = -1;
             pages_allocated--;
            if(verbose)             $display("%d : force_free %d, used = %d", i, page, pages_allocated);

          end
        endcase // case (rqs[i].t)

          if(pages_allocated > peak) peak = pages_allocated;

     end


   for(i=0;i<1024;i++) begin
      if(page_table[i] >= 0) begin
         n++;
         $sformat(s, "%s %-1d", s, i);
      end
   end

   if(verbose) $display("Pages occupied after test: %s", s);
   
   occupied = n;
endtask // count_occupied_pages


function automatic int my_dist_uniform(ref int seed, input int start, int _end);
   if(start >= _end)
     return start;

   return $dist_uniform(seed, start, _end);
endfunction // my_dist_uniform

     


task automatic gen_random_requests(ref alloc_request_t rqs[$], input int n, int seed, int max_occupied_pages = 0, int max_use_count = 3);
   int i;
   static int uniq_id = 0;
   int        temp_page = 0;
   

   for(i=0;i<=n;i++)
     begin
        alloc_request_t rq;

        int orig_id = uniq_id++;
        int j;
        int use_count = my_dist_uniform(seed, 0, max_use_count);
        int orig_idx;
        int idx, peak, occupied;
        
        idx = my_dist_uniform(seed, 0, rqs.size()-1);
        
        orig_idx = idx;
        
        // $display("Gen %d", i);
        
        rq.t = ALLOC;
        rq.id = orig_id;
        rq.use_count = use_count;

        rqs.insert(idx, rq);

     

        
        if(!use_count) /* Insert a "set use count" command somewhere after the allocation request */
          begin
             int idx = my_dist_uniform(seed, orig_idx + 1, rqs.size()), peak, occupied;
          //   $display("InsertUseCnt page=%d at=%d",temp_page-1, idx);
             
             rq.t = SET_USECOUNT;
             rq.origin = orig_id;
             rq.id = -1;
             use_count = my_dist_uniform(seed, 1, max_use_count);
             rq.use_count = use_count;
             rqs.insert(idx, rq);
             orig_idx = idx;
          end
        
        for(j=0; j<use_count;j++)
          begin
             orig_idx = my_dist_uniform(seed, orig_idx + 1, rqs.size());
             rq.t = FREE;
             rq.id = -1 ;
             rq.origin = orig_id;

             if(my_dist_uniform(seed, 1, 100) < 20) 
               begin
                  rq.t = FORCE_FREE;
               end

          //   $display("Insertidx: %d size %d", idx, rqs.size());

             rqs.insert(orig_idx, rq);
             if(rq.t == FORCE_FREE)
               break;
          end // for (j=0; j<use_count;j++)

        temp_page++;
        
     end
endtask // gen_random_requests


interface IAllocatorPort (input clk_i);

   // make sure they are the same as in the main one
   parameter g_page_addr_width= 10;
   parameter g_usecnt_width = 5; 
   
   logic alloc=0, free=0, force_free=0, set_usecnt=0, done;
   logic alloc_done, free_done, force_free_done, set_usecnt_done;
   logic free_last_usecnt;
   logic no_mem;
   
   
   logic [g_page_addr_width-1:0] pg_addr_free;
   logic [g_page_addr_width-1:0] pg_addr_force_free;
   logic [g_page_addr_width-1:0] pg_addr_usecnt;
   logic [g_page_addr_width-1:0] pg_addr_alloc, pg_addr_muxed;
   logic [g_usecnt_width-1:0] usecnt;

   assign pg_addr_muxed = free ? pg_addr_free :
                    force_free ? pg_addr_force_free :
                    pg_addr_usecnt;
   
endinterface // IAllocatorPort

// `ifdef dupa1234
typedef virtual IAllocatorPort VIAllocatorPort;

task automatic execute_requests(VIAllocatorPort port, ref alloc_request_t rqs[$], input int verbose =0);

      int i,j=0, idx;
      for(idx=0;idx<rqs.size();idx++)
        begin
//            if(port.no_mem) begin
//               while(rqs[idx+j].t == ALLOC && idx+j < rqs.size())
//                 j++;
//               while(rqs[idx+j].origin > rqs[idx].id && idx+j < rqs.size())
//                 j++;
//            end
//            i = idx+j;
           i = idx;
//            $display("Request id=%d", i);
           case(rqs[i].t)
             ALLOC: begin
                port.alloc <= 1;
                port.usecnt <= rqs[i].use_count;
                
                @(posedge port.clk_i);
                while(!port.done) @(posedge port.clk_i);
                port.alloc <= 0;
                rqs[i].page = port.pg_addr_alloc;
                if(verbose)$display("Alloc [id=%-1d, usecount=%-1d, page=%-1d]", rqs[i].id, rqs[i].use_count, rqs[i].page);
                end
   
             SET_USECOUNT:begin
                rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
              if(verbose)  $display("Set_Usecount [origin=%-1d, usecount=%-1d, page=%-1d]", rqs[i].origin, rqs[i].use_count, rqs[i].page);
                port.pg_addr_usecnt <= rqs[i].page;
                port.usecnt <= rqs[i].use_count;
                port.set_usecnt <= 1;
                @(posedge port.clk_i);
                while(!port.done) @(posedge port.clk_i);
                port.set_usecnt <= 0;
             end
             
             FREE: begin
                rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
                if(verbose)$display("Free [origin=%-1d, page=%-1d]", rqs[i].origin, rqs[i].page);
                port.pg_addr_free <= rqs[i].page;
                port.free <= 1;
                @(posedge port.clk_i);
                while(!port.done) @(posedge port.clk_i);
                port.free <= 0;
//                 if(idx != i) rqs.delete(i);  //delete executed command (so that we don't repeat later)
             end
             
             FORCE_FREE: begin
                rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
                if(verbose)$display("Forced Free [origin=%-1d, page=%-1d]", rqs[i].origin, rqs[i].page);
                port.pg_addr_force_free <= rqs[i].page;
                port.force_free <= 1;
                @(posedge port.clk_i);
                while(!port.done) @(posedge port.clk_i);
                port.force_free <= 0;
//                 if(idx != i) rqs.delete(i); //delete executed command (so that we don't repeat later)
             end
             
           endcase // case (rqs[i].t)
//            @(posedge port.clk_i);
        end
   endtask // execute_requests
// `endif