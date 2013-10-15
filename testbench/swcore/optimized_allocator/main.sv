
typedef enum 
             {
              ALLOC,
              FREE,
              FORCE_FREE,
              SET_USECOUNT
              } alloc_req_type_t ;

typedef struct {
   alloc_req_type_t t;   // request type
   int         use_count;// use count
   int         id;       //
   int         origin;   //
   int         page;     // page_num_index
   int         port_id;  // id of port made the requested 
} alloc_request_t;

//return the index of the first free page (eq: -1)
function automatic int first_free(int tab[]);
   int         i; 
   for(i=0;i<tab.size;i++)
     if(tab[i] < 0)
       return i;
endfunction // first_free

//
function automatic int lookup_origin_page(ref alloc_request_t rqs[$], int id);
   foreach(rqs[i])
     begin
        if(rqs[i].id == id)
            return rqs[i].page;
     end
   $fatal("ID Not found: %i", id);
endfunction // lookup_origin_page


task automatic count_occupied_pages(ref alloc_request_t rqs[$], ref int peak, output int occupied, input int up_to=0, int verbose=0);
   int         i, n =0;
   int         page_table[1024]; /* fixme: this is ugly */
   int         pages_allocated = 0;

   
   peak = 0;
   
   if(!up_to)
     up_to = rqs.size() - 1;
   
   for(i=0;i<1024;i++) page_table[i] = -1;
   
   for(i=0;i<=up_to;i++)
     begin
        case(rqs[i].t)
          ALLOC:begin
             int page         = first_free(page_table);
             rqs[i].page      = page;
             page_table[page] = rqs[i].use_count; 
             pages_allocated++;
             if(verbose)      $display("%d : alloc %d [cnt=%d, used=%d]",i, rqs[i].page, rqs[i].use_count, pages_allocated);
          end
          SET_USECOUNT: begin
             int page         = lookup_origin_page(rqs, rqs[i].origin);
             page_table[page] = rqs[i].use_count;
             if(verbose)      $display("%d : set_ucnt %d [cnt=%d]", i, page, rqs[i].use_count);
          end
          FREE: begin
             int page = lookup_origin_page(rqs, rqs[i].origin);
             if(page_table[page] < 0)
               $fatal("attempt to free a free page\n");
             page_table[page]--; 
             if(!page_table[page])
               begin
                  page_table[page] = -1;
                  pages_allocated--;
               end
             if(verbose) $display("%d : free %d, used = %d", i, page, pages_allocated);
          end
          FORCE_FREE:begin
             int page = lookup_origin_page(rqs, rqs[i].origin);
             page_table[page] = -1;
             pages_allocated--;
            if(verbose) $display("%d : force_free %d, used = %d", i, page, pages_allocated);
          end
        endcase // case (rqs[i].t)
        
        //check the max accolcated page
        if(pages_allocated > peak) peak = pages_allocated;
     end

   for(i=0;i<1024;i++) if(page_table[i] >= 0) n++;
   occupied = n;
endtask // count_occupied_pages

function automatic int my_dist_uniform(ref int seed, input int start, int _end);
   if(start >= _end)
     return start;

   return $dist_uniform(seed, start, _end);
endfunction // my_dist_uniform

// fill in fifo/queue with different requrests (which make sense) -> WOW
task automatic gen_random_requests(ref alloc_request_t rqs[$], input int n, int seed, int max_occupied_pages = 0, int max_use_count = 3, int max_port_num=18);
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
//         $display("idx = %d", idx);

        orig_idx = idx;
        
        // $display("Gen %d", i);
        
        rq.t = ALLOC;
        rq.id = orig_id;
        rq.use_count = use_count;
        rq.port_id = i;// my_dist_uniform(seed, 0, max_port_num-1);

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
             rqs.insert(orig_idx, rq);
             if(rq.t == FORCE_FREE)
               break;
          end // for (j=0; j<use_count;j++)
        temp_page++;
     end
endtask // gen_random_requests

