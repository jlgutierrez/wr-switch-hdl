`timescale 1ns/1ps

`define slice(array, index, ent_size) array[(ent_size) * ((index) + 1) - 1 : (ent_size) * (index)]

/* Interface'ized SystemVerilog wrapper for VHDL MPM module */
 
module mpm_top_swwrap
  (
   clk_core_i,
   clk_io_i,
   rst_n_i,
   wport,
   rport,
   ll
   );
   parameter t_swcore_parameters P = `DEFAULT_SWC_PARAMS;


   input         clk_io_i, clk_core_i, rst_n_i;

   IMPMWritePort wport [P.g_num_ports] ;
   IMPMReadPort rport [P.g_num_ports] ;
   ILinkedList ll;
   
   
   wire [P.g_num_ports * P.g_data_width -1:0] wp_data, rp_data;
   wire [P.g_num_ports-1:0]                   wp_dvalid, wp_dlast, wp_dreq, wp_pg_req;
   wire [P.g_num_ports-1:0]                   rp_dvalid, rp_dlast, rp_dreq, rp_pg_req, rp_pg_valid, rp_abort;
   wire [P.g_num_ports * P.g_page_address_width -1 : 0]   wp_pgaddr;
   wire [P.g_num_ports * P.g_page_address_width -1 : 0]   rp_pgaddr;
   wire [P.g_num_ports * P.g_partial_select_width -1 : 0]   rp_dsel;
   
   generate
      genvar i;

      for(i=0;i<P.g_num_ports;i++)
        begin
           /* Write port packing */
           assign `slice(wp_data, i, P.g_data_width) = wport[i].d;
           assign `slice(wp_dvalid, i, 1) = wport[i].d_valid;
           assign `slice(wp_dlast, i, 1) = wport[i].d_last;
           assign `slice(wp_pgaddr, i ,P.g_page_address_width) = wport[i].pg_addr;
           assign wport[i].dreq = wp_dreq[i];
           assign wport[i].pg_req = wp_pg_req[i];

           /* Read port packing */
           assign `slice(rp_pgaddr, i ,P.g_page_address_width) = rport[i].pg_addr;
           assign rp_abort[i] = rport[i].abort;
           assign rp_pg_valid[i] = rport[i].pg_valid;
           assign rp_dreq[i] = rport[i].dreq;
           assign rport[i].pg_req = rp_pg_req[i];
           assign rport[i].d_valid = rp_dvalid[i];
           assign rport[i].d_last = rp_dlast[i];
           assign rport[i].d_sel = `slice(rp_dsel, i, P.g_partial_select_width);
           assign rport[i].d = `slice(rp_data, i, P.g_data_width);
        end
   endgenerate
   
   
   mpm_top
     #(
       .g_data_width    (P.g_data_width),
       .g_ratio         (P.g_ratio),
       .g_page_size     (P.g_page_size),
       .g_num_pages     (P.g_num_pages),
       .g_num_ports     (P.g_num_ports),
       .g_fifo_size          (P.g_fifo_size),
       .g_page_addr_width       (P.g_page_address_width),
       .g_partial_select_width (P.g_partial_select_width)
    )
   Wrapped_MPM
     (
   
      .clk_io_i   (clk_io_i),
      .clk_core_i (clk_core_i),
      .rst_n_i    (rst_n_i),

      .wport_d_i       (wp_data),
      .wport_dvalid_i  (wp_dvalid),
      .wport_dlast_i   (wp_dlast),
      .wport_pg_addr_i (wp_pgaddr),
      .wport_dreq_o    (wp_dreq),
      .wport_pg_req_o    (wp_pg_req),

      .rport_d_o       (rp_data),
      .rport_dvalid_o  (rp_dvalid),
      .rport_dlast_o   (rp_dlast),
      .rport_dreq_i    (rp_dreq),
      .rport_dsel_o    (rp_dsel),
      .rport_abort_i   (rp_abort),
      .rport_pg_addr_i (rp_pgaddr),
      .rport_pg_valid_i(rp_pg_valid),
      .rport_pg_req_o  (rp_pg_req),

      .ll_addr_o (ll.ll_addr),
      .ll_data_i (ll.ll_data)
    );
   
   
endmodule // mpm_top_swwrap