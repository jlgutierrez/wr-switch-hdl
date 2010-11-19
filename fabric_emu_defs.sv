`ifndef __FABRIC_EMU_DEFS_SV
`define __FABRIC_EMU_DEFS_SV

/* Ethernet frame header extended with WR-compliant OOB signalling */
typedef struct {
   bit no_mac; // when 1, there's no valid source MAC present in the frame header and the SRC MAC field must be filled by the endpoint
   bit [47:0] dst; // DST MAC
   bit [47:0] src; // SRC MAC
   bit [15:0] ethertype;
   bit is_802_1q;  // when 1, the frame has 802.1q header
   bit [11:0] vid; // VLAN ID
   bit [2:0] prio; // PCP priority tag
   int oob_type;   // OOB TYPE: OOB_TYPE_TXTS = TX frame ID (for TX timestamping), OOB_TYPE_RXTS = RX timestamp
   bit[15:0] oob_fid;  // 
   bit [27:0] timestamp_r;
   bit [3:0] timestamp_f;
   bit [4:0] port_id;
   bit has_timestamp; // when 1, the TX/RX timestamp is valid
} ether_header_t;

/* Full ethernet frame */
typedef struct {
   ether_header_t hdr;
   int size;
   int payload[2048];
   bit[31:0] fcs;
   bit error;
   bit has_payload;
} ether_frame_t;

/* WR-compliant TX frame timestamp */
typedef struct {
   bit[15:0] fid;
   bit [4:0] pid;
   bit [27:0] timestamp_r;
   bit [3:0] timestamp_f;
} tx_timestamp_t;



`timescale 1ns/1ps


/* Bus widths definition, taken from global_defs.vhd */

`define c_wrsw_ctrl_size 4
`define c_wrsw_oob_frame_id_size 16
`define c_wrsw_timestamp_size_r 28
`define c_wrsw_timestamp_size_f 4
`define c_wrsw_mac_addr_width 48
`define c_wrsw_vid_width 12
`define c_wrsw_prio_width 3
`define c_wrsw_num_ports 11

/* ctrl bus codes */

`define c_wrsw_ctrl_none       4'h0
`define c_wrsw_ctrl_dst_mac    4'h1
`define c_wrsw_ctrl_src_mac    4'h2
`define c_wrsw_ctrl_ethertype  4'h3
`define c_wrsw_ctrl_vid_prio   4'h4
`define c_wrsw_ctrl_tx_oob     4'h5
`define c_wrsw_ctrl_rx_oob     4'h6
`define c_wrsw_ctrl_payload    4'h7


/* OOB types */
`define OOB_TYPE_TXTS 1
`define OOB_TYPE_RXTS 2

`define QUEUE_MAX_FRAMES 128

//
// WhiteRabbit Fabric Interface (WRF) Macros
//

// declares basic fabric interface (only the mandatory singals)
// sink port list in a verilog/SV module, prefixed with "prefix":
// for example `WRF_PORTS_SINK(test) will generate the following signals
// test_sof_p1_i, test_eof_p1_i, test_data_i, etc....
`define WRF_PORTS_SINK(prefix) \
input [15:0] prefix``_data_i,\
input [3:0] prefix``_ctrl_i,\
input prefix``_bytesel_i,\
input prefix``_sof_p1_i,\
input prefix``_eof_p1_i,\
output prefix``_dreq_o,\
input prefix``_valid_i,\
input prefix``_rerror_p1_i


// array version
/*
`define WRF_PORTS_SINK_ARRAY(prefix) \
input [11*15-1:0] prefix``_data_i,\
input [11* 3-1:0]  prefix``_ctrl_i,\
input [10:0]       prefix``_bytesel_i,\
input [10:0]       prefix``_sof_p1_i,\
input [10:0]       prefix``_eof_p1_i[size - 1 : 0],\
output[10:0]       prefix``_dreq_o,\
input [10:0]       prefix``_valid_i,\
input [10:0]       prefix``_rerror_p1_i
*/
// same as above but with all WRF signals
`define WRF_FULL_PORTS_SINK(prefix) \
`WRF_PORTS_SINK(prefix),\
output prefix``_terror_p1_o,\
input prefix``_idle_i,\
input prefix``_tabort_p1_i,\
output prefix``_rabort_p1_o

  
// like the macro above, but for fabric source, mandatory signals only
`define WRF_PORTS_SOURCE(prefix) \
output [15:0] prefix``_data_o,\
output [3:0] prefix``_ctrl_o,\
output prefix``_bytesel_o,\
output prefix``_sof_p1_o,\
output prefix``_eof_p1_o,\
input prefix``_dreq_i,\
output prefix``_valid_o,\
output prefix``_rerror_p1_o

// same as above, but for full WRF
`define WRF_FULL_PORTS_SOURCE(prefix) \
`WRF_PORTS_SOURCE(prefix), \
input prefix``_terror_p1_i,\
output prefix``_idle_o,\
output prefix``_tabort_p1_o,\
input prefix``_rabort_p1_i
  
  
// declares a list of verilog/SV wires for a given fabric name
`define WRF_WIRES(prefix) \
wire [15:0] prefix``_data;\
wire [3 :0] prefix``_ctrl;\
wire prefix``_bytesel;\
wire prefix``_dreq;\
wire prefix``_valid;\
wire prefix``_sof_p1;\
wire prefix``_eof_p1;\
wire prefix``_rerror_p1;

