`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "simdrv_wr_endpoint.svh"
`include "if_wb_master.svh"
`include "if_wb_slave.svh"

`define c_max_pipe_len 100


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

   bit[17:0] pipeline[2][`c_max_pipe_len];

function automatic bit[17:0] f_link_simulation(bit[17:0] int_data, int delay, int nbr);
   
   for(int i=`c_max_pipe_len-1;i>0;i--)
   begin
     pipeline[nbr][i] = pipeline[nbr][i-1];
   end
   pipeline[nbr][0] =  int_data;
   return pipeline[nbr][delay];
   
endfunction;

module scb_top_sim_svwrap
  (
   clk_sys_i,
   clk_ref_i,
   rst_n_i,
   cpu_irq,
   clk_swc_mpm_core_i,
   ep_ctrl_i
//    links_ctrl_i   
   );

   parameter g_num_ports = 18; // default  
   parameter g_port_bunch_number = 6;
   
   input clk_sys_i, clk_ref_i,rst_n_i,clk_swc_mpm_core_i;
   input bit[g_num_ports-1:0] ep_ctrl_i;      // control (up/down) of "simulation endpoints"
   //input bit[g_num_ports-1:0] links_ctrl_i;   // control (up/down) of links connecting switches
   //input int links_delay_i[g_num_ports-1:0] ; // delay on links connecting switches
   output bit[2:0] cpu_irq;

   wire [g_num_ports-1:0] rbclk;
   
   wire [18 * g_num_ports - 1:0] td, rd;
   reg [18 * g_num_ports - 1:0] sw_td[3], sw_rd[3];
   

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

   IWishboneMaster #(32, 32) cpu_0(clk_sys_i, rst_n_i);
   IWishboneMaster #(32, 32) cpu_1(clk_sys_i, rst_n_i);
   IWishboneMaster #(32, 32) cpu_2(clk_sys_i, rst_n_i);
   
   initial 
     begin
        cpu_0.settings.cyc_on_stall = 1;
        cpu_0.settings.addr_gran = BYTE;
        cpu_1.settings.cyc_on_stall = 1;
        cpu_1.settings.addr_gran = BYTE;
        cpu_2.settings.cyc_on_stall = 1;
        cpu_2.settings.addr_gran = BYTE;
     end
   
   reg [g_num_ports-1:0] clk_ref_phys = 0; 
   time  periods[g_num_ports];
   


   
   
   /// generate simulation endpints 
   generate 
      genvar    i;
      for(i=0; i<g_num_ports; i++) begin
        initial forever #(periods[i]) clk_ref_phys[i] <= ~clk_ref_phys[i];
        initial periods[i] = 8ns;
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
              .g_with_vlans          (0),
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
                     .tru_status_o(),        
                     .tru_ctrlRd_o(),        
                     .tru_rx_pck_o(),        
                     .tru_rx_pck_class_o(),  
   
                     .tru_ctrlWr_i(ep_ctrl_i[i]),            
                     .tru_tx_pck_i(1'b0),            
                     .tru_tx_pck_class_i(8'b0),      
                     .tru_pauseSend_i(1'b0),         
                     .tru_pauseTime_i(16'b0),         
                     .tru_outQueueBlockMask_i(8'b0)
                     );
           /// initialize the simulation endpints
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

   /// connections: ALL endpints/switches
   
   generate
      genvar g;  
      for(g=0;g<g_num_ports;g++) begin
         
         /// ALL switches
         assign rbclk[g] = clk_ref_phys[g];
         
         /// ALL endpints
         assign phys_in[g].tx_enc_err               = ~ep_ctrl_i[g];
         assign phys_in[g].ref_clk                  = clk_ref_phys[g];
         assign phys_in[g].rx_clk                   = clk_ref_i;
         assign phys_in[g].rx_enc_err = 0;
         always@(posedge clk_ref_i) begin : gen_disparity
            if(phys_out[g].rst)
              phys_in[g].tx_disparity = 0;
            else
              phys_in[g].tx_disparity = f_next_8b10b_disparity16
                                         (
                                          phys_in[g].tx_disparity, 
                                          phys_out[g].tx_k, 
                                          phys_out[g].tx_data);
         end         
      end
   endgenerate
  

//    always@(posedge clk_ref_i) begin : gen_link_delay
//       sw_td[0][18 * (g_port_bunch_number)+ 17 : 18 * (g_port_bunch_number)] = f_link_simulation(sw_rd[1][18 * (g_port_bunch_number)+ 17 : 18 * (g_port_bunch_number)],90,0);
//       sw_td[1][18 * (g_port_bunch_number)+ 17 : 18 * (g_port_bunch_number)] = f_link_simulation(sw_rd[0][18 * (g_port_bunch_number)+ 17 : 18 * (g_port_bunch_number)],90,1);
//    end
   generate
      genvar j;  
      for(j=0;j<g_port_bunch_number;j++) begin
          
         /// connections: Endpints to Switch 0
         assign sw_td[0][18 * j + 15 : 18 * j]      = ep_ctrl_i[j] ? phys_out[j].tx_data :  'h00BC;
         assign sw_td[0][18 * j + 17 : 18 * j + 16] = ep_ctrl_i[j] ? phys_out[j].tx_k    : 2'b01;         
         assign phys_in[j].rx_data                  = sw_rd[0][18 * j + 15 : 18 * j];
         assign phys_in[j].rx_k                     = sw_rd[0][18 * j + 17 : 18 * j + 16];         

         /// connections: Endpints to Switch 1
         assign sw_td[1][18 * j + 15 : 18 * j]           = ep_ctrl_i[1*g_port_bunch_number + j] ? phys_out[1*g_port_bunch_number + j].tx_data :  'h00BC;
         assign sw_td[1][18 * j + 17 : 18 * j + 16]      = ep_ctrl_i[1*g_port_bunch_number + j] ? phys_out[1*g_port_bunch_number + j].tx_k    : 2'b01;         
         assign phys_in[1*g_port_bunch_number + j].rx_data = sw_rd[1][18 * j + 15 : 18 * j];
         assign phys_in[1*g_port_bunch_number + j].rx_k    = sw_rd[1][18 * j + 17 : 18 * j + 16];         

         /// connections: Endpints to Switch 2
         assign sw_td[2][18 * j + 15 : 18 * j]             = ep_ctrl_i[2*g_port_bunch_number + j] ? phys_out[2*g_port_bunch_number + j].tx_data :  'h00BC;
         assign sw_td[2][18 * j + 17 : 18 * j + 16]        = ep_ctrl_i[2*g_port_bunch_number + j] ? phys_out[2*g_port_bunch_number + j].tx_k    : 2'b01;         
         assign phys_in[2*g_port_bunch_number + j].rx_data   = sw_rd[2][18 * j + 15 : 18 * j];
         assign phys_in[2*g_port_bunch_number + j].rx_k      = sw_rd[2][18 * j + 17 : 18 * j + 16];         

         /// connections: Switch 0 <=> Switch 1
//          if(j != 0)begin
           assign sw_td[0][18 * (g_port_bunch_number+j)+ 17 : 18 * (j+g_port_bunch_number)] = sw_rd[1][18 * (g_port_bunch_number+j)+ 17 : 18 * (g_port_bunch_number+j)];
           assign sw_td[1][18 * (g_port_bunch_number+j)+ 17 : 18 * (j+g_port_bunch_number)] = sw_rd[0][18 * (g_port_bunch_number+j)+ 17 : 18 * (g_port_bunch_number+j)];
//          end

         /// connections: Switch 0 <=> Switch 2
         assign sw_td[2][18 * (  g_port_bunch_number+j) + 17 : 18 * (  g_port_bunch_number+j)]  = sw_rd[0][18 * (2*g_port_bunch_number+j)+ 17 : 18 * (2*g_port_bunch_number+j)];
         assign sw_td[0][18 * (2*g_port_bunch_number+j) + 17 : 18 * (2*g_port_bunch_number+j)]  = sw_rd[2][18 * (  g_port_bunch_number+j)+ 17 : 18 * (  g_port_bunch_number+j)];

         /// connections: Switch 1 <=> Switch 2
         assign sw_td[2][18 * (2*g_port_bunch_number+j) + 17 : 18 * (2*g_port_bunch_number+j)]      = sw_rd[1][18 * (2*g_port_bunch_number+j) + 17 : 18 * (2*g_port_bunch_number+j)];
         assign sw_td[1][18 * (2*g_port_bunch_number+j) + 17 : 18 * (2*g_port_bunch_number+j)]      = sw_rd[2][18 * (2*g_port_bunch_number+j) + 17 : 18 * (2*g_port_bunch_number+j)];
      end
   endgenerate
   ///  =======================  Devices Under Test (3 WR switches) ========================//
  
   /// WR Switch 0
   scb_top_sim 
     #(
       .g_num_ports(g_num_ports)
       )
     U_SW_0 
     (
      .sys_rst_n_i         ( rst_n_i),
      .clk_startup_i       ( clk_sys_i),
      .clk_ref_i           ( clk_ref_i),
      .clk_dmtd_i          ( clk_ref_i),
      .clk_aux_i           ( clk_swc_mpm_core_i),
      .wb_adr_i            ( cpu_0.master.adr),
      .wb_dat_i            ( cpu_0.master.dat_o),
      .wb_dat_o            ( cpu_0.master.dat_i),
      .wb_cyc_i            ( cpu_0.master.cyc),
      .wb_sel_i            ( cpu_0.master.sel),
      .wb_stb_i            ( cpu_0.master.stb),
      .wb_we_i             ( cpu_0.master.we),
      .wb_ack_o            ( cpu_0.master.ack),
      .wb_stall_o          ( cpu_0.master.stall),
      .wb_irq_o            ( cpu_irq[0] ),
      .pps_i               ( 1'b0 ),
      .td_o                ( sw_rd[0]),
      .rd_i                ( sw_td[0]),
      .rbclk_i             ( rbclk)
      );

   /// WR Switch 1
   scb_top_sim 
     #(
       .g_num_ports(g_num_ports)
       )
      U_SW_1 
     (
      .sys_rst_n_i         ( rst_n_i),
      .clk_startup_i       ( clk_sys_i),
      .clk_ref_i           ( clk_ref_i),
      .clk_dmtd_i          ( clk_ref_i),
      .clk_aux_i           ( clk_swc_mpm_core_i),
      .wb_adr_i            ( cpu_1.master.adr),
      .wb_dat_i            ( cpu_1.master.dat_o),
      .wb_dat_o            ( cpu_1.master.dat_i),
      .wb_cyc_i            ( cpu_1.master.cyc),
      .wb_sel_i            ( cpu_1.master.sel),
      .wb_stb_i            ( cpu_1.master.stb),
      .wb_we_i             ( cpu_1.master.we),
      .wb_ack_o            ( cpu_1.master.ack),
      .wb_stall_o          ( cpu_1.master.stall),
      .wb_irq_o            ( cpu_irq[1] ),
      .pps_i               ( 1'b0 ),
      .td_o                ( sw_rd[1]),
      .rd_i                ( sw_td[1]),
      .rbclk_i             ( rbclk)
      );
   
   /// WR Switch 2
   scb_top_sim 
     #(
       .g_num_ports(g_num_ports)
       )
      U_SW_2 
     (
      .sys_rst_n_i         ( rst_n_i),
      .clk_startup_i       ( clk_sys_i),
      .clk_ref_i           ( clk_ref_i),
      .clk_dmtd_i          ( clk_ref_i),
      .clk_aux_i           ( clk_swc_mpm_core_i),
      .wb_adr_i            ( cpu_2.master.adr),
      .wb_dat_i            ( cpu_2.master.dat_o),
      .wb_dat_o            ( cpu_2.master.dat_i),
      .wb_cyc_i            ( cpu_2.master.cyc),
      .wb_sel_i            ( cpu_2.master.sel),
      .wb_stb_i            ( cpu_2.master.stb),
      .wb_we_i             ( cpu_2.master.we),
      .wb_ack_o            ( cpu_2.master.ack),
      .wb_stall_o          ( cpu_2.master.stall),
      .wb_irq_o            ( cpu_irq[2] ),
      .pps_i               ( 1'b0 ),
      .td_o                ( sw_rd[2]),
      .rd_i                ( sw_td[2]),
      .rbclk_i             ( rbclk)
      );
   
      
endmodule // scb_top_sim_svwrap

