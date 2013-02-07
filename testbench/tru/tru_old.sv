`timescale 1ns/1ps

`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];

   `define c_num_ports              8
   `define c_tru_addr_width         8
   `define c_tru_subentry_num       8
   `define c_tru_subentry_width     (1+5*`c_num_ports+`c_pattern_mode_width) //49 //(3*24+3*8+1)
   `define c_patternID_width        4
   `define c_pattern_mode_width     4 // needs to be the same as num_port
   `define c_stableUP_treshold      100 // numbers of cycles after which port is assumed to be stably UP
   `define c_pclass_number          8
   `define c_pause_delay_width      16
   `define c_swc_max_queue_number   8
   `define c_fid_width              8
   `define c_mac_addr_width         48
   `define c_tru2ep_record_width    (3+`c_pclass_number+`c_pause_delay_width+`c_swc_max_queue_number)
   `define c_ep2tru_record_width    (3+`c_pclass_number)
   `define c_rtu2tru_record_width   (3*`c_num_ports+`c_num_ports*`c_prio_width)
   `define c_tru_req_record_width   (1+2*`c_mac_addr_width+`c_fid_width+2+`c_num_ports)
   `define c_tru_resp_record_width  (1+`c_num_ports+1+`c_num_ports) 
   `define c_tru_tab_size        256 // max 256
   `define c_vlan_tab_size       2048
   `define c_mt_trans_max_fr_cnt 1000
   `define c_prio_width          3

typedef struct packed {
    bit[`c_pattern_mode_width -1:0] pattern_mode   ; 
    bit[`c_num_ports-1:0]           pattern_mask    ;
    bit[`c_num_ports-1:0]           pattern_match;
    bit[`c_num_ports-1:0]           ports_mask   ;
    bit[`c_num_ports-1:0]           ports_egress ;
    bit[`c_num_ports-1:0]           ports_ingress; 
    bit                             valid;
} tru_tab_subentry_p_s;

typedef struct packed {
    tru_tab_subentry_p_s [`c_tru_subentry_num-1:0] subent;
} tru_tab_entry_p_s;

typedef struct packed {
    bit                   has_prio;
    bit[ 2:0]             prio;
    bit                   prio_override;
    bit                   drop;
    bit[ 7:0]             fid;
    bit[`c_num_ports-1:0] port_mask; 
} vlan_tab_entry_p_s;

typedef struct packed {
    bit[`c_num_ports-1 :0] reqMask;
    bit                    isBR;
    bit                    isHP;
    bit[ 7:0]              fid; 
    bit[47:0]              dmac; 
    bit[47:0]              smac;  
    bit                    valid;
} tru_req_p_s;

typedef struct packed {
    bit[`c_num_ports-1 :0] respMask;    
    bit[47:0]              drop; 
    bit[`c_num_ports-1 :0] portID; 
    bit                    valid;
} tru_resp_p_s;

typedef struct packed {
    bit[`c_num_ports-1:0] rxFrameMaskReg; 
    bit[`c_num_ports-1:0] rxFrameMask; 
    bit[`c_num_ports-1:0] portStateMask;
} tru_endpoint_p_s;

typedef struct packed {
    bit[`c_prio_width-1:0][`c_num_ports-1:0] priorities;
    bit[`c_num_ports-1:0] request_valid; 
    bit[`c_num_ports-1:0] forward_bpdu_only; 
    bit[`c_num_ports-1:0] pass_all;
} tru_rtu_p_s;


typedef struct packed {
    bit[`c_pclass_number-1:0] rx_pck_class;  
    bit                       rx_pck;    
    bit                       ctrlRd;
    bit                       status;
} tru_ep2tru_p_s;

typedef struct packed {
    bit[`c_swc_max_queue_number-1:0] outQueueBlockMask;
    bit[`c_pause_delay_width-1:0]    pauseTime;
    bit                              pauseSend;
    bit[`c_pclass_number-1:0]        tx_pck_class;  
    bit                              tx_pck;
    bit                              ctrlWr;
} tru_tru2ep_p_s;