// same as above, but for full WRF
`define WRF_FULL_WIRES(prefix) \
`WRF_SIGNALS(prefix)\
wire prefix``_terror_p1;\
wire prefix``_idle;\
wire prefix``_tabort_p1;\
wire prefix``_rabort_p1;





// Connects fabric sink ports prefixed with port_pfx to fabric wires prefixed with fab_pfx
`define _WRF_CONNECT_MANDATORY_SINK(port_pfx, fab_pfx) \
.port_pfx``_data_i(fab_pfx``_data),\
.port_pfx``_ctrl_i(fab_pfx``_ctrl),\
.port_pfx``_bytesel_i(fab_pfx``_bytesel),\
.port_pfx``_dreq_o(fab_pfx``_dreq),\
.port_pfx``_valid_i(fab_pfx``_valid),\
.port_pfx``_sof_p1_i(fab_pfx``_sof_p1),\
.port_pfx``_eof_p1_i(fab_pfx``_eof_p1),\
.port_pfx``_rerror_p1_i(fab_pfx``_rerror_p1)

      `define _WRF_CONNECT_MANDATORY_SINK_ML(port_pfx, fab_pfx, port) \
      .port_pfx``_data_i(fab_pfx``_data[(port + 1)*16 - 1 : port*16]),\
      .port_pfx``_ctrl_i(fab_pfx``_ctrl[(port + 1)*4  - 1 : port*4 ]),\
      .port_pfx``_bytesel_i(fab_pfx``_bytesel[port]),\
      .port_pfx``_dreq_o(fab_pfx``_dreq[port]),\
      .port_pfx``_valid_i(fab_pfx``_valid[port]),\
      .port_pfx``_sof_p1_i(fab_pfx``_sof_p1[port]),\
      .port_pfx``_eof_p1_i(fab_pfx``_eof_p1[port]),\
      .port_pfx``_rerror_p1_i(fab_pfx``_rerror_p1[port])

// full fabric I/F version
`define WRF_FULL_CONNECT_SINK(port_pfx, fab_pfx) \
`_WRF_CONNECT_MANDATORY_SINK(port_pfx, fab_pfx), \
.port_pfx``_terror_p1_o(fab_pfx``_terror_p1),\
.port_pfx``_tabort_p1_i(fab_pfx``_tabort_p1),\
.port_pfx``_rabort_p1_o(fab_pfx``_rabort_p1),\
.port_pfx``_idle_i(fab_pfx``_idle)

      `define WRF_FULL_CONNECT_SINK_ML(port_pfx, fab_pfx, port) \
      `_WRF_CONNECT_MANDATORY_SINK_ML(port_pfx, fab_pfx, port), \
      .port_pfx``_terror_p1_o(fab_pfx``_terror_p1[port]),\
//      .port_pfx``_tabort_p1_i(fab_pfx``_tabort_p1[port]),\
      .port_pfx``_rabort_p1_o(fab_pfx``_tabort_p1[port]),\
      .port_pfx``_idle_i(fab_pfx``_idle[port])

