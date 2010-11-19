// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        8
`define c_swc_page_addr_width 10
`define c_swc_usecount_width  4 
`define c_wrsw_prio_width     3
`define c_swc_ctrl_width      4
`define c_swc_data_width      16
`define c_wrsw_num_ports      11


`timescale 1ns / 1ps

`include "fabric_emu.sv"


`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];



module main;



   
   
   reg clk 		       = 0;
   reg rst_n 		     = 0;

   //`WRF_WIRES(a_to_input_block); // Emu A to B fabric
   

   wire [`c_wrsw_num_ports * 16- 1:0] a_to_input_block_data;
   wire [`c_wrsw_num_ports * 4 - 1:0] a_to_input_block_ctrl;

//   wire [`c_wrsw_num_ports - 1:0][15:0]     a_to_input_block_data;
//   wire [`c_wrsw_num_ports - 1:0][3 :0]     a_to_input_block_ctrl;

   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_bytesel;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_dreq;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_valid;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_sof_p1;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_eof_p1;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_rerror_p1;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_abort_p1;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_terror_p1;
   wire [`c_wrsw_num_ports-1:0]       a_to_input_block_tabort_p1;

   wire [`c_wrsw_num_ports * 16- 1:0] input_block_to_a_data;
   wire [`c_wrsw_num_ports * 4 - 1:0] input_block_to_a_ctrl;

//   wire [`c_wrsw_num_ports - 1:0][15:0]     input_block_to_a_data;
//   wire [`c_wrsw_num_ports:0][3 :0]     input_block_to_a_ctrl;


   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_bytesel;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_dreq;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_valid;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_sof_p1;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_eof_p1;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_rerror_p1;
   
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_idle;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_terror_p1;
   wire [`c_wrsw_num_ports-1:0]       input_block_to_a_tabort_p1;
  
   `WRF_WIRES(ab); // Emu A to B fabric
   `WRF_WIRES(ba); // And the other way around
    
   // `WRF_PORTS_SINK_ARRAY(dupa);
    
   reg  [`c_wrsw_num_ports-1:0]                         rtu_rsp_valid        = 0;     
   wire [`c_wrsw_num_ports-1:0]                         rtu_rsp_ack;       
   reg  [`c_wrsw_num_ports * `c_wrsw_num_ports - 1 : 0] rtu_dst_port_mask    = 0; 
   reg  [`c_wrsw_num_ports-1:0]                         rtu_drop             = 0;          
   reg  [`c_wrsw_num_ports * `c_wrsw_prio_width -1 : 0] rtu_prio             = 0;     

   // generate clock and reset signals
   always #(`c_clock_period/2) clk <= ~clk;
   
   initial begin 
      repeat(3) @(posedge clk);
      rst_n  = 1;
   end

   
   swc_core 
    DUT (
    .clk_i                 (clk),
    .rst_n_i               (rst_n),
//-------------------------------------------------------------------------------
//-- Fabric I/F  
//-------------------------------------------------------------------------------  
    .tx_sof_p1_i         (a_to_input_block_sof_p1),
    .tx_eof_p1_i         (a_to_input_block_eof_p1),
    .tx_data_i           (a_to_input_block_data),
    .tx_ctrl_i           (a_to_input_block_ctrl),
    .tx_valid_i          (a_to_input_block_valid),
    .tx_bytesel_i        (a_to_input_block_bytesel),
    .tx_dreq_o           (a_to_input_block_dreq),
    .tx_abort_p1_i       (a_to_input_block_abort_p1),
    .tx_rerror_p1_i      (a_to_input_block_rerror_p1),

//-------------------------------------------------------------------------------
//-- Fabric I/F : output (goes to the Endpoint)
//-------------------------------------------------------------------------------  

    .rx_sof_p1_o         (input_block_to_a_sof_p1),
    .rx_eof_p1_o         (input_block_to_a_eof_p1),
    .rx_dreq_i           (input_block_to_a_dreq),
    .rx_ctrl_o           (input_block_to_a_ctrl),
    .rx_data_o           (input_block_to_a_data),
    .rx_valid_o          (input_block_to_a_valid),
    .rx_bytesel_o        (input_block_to_a_bytesel),
    .rx_idle_o           (input_block_to_a_idle),
    .rx_rerror_p1_o      (input_block_to_a_rerror_p1),
    .rx_terror_p1_i      (input_block_to_a_terror_p1),
    .rx_tabort_p1_i      (input_block_to_a_tabort_p1),// tx_rabort_p1_i ????????

       

//-------------------------------------------------------------------------------
//-- I/F with Routing Table Unit (RTU)
//-------------------------------------------------------------------------------      
    
    .rtu_rsp_valid_i       (rtu_rsp_valid),
    .rtu_rsp_ack_o         (rtu_rsp_ack),
    .rtu_dst_port_mask_i   (rtu_dst_port_mask),
    .rtu_drop_i            (rtu_drop),
    .rtu_prio_i            (rtu_prio)
    );
    
    task wait_cycles;
       input [31:0] ncycles;
       begin : wait_body
    integer i;
 
    for(i=0;i<ncycles;i=i+1) @(posedge clk);
 
       end
    endtask // wait_cycles
    


   fabric_emu test_input_block_0
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE_ML(rx, a_to_input_block,0),

/*
      .rx_data_o      (a_to_input_block_data[15:0]),
      .rx_ctrl_o      (a_to_input_block_ctrl[15:0]),
      .rx_bytesel_o   (a_to_input_block_bytesel[0]),
      .rx_dreq_i      (a_to_input_block_dreq[0]),
      .rx_valid_o     (a_to_input_block_valid[0]),
      .rx_sof_p1_o    (a_to_input_block_sof_p1[0]),
      .rx_eof_p1_o    (a_to_input_block_eof_p1[0]),
      .rx_rerror_p1_o (a_to_input_block_rerror_p1[0]),
      .rx_terror_p1_i (1'b0),
      .rx_tabort_p1_o (),
      .rx_rabort_p1_i (1'b0),
      .rx_idle_o      (),
 */
      `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,0)

/*      
      .tx_data_i      (input_block_to_a_data[15:0]),
      .tx_ctrl_i      (input_block_to_a_ctrl[15:0]),
      .tx_bytesel_i   (input_block_to_a_bytesel[0]),
      .tx_dreq_o      (input_block_to_a_dreq[0]),
      .tx_valid_i     (input_block_to_a_valid[0]),
      .tx_sof_p1_i    (input_block_to_a_sof_p1[0]),
      .tx_eof_p1_i    (input_block_to_a_eof_p1[0]),
      .tx_rerror_p1_i (input_block_to_a_rerror_p1[0]),
      .tx_terror_p1_o (input_block_to_a_terror_p1[0]),
      .tx_rabort_p1_o (input_block_to_a_rabort_p1[0]),
      .tx_idle_i      (input_block_to_a_idle[0])
*/
      );
   fabric_emu test_input_block_1
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,1),
      `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,1)
      );
   fabric_emu test_input_block_2
        (
         .clk_i(clk),
         .rst_n_i(rst_n),
         `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,2),
         `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,2)
         );
   fabric_emu test_input_block_3
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,3),
      `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,3)
      );
   fabric_emu test_input_block_4
        (
         .clk_i(clk),
         .rst_n_i(rst_n),
         `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,4),
         `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,4)
         );  
   fabric_emu test_input_block_5
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,5),
      `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,5)
      );
   fabric_emu test_input_block_6
        (
         .clk_i(clk),
         .rst_n_i(rst_n),
         `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,6),
         `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,6)
         );
   fabric_emu test_input_block_7
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,7),
      `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,7)
      );
   fabric_emu test_input_block_8
        (
         .clk_i(clk),
         .rst_n_i(rst_n),
         `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,8),
         `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,8)
         );   
         
       
   fabric_emu test_input_block_9
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,9),
      `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,9)
      );
   fabric_emu test_input_block_10
        (
         .clk_i(clk),
         .rst_n_i(rst_n),
         `WRF_FULL_CONNECT_SOURCE_ML(rx, a_to_input_block,10),
         `WRF_FULL_CONNECT_SINK_ML(tx, input_block_to_a,10)
         );     
         
         
    task set_rtu_rsp;
       input [31:0]                    chan;
       input                           valid;
       input                           drop;
       input [`c_wrsw_num_ports - 1:0] prio;
       input [`c_wrsw_num_ports - 1:0] mask;
       begin : wait_body
    integer i;
    integer k; // for the macro array_copy()
    `array_copy(rtu_dst_port_mask,(chan+1)*`c_wrsw_num_ports  - 1, chan*`c_wrsw_num_ports,  mask ,0); 
    `array_copy(rtu_prio         ,(chan+1)*`c_wrsw_prio_width - 1, chan*`c_wrsw_prio_width, prio, 0); 
    
