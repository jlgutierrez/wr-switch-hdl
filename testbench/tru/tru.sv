`timescale 1ns/1ps

`include "if_wb_master.svh"
`include "simdrv_wr_tru.svh"

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
    bit                    drop; 
    bit[`c_num_ports-1 :0] portMask; 
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


module main;

   genvar kk;
   reg clk   = 0;
   reg rst_n = 0;
   
   reg nasty_one_bit = 0;
   
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

   IWishboneMaster U_tru_wb (clk, rst_n) ;

   wrsw_tru_wb
   #(     
     .g_num_ports              (`c_num_ports),
     .g_tru_subentry_num       (`c_tru_subentry_num),
     .g_tru_subentry_width     (`c_tru_subentry_width),
     .g_tru_addr_width         (`c_tru_addr_width),
     .g_pattern_mode_width     (`c_pattern_mode_width),
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
   
     .wb_addr_i                (U_tru_wb.master.adr[3:0]),
     .wb_data_i                (U_tru_wb.master.dat_o),
     .wb_data_o                (U_tru_wb.master.dat_i),
     .wb_cyc_i                 (U_tru_wb.master.cyc),
     .wb_sel_i                 (U_tru_wb.master.sel),
     .wb_stb_i                 (U_tru_wb.master.stb),
     .wb_we_i                  (U_tru_wb.master.we),
     .wb_ack_o                 (U_tru_wb.master.ack)
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

   // simulate endpoint ctrl
   always @(posedge clk) //@(posedge clk) 
   begin
     integer i;
     for(i=0;i<`c_num_ports;i++) begin
        t_ep2tru[i].ctrlRd = t_tru2ep[i].ctrlWr;
     end;
   end

   // track responses from TRU -> print info
   always @(posedge clk) if(t_resp.valid == 1)
   begin
      integer i, cnt;
      cnt=0;
      for (i=0;i<`c_num_ports;i++)
      if(t_resp.respMask[i] == 1) break;
      else cnt++;
   
      if(t_resp.drop == 1) $display("Resp @ port %2d: drop\n",cnt);
      else                 $display("Resp @ port %2d: pass, %b [0x%x]\n",cnt,t_resp.portMask,t_resp.portMask);
   end

   // track HW-sent frames
   generate 
      genvar    i;
      for(i=0; i<`c_num_ports; i++) begin
         always @(posedge clk) if(t_tru2ep[i].tx_pck == 1)
         begin
           $display("TRU -> EP[%2d]: Send WR-generated frame [class = %bd]",i, t_tru2ep[i].tx_pck_class);
         end
         always @(posedge clk) if(t_tru2ep[i].pauseSend == 1)
         begin
           $display("TRU -> EP[%2d]: Send WR-generated pause [pauseTime = %2d us]",i, t_tru2ep[i].pauseTime);
         end
         always @(posedge t_tru2ep[i].ctrlWr) 
         begin
           $display("TRU -> EP[%2d]: ON",i);
         end
         always @(negedge t_tru2ep[i].ctrlWr) 
         begin
           $display("TRU -> EP[%2d]: OFF",i);
         end
         always @(posedge t_tru2ep[i].outQueueBlockMask) 
         begin
           integer j, cnt;
           cnt = 0;
           for (j=0;j<`c_num_ports;j++)
           if(t_tru2ep[i].outQueueBlockMask[j] == 1) break;
           else cnt++;            
           $display("TRU -> SWcore [%2d]: block outque %2d",i, cnt);
         end         
      end
   endgenerate;

   // print detailed info about output mask decision process
   `define dut_port DUT.X_TRU.U_T_PORT
   always @(posedge clk) if(DUT.X_TRU.U_T_PORT.s_valid_d0 == 1)
   begin
      integer i, cnt;
      $display("\tMATCH USED inputs: patterns{replacement[mode=0] = 0x%x, addition[mode=1]= 0x%x}, state{portsUp=%b, rx_frame_reg=%b}",
                                                `dut_port.s_patternRep_d0,
                                                `dut_port.s_patternAdd_d0,
                                                `dut_port.endpoints_i.status,
                                                `dut_port.endpoints_i.rxFrameMaskReg[`dut_port.ADD_PATTERN.rxFrameNumber],);
      $display("\t-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------");
      for(i=0;i<`dut_port.g_tru_subentry_num;i++) if(`dut_port.tru_tab_entry_i[i].valid == 1)
      $display("\tTRU_TAB[fid=%2d, sub_fid=%1d]: pattern{mode=%1d, mask=0x%4x, match=0x%4x}, ports{mask=0x%4x, ingress=%b, egress=%b}",
                                                `dut_port.tru_tab_addr_o,
                                                 i,
                                                `dut_port.tru_tab_entry_i[i].pattern_mode,
                                                `dut_port.tru_tab_entry_i[i].pattern_mask,
                                                `dut_port.tru_tab_entry_i[i].pattern_match,
                                                `dut_port.tru_tab_entry_i[i].ports_mask,
                                                `dut_port.tru_tab_entry_i[i].ports_ingress,
                                                `dut_port.tru_tab_entry_i[i].ports_egress);
      $display("\t-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------");
   end

   task print_tru_state;
        input CSimDrv_WR_TRU tru_drv;
      begin
         bit[`c_num_ports-1:0]   endp_up;
         integer i;
         integer bank,ports_up, ports_stb_up;
         
         tru_drv.read_status(bank,ports_up, ports_stb_up);
         
         for(i=0;i<`c_num_ports;i++)
           endp_up[i]=t_ep2tru[i].status;
         $display("\n------------------------ STATUS DUMP -----------------------------");
         $display("[RTU_config ]: ports forwarding : %32b",t_rtu.pass_all);
         $display("[Endpoint   ]: ports up         : %32b",endp_up);
         $display("[TRU_status ]: ports up         : %32b",ports_up);
         $display("[TRU_status ]: ports up (stable): %32b",ports_stb_up);
         $display("[TRU_status ]: active bank      : %1d",bank);
         $display("------------------------------------------------------------------\n");
      end
   endtask;
   
   task ep_ports_up_all;
     integer i;
     
     for(i=0;i<`c_num_ports; i++) ep_port_up(i);
     
   endtask;

   ////////////////// simulating inputs from RTU ///////////////////
   task automatic rtu_enable_port;
      input[31:0]            portId;
      begin
         t_rtu.pass_all[portId] = 1;     
         $display("[RTU_config ] port %d forwarding", portId); 
      end;
   endtask;

   task automatic rtu_disable_port;
      input[31:0]            portId;
      begin
         t_rtu.pass_all[portId] = 0;      
         $display("[RTU_config ] port %d blocking", portId); 
      end;
   endtask;
   ////////////////   simulated endpoint inputs  //////////////////
   task automatic ep_port_up;
      input[31:0]            portId;
      begin
         t_ep2tru[portId].status = 1;      
         $display("[Endpoint in] port %d UP", portId); 
      end;
   endtask;

   task automatic ep_port_down;
      input[31:0]            portId;
      begin
         t_ep2tru[portId].status = 0;      
         $display("[Endpoint in] port %d DOWN", portId); 
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
         $display("[Endpoint in] port %d UP", portId); 
      end;
   endtask;

   task automatic init_stuff;
        input CSimDrv_WR_TRU tru_drv;
      begin
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

        for(i=0;i<`c_num_ports;i++)   
           t_ep2tru[i] = 0;
        
        /*
         * Globacl Config Register
         **/

        wait_cycles(100);
        tru_drv.pattern_config(1 /*replacement*/ ,2 /*addition*/);
        tru_drv.rt_reconf_config(4 /*tx_frame_id*/, 4/*rx_frame_id*/, 1 /*mode*/);
        tru_drv.rt_reconf_enable();
        
        /*
         * transition
         **/
        tru_drv.transition_config(0 /*mode */,     4 /*rx_id*/, 0 /*prio*/, 20 /*time_diff*/, 
                                  3 /*port_a_id*/, 4 /*port_b_id*/);
        tru_drv.tru_enable();
        $display("TRU initiated\n");
        
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
        $display("Ports up");
      end;
    endtask;
 


   task tru_tab_config_1;
      input CSimDrv_WR_TRU tru_drv;
      begin
        /*
         **/
        //////////////////////////////////////////// ENTRY 0 ///////////////////////////////////////

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  0  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/, 'h0 /* pattern_mode */,
                               'h0F /*ports_mask  */, 'h02 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h02 /* pattern_match*/,'h1  /* pattern_mode */,
                               'h00 /*ports_mask  */, 'h04 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h0  /* pattern_mode */,
                               'h00 /*ports_mask  */, 'h30 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                               'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);


        //////////////////////////////////////////// ENTRY 1 ///////////////////////////////////////
        tru_drv.write_tru_tab(  1   /* valid     */,   1  /* entry_addr   */,  0  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h0 /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h12 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   1  /* entry_addr   */,  1  /* subentry_addr*/,
                               'h0F /*pattern_mask*/, 'h02 /* pattern_match*/,'h0  /* pattern_mode */,
                               'h0F /*ports_mask  */, 'h04 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   1  /* entry_addr   */,  2  /* subentry_addr*/,
                               'hF0 /*pattern_mask*/, 'h10 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hF0 /*ports_mask  */, 'h20 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   1  /* entry_addr   */,  3  /* subentry_addr*/,
                               'hFF /*pattern_mask*/, 'hC0 /* pattern_match*/,'h2  /* pattern_mode */,
                              'hFF /*ports_mask  */, 'hC0 /* ports_egress */,'hC0 /* ports_ingress   */);

        tru_drv.tru_swap_bank();      
        $display("configuration 1");
      end;
   endtask;

   task tru_tab_config_2;
      input CSimDrv_WR_TRU tru_drv;
      begin
        /*
         * | port  | ingress | egress |
         * |--------------------------|
         * |   0   |   1     |   1    |   
         * |   1   |   0     |   1    |   
         * |   2   |   1     |   1    |   
         * |   3   |   1     |   1    |   
         * |   4   |   1     |   1    |   
         * |   5   |   0     |   1    |   
         * |--------------------------|
         * 
         *      5 -> 1 -> 0 
         *    ----------------
         *  port 1 is backup for 0
         *  port 5 is backup ofr 1
         * 
         **/

        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,   0 /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/, 'h0 /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3F /* ports_egress */,'h1D /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               'h03 /*pattern_mask*/, 'h01 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3E /* ports_egress */,'h1E /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               'h03 /*pattern_mask*/, 'h03 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3C /* ports_egress */,'h3C /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                               'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);

        tru_drv.tru_swap_bank();      
        $display("configuration 2");
      end;
   endtask;

   task simulate_transition ;
      input[31:0]            portA;
      input[31:0]            portB;
      input[31:0]            timeDiff;
      input[31:0]            rx_frame_id;
      input[31:0]            prio;
      begin
      
      $display("\t > ------------ Simulating transition -----------< ");
      $display("\t > \t\t From  portA    %2d \t\t <",portA);
      $display("\t > \t\t To    portB    %2d \t\t <",portB);
      $display("\t > \t\t At    Priority %2d \t\t <",prio);
      $display("\t > \t\t With  TimeDiff %2d \t\t <",timeDiff);
      $display("\t > \t\t Using RxFrames %2d \t\t <",rx_frame_id);
      $display("\t > ----------------------------------------------< ");
      wait_cycles(1);      

      t_rtu.priorities[portA] = prio;
      t_rtu.priorities[portB] = prio;
      
      t_ep2tru[portA].rx_pck_class[rx_frame_id] = 1;      
      t_ep2tru[portA].rx_pck = 1;   
      wait_cycles(1);
      t_ep2tru[portA].rx_pck_class[rx_frame_id] = 0;      
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
      t_ep2tru[portB].rx_pck_class[rx_frame_id] = 1;      
      t_ep2tru[portB].rx_pck = 1;   
      wait_cycles(1);
      t_ep2tru[portB].rx_pck_class[rx_frame_id] = 0;      
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
      input[`c_num_ports-1:0] portID;
      begin 
        t_req.valid    = 1;    
        t_req.smac     = smac;
        t_req.dmac     = dmac;
        t_req.fid      = fid;
        t_req.isHP     = isHP;
        t_req.isBR     = isBR;
        t_req.reqMask  = 1 << portID;
        
        wait_cycles(1);
        
        t_req.valid    = 0;    
        t_req.smac     = 0;
        t_req.dmac     = 0;
        t_req.fid      = 0;
        t_req.isHP     = 0;
        t_req.isBR     = 0;
        t_req.reqMask  = 0;
        
        if(isHP==1)      $display("\nReq  @ port %2d: fid=%2d, smac=0x%x, dmac=0x%x, high prio traffic", portID, fid, smac, dmac);
        else if(isBR==1) $display("\nReq  @ port %2d: fid=%2d, smac=0x%x, dmac=0x%x, broadcast traffic", portID, fid, smac, dmac);
        else             $display("\nReq  @ port %2d: fid=%2d, smac=0x%x, dmac=0x%x, normal traffic", portID, fid, smac, dmac);

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

   task test_1;
     input CSimDrv_WR_TRU tru_drv;
     begin
        integer i;
        $display("\n");
        $display("-------------------------------------------------------------------------------");
        $display("------------------------             TEST 1             -----------------------");
        $display("------------------------           [ START ]            -----------------------");
        $display("-------------------------------------------------------------------------------");
        $display("Simple test to check normal response, respons with port broken and transition");
        $display("-------------------------------------------------------------------------------");
        $display("\n");
        
        wait_cycles(100);
     
        tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,0/*portID*/);
        wait_cycles(20);
        tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,1/*portID*/);
        tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,2/*portID*/);
        tru_request (1234/*smac*/, 5678/*dmac*/, 2/*fid*/, 0/*isHP*/, 0/*isBR*/,3/*portID*/);
        tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,4/*portID*/);     
     
        ep_port_down(1);     
   
        wait_cycles(10);
        tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,0/*portID*/);
        wait_cycles(10);
        ep_port_down(4);
        wait_cycles(1);
        tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,0/*portID*/);
        wait_cycles(10);
        ep_port_down(5);
        wait_cycles(1);
        tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,0/*portID*/);
     
        print_tru_state(tru_drv);
     
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
        tru_request (1234/*smac*/, 5678/*dmac*/, 1/*fid*/, 0/*isHP*/, 0/*isBR*/,0/*portID*/);
     
        tru_drv.transition_enable();

        wait_cycles(100);
        simulate_transition(3 /*portA*/,4 /*portB*/,20/*timeDiff*/,4 /*rx_frame_id*/,0/*priority*/);
        $display("-------------------------------------------------------------------------------");
        $display("------------------------             TEST 1             -----------------------");
        $display("------------------------          [ FINISH ]            -----------------------");
        $display("-------------------------------------------------------------------------------");


     end;
   endtask;

   task test_2;
     input CSimDrv_WR_TRU tru_drv;
     begin
        integer i;
        $display("\n");
        $display("-------------------------------------------------------------------------------");
        $display("------------------------             TEST 2             -----------------------");
        $display("------------------------           [ START ]            -----------------------");
        $display("-------------------------------------------------------------------------------");
        $display("Simple test to check normal response, respons with port broken and transition");
        $display("-------------------------------------------------------------------------------");
        $display("\n");
        
        wait_cycles(100);
        ep_ports_up_all();
        wait_cycles(10);
        print_tru_state(tru_drv);   // port 1 should indicate stable up
        /*
         * All is working
         **/
        $display("\n>>>>>>>>>>> (1) send frame from each port, all ports OK: <<<<<<<<<<<<<<<\n");
        for(i=0;i<`c_num_ports; i++)
          tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,i/*portID*/);

        /*
         * A single port (number 0) goes down, it has backup
         **/        
        wait_cycles(10);
        ep_port_down(0);
        wait_cycles(10);
        
        $display("\n>>>>>>>>>>> (2) send frame from each port, port 0 down: <<<<<<<<<<<<<<<\n");
        for(i=0;i<`c_num_ports; i++)
          tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,i/*portID*/);

        /*
         * The backup port (numbet 1) goes down as well, it has backup
         **/                
        wait_cycles(10);
        ep_port_down(1);
        wait_cycles(10);
        
        $display("\n>>>>>>>>>>> (3) send frame from each port, porgs 0 and 1 down: <<<<<<<<<<<<<<<\n");
        for(i=0;i<`c_num_ports; i++)
          tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,i/*portID*/);

        wait_cycles(10);
        $display("\n>>>>>>>>>>> (4) re-configure table <<<<<<<<<<<<<<<\n");
        /*
         * eRSTP reconfigures topology to include new arrangement (with two ports down)
         **/        

        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,   0 /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/, 'h0 /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3C /* ports_egress */,'h3C /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               'h03 /*pattern_mask*/, 'h01 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3E /* ports_egress */,'h1E /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               'h03 /*pattern_mask*/, 'h03 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3C /* ports_egress */,'h3C /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                               'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);
        
        tru_drv.tru_swap_bank();  // flush TRU TAB
        wait_cycles(10);
        
        $display("\n>>>>>>>>>>> (5) disable non-working ports <<<<<<<<<<<<<<<\n");
        // disable not used / working ports
        rtu_disable_port(0);
        rtu_disable_port(1);
        wait_cycles(10);

        print_tru_state(tru_drv);   // ports 
        
        wait_cycles(10);
        $display("\n>>>>>>>>>>> (6) send frame from each port, all enabled/configured ports OK: <<<<<<<<<<<<<<<\n");
        for(i=0;i<`c_num_ports; i++)
          tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,i/*portID*/);

        wait_cycles(10);        
        $display("\n>>>>>>>>>>> (7) reviving port 0<<<<<<<<<<<<<<<\n");
        // revive port 0
        ep_port_up(0);
        wait_cycles(10);
        $display("\n port 0 just come up so not stable, but seen up because is disabled");
        print_tru_state(tru_drv);   // ports 
        wait_cycles(100);
        $display("\n port 0 up and stable\n");
        print_tru_state(tru_drv);   // port 1 should indicate stable up
        wait_cycles(10);
        
        wait_cycles(10);        
        $display("\n>>>>>>>>>>> (8) enabling port 0 in RTU, no config in TRU <<<<<<<<<<<<<<<\n");
        rtu_enable_port(0);

        wait_cycles(10);

        $display("\n>>>>>>>>>>> (9) send frame from each port, all enabled/configured ports OK: <<<<<<<<<<<<<<<\n");
        for(i=0;i<`c_num_ports; i++)
          tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,i/*portID*/);

        wait_cycles(10);
        
        $display("\n>>>>>>>>>>> (10) reconfig TRU TAB without changing banks <<<<<<<<<<<<<<<\n");
        wait_cycles(10);
        
        tru_drv.write_tru_tab(  1   /* valid     */,     0 /* entry_addr   */,   0 /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/, 'h0 /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3F /* ports_egress */,'h1D /* ports_ingress   */);

        tru_drv.write_tru_tab(  1   /* valid     */,   0  /* entry_addr   */,  1  /* subentry_addr*/,
                               'h03 /*pattern_mask*/, 'h01 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3E /* ports_egress */,'h1E /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  2  /* subentry_addr*/,
                               'h03 /*pattern_mask*/, 'h03 /* pattern_match*/,'h0  /* pattern_mode */,
                               'hFF /*ports_mask  */, 'h3C /* ports_egress */,'h3C /* ports_ingress   */);

        tru_drv.write_tru_tab(  0   /* valid     */,   0  /* entry_addr   */,  3  /* subentry_addr*/,
                               'h00 /*pattern_mask*/, 'h00 /* pattern_match*/,'h20 /* pattern_mode */,
                               'h00 /*ports_mask  */, 'h40 /* ports_egress */,'h01 /* ports_ingress   */);
        wait_cycles(10)   ;     
        $display("\n>>>>>>>>>>> (11) configure transition <<<<<<<<<<<<<<<\n");
        wait_cycles(10);

        tru_drv.transition_config(0 /*mode */,     4 /*rx_id*/, 0 /*prio*/, 20 /*time_diff*/, 
                                  5 /*port_a_id*/, 0 /*port_b_id*/);        
        tru_drv.transition_enable();
        $display("\n>>>>>>>>>>> (12) perform transition <<<<<<<<<<<<<<<\n");
        wait_cycles(100);
        simulate_transition(5 /*portA*/,0 /*portB*/,20/*timeDiff*/,4 /*rx_frame_id*/, 0/*priority*/);
        wait_cycles(100);

        print_tru_state(tru_drv);   // port 1 should indicate stable up
        wait_cycles(10);

        $display("\n>>>>>>>>>>> (13) send frame from each port, all enabled/configured ports OK: <<<<<<<<<<<<<<<\n");
        for(i=0;i<`c_num_ports; i++)
          tru_request (1234/*smac*/, 5678/*dmac*/, 0/*fid*/, 0/*isHP*/, 0/*isBR*/,i/*portID*/);


        wait_cycles(10);
        $display("-------------------------------------------------------------------------------");
        $display("------------------------             TEST 2             -----------------------");
        $display("------------------------          [ FINISH ]            -----------------------");
        $display("-------------------------------------------------------------------------------");


     end;
   endtask;


   initial begin
     
     integer i;
     CWishboneAccessor tru_acc;
     CSimDrv_WR_TRU    tru_drv;
     
     /******************************* INIT STUFF **********************************/
     
     tru_acc = U_tru_wb.get_accessor();
     tru_drv = new(tru_acc, 0);
     
     init_stuff(tru_drv);
     
     /******************************* Simulate stuff *******************************/
     
//      tru_tab_config_1(tru_drv);
//      test_1(tru_drv);

        tru_tab_config_2(tru_drv);
        test_2(tru_drv);
   end    

endmodule // main