typedef struct {
    bit                   gcr_g_ena;
    bit                   gcr_tru_bank;
    bit[23:0]             gcr_rx_frame_reset;
    bit[ 3:0]             mcr_pattern_mode_rep;
    bit[ 3:0]             mcr_pattern_mode_add;
    bit[ 3:0]             lacr_agg_gr_num;
    bit[ 3:0]             lacr_agg_df_br_id;
    bit[ 3:0]             lacr_agg_df_un_id;
    bit[8*4-1:0]          lagt_gr_id_mask;
    bit                   tcr_trans_ena;
    bit                   tcr_trans_clr;
    bit[ 2:0]             tcr_trans_mode;
    bit[ 2:0]             tcr_trans_rx_id;
    bit[ 2:0]             tcr_trans_prio;
    bit[ 5:0]             tcr_trans_port_a_id;
    bit[15:0]             tcr_trans_port_a_pause;
    bit                   tcr_trans_port_a_valid;
    bit[ 5:0]             tcr_trans_port_b_id;
    bit[15:0]             tcr_trans_port_b_pause;
    bit                   tcr_trans_port_b_valid;
    bit                   rtrcr_rtr_ena;
    bit                   rtrcr_rtr_reset;
    bit[ 3:0]             rtrcr_rtr_mode;
    bit[ 3:0]             rtrcr_rtr_rx ;
} tru_config_s;


module main;


   genvar kk;
   reg clk   = 0;
   reg rst_n = 0;
   
   reg nasty_one_bit = 0;
//    reg [`c_tru_entry_width -1:0]                                           tru_tab  [`c_tru_tab_size];
   tru_tab_subentry_p_s[`c_tru_subentry_num-1:0]                           tru_tab[`c_tru_tab_size];