task automatic gen_simple_requests(ref alloc_request_t rqs[$], input int max_port_num=18);
   int i;
                          //   req_typ     ,usecnt, id, origin, page,port_id
   alloc_request_t rq[]  = '{'{ALLOC       , 1    , 0 , 0     , 0   , 0},
                             '{ALLOC       , 0    , 1 , 0     , 0   , 1},
                             '{SET_USECOUNT, 3    , 2 , 1     , 1   , 2},
                             '{ALLOC       , 0    , 3 , 0     , 0   , 3},
                             '{FREE        , 0    , 4 , 1     , 1   , 4},
                             '{ALLOC       , 3    , 5 , 0     , 0   , 5},
                             '{FORCE_FREE  , 0    , 6 , 1     , 1   , 6},
                             '{ALLOC       , 3    , 7 , 0     , 0   , 7},
                             '{FREE        , 0    , 8 , 0     , 0   , 8},
                             '{FREE        , 0    , 9 , 5     , 0   , 8},
                             '{FREE        , 0    , 9 , 5     , 0   , 8},
                             '{FREE        , 0    , 9 , 5     , 0   , 8}
                            };
   for(i=0;i<rq.size();i++)
     rqs.insert(i, rq[i]);
  
endtask // gen_random_requests


interface IAllocatorPort (input clk_i);

   parameter g_page_addr_width = 10;
   parameter g_usecnt_width    = 4;
   parameter g_num_ports       = 18;
   
   logic alloc=0, free=0, force_free=0, set_usecnt=0, done;
   logic alloc_done, free_done, force_free_done, set_usecnt_done;
   logic free_last_usecnt;
   logic no_mem;
   
   
   logic [g_page_addr_width-1:0] pg_addr_free;
   logic [g_page_addr_width-1:0] pg_addr_force_free;
   logic [g_page_addr_width-1:0] pg_addr_usecnt;
   logic [g_page_addr_width-1:0] pg_addr_alloc, pg_addr_muxed;
   logic [g_num_ports      -1:0] pg_addr_req_vec;
   logic [g_num_ports      -1:0] pg_addr_rsp_vec;
   logic [g_usecnt_width-1:0] usecnt;

   assign pg_addr_muxed = free ? pg_addr_free :
                    force_free ? pg_addr_force_free :
                    pg_addr_usecnt;
   
endinterface // IAllocatorPort

typedef virtual IAllocatorPort VIAllocatorPort;

