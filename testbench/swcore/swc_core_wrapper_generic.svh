

`include "swc_param_defs.svh"

`define array_assign(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) begin assign a[k] = b[bl+k-al]; end

module swc_core_wrapper_generic
  (
   clk_i,
   clk_mpm_core_i,
   rst_n_i,
   src,
   snk,

   rtu_rsp_valid_i,
   rtu_rsp_ack_o,
   rtu_dst_port_mask_i,
   rtu_drop_i,
   rtu_prio_i

   );

   input clk_i;
   input clk_mpm_core_i;
   input rst_n_i;

   IWishboneMaster  #(2,16) src[`c_num_ports] (clk_i,rst_n_i);
   IWishboneSlave   #(2,16) snk[`c_num_ports] (clk_i,rst_n_i);

   input  [`c_num_ports-1 :0]              rtu_rsp_valid_i;
   output [`c_num_ports-1 :0]              rtu_rsp_ack_o;
   input  [`c_num_ports*`c_num_ports-1 :0] rtu_dst_port_mask_i;
   input  [`c_num_ports-1 :0]              rtu_drop_i;
   input  [`c_num_ports*3-1 :0]            rtu_prio_i;

    wire [`c_num_ports*16 -1 :0] snk_dat  ;
    wire [`c_num_ports*2  -1 :0] snk_adr  ;
    wire [`c_num_ports*2  -1 :0] snk_sel  ;
    wire [`c_num_ports    -1 :0] snk_cyc  ;
    wire [`c_num_ports    -1 :0] snk_stb  ;
    wire [`c_num_ports    -1 :0] snk_we   ;
    wire [`c_num_ports    -1 :0] snk_stall;
    wire [`c_num_ports    -1 :0] snk_ack  ;
    wire [`c_num_ports    -1 :0] snk_err  ;
    wire [`c_num_ports    -1 :0] snk_rty  ;

    wire [`c_num_ports*16 -1 :0] src_dat  ;
    wire [`c_num_ports*2  -1 :0] src_adr  ;
    wire [`c_num_ports*2  -1 :0] src_sel  ;
    wire [`c_num_ports    -1 :0] src_cyc  ;
    wire [`c_num_ports    -1 :0] src_stb  ;
    wire [`c_num_ports    -1 :0] src_we   ;
    wire [`c_num_ports    -1 :0] src_stall;
    wire [`c_num_ports    -1 :0] src_ack  ;
    wire [`c_num_ports    -1 :0] src_err  ;
   
   swc_core
     #(
       .g_prio_num                         (`c_prio_num),
       .g_max_pck_size                     (`c_max_pck_size),
       .g_num_ports                        (`c_num_ports),
       .g_pck_pg_free_fifo_size            (`c_pck_pg_free_fifo_size),
       .g_input_block_cannot_accept_data   (`c_input_block_cannot_accept_data),
       .g_output_block_per_prio_fifo_size  (`c_output_block_per_prio_fifo_size),

       .g_wb_data_width                    (`c_wb_data_width),
       .g_wb_addr_width                    (`c_wb_addr_width),
       .g_wb_sel_width                     (`c_wb_sel_width),

       .g_mpm_mem_size                     (`c_mpm_mem_size),
       .g_mpm_page_size                    (`c_mpm_page_size),
       .g_mpm_ratio                        (`c_mpm_ratio),
       .g_mpm_fifo_size                    (`c_mpm_fifo_size),

       .g_ctrl_width                       (`c_ctrl_width),
       .g_packet_mem_multiply              (`c_packet_mem_multiply),
       .g_input_block_fifo_size            (`c_input_block_fifo_size),
       .g_input_block_fifo_full_in_advance (`c_input_block_fifo_full_in_advance)
       ) DUT_swc_core(
              .clk_i               (clk_i),
              .clk_mpm_core_i      (clk_mpm_core_i),
              .rst_n_i             (rst_n_i),

              .snk_dat_i           (snk_dat),
              .snk_adr_i           (snk_adr),
              .snk_sel_i           (snk_sel),
              .snk_cyc_i           (snk_cyc),
              .snk_stb_i           (snk_stb),
              .snk_we_i            (snk_we),
              .snk_stall_o         (snk_stall),
              .snk_ack_o           (snk_ack),
              .snk_err_o           (snk_err),
              .snk_rty_o           (snk_rty),

              .src_dat_o           (src_dat),
              .src_adr_o           (src_adr),
              .src_sel_o           (src_sel),
              .src_cyc_o           (src_cyc),
              .src_stb_o           (src_stb),
              .src_we_o            (src_we),
              .src_stall_i         (src_stall),
              .src_ack_i           (src_ack),
              .src_err_i           (src_err),

	      .rtu_rsp_valid_i     (rtu_rsp_valid_i),
	      .rtu_rsp_ack_o       (rtu_rsp_ack_o),
	      .rtu_dst_port_mask_i (rtu_dst_port_mask_i),
	      .rtu_drop_i          (rtu_drop_i),
	      .rtu_prio_i          (rtu_prio_i)

    );
   genvar i, k;
   generate
     for(i=0;i<`c_num_ports;i=i+1)
     begin
      `array_assign(snk_dat,(i+1)*16-1, i*16,src[i].dat_o,0);
      `array_assign(snk_adr,(i+1)*2 -1, i*2 ,src[i].adr,0);
      `array_assign(snk_sel,(i+1)*2 -1 ,i*2 ,src[i].sel,0);
      assign snk_cyc[i]     = src[i].cyc;
      assign snk_stb[i]     = src[i].stb;
      assign snk_we[i]      = src[i].we;
      
      assign src[i].stall = snk_stall[i];
      assign src[i].ack   = snk_ack[i];
      assign src[i].err   = snk_err[i];
      assign src[i].rty   = snk_rty[i];
      
      `array_assign(snk[i].dat_i,15,0,src_dat,i*16);
      `array_assign(snk[i].adr  ,1, 0,src_adr,i*2);
      `array_assign(snk[i].sel  ,1, 0,src_sel,i*2);

      assign snk[i].cyc  = src_cyc[i];
      assign snk[i].stb  = src_stb[i];
      assign snk[i].we   = src_we[i];
   
      assign src_stall[i]         = snk[i].stall;
      assign src_ack[i]           = snk[i].ack;
      assign src_err[i]           = snk[i].err;

     end //for(i=0;i<`c_num_ports;i=i+1)
   endgenerate

endmodule 