//    rtu_dst_port_mask[(chan+1)*`c_wrsw_num_ports  : `c_wrsw_num_ports*chan]  = mask; 
//    rtu_prio         [(chan+1)*`c_wrsw_prio_width : `c_wrsw_prio_width*chan] = prio;
    rtu_drop         [ chan ]                                                = drop;          
    rtu_rsp_valid    [ chan ]                                                = valid;
 
       end
    endtask // wait_cycles         
                   
   initial begin
      ether_header_t hdr;
      int buffer[1024];
      int i;
      
      wait(test_input_block_0.ready);
      wait(test_input_block_3.ready);
      wait(test_input_block_6.ready);
      wait(test_input_block_9.ready);
      
      
      hdr.src 	       = 'h123456789abcdef;
      hdr.dst 	       = 'hcafeb1badeadbef;
      hdr.ethertype    = 1234;
      hdr.is_802_1q    = 0;
      hdr.oob_type     = `OOB_TYPE_RXTS;
      hdr.timestamp_r  = 10000;
      hdr.timestamp_f  = 4;
      hdr.port_id      = 5;
      
      for(i=0;i<1000;i++)
	        buffer[i]      = i;

//    
//    task set_rtu_rsp;
//       input [31:0]                    chan;
//       input                           valid;
//       input                           drop;
//       input [`c_wrsw_num_ports - 1:0] prio;
//       input [`c_wrsw_num_ports - 1:0] mask;
//       begin : wait_body

    
      wait_cycles(50);