task automatic execute_requests(VIAllocatorPort port, ref alloc_request_t rqs[$], input int space=0, input int verbose =0);

      fork 
      begin // make requets
      automatic int i;
      for(i=0;i<rqs.size();i++)
        begin
           
           port.pg_addr_req_vec <= rqs[i].port_id;
           
           case(rqs[i].t)
             ALLOC: begin
                port.alloc <= 1;
                port.usecnt <= rqs[i].use_count;
                @(posedge port.clk_i);
                port.alloc <= 0;
                port.usecnt <= 32'hx;
                if(verbose)$display("REQ[%-1d]: Alloc [id=%-1d, usecount=%-1d, port_id==%-1d]", i, rqs[i].id, rqs[i].use_count, rqs[i].port_id);
                end
   
             SET_USECOUNT:begin
                rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
                if(verbose)  $display("REQ[%-1d]: Set_Usecount [origin=%-1d, usecount=%-1d, port_id==%-1d, page=%-1d]", i, rqs[i].origin, rqs[i].use_count, rqs[i].port_id, rqs[i].page);
                port.pg_addr_usecnt <= rqs[i].page;
                port.usecnt <= rqs[i].use_count;
                port.set_usecnt <= 1;
                @(posedge port.clk_i);
                port.pg_addr_usecnt <= 32'hx;
                port.usecnt         <= 32'hx;
                port.set_usecnt <= 0;
             end
             
             FREE: begin
                rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
                if(verbose)$display("REQ[%-1d]: Free [origin=%-1d, port_id==%-1d, page=%-1d]", i, rqs[i].origin, rqs[i].port_id, rqs[i].page);
                port.pg_addr_free <= rqs[i].page;
                port.free <= 1;
                @(posedge port.clk_i);
                port.free         <=  0;
                port.pg_addr_free <= 32'hx;
             end
             
             FORCE_FREE: begin
                rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
                if(verbose)$display("REQ[%-1d]: Forced Free [origin=%-1d, port_id==%-1d, page=%-1d]", i,rqs[i].origin, rqs[i].port_id, rqs[i].page);
                port.pg_addr_force_free <= rqs[i].page;
                port.force_free <= 1;
                @(posedge port.clk_i);
                port.force_free <= 0;
                port.pg_addr_force_free <= 32'hx;
             end
             
           endcase // case (rqs[i].t)
           if(space)
              repeat(space) @(posedge port.clk_i);
        end
      end    // finish thread for with requets
      begin  // start  thread with respoinses
      automatic int j;
      for(j=0;j<rqs.size();j++)
        begin
                      
           while(!port.done) 
             begin
             $display("wait [page=%-1d, done=%-1d, port_id==%-1d]", port.pg_addr_alloc,port.done, port.pg_addr_rsp_vec );
             @(posedge port.clk_i);
             end
           $display("end wait [page=%-1d, done=%-1d, port_id==%-1d]", port.pg_addr_alloc,port.done, port.pg_addr_rsp_vec );
           if(rqs[j].port_id != port.pg_addr_rsp_vec)
            $display("RSP[%-1d]: Response for wrong port [pg_addr_rsp_vec (port_id) should be 0x%x but is 0x%x]", j, rqs[j].id, rqs[j].port_id, rqs[j].port_id);
           case(rqs[j].t)
             ALLOC: begin
                rqs[j].page = port.pg_addr_alloc;
                if(verbose)$display("RSP[%-1d]: Alloc [id=%-1d, usecount=%-1d, port_id==%-1d, page=%-1d]", j, rqs[j].id, rqs[j].use_count, rqs[j].port_id, rqs[j].page);
                end
   
             SET_USECOUNT:begin
                 if(verbose)  $display("RSP[%-1d]: Set_Usecount [origin=%-1d, usecount=%-1d, port_id==%-1d, page=%-1d]", j, rqs[j].origin, rqs[j].use_count, rqs[j].port_id, rqs[j].page);
             end
             
             FREE: begin
               if(verbose)$display("RSP[%-1d]: Free [origin=%-1d, port_id==%-1d, page=%-1d, free_last=%-1d]", j, rqs[j].origin, rqs[j].port_id, rqs[j].page, port.free_last_usecnt);
             end
             
             FORCE_FREE: begin
                if(verbose)$display("REQ[%-1d]: Forced Free [origin=%-1d, port_id==%-1d, page=%-1d]", j,rqs[j].origin, rqs[j].port_id, rqs[j].page);
             end
             
           endcase // case (rqs[i].t)
        end
      end // finish thread with respoinses
      join


   endtask // execute_requests


task automatic execute_requests_2(VIAllocatorPort port, ref alloc_request_t rqs[$], input int space=0, input int verbose =0);

      int i=0,j=0;
      int wait_space = space;
      int origin_d0 = -1;
      int origin_d1 = -1;

      while(j<rqs.size()) begin
        
        if(wait_space == space && i<rqs.size()) begin

          
          if(rqs[i].t == ALLOC) begin
            origin_d1 = origin_d0;
            origin_d0 = rqs[i].id;
          end
          else begin
            if((origin_d0 == rqs[i].origin || origin_d1 == rqs[i].origin) && space < 3) begin
              if(verbose)  $display("enforce space because origin=%-1d is the same as previous [d0=%-1d or d1=%-1d] ", rqs[i].origin, origin_d0, origin_d1);
              wait_space =  3;
              origin_d1  = -1;
              origin_d0  = -1;
            end 
            else begin
              origin_d1 = origin_d0;
              origin_d0  = -1;
            end
          end
        end

        if(port.done) begin
