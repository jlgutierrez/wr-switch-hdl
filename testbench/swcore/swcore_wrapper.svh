`define PORT_NUMBER 7
`define PORT_PRIO_W 3



`define WIRE_WB_SINK(iface, nr, prefix) \
.prefix``_adr_``nr``_i(iface.adr), \
.prefix``_dat_``nr``_i(iface.dat_o), \
.prefix``_stb_``nr``_i(iface.stb), \
.prefix``_sel_``nr``_i(iface.sel), \
.prefix``_cyc_``nr``_i(iface.cyc), \
.prefix``_ack_``nr``_o(iface.ack), \
.prefix``_err_``nr``_o(iface.err), \
.prefix``_stall_``nr``_o(iface.stall)
  

`define WIRE_WB_SOURCE(iface, nr, prefix) \
.prefix``_adr_``nr``_o(iface.adr), \
.prefix``_dat_``nr``_o(iface.dat_i), \
.prefix``_stb_``nr``_o(iface.stb), \
.prefix``_sel_``nr``_o(iface.sel), \
.prefix``_cyc_``nr``_o(iface.cyc), \
.prefix``_ack_``nr``_i(iface.ack), \
.prefix``_err_``nr``_i(iface.err), \
.prefix``_stall_``nr``_i(iface.stall)


module swcore_wrapper
  (
   input clk_i,
   input rst_n_i,

   IWishboneMaster.master src_0,
   IWishboneMaster.master src_1,
   IWishboneMaster.master src_2,
   IWishboneMaster.master src_3,
   IWishboneMaster.master src_4,
   IWishboneMaster.master src_5,
   IWishboneMaster.master src_6,

   IWishboneSlave.slave   snk_0,
   IWishboneSlave.slave   snk_1,
   IWishboneSlave.slave   snk_2,
   IWishboneSlave.slave   snk_3,
   IWishboneSlave.slave   snk_4,
   IWishboneSlave.slave   snk_5,
   IWishboneSlave.slave   snk_6,
   
   
   input  [`PORT_NUMBER-1 :0]              rtu_rsp_valid_i,
   output [`PORT_NUMBER-1 :0]              rtu_rsp_ack_o,
   input  [`PORT_NUMBER*`PORT_NUMBER-1 :0] rtu_dst_port_mask_i,
   input  [`PORT_NUMBER-1 :0]              rtu_drop_i,
   input  [`PORT_NUMBER*`PORT_PRIO_W-1 :0] rtu_prio_i

   );

   
   xswc_core_7_ports_wrapper
     #(
       .g_swc_num_ports (`PORT_NUMBER),
       .g_swc_prio_width(`PORT_PRIO_W)
       ) DUT (
              .clk_i (clk_i),
              .rst_n_i (rst_n_i),


	      `WIRE_WB_SINK(src_0, 0, snk),
	      `WIRE_WB_SINK(src_1, 1, snk),
	      `WIRE_WB_SINK(src_2, 2, snk),
	      `WIRE_WB_SINK(src_3, 3, snk),
	      `WIRE_WB_SINK(src_4, 4, snk),
	      `WIRE_WB_SINK(src_5, 5, snk),
	      `WIRE_WB_SINK(src_6, 6, snk),
	     
	      `WIRE_WB_SOURCE(snk_0, 0, src),
	      `WIRE_WB_SOURCE(snk_1, 1, src),
	      `WIRE_WB_SOURCE(snk_2, 2, src),
	      `WIRE_WB_SOURCE(snk_3, 3, src),
	      `WIRE_WB_SOURCE(snk_4, 4, src),
	      `WIRE_WB_SOURCE(snk_5, 5, src),
	      `WIRE_WB_SOURCE(snk_6, 6, src),

	      .rtu_rsp_valid_i     (rtu_rsp_valid_i),
	      .rtu_rsp_ack_o       (rtu_rsp_ack_o),
	      .rtu_dst_port_mask_i (rtu_dst_port_mask_i),
	      .rtu_drop_i          (rtu_drop_i),
	      .rtu_prio_i          (rtu_prio_i)

    );

endmodule // endpoint_phy_wrapper