// Connects fabric sink ports prefixed with port_pfx to fabric wires prefixed with fab_pfx
`define WRF_CONNECT_SINK(port_pfx, fab_pfx) \
`_WRF_CONNECT_MANDATORY_SINK(port_pfx, fab_pfx), \
.port_pfx``_terror_p1_o(),\
.port_pfx``_tabort_p1_i(1'b0),\
.port_pfx``_rabort_p1_o(),\
.port_pfx``_idle_i(1'b0)

      `define WRF_CONNECT_SINK_ML(port_pfx, fab_pfx, port) \
      `_WRF_CONNECT_MANDATORY_SINK_ML(port_pfx, fab_pfx, port), \
      .port_pfx``_terror_p1_o(),\
      .port_pfx``_tabort_p1_i(1'b0),\
      .port_pfx``_rabort_p1_o(),\
      .port_pfx``_idle_i(1'b0)

  
`define _WRF_CONNECT_MANDATORY_SOURCE(port_pfx, fab_pfx) \
.port_pfx``_data_o(fab_pfx``_data),\
.port_pfx``_ctrl_o(fab_pfx``_ctrl),\
.port_pfx``_bytesel_o(fab_pfx``_bytesel),\
.port_pfx``_dreq_i(fab_pfx``_dreq),\
.port_pfx``_valid_o(fab_pfx``_valid),\
.port_pfx``_sof_p1_o(fab_pfx``_sof_p1),\
.port_pfx``_eof_p1_o(fab_pfx``_eof_p1),\
.port_pfx``_rerror_p1_o(fab_pfx``_rerror_p1)

      `define _WRF_CONNECT_MANDATORY_SOURCE_ML(port_pfx, fab_pfx, port) \
      .port_pfx``_data_o(fab_pfx``_data[(port + 1)*16 - 1: port*16]),\
      .port_pfx``_ctrl_o(fab_pfx``_ctrl[(port + 1)*4  - 1: port*4]),\
      .port_pfx``_bytesel_o(fab_pfx``_bytesel[port]),\
      .port_pfx``_dreq_i(fab_pfx``_dreq[port]),\
      .port_pfx``_valid_o(fab_pfx``_valid[port]),\
      .port_pfx``_sof_p1_o(fab_pfx``_sof_p1[port]),\
      .port_pfx``_eof_p1_o(fab_pfx``_eof_p1[port]),\
      .port_pfx``_rerror_p1_o(fab_pfx``_rerror_p1[port])

  // same as above, but for source ports, full WRF version
`define WRF_FULL_CONNECT_SOURCE(port_pfx, fab_pfx) \
`_WRF_CONNECT_MANDATORY_SOURCE(port_pfx, fab_pfx),\
.port_pfx``_terror_p1_i(fab_pfx``_terror_p1),\
.port_pfx``_tabort_p1_o(fab_pfx``_tabort_p1),\
.port_pfx``_rabort_p1_i(fab_pfx``_rabort_p1),\
.port_pfx``_idle_o(fab_pfx``_idle)


       `define WRF_FULL_CONNECT_SOURCE_ML(port_pfx, fab_pfx, port) \
       `_WRF_CONNECT_MANDATORY_SOURCE_ML(port_pfx, fab_pfx, port),\
       .port_pfx``_terror_p1_i(fab_pfx``_terror_p1[port]),\
       .port_pfx``_tabort_p1_o(fab_pfx``_tabort_p1[port])
//       .port_pfx``_rabort_p1_i(fab_pfx``_rabort_p1[port])
//       .port_pfx``_idle_o(fab_pfx``_idle[port])

  // same as above, but for source ports, basic WRF version
`define WRF_CONNECT_SOURCE(port_pfx, fab_pfx) \
`_WRF_CONNECT_MANDATORY_SOURCE(port_pfx, fab_pfx),\
.port_pfx``_terror_p1_i(1'b0),\
.port_pfx``_tabort_p1_o(),\
.port_pfx``_rabort_p1_i(1'b0),\
.port_pfx``_idle_o()
  
      // same as above, but for source ports, basic WRF version
      `define WRF_CONNECT_SOURCE_ML(port_pfx, fab_pfx, port) \
      `_WRF_CONNECT_MANDATORY_SOURCE_ML(port_pfx, fab_pfx, port),\
      .port_pfx``_terror_p1_i(1'b0),\
      .port_pfx``_tabort_p1_o(),\
      .port_pfx``_rabort_p1_i(1'b0),\
      .port_pfx``_idle_o()
  
  
`endif