//           if(rqs[j].port_id != port.pg_addr_rsp_vec)
          if(j != port.pg_addr_rsp_vec)
             $display("RSP[%-1d]: Response for wrong port [pg_addr_rsp_vec (port_id) should be 0x%x but is 0x%x]", j, rqs[j].id, rqs[j].port_id, rqs[j].port_id);
          else begin
            case(rqs[j].t)
              ALLOC: begin
                rqs[j].page = port.pg_addr_alloc;
                if(verbose)  $display("RSP[%-1d]: Alloc        [id=%-1d,     usecount=%-1d, port_id==%-1d, page=%-1d]", j, rqs[j].id, rqs[j].use_count, rqs[j].port_id, rqs[j].page);
              end
              
              SET_USECOUNT:begin
                if(verbose)  $display("RSP[%-1d]: Set_Usecount [origin=%-1d, usecount=%-1d, port_id==%-1d, page=%-1d]", j, rqs[j].origin, rqs[j].use_count, rqs[j].port_id, rqs[j].page);
              end
              
              FREE: begin
                if(verbose)  $display("RSP[%-1d]: Free         [origin=%-1d,             port_id==%-1d, page=%-1d, free_last=%-1d]", j, rqs[j].origin, rqs[j].port_id, rqs[j].page, port.free_last_usecnt);
              end
              
              FORCE_FREE: begin
                if(verbose)  $display("RSP[%-1d]: Forced Free  [origin=%-1d,             port_id==%-1d, page=%-1d]", j,rqs[j].origin, rqs[j].port_id, rqs[j].page);
              end
            endcase // case (rqs[i].t)           
          end //else begin
          j++;
        end //if(port.done) begin

        if(wait_space == space && i<rqs.size()) begin

          port.pg_addr_req_vec <= i;                      
          case(rqs[i].t)
            ALLOC: begin
              port.alloc <= 1;
              port.usecnt <= rqs[i].use_count;
              if(verbose)  $display("REQ[%-1d]: Alloc        [id=%-1d,     usecount=%-1d, port_id==%-1d]", i, rqs[i].id, rqs[i].use_count, rqs[i].port_id);
            end
   
            SET_USECOUNT:begin
              rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
              if(verbose)  $display("REQ[%-1d]: Set_Usecount [origin=%-1d, usecount=%-1d, port_id==%-1d, page=%-1d]", i, rqs[i].origin, rqs[i].use_count, rqs[i].port_id, rqs[i].page);
              port.pg_addr_usecnt <= rqs[i].page;
              port.usecnt <= rqs[i].use_count;
              port.set_usecnt <= 1;
            end
             
            FREE: begin
              rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
              if(verbose)  $display("REQ[%-1d]: Free         [origin=%-1d,             port_id==%-1d, page=%-1d]", i, rqs[i].origin, rqs[i].port_id, rqs[i].page);
              port.pg_addr_free <= rqs[i].page;
              port.free <= 1;
            end
             
            FORCE_FREE: begin
              rqs[i].page = lookup_origin_page(rqs, rqs[i].origin);
              if(verbose)  $display("REQ[%-1d]: Forced Free  [origin=%-1d,             port_id==%-1d, page=%-1d]", i,rqs[i].origin, rqs[i].port_id, rqs[i].page);
              port.pg_addr_force_free <= rqs[i].page;
              port.force_free <= 1;
            end
          endcase // case (rqs[i].t)
          i++;
        end //if(wait == space) begin   



        @(posedge port.clk_i);

        port.alloc              <= 0;
        port.usecnt             <= 32'hx;
        port.pg_addr_usecnt     <= 32'hx;
        port.usecnt             <= 32'hx;
        port.set_usecnt         <= 0;
        port.free               <= 0;
        port.pg_addr_free       <= 32'hx;
        port.force_free         <= 0;
        port.pg_addr_force_free <= 32'hx;
 
        if(wait_space)
          wait_space--;
        else
          wait_space = space ;
      end    // for(i=0;i<rqs.size();i++) begin
   endtask // execute_requests