//   tru_tab_entry_p_s                                                       tru_tab[`c_tru_tab_size];
   reg[`c_tru_subentry_num*`c_tru_subentry_width-1:0]                     tru_tab_entry;   
   wire[`c_tru_addr_width  -1:0]                                           tru_tab_addr;
  
   
   reg [`c_tru_req_record_width-1: 0]                                      tru_req;
   tru_req_p_s                                                             t_req;

   wire[`c_tru_resp_record_width-1 : 0]                                    tru_resp;
   tru_resp_p_s                                                            t_resp;
   
   reg[`c_rtu2tru_record_width-1:0]                                        tru_rtu;
   tru_rtu_p_s                                                             t_rtu;

   reg[`c_num_ports*`c_ep2tru_record_width-1:0]                            tru_ep2tru;
   tru_ep2tru_p_s[`c_num_ports-1:0]                                        t_ep2tru;

   wire[`c_num_ports*`c_tru2ep_record_width-1:0]                           tru_tru2ep;
   tru_tru2ep_p_s[`c_num_ports-1:0]                                        t_tru2ep;

   wire[`c_num_ports-1:0]                                                  tru_swc2tru;

   tru_config_s                                                            t_conf;

   wrsw_tru
   #(     
     .g_num_ports              (`c_num_ports),
     .g_tru_subentry_num       (`c_tru_subentry_num),
     .g_tru_subentry_width     (`c_tru_subentry_width),
     .g_tru_addr_width         (`c_tru_addr_width),
     .g_pattern_mode_width     (`c_num_ports),
     .g_patternID_width        (`c_patternID_width),
     .g_stableUP_treshold      (`c_stableUP_treshold),
     .g_pclass_number          (`c_pclass_number),
     .g_tru2ep_record_width    (`c_tru2ep_record_width),
     .g_ep2tru_record_width    (`c_ep2tru_record_width),
     .g_rtu2tru_record_width   (`c_rtu2tru_record_width),
     .g_tru_req_record_width   (`c_tru_req_record_width),
     .g_tru_resp_record_width  (`c_tru_resp_record_width),
     .g_mt_trans_max_fr_cnt    (`c_mt_trans_max_fr_cnt),
     .g_prio_width             (`c_prio_width),
     .g_tru_entry_num          (`c_tru_tab_size)
    ) DUT (
     .clk_i                    (clk),
     .rst_n_i                  (rst_n),
     .tru_req_i                (tru_req),
     .tru_resp_o               (tru_resp),
     .rtu_i                    (tru_rtu),
     .ep_i                     (tru_ep2tru),
     .ep_o                     (tru_tru2ep),
     .swc_o                    (tru_swc2tru),
   
     /////// temp ///////
     .tru_tab_addr_o           (tru_tab_addr),
     .tru_tab_entry_i          (tru_tab_entry),
     
     .gcr_g_ena_i              (t_conf.gcr_g_ena),
     .gcr_tru_bank_i           (t_conf.gcr_tru_bank),
     .gcr_rx_frame_reset_i     (t_conf.gcr_rx_frame_reset),
     .mcr_pattern_mode_rep_i   (t_conf.mcr_pattern_mode_rep),
     .mcr_pattern_mode_add_i   (t_conf.mcr_pattern_mode_add),
     .lacr_agg_gr_num_i        (t_conf.lacr_agg_gr_num),
     .lacr_agg_df_br_id_i      (t_conf.lacr_agg_df_br_id),
     .lacr_agg_df_un_id_i      (t_conf.lacr_agg_df_un_id),
     .lagt_gr_id_mask_i        (t_conf.lagt_gr_id_mask),
     .tcr_trans_ena_i          (t_conf.tcr_trans_ena),
     .tcr_trans_mode_i         (t_conf.tcr_trans_mode),
     .tcr_trans_clr_i          (t_conf.tcr_trans_clr),
     .tcr_trans_rx_id_i        (t_conf.tcr_trans_rx_id),
     .tcr_trans_prio_i         (t_conf.tcr_trans_prio),
     .tcr_trans_port_a_id_i    (t_conf.tcr_trans_port_a_id),
     .tcr_trans_port_a_pause_i (t_conf.tcr_trans_port_a_pause),
     .tcr_trans_port_a_valid_i (t_conf.tcr_trans_port_a_valid),
     .tcr_trans_port_b_id_i    (t_conf.tcr_trans_port_b_id),
     .tcr_trans_port_b_pause_i (t_conf.tcr_trans_port_b_pause),
     .tcr_trans_port_b_valid_i (t_conf.tcr_trans_port_b_valid),
     .rtrcr_rtr_ena_i          (t_conf.rtrcr_rtr_ena),
     .rtrcr_rtr_reset_i        (t_conf.rtrcr_rtr_reset),
     .rtrcr_rtr_mode_i         (t_conf.rtrcr_rtr_mode),
     .rtrcr_rtr_rx_i           (t_conf.rtrcr_rtr_rx)
    );

  assign tru_req               = t_req;
  assign t_resp                = tru_resp;
  assign tru_rtu               = t_rtu;
  assign tru_ep2tru            = t_ep2tru;
  assign t_tru2ep              = tru_tru2ep;
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

   always @(posedge clk) //@(posedge clk) 
   begin
     
     tru_tab_entry  = tru_tab[tru_tab_addr];
   end

   always @(posedge clk) //@(posedge clk) 
   begin
     integer i;
     for(i=0;i<`c_num_ports;i++) begin
        t_ep2tru[i].ctrlRd = t_tru2ep[i].ctrlWr;
     end;
     
   end

   task automatic set_tru_subentry;
      input                             valid;
      input[31:0]                       tru_entry_addr;
      input[31:0]                       tru_subentry_addr;
      input[`c_num_ports-1:0]           pattern_mask   ;
      input[`c_num_ports-1:0]           pattern_match;
      input[`c_pattern_mode_width-1:0]  pattern_mode   ; 
      input[`c_num_ports-1:0]           ports_mask   ;
      input[`c_num_ports-1:0]           ports_egress ;
      input[`c_num_ports-1:0]           ports_ingress; 
      begin
        
        tru_tab[tru_entry_addr][tru_subentry_addr].pattern_mode    = pattern_mode;
        tru_tab[tru_entry_addr][tru_subentry_addr].pattern_mask    = pattern_mask;
        tru_tab[tru_entry_addr][tru_subentry_addr].pattern_match   = pattern_match;
        tru_tab[tru_entry_addr][tru_subentry_addr].ports_mask      = ports_mask;
        tru_tab[tru_entry_addr][tru_subentry_addr].ports_egress    = ports_egress;
        tru_tab[tru_entry_addr][tru_subentry_addr].ports_ingress   = ports_ingress;
        tru_tab[tru_entry_addr][tru_subentry_addr].valid           = valid;
        
      end;
    endtask;

   task automatic rtu_enable_port;
      input[31:0]            portId;
      begin
         t_rtu.pass_all[portId] = 1;      
      end;
   endtask;

   task automatic rtu_disable_port;
      input[31:0]            portId;
      begin
         t_rtu.pass_all[portId] = 0;      
      end;
   endtask;

   task automatic ep_port_up;
      input[31:0]            portId;
      begin
         t_ep2tru[portId].status = 1;      
      end;
   endtask;

   task automatic ep_port_down;
      input[31:0]            portId;
      begin
         t_ep2tru[portId].status = 0;      
      end;
   endtask;

   task automatic ep_port_rx_quick_fw;
      input[31:0]            portId;
      input[31:0]            classID;
      begin
         t_ep2tru[portId].rx_pck_class[classID] = 1;      
         t_ep2tru[portId].rx_pck = 1;
         wait_cycles(1);
         t_ep2tru[portId].rx_pck_class[classID] = 0;      
         t_ep2tru[portId].rx_pck = 0;
      end;
   endtask;

   task automatic trans_config;
      input[ 2:0]            mode;
      input[ 2:0]            rx_id;
      input[ 2:0]            prio;
      input[ 5:0]            port_a_id;
      input[15:0]            port_a_pause;
      input[ 5:0]            port_b_id;
      input[15:0]            port_b_pause;
      begin
      
        /*
         * transition
         **/
        t_conf.tcr_trans_clr          = 0 ;
        t_conf.tcr_trans_mode         = mode;

        t_conf.tcr_trans_rx_id        = rx_id;
        
        t_conf.tcr_trans_port_a_valid = 1;
        t_conf.tcr_trans_port_a_pause = port_a_pause;
        t_conf.tcr_trans_port_a_id    = port_a_id;
        
        t_conf.tcr_trans_port_b_valid = 1;
        t_conf.tcr_trans_port_b_pause = port_b_pause;       
        t_conf.tcr_trans_port_b_id    = port_b_id;
      end;
   endtask;


   task automatic trans_enable;
      begin
        t_conf.tcr_trans_clr          = 0 ;
        wait_cycles(1);
        t_conf.tcr_trans_ena          = 1 ;
      end;
   endtask;

   task automatic trans_disable;
      begin
        t_conf.tcr_trans_clr          = 0 ;
        t_conf.tcr_trans_ena          = 1 ;
      end;
   endtask;


   task automatic init_stuff;
        
      begin
        vlan_tab_entry_p_s vt ;
        tru_tab_entry_p_s  tt;
        integer i;
        
        t_req.valid    = 0;    
        t_req.smac     = 0;
        t_req.dmac     = 0;
        t_req.fid      = 0;
        t_req.isHP     = 0;
        t_req.isBR     = 0;
        t_req.reqMask  = 0;
        
        t_rtu.pass_all          = 0;
        t_rtu.forward_bpdu_only = 0;
        t_rtu.request_valid     = 0;

        for(i=0;i<`c_tru_tab_size;i++)
           tru_tab[i] = 0;

        for(i=0;i<`c_num_ports;i++)   
           t_ep2tru[i] = 0;
        
        /*
         * Globacl Config Register
         **/
        t_conf.gcr_g_ena = 1; // enable the module
        t_conf.mcr_pattern_mode_rep = 1;
        t_conf.mcr_pattern_mode_add = 2;
        t_conf.rtrcr_rtr_rx         = 4;
        t_conf.rtrcr_rtr_mode       = 1;
        t_conf.rtrcr_rtr_ena        = 1;
        
        /*
         * transition
         **/
        trans_config(0 /*mode*/,     4  /*rx_id*/,       0 /*prio*/,
                     3 /*port_a_id*/,20 /*port_a_pause*/,
                     4 /*port_b_id*/,20 /*port_b_pause*/);
        
        /*
         * General ifno regarding entries:
         * we use replace pattern, the add pattern is especially set such that it will never match
         * (the pattern is outside of pattern mask)
         **/
        //////////////////////////////////////////// ENTRY 0 ///////////////////////////////////////
        set_tru_subentry(  1   /* valid     */,   0  /* entry_addr   */,  0  /* subentry_addr*/,
                         'h00 /*pattern_mask*/, 'h00 /* pattern_match*/, 'h0 /* pattern_mode */,
                         'h0F /*ports_mask  */, 'h02 /* ports_egress */,'h01 /* ports_ingress   */);

        set_tru_subentry(  0   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                         'h00 /*pattern_mask*/, 'h02 /* pattern_match*/,'h1  /* pattern_mode */,
                         'h00 /*ports_mask  */, 'h04 /* ports_egress */,'h01 /* ports_ingress   */);

        set_tru_subentry(  0   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                         'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h0  /* pattern_mode */,
                         'h00 /*ports_mask  */, 'h30 /* ports_egress */,'h01 /* ports_ingress   */);

        set_tru_subentry(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                         'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                         'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);


        //////////////////////////////////////////// ENTRY 1 ///////////////////////////////////////
        set_tru_subentry(  1   /* valid     */,   1  /* entry_addr   */,  0  /* subentry_addr*/,
                         'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h0 /* pattern_mode */,
                         'hFF /*ports_mask  */, 'h12 /* ports_egress */,'h01 /* ports_ingress   */);

        set_tru_subentry(  1   /* valid     */,   1  /* entry_addr   */,  1  /* subentry_addr*/,
                         'h0F /*pattern_mask*/, 'h02 /* pattern_match*/,'h0  /* pattern_mode */,
                         'h0F /*ports_mask  */, 'h04 /* ports_egress */,'h01 /* ports_ingress   */);

        set_tru_subentry(  1   /* valid     */,   1  /* entry_addr   */,  2  /* subentry_addr*/,
                         'hF0 /*pattern_mask*/, 'h10 /* pattern_match*/,'h0  /* pattern_mode */,
                         'hF0 /*ports_mask  */, 'h20 /* ports_egress */,'h01 /* ports_ingress   */);

        set_tru_subentry(  1   /* valid     */,   1  /* entry_addr   */,  3  /* subentry_addr*/,
                         'hFF /*pattern_mask*/, 'hC0 /* pattern_match*/,'h2  /* pattern_mode */,
                         'hFF /*ports_mask  */, 'hC0 /* ports_egress */,'hC0 /* ports_ingress   */);

        //////////////////////////////////////////// ENTRY 2 ///////////////////////////////////////
//         set_tru_subentry(  1   /* valid     */,   2  /* entry_addr   */,  0  /* subentry_addr*/,
//                          'h0F /*pattern_mask*/, 'h10 /* pattern_match*/,  0  /* pattern_mode */,
//                          'hFF /*ports_mask  */, 'h11 /* ports_egress */,'h05 /* ports_ingress   */);
// 
//         set_tru_subentry(  1   /* valid     */,   2  /* entry_addr   */,  1  /* subentry_addr*/,
//                          'h0F /*pattern_mask*/, 'h10 /* pattern_match*/,  1  /* pattern_mode */,
//                          'hFF /*ports_mask  */, 'h22 /* ports_egress */,'h06 /* ports_ingress   */);
// 
//         set_tru_subentry(  1   /* valid     */,   2  /* entry_addr   */,  2  /* subentry_addr*/,
//                          'h0F /*pattern_mask*/, 'h10 /* pattern_match*/,  2  /* pattern_mode */,
//                          'hFF /*ports_mask  */, 'h33 /* ports_egress */,'h07 /* ports_ingress   */);
// 
//         set_tru_subentry(  1   /* valid     */,   2  /* entry_addr   */,  3  /* subentry_addr*/,
//                          'h0F /*pattern_mask*/, 'h10 /* pattern_match*/,  3  /* pattern_mode */,
//                          'hFF /*ports_mask  */, 'h44 /* ports_egress */,'h08 /* ports_ingress   */);
        
        wait_cycles(5);
        ep_port_up(0);
        ep_port_up(1);
        ep_port_up(2);
        ep_port_up(3);        
        ep_port_up(4);
        ep_port_up(5);
        ep_port_up(6);
        ep_port_up(7);      
        wait_cycles(5);
        rtu_enable_port(0);
        rtu_enable_port(1);
        rtu_enable_port(2);
        rtu_enable_port(3);        
        rtu_enable_port(4);
        rtu_enable_port(5);
        rtu_enable_port(6);
        rtu_enable_port(7);        

      end;
    endtask;
 
   task simulate_transition ;
      input[31:0]            portA;
      input[31:0]            portB;
      input[31:0]            timeDiff;
      begin
      
      
      t_ep2tru[portA].rx_pck_class[t_conf.tcr_trans_rx_id] = 1;      
      t_ep2tru[portA].rx_pck = 1;   
      wait_cycles(1);
      t_ep2tru[portA].rx_pck_class[t_conf.tcr_trans_rx_id] = 0;      
      t_ep2tru[portA].rx_pck = 0;   
      wait_cycles(10);
      t_rtu.request_valid[portA] = 1;
      wait_cycles(1);
      t_rtu.request_valid[portA]=0;

      wait_cycles(10);
      t_rtu.request_valid[portA]=1;
      wait_cycles(1);
      t_rtu.request_valid[portA]=0;

      wait_cycles(10);
      t_rtu.request_valid[portA]=1;
      wait_cycles(1);
      t_rtu.request_valid[portA]=0;

      wait_cycles(timeDiff);         
      t_ep2tru[portB].rx_pck_class[t_conf.tcr_trans_rx_id] = 1;      
      t_ep2tru[portB].rx_pck = 1;   
      wait_cycles(1);
      t_ep2tru[portB].rx_pck_class[t_conf.tcr_trans_rx_id] = 0;      
      t_ep2tru[portB].rx_pck = 0;   

      t_rtu.request_valid[portB]=1;
      wait_cycles(1);
      t_rtu.request_valid[portB]=0;

      wait_cycles(10);
      t_rtu.request_valid[portB]=1;
      wait_cycles(1);
      t_rtu.request_valid[portB]=0;

      wait_cycles(10);
      t_rtu.request_valid[portB]=1;
      wait_cycles(1);
      t_rtu.request_valid[portB]=0;

      wait_cycles(10);         
      t_rtu.request_valid[portB]=1;
      wait_cycles(1);
      t_rtu.request_valid[portB]=0;

      wait_cycles(10);         

      
      end;
   endtask;
   task automatic tru_request;
      input[47:0]             smac; 
      input[47:0]             dmac; 
      input[ 7:0]             fid; 
      input                   isHP;
      input                   isBR;
      input[`c_num_ports-1:0] reqMask;
      begin 
        t_req.valid    = 1;    
        t_req.smac     = smac;
        t_req.dmac     = dmac;
        t_req.fid      = fid;
        t_req.isHP     = isHP;
        t_req.isBR     = isBR;
        t_req.reqMask  = reqMask;
        
        wait_cycles(1);
        
        t_req.valid    = 0;    
        t_req.smac     = 0;
        t_req.dmac     = 0;
        t_req.fid      = 0;
        t_req.isHP     = 0;
        t_req.isBR     = 0;
        t_req.reqMask  = 0;
        
      end;
   endtask;
 
   task automatic all_ports_up;
      begin 
         integer i;
         for(i=0;i<`c_num_ports;i++) begin
            ep_port_up(i);
            rtu_disable_port(i);
         end;
         wait_cycles(101);
         for(i=0;i<`c_num_ports;i++) begin
            rtu_enable_port(i);
         end;
      end;
   endtask;
 

   always #5ns clk <= ~clk;
   initial begin
      repeat(3) @(posedge clk);
      rst_n = 1;
   end

   initial begin
      repeat(3) @(posedge clk);
      rst_n = 1;
   end

   initial begin
     
     integer i;
     init_stuff();
     wait_cycles(10);
     
     tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,1/*reqMask*/);
     wait_cycles(20);
     tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,2/*reqMask*/);
     tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,4/*reqMask*/);
     tru_request (1234/*smac*/, 5678/*dmac*/, 2/*fid*/, 0/*isHP*/, 0/*isBR*/,8/*reqMask*/);
     tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,16/*reqMask*/);

     ep_port_down(1);     

     wait_cycles(10);
     tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,1/*reqMask*/);
     wait_cycles(10);
     ep_port_down(4);
     wait_cycles(1);
     tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,1/*reqMask*/);
     wait_cycles(10);
     ep_port_down(5);
     wait_cycles(1);
     tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,1/*reqMask*/);

     
     wait_cycles(20);
     for(i=0;i<10;i++) begin
        ep_port_up(1);
        wait_cycles(2);
        ep_port_down(1);
        wait_cycles(2);
     end;

     
     ep_port_up(1);

     rtu_disable_port(1);
     wait_cycles(101);
     rtu_enable_port(1);
     
     all_ports_up();

     wait_cycles(20);
     ep_port_rx_quick_fw(7 /*portId*/, 4 /*classID*/);
     //ep_port_rx_quick_fw(6 /*portId*/, 4 /*classID*/);
    
     wait_cycles(10);
     tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,1/*reqMask*/);
     
     trans_enable();

     wait_cycles(100);
     simulate_transition(3 /*portA*/,4 /*portB*/,20/*timeDiff*/);

   end    

endmodule // main

