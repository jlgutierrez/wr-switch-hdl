// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        8
`define c_swc_page_addr_width 10
`define c_swc_usecount_width  4 
`define c_wrsw_prio_width     3
`define c_swc_ctrl_width      16
`define c_swc_data_width      4
`define c_wrsw_num_ports      11


`timescale 1ns / 1ps

`include "fabric_emu.sv"






module main;



   
   
   reg clk 		       = 0;
   reg rst_n 		     = 0;

   //`WRF_WIRES(a_to_input_block); // Emu A to B fabric
   

   wire [15:0] a_to_input_block_data;
   wire [3 :0] a_to_input_block_ctrl;
   wire        a_to_input_block_bytesel;
   wire        a_to_input_block_dreq;
   wire        a_to_input_block_valid;
   wire        a_to_input_block_sof_p1;
   wire        a_to_input_block_eof_p1;
   wire        a_to_input_block_rerror_p1;

   wire [15:0] input_block_to_a_data;
   wire [3 :0] input_block_to_a_ctrl;
   wire        input_block_to_a_bytesel;
   wire        input_block_to_a_dreq;
   wire        input_block_to_a_valid;
   wire        input_block_to_a_sof_p1;
   wire        input_block_to_a_eof_p1;
   wire        input_block_to_a_rerror_p1;
  
   `WRF_WIRES(ab); // Emu A to B fabric
   `WRF_WIRES(ba); // And the other way around
  
   reg                                   rtu_rsp_valid        = 0;     
   wire                                  rtu_rsp_ack;       
   reg  [`c_wrsw_num_ports - 1 : 0]      rtu_dst_port_mask    = 0; 
   reg                                   rtu_drop             = 0;          
   reg  [`c_wrsw_prio_width - 1 : 0]     rtu_prio             = 0;     

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
    `_WRF_CONNECT_MANDATORY_SINK      (tx, a_to_input_block),
    `_WRF_CONNECT_MANDATORY_SOURCE    (rx, input_block_to_a),

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
    


   fabric_emu test_input_block
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, a_to_input_block),
      `WRF_CONNECT_SINK(tx, input_block_to_a)
      );

   // Two fabric emulators talking to each other
   fabric_emu U_emuA
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, ba), // connect fabric source/sinks
      `WRF_CONNECT_SINK(tx, ab)
      );

   fabric_emu U_emuB
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, ab),
      `WRF_CONNECT_SINK(tx, ba)
      );

   
   initial begin
      ether_header_t hdr;
      int buffer[1024];
      int i;


//      wait(U_emuA.ready); // wait until both emulators are initialized
///      wait(U_emuB.ready);
      wait(test_input_block.ready);
      
      
      hdr.src 	       = 'h123456789abcdef;
      hdr.dst 	       = 'hcafeb1badeadbef;
      hdr.ethertype    = 1234;
      hdr.is_802_1q    = 0;
      hdr.oob_type     = `OOB_TYPE_RXTS;
      hdr.timestamp_r  = 10000;
      hdr.timestamp_f  = 4;
      hdr.port_id      = 5;
      


      rtu_dst_port_mask    = 1; 
      rtu_drop             = 0;          
      rtu_prio             = 2;
      
      
      for(i=0;i<1000;i++)
	        buffer[i]      = i;


      // simulate some flow throttling
      //U_emuA.simulate_rx_throttling(1, 50);
//      test_input_block.simulate_rx_throttling(1, 0);
//      test_input_block.simulate_rx_error(1,10);
//      test_input_block.simulate_tx_error(1,100);

      //U_emuA.send(hdr, buffer, 100);
    
      wait_cycles(20);
      rtu_rsp_valid        = 1;
      rtu_prio             = 1;     
      test_input_block.send(hdr, buffer, 200);
      rtu_prio             = 2;
      test_input_block.send(hdr, buffer, 201);
      rtu_prio             = 2;
      test_input_block.send(hdr, buffer, 202);
      rtu_prio             = 1;
      test_input_block.send(hdr, buffer, 203);
      rtu_prio             = 4;
      test_input_block.send(hdr, buffer, 204);
      rtu_prio             = 6;
      test_input_block.send(hdr, buffer, 205);
      rtu_prio             = 7;
      test_input_block.send(hdr, buffer, 206);
      rtu_prio             = 3;
      test_input_block.send(hdr, buffer, 207);
      rtu_prio             = 1;
      test_input_block.send(hdr, buffer, 208);
      rtu_prio             = 7;
      test_input_block.send(hdr, buffer, 495);
      rtu_drop             = 1;
      test_input_block.send(hdr, buffer, 595);
      rtu_drop             = 0;
      rtu_prio             = 4;      
      test_input_block.send(hdr, buffer, 95);
      rtu_rsp_valid        = 0;     
      test_input_block.send(hdr, buffer, 100);
      //hdr.src  = 'h0f0e0a0b0d00;
      
      //U_emuB.send(hdr, buffer, 50);

      
   end

   // Check if there's anything received by EMU B
   always @(posedge clk) if (test_input_block.poll())
     begin
    	ether_frame_t frame;
	   $display("Emulator test received a frame!");
 
	   test_input_block.receive(frame);
	   dump_frame_header("test RX: ", frame);
	   end



   // Check if there's anything received by EMU B
   always @(posedge clk) if (U_emuB.poll())
     begin
    	ether_frame_t frame;
	   $display("Emulator B received a frame!");
 
	   U_emuB.receive(frame);
	   dump_frame_header("EmuB RX: ", frame);
	   end

   // Check if there's anything received by EMU A
   always @(posedge clk) if (U_emuA.poll())
     begin
	   ether_frame_t frame;
	   $display("Emulator A received a frame!");

    	U_emuA.receive(frame);
    	dump_frame_header("EmuA RX: ", frame);
	
     end
   
      
   


endmodule // main