module main;

   
   reg    clk = 0;
   reg    rst_n = 0;

   IAllocatorPort alloc_port (clk);
   VIAllocatorPort valloc_port = alloc_port;

   assign alloc_port.set_usecnt_done = alloc_port.done;
   assign alloc_port.alloc_done = alloc_port.done;
   assign alloc_port.free_done = alloc_port.done;
   assign alloc_port.force_free_done = alloc_port.done;
   
   
   swc_page_allocator_new
  #(
    .g_num_pages (1024),
    .g_page_addr_width (alloc_port.g_page_addr_width),
    .g_num_ports      (alloc_port.g_num_ports),
    .g_usecount_width (alloc_port.g_usecnt_width)
    ) DUT (
           .clk_i   (clk),
           .rst_n_i (rst_n),
           .alloc_i (alloc_port.alloc),
           .free_i(alloc_port.free),
           .force_free_i(alloc_port.force_free),
           .set_usecnt_i(alloc_port.set_usecnt),
           .usecnt_i(alloc_port.usecnt),
           .pgaddr_i(alloc_port.pg_addr_muxed),
           .req_vec_i(alloc_port.pg_addr_req_vec),
           .rsp_vec_o(alloc_port.pg_addr_rsp_vec),
           .pgaddr_o(alloc_port.pg_addr_alloc),
           .free_last_usecnt_o (alloc_port.free_last_usecnt),
           .done_o (alloc_port.done),
           .nomem_o (alloc_port.no_mem)
           );

   const int MAX_USE_COUNT=3;
   int       uniq_id = 0;
   
/*
 *  wait ncycles
 */
    task automatic wait_cycles;
       input [31:0] ncycles;
       begin : wait_body
       integer i;
       for(i=0;i<ncycles;i=i+1) @(posedge clk);
       end
    endtask // wait_cycles   
         
       
   always #5ns clk <= ~clk;
   initial begin
      repeat(3) @(posedge clk);
      rst_n = 1;
   end
   
      
   initial begin
      alloc_request_t rqs[$], simple_rqs[$];
      int seed;
      int repeat_n = 8; // 100000
      int requests_num = 10;  

      while(!rst_n) @(posedge clk);

//seed;
           
     rst_n <= 0;
     @(posedge clk);
     rst_n <= 1;
     @(posedge clk);
           
     while(DUT.initializing)
     @(posedge clk);

     wait_cycles(50);
          
//      simple_rqs = '{};
//      gen_simple_requests(simple_rqs, 18);
//      execute_requests_2(valloc_port, simple_rqs, 3, 1); // 3 cycles between requests
// 
//      wait_cycles(30);
// 
//      execute_requests_2(valloc_port, simple_rqs, 0, 1); // no cycles between requests
//           
//      wait_cycles(50);
        
      for(seed = 0; seed < repeat_n; seed++)
        begin
           automatic int init_seed = seed;
           int occupied, peak;

           rst_n <= 0;
           @(posedge clk);
           rst_n <= 1;
           @(posedge clk);
           
           while(DUT.initializing)
             @(posedge clk);

           wait_cycles(50);

           rqs = '{};
           gen_random_requests(rqs, requests_num, init_seed, 1000);
           count_occupied_pages(rqs, peak, occupied, rqs.size()-1, 0);

           //$display("Pages occupied after test: %-1d, peak page usage %-1d", occupied, peak);
           
           
           execute_requests_2(valloc_port, rqs, 0 /*space*/, 0 /*verbose*/);
          #1;
           
           $display("AtTheEnd: free_blocks = %-1d", DUT.free_pages);
           if(DUT.free_pages != 1023) break;
           
           if(requests_num < 1000)
             requests_num = 10* requests_num;
           else
             requests_num = 2000;
         

        end
   end // initial begin

endmodule // main