//////////////// input port = 0  ////////////////

      set_rtu_rsp(0,1,0,2,'h7FF);  
      test_input_block_0.send(hdr, buffer, 901);
      
//      set_rtu_rsp(0,1,0,2,'h7FF);  
//      test_input_block_0.send(hdr, buffer, 202);

//      set_rtu_rsp(0,1,0,2,'h7FF);  
//      test_input_block_0.send(hdr, buffer, 203);
      
//      set_rtu_rsp(0,1,0,2,'h7FF);  
//      test_input_block_0.send(hdr, buffer, 204);
      
//      set_rtu_rsp(0,1,0,2,'h7FF);  
//      test_input_block_0.send(hdr, buffer, 205);
      
//      set_rtu_rsp(0,1,0,2,'h7FF);  
 //     test_input_block_0.send(hdr, buffer, 206);


//////////////// input port = 3  ////////////////
      set_rtu_rsp(3,1,0,2,'h7FF);  
      test_input_block_3.send(hdr, buffer, 931);

//      set_rtu_rsp(3,1,0,2,'h7FF);  
//      test_input_block_3.send(hdr, buffer, 232);

//      set_rtu_rsp(3,1,0,2,'h7FF);  
//      test_input_block_3.send(hdr, buffer, 233);
      
//      set_rtu_rsp(3,1,0,2,'h7FF);  
//      test_input_block_3.send(hdr, buffer, 234);
      
//      set_rtu_rsp(3,1,0,2,'h7FF);  
//      test_input_block_3.send(hdr, buffer, 235);
      
 //     set_rtu_rsp(3,1,0,2,'h7FF);  
 //     test_input_block_3.send(hdr, buffer, 236);
      
//////////////// input port = 6  ////////////////
      set_rtu_rsp(6,1,0,2,'h7FF);  
      test_input_block_6.send(hdr, buffer, 761);

//      set_rtu_rsp(6,1,0,2,'h7FF);  
//      test_input_block_6.send(hdr, buffer, 262);

//      set_rtu_rsp(6,1,0,2,'h7FF);  
//      test_input_block_6.send(hdr, buffer, 263);
//      
//      set_rtu_rsp(6,1,0,2,'h7FF);  
//      test_input_block_6.send(hdr, buffer, 264);
//      
//      set_rtu_rsp(6,1,0,2,'h7FF);  
//      test_input_block_6.send(hdr, buffer, 265);
      
//      set_rtu_rsp(6,1,0,2,'h7FF);  
 //     test_input_block_6.send(hdr, buffer, 266);
      
      
//////////////// input port = 9  ////////////////
      set_rtu_rsp(9,1,0,2,'h7FF);  
      test_input_block_9.send(hdr, buffer, 991);

//      set_rtu_rsp(9,1,0,2,'h7FF);  
//      test_input_block_9.send(hdr, buffer, 292);
//
//      set_rtu_rsp(9,1,0,2,'h7FF);  
//      test_input_block_9.send(hdr, buffer, 293);
//      
//      set_rtu_rsp(9,1,0,2,'h7FF);  
//      test_input_block_9.send(hdr, buffer, 294);
//      
//      set_rtu_rsp(9,1,0,2,'h7FF);  
//      test_input_block_9.send(hdr, buffer, 295);
      
  //    set_rtu_rsp(9,1,0,2,'h7FF);  
  //    test_input_block_9.send(hdr, buffer, 296);
      
      
   end



//////////////////////////////////////////////////////////
   initial begin
      ether_header_t hdr;
      int buffer[1024];
      int i;
      

      wait(test_input_block_1.ready);
      wait(test_input_block_4.ready);
      wait(test_input_block_7.ready);
      wait(test_input_block_10.ready);
      
      
      hdr.src 	       = 'h123456789abcdef;
      hdr.dst 	       = 'hcafeb1badeadbef;
      hdr.ethertype    = 1234;
      hdr.is_802_1q    = 0;
      hdr.oob_type     = `OOB_TYPE_RXTS;
      hdr.timestamp_r  = 10000;
      hdr.timestamp_f  = 4;
      hdr.port_id      = 5;
      
      for(i=0;i<1000;i++)
	        buffer[i]      = i;

//    
//    task set_rtu_rsp;
//       input [31:0]                    chan;
//       input                           valid;
//       input                           drop;
//       input [`c_wrsw_num_ports - 1:0] prio;
//       input [`c_wrsw_num_ports - 1:0] mask;
//       begin : wait_body

    
      wait_cycles(260);


//////////////// input port = 1  ////////////////

      set_rtu_rsp(1,1,0,2,'h7FF);  
//      test_input_block_1.simulate_tx_throttling(1, 10);

//      test_input_block_0.simulate_rx_abort(1,80);
//     test_input_block_1.simulate_tx_error(1,100);
      test_input_block_1.send(hdr, buffer, 911);

//      set_rtu_rsp(1,1,0,2,'h7FF);  
//      test_input_block_1.send(hdr, buffer, 212);
//
//      set_rtu_rsp(1,1,0,2,'h7FF);  
//      test_input_block_1.send(hdr, buffer, 213);
//      
//      set_rtu_rsp(1,1,0,2,'h7FF);  
//     test_input_block_1.send(hdr, buffer, 214);
//      
//      set_rtu_rsp(1,1,0,2,'h7FF);  
//      test_input_block_1.send(hdr, buffer, 215);
      
//      set_rtu_rsp(1,1,0,2,'h002);  
 //     test_input_block_1.send(hdr, buffer, 216);

//////////////// input port = 4  ////////////////
      set_rtu_rsp(4,1,0,2,'h7FF);  
      test_input_block_4.send(hdr, buffer, 941);

//      set_rtu_rsp(4,1,0,2,'h7FF);  
//      test_input_block_4.send(hdr, buffer, 242);
//
//      set_rtu_rsp(4,1,0,2,'h7FF);  
//      test_input_block_4.send(hdr, buffer, 243);
//      
//      set_rtu_rsp(4,1,0,2,'h7FF);  
//      test_input_block_4.send(hdr, buffer, 244);
//      
//      set_rtu_rsp(4,1,0,2,'h7FF);  
//      test_input_block_4.send(hdr, buffer, 245);
      
 //     set_rtu_rsp(4,1,0,2,'h008);  
 //     test_input_block_4.send(hdr, buffer, 246);
      
      
//////////////// input port = 7  ////////////////
      set_rtu_rsp(7,1,0,2,'h7FF);  
      test_input_block_7.send(hdr, buffer, 971);

//      set_rtu_rsp(7,1,0,2,'h7FF);  
//      test_input_block_7.send(hdr, buffer, 272);
//
//      set_rtu_rsp(7,1,0,2,'h7FF);  
//      test_input_block_7.send(hdr, buffer, 273);
//      
//      set_rtu_rsp(7,1,0,2,'h7FF);  
//      test_input_block_7.send(hdr, buffer, 274);
//      
//      set_rtu_rsp(7,1,0,2,'h7FF);  
//      test_input_block_7.send(hdr, buffer, 275);
      
 //     set_rtu_rsp(7,1,0,2,'h7FF);  
 //     test_input_block_7.send(hdr, buffer, 276);
      
//////////////// input port = 10  ////////////////
      set_rtu_rsp(10,1,0,2,'h7FF);  
      test_input_block_10.send(hdr, buffer, 901);

//      set_rtu_rsp(10,1,0,2,'h7FF);  
//      test_input_block_10.send(hdr, buffer, 202);
//
//      set_rtu_rsp(10,1,0,2,'h7FF);  
//      test_input_block_10.send(hdr, buffer, 203);
//      
//      set_rtu_rsp(10,1,0,2,'h7FF);  
//      test_input_block_10.send(hdr, buffer, 204);
//      
//      set_rtu_rsp(10,1,0,2,'h7FF);  
//      test_input_block_10.send(hdr, buffer, 205);
      
 //    set_rtu_rsp(10,1,0,2,'h7FF);  
 //    test_input_block_10.send(hdr, buffer, 206);
                                                      

      
   end


//////////////////////////////////////////////////////////////


initial begin
    ether_header_t hdr;
    int buffer[1024];
    int i;
    
    wait(test_input_block_2.ready);
    wait(test_input_block_5.ready);
    wait(test_input_block_8.ready);

   
    
    
    
    hdr.src 	       = 'h123456789abcdef;
    hdr.dst 	       = 'hcafeb1badeadbef;
    hdr.ethertype    = 1234;
    hdr.is_802_1q    = 0;
    hdr.oob_type     = `OOB_TYPE_RXTS;
    hdr.timestamp_r  = 10000;
    hdr.timestamp_f  = 4;
    hdr.port_id      = 5;
    
    for(i=0;i<1000;i++)
        buffer[i]      = i;

//    
//  task set_rtu_rsp;
//     input [31:0]                    chan;
//     input                           valid;
//     input                           drop;
//     input [`c_wrsw_num_ports - 1:0] prio;
//     input [`c_wrsw_num_ports - 1:0] mask;
//     begin : wait_body

  
    wait_cycles(80);

//////////////// input port = 2  ////////////////
    set_rtu_rsp(2,1,0,2,'h7FF);  
    test_input_block_2.send(hdr, buffer, 921);

//    set_rtu_rsp(2,1,0,2,'h7FF);  
//    test_input_block_2.send(hdr, buffer, 222);
//
//    set_rtu_rsp(2,1,0,2,'h7FF);  
//    test_input_block_2.send(hdr, buffer, 223);
//    
//    set_rtu_rsp(2,1,0,2,'h7FF);  
//    test_input_block_2.send(hdr, buffer, 224);
//    
//    set_rtu_rsp(2,1,0,2,'h7FF);  
//    test_input_block_2.send(hdr, buffer, 225);
    
//    set_rtu_rsp(2,1,0,2,'h7FF);  
//    test_input_block_2.send(hdr, buffer, 226);
//////////////// input port = 5  ////////////////
    set_rtu_rsp(5,1,0,2,'h7FF);  
    test_input_block_5.send(hdr, buffer, 951);

//    set_rtu_rsp(5,1,0,2,'h7FF);  
//    test_input_block_5.send(hdr, buffer, 252);
//
//    set_rtu_rsp(5,1,0,2,'h7FF);  
//    test_input_block_5.send(hdr, buffer, 253);
//    
//    set_rtu_rsp(5,1,0,2,'h7FF);  
//    test_input_block_5.send(hdr, buffer, 254);
//    
//    set_rtu_rsp(5,1,0,2,'h7FF);  
//    test_input_block_5.send(hdr, buffer, 255);
    
//    set_rtu_rsp(5,1,0,2,'h7FF);  
//    test_input_block_5.send(hdr, buffer, 256);
  
//////////////// input port = 8  ////////////////
    set_rtu_rsp(8,1,0,2,'h7FF);  
    test_input_block_8.send(hdr, buffer, 981);

//    set_rtu_rsp(8,1,0,2,'h7FF);  
//    test_input_block_8.send(hdr, buffer, 282);
//
//    set_rtu_rsp(8,1,0,2,'h7FF);  
//    test_input_block_8.send(hdr, buffer, 283);
//    
//    set_rtu_rsp(8,1,0,2,'h7FF);  
//    test_input_block_8.send(hdr, buffer, 284);
//    
//    set_rtu_rsp(8,1,0,2,'h7FF);  
//    test_input_block_8.send(hdr, buffer, 285);
    
 //   set_rtu_rsp(8,1,0,2,'h7FF);  
//    test_input_block_8.send(hdr, buffer, 286);
    
    
 end

//////////////////////////////////////////////////////////


   always @(posedge clk) if (rtu_rsp_ack != 0)
     begin
       
       rtu_rsp_valid = rtu_rsp_valid & !rtu_rsp_ack;
       rtu_drop      = rtu_drop      & !rtu_rsp_ack;
       
     end
   
   
   // Check if there's anything received by EMU B
   always @(posedge clk) if (test_input_block_0.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 0!");
 
	   test_input_block_0.receive(frame);
	   dump_frame_header("test RX_0: ", frame);
	   end
	   
   always @(posedge clk) if (test_input_block_1.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 1!");
 
	   test_input_block_1.receive(frame);
	   dump_frame_header("test RX_1: ", frame);
	   end      
   always @(posedge clk) if (test_input_block_2.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 2!");
 
	   test_input_block_2.receive(frame);
	   dump_frame_header("test RX_2: ", frame);
	   end
	   
   always @(posedge clk) if (test_input_block_3.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 3!");
 
	   test_input_block_3.receive(frame);
	   dump_frame_header("test RX_3: ", frame);
	   end      
   always @(posedge clk) if (test_input_block_4.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 4!");
 
	   test_input_block_4.receive(frame);
	   dump_frame_header("test RX_4: ", frame);
	   end
	   
   always @(posedge clk) if (test_input_block_5.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 5!");
 
	   test_input_block_5.receive(frame);
	   dump_frame_header("test RX_5: ", frame);
	   end      
   always @(posedge clk) if (test_input_block_6.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 6!");
 
	   test_input_block_6.receive(frame);
	   dump_frame_header("test RX_6: ", frame);
	   end
	   
   always @(posedge clk) if (test_input_block_7.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 7!");
 
	   test_input_block_7.receive(frame);
	   dump_frame_header("test RX_7: ", frame);
	   end  
      
     always @(posedge clk) if (test_input_block_8.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 8!");
 
	   test_input_block_8.receive(frame);
	  
	   dump_frame_header("test RX_8: ", frame);
	   end
   
   always @(posedge clk) if (test_input_block_9.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 9!");
 
	   test_input_block_9.receive(frame);
	   dump_frame_header("test RX_9: ", frame);
	   end      
   always @(posedge clk) if (test_input_block_10.poll())
     begin
    	ether_frame_t frame;
//	   $display("Emulator test received a frame on port 10!");
 
	   test_input_block_10.receive(frame);
	   dump_frame_header("test RX_10: ", frame);
	   end      


endmodule // main
