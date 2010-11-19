// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`timescale 1ns / 1ps

`include "fabric_emu.sv"


module main;

   const int c_clock_period  = 8;
   
   reg clk 		     = 0;
   reg rst_n 		     = 0;

   `WRF_WIRES(ab); // Emu A to B fabric
   `WRF_WIRES(ba); // And the other way around
   
   // generate clock and reset signals
   always #(c_clock_period/2) clk <= ~clk;
   
   initial begin 
      repeat(3) @(posedge clk);
      rst_n  = 1;
   end


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


      wait(U_emuA.ready); // wait until both emulators are initialized
      wait(U_emuB.ready);
      
      
      hdr.src 	       = 'h123456789abcdef;
      hdr.dst 	       = 'hcafeb1badeadbef;
      hdr.ethertype    = 1234;
      hdr.is_802_1q    = 0;
      hdr.oob_type     = `OOB_TYPE_RXTS;
      hdr.timestamp_r  = 10000;
      hdr.timestamp_f  = 4;
      hdr.port_id      = 5;
      
      
      for(i=0;i<100;i++)
	buffer[i]      = i;


      // simulate some flow throttling
      U_emuA.simulate_rx_throttling(1, 50);
      
      
      U_emuA.send(hdr, buffer, 100);

      hdr.src  = 'h0f0e0a0b0d00;
      
      U_emuB.send(hdr, buffer, 50);

      
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
