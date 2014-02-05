
typedef enum 
             {
              ALLOC,
              FREE,
              FORCE_FREE,
              SET_USECOUNT
              } alloc_req_type_t ;

typedef struct {
   int        is_allocated;
   int        last_page_freed;
   int        usecnt;
   int        free_cnt; //for 3 resoruces
   int        force_free_cnt; // 3 resoruces
   int        alloc_port_vec;
   int        free_port_vec;
   int        f_free_port_vec;
} alloc_page_instance_t;



`define g_alloc_pages    1024
`define g_usecnt_width   5
`define g_pg_addr_width  10
`define g_num_ports      19
`define g_res_num_width  2
`define g_alloc_inst_num 100

typedef struct {
   int                   alloc_cnt; // number of allocations of that page
   alloc_page_instance_t alloc_inst[`g_alloc_inst_num];
} alloc_page_t;


alloc_page_t alloc_tab[`g_alloc_pages];
int    pre_s_alloc_tab[`g_alloc_pages]; // pre-allocated start page
int    pre_i_alloc_tab[`g_alloc_pages]; // pre-allocated inter page

function init_alloc_tab();
    int i;
    for(i=0;i<`g_alloc_pages;i++) begin
      alloc_tab[i].alloc_cnt = -1;
      pre_s_alloc_tab[i]     =  0;
      pre_i_alloc_tab[i]     =  0;
    end
endfunction;

function automatic alloc_check(
         input bit alloc_done,
         input bit set_usecnt,
         input bit free,
         input bit force_free,
         input bit [`g_usecnt_width -1:0] usecnt_alloc,
         input bit [`g_usecnt_width -1:0] usecnt_set,
         input bit [`g_pg_addr_width-1:0] pga_f, //page address freed
         input bit [`g_pg_addr_width-1:0] pga_u, //page address usecnt
         input bit [`g_pg_addr_width-1:0] pga_a, //page address allocated
         input bit [`g_num_ports    -1:0] req_vec
   );
     int cnt=0;
     if(alloc_done) begin
       cnt = ++alloc_tab[pga_a].alloc_cnt;
       if(cnt >= `g_alloc_inst_num) $fatal("not enough alloc instances [see define g_alloc_inst_num in alloc.svh]");
       alloc_tab[pga_a].alloc_inst[cnt].is_allocated   = 1;
       alloc_tab[pga_a].alloc_inst[cnt].usecnt         = usecnt_alloc;
       alloc_tab[pga_a].alloc_inst[cnt].free_cnt       = 0;
       alloc_tab[pga_a].alloc_inst[cnt].force_free_cnt = 0;
       alloc_tab[pga_a].alloc_inst[cnt].alloc_port_vec = req_vec;
       alloc_tab[pga_a].alloc_inst[cnt].free_port_vec  = 0;
       alloc_tab[pga_a].alloc_inst[cnt].f_free_port_vec= 0;       
     end
     if(set_usecnt) begin
       cnt = alloc_tab[pga_u].alloc_cnt;
       alloc_tab[pga_u].alloc_inst[cnt].usecnt                   = usecnt_set;
     end
     if(free) begin
       cnt = alloc_tab[pga_f].alloc_cnt;
       alloc_tab[pga_f].alloc_inst[cnt].free_cnt++;
       alloc_tab[pga_f].alloc_inst[cnt].free_port_vec = req_vec | alloc_tab[pga_f].alloc_inst[cnt].free_port_vec;
     end

     if(force_free) begin
       cnt = alloc_tab[pga_f].alloc_cnt;
       alloc_tab[pga_f].alloc_inst[cnt].force_free_cnt++;
       alloc_tab[pga_f].alloc_inst[cnt].f_free_port_vec = req_vec | alloc_tab[pga_f].alloc_inst[cnt].f_free_port_vec;
     end
endfunction // first_free


function automatic int check_if_prealloc(
        input bit [`g_pg_addr_width*`g_num_ports-1:0] pckstart_pageaddr,
        input bit [`g_pg_addr_width*`g_num_ports-1:0] pckinter_pageaddr,
        input int pageaddr);
   int i; 
   int tab_s[19];
   int tab_i[19];

   tab_s[ 0] = pckstart_pageaddr[(( 0+1)*`g_pg_addr_width-1):( 0*`g_pg_addr_width)];
   tab_s[ 1] = pckstart_pageaddr[(( 1+1)*`g_pg_addr_width-1):( 1*`g_pg_addr_width)];
   tab_s[ 2] = pckstart_pageaddr[(( 2+1)*`g_pg_addr_width-1):( 2*`g_pg_addr_width)];
   tab_s[ 3] = pckstart_pageaddr[(( 3+1)*`g_pg_addr_width-1):( 3*`g_pg_addr_width)];
   tab_s[ 4] = pckstart_pageaddr[(( 4+1)*`g_pg_addr_width-1):( 4*`g_pg_addr_width)];
   tab_s[ 5] = pckstart_pageaddr[(( 5+1)*`g_pg_addr_width-1):( 5*`g_pg_addr_width)];
   tab_s[ 6] = pckstart_pageaddr[(( 6+1)*`g_pg_addr_width-1):( 6*`g_pg_addr_width)];
   tab_s[ 7] = pckstart_pageaddr[(( 7+1)*`g_pg_addr_width-1):( 7*`g_pg_addr_width)];
   tab_s[ 8] = pckstart_pageaddr[(( 8+1)*`g_pg_addr_width-1):( 8*`g_pg_addr_width)];
   tab_s[ 9] = pckstart_pageaddr[(( 9+1)*`g_pg_addr_width-1):( 9*`g_pg_addr_width)];
   tab_s[10] = pckstart_pageaddr[((10+1)*`g_pg_addr_width-1):(10*`g_pg_addr_width)];
   tab_s[11] = pckstart_pageaddr[((11+1)*`g_pg_addr_width-1):(11*`g_pg_addr_width)];
   tab_s[12] = pckstart_pageaddr[((12+1)*`g_pg_addr_width-1):(12*`g_pg_addr_width)];
   tab_s[13] = pckstart_pageaddr[((13+1)*`g_pg_addr_width-1):(13*`g_pg_addr_width)];
   tab_s[14] = pckstart_pageaddr[((14+1)*`g_pg_addr_width-1):(14*`g_pg_addr_width)];
   tab_s[15] = pckstart_pageaddr[((15+1)*`g_pg_addr_width-1):(15*`g_pg_addr_width)];
   tab_s[16] = pckstart_pageaddr[((16+1)*`g_pg_addr_width-1):(16*`g_pg_addr_width)];
   tab_s[17] = pckstart_pageaddr[((17+1)*`g_pg_addr_width-1):(17*`g_pg_addr_width)];
   tab_s[18] = pckstart_pageaddr[((18+1)*`g_pg_addr_width-1):(18*`g_pg_addr_width)];
   
   tab_i[ 0] = pckinter_pageaddr[(( 0+1)*`g_pg_addr_width-1):( 0*`g_pg_addr_width)];
   tab_i[ 1] = pckinter_pageaddr[(( 1+1)*`g_pg_addr_width-1):( 1*`g_pg_addr_width)];
   tab_i[ 2] = pckinter_pageaddr[(( 2+1)*`g_pg_addr_width-1):( 2*`g_pg_addr_width)];
   tab_i[ 3] = pckinter_pageaddr[(( 3+1)*`g_pg_addr_width-1):( 3*`g_pg_addr_width)];
   tab_i[ 4] = pckinter_pageaddr[(( 4+1)*`g_pg_addr_width-1):( 4*`g_pg_addr_width)];
   tab_i[ 5] = pckinter_pageaddr[(( 5+1)*`g_pg_addr_width-1):( 5*`g_pg_addr_width)];
   tab_i[ 6] = pckinter_pageaddr[(( 6+1)*`g_pg_addr_width-1):( 6*`g_pg_addr_width)];
   tab_i[ 7] = pckinter_pageaddr[(( 7+1)*`g_pg_addr_width-1):( 7*`g_pg_addr_width)];
   tab_i[ 8] = pckinter_pageaddr[(( 8+1)*`g_pg_addr_width-1):( 8*`g_pg_addr_width)];
   tab_i[ 9] = pckinter_pageaddr[(( 9+1)*`g_pg_addr_width-1):( 9*`g_pg_addr_width)];
   tab_i[10] = pckinter_pageaddr[((10+1)*`g_pg_addr_width-1):(10*`g_pg_addr_width)];
   tab_i[11] = pckinter_pageaddr[((11+1)*`g_pg_addr_width-1):(11*`g_pg_addr_width)];
   tab_i[12] = pckinter_pageaddr[((12+1)*`g_pg_addr_width-1):(12*`g_pg_addr_width)];
   tab_i[13] = pckinter_pageaddr[((13+1)*`g_pg_addr_width-1):(13*`g_pg_addr_width)];
   tab_i[14] = pckinter_pageaddr[((14+1)*`g_pg_addr_width-1):(14*`g_pg_addr_width)];
   tab_i[15] = pckinter_pageaddr[((15+1)*`g_pg_addr_width-1):(15*`g_pg_addr_width)];
   tab_i[16] = pckinter_pageaddr[((16+1)*`g_pg_addr_width-1):(16*`g_pg_addr_width)];
   tab_i[17] = pckinter_pageaddr[((17+1)*`g_pg_addr_width-1):(17*`g_pg_addr_width)];
   tab_i[18] = pckinter_pageaddr[((18+1)*`g_pg_addr_width-1):(18*`g_pg_addr_width)];
   
   for(i=0;i<19;i++) begin
     if(tab_s[i] == pageaddr) begin
       pre_s_alloc_tab[i]++;
//        $display("start pck pre-alloc page: pageaddr=%3d | %3d [port=%2d | vector: %p]", pageaddr,tab_s[i],i, pckstart_pageaddr);
       return i;     
     end
     if(tab_i[i] == pageaddr) begin
       pre_i_alloc_tab[i]++;
//        $display("inter pck pre-alloc page: pageaddr=%3d | %3d [port=%2d | vector: %p]", pageaddr,tab_i[i],i, pckstart_pageaddr);
       return i;     
     end
   end
   
//    if(pckstart_pageaddr[(( 0+1)*`g_pg_addr_width-1):( 0*`g_pg_addr_width)] == pageaddr) return 0;
//    if(pckstart_pageaddr[(( 1+1)*`g_pg_addr_width-1):( 1*`g_pg_addr_width)] == pageaddr) return 1;
//    if(pckstart_pageaddr[(( 2+1)*`g_pg_addr_width-1):( 2*`g_pg_addr_width)] == pageaddr) return 2;
//    if(pckstart_pageaddr[(( 3+1)*`g_pg_addr_width-1):( 3*`g_pg_addr_width)] == pageaddr) return 3;
//    if(pckstart_pageaddr[(( 4+1)*`g_pg_addr_width-1):( 4*`g_pg_addr_width)] == pageaddr) return 4;
//    if(pckstart_pageaddr[(( 5+1)*`g_pg_addr_width-1):( 5*`g_pg_addr_width)] == pageaddr) return 5;
//    if(pckstart_pageaddr[(( 6+1)*`g_pg_addr_width-1):( 6*`g_pg_addr_width)] == pageaddr) return 6;
//    if(pckstart_pageaddr[(( 7+1)*`g_pg_addr_width-1):( 7*`g_pg_addr_width)] == pageaddr) return 7;
//    if(pckstart_pageaddr[(( 8+1)*`g_pg_addr_width-1):( 8*`g_pg_addr_width)] == pageaddr) return 8;
//    if(pckstart_pageaddr[(( 9+1)*`g_pg_addr_width-1):( 9*`g_pg_addr_width)] == pageaddr) return 9;
//    if(pckstart_pageaddr[((10+1)*`g_pg_addr_width-1):(10*`g_pg_addr_width)] == pageaddr) return 0;
//    if(pckstart_pageaddr[((11+1)*`g_pg_addr_width-1):(11*`g_pg_addr_width)] == pageaddr) return 11;
//    if(pckstart_pageaddr[((12+1)*`g_pg_addr_width-1):(12*`g_pg_addr_width)] == pageaddr) return 12;
//    if(pckstart_pageaddr[((13+1)*`g_pg_addr_width-1):(13*`g_pg_addr_width)] == pageaddr) return 13;
//    if(pckstart_pageaddr[((14+1)*`g_pg_addr_width-1):(14*`g_pg_addr_width)] == pageaddr) return 14;
//    if(pckstart_pageaddr[((15+1)*`g_pg_addr_width-1):(15*`g_pg_addr_width)] == pageaddr) return 15;
//    if(pckstart_pageaddr[((16+1)*`g_pg_addr_width-1):(16*`g_pg_addr_width)] == pageaddr) return 16;
//    if(pckstart_pageaddr[((17+1)*`g_pg_addr_width-1):(17*`g_pg_addr_width)] == pageaddr) return 17;
//    if(pckstart_pageaddr[((18+1)*`g_pg_addr_width-1):(18*`g_pg_addr_width)] == pageaddr) return 18;
// 
//    if(pckinter_pageaddr[(( 0+1)*`g_pg_addr_width-1):( 0*`g_pg_addr_width)] == pageaddr) return 0;
//    if(pckinter_pageaddr[(( 1+1)*`g_pg_addr_width-1):( 1*`g_pg_addr_width)] == pageaddr) return 1;
//    if(pckinter_pageaddr[(( 2+1)*`g_pg_addr_width-1):( 2*`g_pg_addr_width)] == pageaddr) return 2;
//    if(pckinter_pageaddr[(( 3+1)*`g_pg_addr_width-1):( 3*`g_pg_addr_width)] == pageaddr) return 3;
//    if(pckinter_pageaddr[(( 4+1)*`g_pg_addr_width-1):( 4*`g_pg_addr_width)] == pageaddr) return 4;
//    if(pckinter_pageaddr[(( 5+1)*`g_pg_addr_width-1):( 5*`g_pg_addr_width)] == pageaddr) return 5;
//    if(pckinter_pageaddr[(( 6+1)*`g_pg_addr_width-1):( 6*`g_pg_addr_width)] == pageaddr) return 6;
//    if(pckinter_pageaddr[(( 7+1)*`g_pg_addr_width-1):( 7*`g_pg_addr_width)] == pageaddr) return 7;
//    if(pckinter_pageaddr[(( 8+1)*`g_pg_addr_width-1):( 8*`g_pg_addr_width)] == pageaddr) return 8;
//    if(pckinter_pageaddr[(( 9+1)*`g_pg_addr_width-1):( 9*`g_pg_addr_width)] == pageaddr) return 9;
//    if(pckinter_pageaddr[((10+1)*`g_pg_addr_width-1):(10*`g_pg_addr_width)] == pageaddr) return 10;
//    if(pckinter_pageaddr[((11+1)*`g_pg_addr_width-1):(11*`g_pg_addr_width)] == pageaddr) return 11;
//    if(pckinter_pageaddr[((12+1)*`g_pg_addr_width-1):(12*`g_pg_addr_width)] == pageaddr) return 12;
//    if(pckinter_pageaddr[((13+1)*`g_pg_addr_width-1):(13*`g_pg_addr_width)] == pageaddr) return 13;
//    if(pckinter_pageaddr[((14+1)*`g_pg_addr_width-1):(14*`g_pg_addr_width)] == pageaddr) return 14;
//    if(pckinter_pageaddr[((15+1)*`g_pg_addr_width-1):(15*`g_pg_addr_width)] == pageaddr) return 15;
//    if(pckinter_pageaddr[((16+1)*`g_pg_addr_width-1):(16*`g_pg_addr_width)] == pageaddr) return 16;
//    if(pckinter_pageaddr[((17+1)*`g_pg_addr_width-1):(17*`g_pg_addr_width)] == pageaddr) return 17;
//    if(pckinter_pageaddr[((18+1)*`g_pg_addr_width-1):(18*`g_pg_addr_width)] == pageaddr) return 18;

//    for(i=0;i<`g_num_ports;i++) begin
//      pg_s = pckstart_pageaddr[((i+1)*`g_pg_addr_width):(i*`g_pg_addr_width)];
//      pg_i = pckinter_pageaddr[((i+1)*`g_pg_addr_width):(i*`g_pg_addr_width)];
//      $display("checking pre-alloc: pg_s =0x%4x | pg_s =0x%4x | pg =0x%4x",pg_s,pg_i, pageaddr);
//      if(pg_s == pageaddr && pg_i == pageaddr ) return 1;
//    end
   return -1;
endfunction

function automatic dump_results(
        input bit [`g_pg_addr_width*`g_num_ports-1:0] pckstart_pageaddr,
        input bit [`g_pg_addr_width*`g_num_ports-1:0] pckinter_pageaddr
   );
   

   int i   = 0;
   int j   = 0;
   int chk = 0;
   int per_alloc_cnt =0;
   int pg_pre_alloc = 0;
   $display("--------------------------------- dumping resutls -------------------------------------");
   while(alloc_tab[i].alloc_cnt >=0)
   begin
     for(j=0;j<=alloc_tab[i].alloc_cnt;j++)
     begin
       chk = alloc_tab[i].alloc_inst[j].usecnt - alloc_tab[i].alloc_inst[j].free_cnt;
       if((chk != 0 || alloc_tab[i].alloc_inst[j].usecnt == 0) &&
           alloc_tab[i].alloc_inst[j].is_allocated       == 1 &&   // allocated and
           alloc_tab[i].alloc_cnt                        == j)   // last usage and 
         pg_pre_alloc = check_if_prealloc(pckstart_pageaddr,pckinter_pageaddr,i);
       else
         pg_pre_alloc = -1;

       if(chk == 0 && alloc_tab[i].alloc_inst[j].usecnt != 0)
         $display("[p=%4d|u=%2d] alloc=%1d | usecnt=%2d | f_cnt=%2d | ff_cnt=%2d | a_v=0x%20x | f_v=0x%20x | ff_v=0x%20x | OK",
         i, j, 
         alloc_tab[i].alloc_inst[j].is_allocated,
         alloc_tab[i].alloc_inst[j].usecnt,
         alloc_tab[i].alloc_inst[j].free_cnt,
         alloc_tab[i].alloc_inst[j].force_free_cnt,
         alloc_tab[i].alloc_inst[j].alloc_port_vec,
         alloc_tab[i].alloc_inst[j].free_port_vec,
         alloc_tab[i].alloc_inst[j].f_free_port_vec);
       else if(pg_pre_alloc > -1) // one of pre-allocated
         begin
         $display("[p=%4d|u=%2d] alloc=%1d | usecnt=%2d | f_cnt=%2d | ff_cnt=%2d | a_v=0x%20x | f_v=0x%20x | ff_v=0x%20x | pre-alloc-ed page for port %2d",
         i, j, 
         alloc_tab[i].alloc_inst[j].is_allocated,
         alloc_tab[i].alloc_inst[j].usecnt,
         alloc_tab[i].alloc_inst[j].free_cnt,
         alloc_tab[i].alloc_inst[j].force_free_cnt,
         alloc_tab[i].alloc_inst[j].alloc_port_vec,
         alloc_tab[i].alloc_inst[j].free_port_vec,
         alloc_tab[i].alloc_inst[j].f_free_port_vec,
         pg_pre_alloc);
         per_alloc_cnt++;
         end
//        else if(chk                    == 1 &&   //possible candidate for pre-allocated page 
//                alloc_tab[i].alloc_cnt == j &&   // needs to be the last usage
//                check_if_prealloc(pckstart_pageaddr,pckinter_pageaddr,i) > -1) // needs to be preallocated in one of ports 
//          begin
//          $display("[p=%4d|u=%2d] alloc=%1d | usecnt=%2d | f_cnt=%2d | ff_cnt=%2d | a_v=0x%20x | f_v=0x%20x | ff_v=0x%20x | pre-alloc-ed page %2d",
//          i, j, 
//          alloc_tab[i].alloc_inst[j].is_allocated,
//          alloc_tab[i].alloc_inst[j].usecnt,
//          alloc_tab[i].alloc_inst[j].free_cnt,
//          alloc_tab[i].alloc_inst[j].force_free_cnt,
//          alloc_tab[i].alloc_inst[j].alloc_port_vec,
//          alloc_tab[i].alloc_inst[j].free_port_vec,
//          alloc_tab[i].alloc_inst[j].f_free_port_vec,
//          check_if_prealloc(pckstart_pageaddr,pckinter_pageaddr,i));
//          per_alloc_cnt++;
//          end
//        else if(alloc_tab[i].alloc_inst[j].is_allocated    == 1 &&   //allocated but...
//                alloc_tab[i].alloc_inst[j].usecnt          == 0 &&   // no usecnt set and
//                alloc_tab[i].alloc_inst[j].free_cnt        == 0 &&   // neither freed ...
//                alloc_tab[i].alloc_inst[j].force_free_cnt  == 0 &&   // nor force-freed and
//                alloc_tab[i].alloc_cnt                     == j &&   // needs to be the last usage
//                check_if_prealloc(pckstart_pageaddr,pckinter_pageaddr,i) >-1) // needs to be preallocated in one of ports 
//          begin
//          $display("[p=%4d|u=%2d] alloc=%1d | usecnt=%2d | f_cnt=%2d | ff_cnt=%2d | a_v=0x%20x | f_v=0x%20x | ff_v=0x%20x | pre-alloc-ed page %2d",
//          i, j, 
//          alloc_tab[i].alloc_inst[j].is_allocated,
//          alloc_tab[i].alloc_inst[j].usecnt,
//          alloc_tab[i].alloc_inst[j].free_cnt,
//          alloc_tab[i].alloc_inst[j].force_free_cnt,
//          alloc_tab[i].alloc_inst[j].alloc_port_vec,
//          alloc_tab[i].alloc_inst[j].free_port_vec,
//          alloc_tab[i].alloc_inst[j].f_free_port_vec,
//          check_if_prealloc(pckstart_pageaddr,pckinter_pageaddr,i));
//          per_alloc_cnt++;
//          end
       else if(alloc_tab[i].alloc_inst[j].force_free_cnt)
         $display("[p=%4d|u=%2d] alloc=%1d | usecnt=%2d | f_cnt=%2d | ff_cnt=%2d | a_v=0x%20x | f_v=0x%20x | ff_v=0x%20x | Force Free",
         i, j, 
         alloc_tab[i].alloc_inst[j].is_allocated,
         alloc_tab[i].alloc_inst[j].usecnt,
         alloc_tab[i].alloc_inst[j].free_cnt,
         alloc_tab[i].alloc_inst[j].force_free_cnt,
         alloc_tab[i].alloc_inst[j].alloc_port_vec,
         alloc_tab[i].alloc_inst[j].free_port_vec,
         alloc_tab[i].alloc_inst[j].f_free_port_vec);
       else 
         $display("[p=%4d|u=%2d] alloc=%1d | usecnt=%2d | f_cnt=%2d | ff_cnt=%2d | a_v=0x%20x | f_v=0x%20x | ff_v=0x%20x | check this one",
         i, j, 
         alloc_tab[i].alloc_inst[j].is_allocated,
         alloc_tab[i].alloc_inst[j].usecnt,
         alloc_tab[i].alloc_inst[j].free_cnt,
         alloc_tab[i].alloc_inst[j].force_free_cnt,
         alloc_tab[i].alloc_inst[j].alloc_port_vec,
         alloc_tab[i].alloc_inst[j].free_port_vec,
         alloc_tab[i].alloc_inst[j].f_free_port_vec);
     end //for 
     i++;
   end //while
   $display("--------------------------------- --------------- -------------------------------------");
   $display("pre-alloc pages: %3d",per_alloc_cnt);
   for(i=0;i<`g_num_ports;i++) begin
     if(pre_s_alloc_tab[i] != 1 || pre_i_alloc_tab[i] != 1)
       $display("something wrong....: port %2d pre-allocation skrewed: start cnt=%2d | inter cnt = %2d",i, pre_s_alloc_tab[i], pre_i_alloc_tab[i]);
   end
   
endfunction



