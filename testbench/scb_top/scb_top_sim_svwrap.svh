`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "simdrv_wr_endpoint.svh"
`include "if_wb_master.svh"
`include "if_wb_slave.svh"


function automatic bit f_next_8b10b_disparity8(bit cur_disp, bit k, bit [7:0] data);
   const bit[0:31] c_disPar_6b = 32'b11101000100000011000000110010111;
   const bit [0:7] c_disPar_4b  = 8'b10001001;
   bit             dp4bit, dp6bit, new_disp;

   dp4bit = c_disPar_4b[data[7:5]];
   dp6bit = c_disPar_6b[data[4:0]];
   new_disp = cur_disp;

   
   case (cur_disp) 
     1'b0: if (k ^ dp6bit ^ dp4bit)
       new_disp = 1;
     1'b1: if (k ^ dp6bit ^ dp4bit)
       new_disp = 0;
   endcase // case (cur_disp)

   if ( data[1:0] != 2'b0 && k) 
     new_disp = cur_disp;
   
   return new_disp;
endfunction // f_next_8b10b_disparity8

function automatic bit f_next_8b10b_disparity16(bit cur_disp,bit[1:0] k, bit[15:0] data);
   bit             tmp;
   bit [7:0]       msb;

   msb = data[15:0];
   tmp = f_next_8b10b_disparity8(cur_disp, k[1], msb);
   tmp = f_next_8b10b_disparity8(tmp, k[0], data[7:0]);
   return tmp;
endfunction // f_next_8b10b_disparity16

module scb_top_sim_svwrap
  (
   clk_sys_i,
   clk_ref_i,
   rst_n_i,
   cpu_irq,
   clk_swc_mpm_core_i,
   ep_ctrl_i
   );

   parameter g_num_ports = 6;
   

   
   input clk_sys_i, clk_ref_i,rst_n_i,clk_swc_mpm_core_i;
   input bit[g_num_ports-1:0] ep_ctrl_i;
   output cpu_irq;

   wire [g_num_ports-1:0] rbclk;
   
   wire [18 * g_num_ports - 1:0] td, rd;

    typedef struct { 
       logic       rst;
       logic       loopen;
       logic       enable;
       logic       syncen;
       logic [15:0] tx_data;
       logic [1:0]  tx_k;
    }  t_phyif_output;
   

   typedef struct {
      logic       ref_clk;
      logic     tx_disparity;
      logic     tx_enc_err  ;
      logic  [15:0]   rx_data     ;
      logic     rx_clk      ;
      logic  [1:0]   rx_k        ;
      logic     rx_enc_err  ;
      logic     rx_bitslide ;
   } t_phyif_input;

   t_phyif_output phys_out[g_num_ports];
   t_phyif_input phys_in[g_num_ports];

   WBPacketSource to_port[g_num_ports];
   WBPacketSink from_port[g_num_ports];
   int       seed2;

   IWishboneMaster #(32, 32) cpu(clk_sys_i, rst_n_i);

   initial 
     begin
        cpu.settings.cyc_on_stall = 1;
        cpu.settings.addr_gran = BYTE;
     end
   
   reg [g_num_ports-1:0] clk_ref_phys = 0; 
   time  periods[g_num_ports];
   


   
   
   
   generate 
      genvar    i;
      
      
      
      for(i=0; i<g_num_ports; i++)
        begin

           initial forever #(periods[i]) clk_ref_phys[i] <= ~clk_ref_phys[i];
           initial periods[i] = 8ns;
//$dist_uniform(seed2, 8ns, 8ns);
           

           
      IWishboneMaster U_ep_wb (clk_sys_i, rst_n_i) ;
      IWishboneMaster #(2,16) U_ep_src (clk_sys_i, rst_n_i) ;
      IWishboneSlave #(2,16) U_ep_snk (clk_sys_i, rst_n_i) ;
        
        wr_endpoint
            #(
              .g_simulation          (1),
              .g_pcs_16bit(1),
              .g_rx_buffer_size (1024),
              .g_with_rx_buffer (0),
              .g_with_timestamper    (1),
              .g_with_dpi_classifier (1),
              .g_with_vlans          (1),
              .g_with_rtu            (0)
              ) DUT (
                     .clk_ref_i (clk_ref_phys[i]),
                     .clk_sys_i (clk_sys_i),
                     .clk_dmtd_i (clk_ref_i),
                     .rst_n_i  (rst_n_i),
                     .pps_csync_p1_i (1'b0),
                     
                     .phy_rst_o   (phys_out[i].rst),
                     .phy_loopen_o (),
                     .phy_enable_o (),
                     .phy_syncen_o (),

                     .phy_ref_clk_i      (phys_in[i].ref_clk),
                     .phy_tx_data_o      (phys_out[i].tx_data),
                     .phy_tx_k_o         (phys_out[i].tx_k),
                     .phy_tx_disparity_i (phys_in[i].tx_disparity),
                     .phy_tx_enc_err_i   (phys_in[i].tx_enc_err),

                     .phy_rx_data_i     (phys_in[i].rx_data),
                     .phy_rx_clk_i      (phys_in[i].rx_clk),
                     .phy_rx_k_i        (phys_in[i].rx_k),
                     .phy_rx_enc_err_i  (phys_in[i].rx_enc_err),
                     .phy_rx_bitslide_i (5'b0),

                     .src_dat_o   (U_ep_snk.slave.dat_i),
                     .src_adr_o   (U_ep_snk.slave.adr),
                     .src_sel_o   (U_ep_snk.slave.sel),
                     .src_cyc_o   (U_ep_snk.slave.cyc),
                     .src_stb_o   (U_ep_snk.slave.stb),
                     .src_we_o    (U_ep_snk.slave.we),
                     .src_stall_i (U_ep_snk.slave.stall),
                     .src_ack_i   (U_ep_snk.slave.ack),
                     .src_err_i(1'b0),

                     .snk_dat_i   (U_ep_src.master.dat_o[15:0]),
                     .snk_adr_i   (U_ep_src.master.adr[1:0]),
                     .snk_sel_i   (U_ep_src.master.sel[1:0]),
                     .snk_cyc_i   (U_ep_src.master.cyc),
                     .snk_stb_i   (U_ep_src.master.stb),
                     .snk_we_i    (U_ep_src.master.we),
                     .snk_stall_o (U_ep_src.master.stall),
                     .snk_ack_o   (U_ep_src.master.ack),
                     .snk_err_o   (U_ep_src.master.err),
                     .snk_rty_o   (U_ep_src.master.rty),
                    
                     .txtsu_ack_i (1'b1),

                     .rtu_full_i (1'b0),

                     .wb_cyc_i(U_ep_wb.master.cyc),
                     .wb_stb_i(U_ep_wb.master.stb),
                     .wb_we_i (U_ep_wb.master.we),
                     .wb_sel_i(U_ep_wb.master.sel),
                     .wb_adr_i(U_ep_wb.master.adr[7:0]),
                     .wb_dat_i(U_ep_wb.master.dat_o),
                     .wb_dat_o(U_ep_wb.master.dat_i),
                     .wb_ack_o (U_ep_wb.master.ack),

                      // new stuff
                     .pfilter_pclass_o    (), 
                     .pfilter_drop_o      (), 
                     .pfilter_done_o      (), 
                     .fc_tx_pause_req_i      (1'b0), 
                     .fc_tx_pause_delay_i    (16'b0), 
                     .fc_tx_pause_ready_o    (), 
                     .inject_req_i        (1'b0), 
                     .inject_ready_o      (), 
                     .inject_packet_sel_i (3'b0), 
                     .inject_user_value_i (16'b0), 
                     .led_link_o          (), 
                     .led_act_o           (), 
                     .link_kill_i         ((~ep_ctrl_i[i])), 
//                     .link_kill_i         (1'b0), 
                     .link_up_o           () 

//                      .tru_status_o(),        
//                      .tru_ctrlRd_o(),        
//                      .tru_rx_pck_o(),        
//                      .tru_rx_pck_class_o(),  
//    
//                      .tru_ctrlWr_i(ep_ctrl_i[i]),            
//                      .tru_tx_pck_i(1'b0),            
//                      .tru_tx_pck_class_i(8'b0),      
//                      .tru_pauseSend_i(1'b0),         
//                      .tru_pauseTime_i(16'b0),         
//                      .tru_outQueueBlockMask_i(8'b0)
                     );

           initial begin
              CWishboneAccessor ep_acc;
              CSimDrv_WR_Endpoint ep_drv;

              U_ep_src.settings.gen_random_throttling = 0;
              U_ep_snk.settings.gen_random_stalls = 0;
              
              
              @(posedge rst_n_i);
              repeat(100) @(posedge clk_sys_i);

              ep_acc = U_ep_wb.get_accessor();
              ep_drv = new (ep_acc, 0);
              ep_drv.init(0);

              from_port[i] = new (U_ep_snk.get_accessor());
              to_port[i] = new (U_ep_src.get_accessor());
              
              
              end
           end // for (i=0; i<g_num_ports; i++)
      endgenerate


   generate
      genvar j;


      
      for(j=0;j<g_num_ports;j++) begin
         assign rbclk[j] = clk_ref_phys[j];
         
         ///////////////// nasty hack by Maciej /////////////////
         // causing sync error in the Switch 
         assign td[18 * j + 15 : 18 * j]      = ep_ctrl_i[j] ? phys_out[j].tx_data :  'h00BC;
         assign td[18 * j + 17 : 18 * j + 16] = ep_ctrl_i[j] ? phys_out[j].tx_k    : 2'b01;
         // causing transmission error in the driving simulation
         assign phys_in[j].tx_enc_err         = ~ep_ctrl_i[j];
         ///////////////////////////////////////////////////////

         assign phys_in[j].ref_clk    = clk_ref_phys[j];
         assign phys_in[j].rx_data    = rd[18 * j + 15 : 18 * j];
         assign phys_in[j].rx_k       = rd[18 * j + 17 : 18 * j + 16];
         assign phys_in[j].rx_clk     = clk_ref_i;
//          assign phys_in[j].tx_enc_err = 0;
         assign phys_in[j].rx_enc_err = 0;
         
 
         always@(posedge clk_ref_i) begin : gen_disparity
            if(phys_out[j].rst)
              phys_in[j].tx_disparity = 0;
            else
              phys_in[j].tx_disparity = f_next_8b10b_disparity16
                                         (
                                          phys_in[j].tx_disparity, 
                                          phys_out[j].tx_k, 
                                          phys_out[j].tx_data);
         end
         
      end
   endgenerate

   
scb_top_sim 
  #(
    .g_num_ports(g_num_ports)
    )
   U_Top 
  (
   .sys_rst_n_i         ( rst_n_i),
   .clk_startup_i       ( clk_sys_i),
   .clk_ref_i           ( clk_ref_i),
   .clk_dmtd_i            ( clk_ref_i),
//   .clk_sys_i           ( clk_sys_i),
   .clk_aux_i   ( clk_swc_mpm_core_i),
   .wb_adr_i            ( cpu.master.adr),
   .wb_dat_i            ( cpu.master.dat_o),
   .wb_dat_o            ( cpu.master.dat_i),
   .wb_cyc_i            ( cpu.master.cyc),
   .wb_sel_i            ( cpu.master.sel),
   .wb_stb_i            ( cpu.master.stb),
   .wb_we_i             ( cpu.master.we),
   .wb_ack_o            ( cpu.master.ack),
   .wb_stall_o          ( cpu.master.stall),
   .wb_irq_o            ( cpu_irq ),
   .pps_i               ( 1'b0 ),
//    .pps_o               ( pps_o),
//    .dac_helper_sync_n_o ( dac_helper_sync_n_o),
//    .dac_helper_sclk_o   ( dac_helper_sclk_o),
//    .dac_helper_data_o   ( dac_helper_data_o),
//    .dac_main_sync_n_o   ( dac_main_sync_n_o),
//    .dac_main_sclk_o     ( dac_main_sclk_o),
//    .dac_main_data_o     ( dac_main_data_o),
//    .pll_status_i        ( pll_status_i),
//    .pll_mosi_o          ( pll_mosi_o),
//    .pll_miso_i          ( pll_miso_i),
//    .pll_sck_o           ( pll_sck_o),
//    .pll_cs_n_o          ( pll_cs_n_o),
//    .pll_sync_n_o        ( pll_sync_n_o),
//    .pll_reset_n_o       ( pll_reset_n_o),
//    .uart_txd_o          ( uart_txd_o),
//    .uart_rxd_i          ( uart_rxd_i),
//    .clk_en_o            ( clk_en_o),
//    .clk_sel_o           ( clk_sel_o),
    .td_o                ( rd),
    .rd_i                ( td),
   .rbclk_i             ( rbclk)
//    .led_link_o          ( led_link_o),
//    .led_act_o           ( led_act_o);
   );
   
      
endmodule // scb_top_sim_svwrap

