// Fabric TAP emulator example.

// usage: (as root)
// tunctl -t tap0
// ifconfig tap0 192.168.100.100
// arping -I tap0 192.168.100.101
// you should see some ARP requests coming

`timescale 1ns / 1ps

`include "fabric_emu.sv"
`include "fabric_emu_tap.sv"

module main;

   const int c_clock_period  = 8;
   
   reg clk 		     = 0;
   reg rst_n 		     = 0;

   `WRF_WIRES(from_tap); // Data coming from tap0 interface
   `WRF_WIRES(to_tap); // Data going to tap0 interface
   
   // generate clock and reset signals
   always #(c_clock_period/2) clk <= ~clk;
   
   initial begin 
      repeat(3) @(posedge clk);
      rst_n  = 1;
   end


   // Two fabric emulators talking to each other
   fabric_emu_tap U_tap
     (
      .clk_sys_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, from_tap), // connect fabric source/sinks
      `WRF_CONNECT_SINK(tx, to_tap)
      );

   fabric_emu U_emu
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, to_tap),
      `WRF_CONNECT_SINK(tx, from_tap)
      );

   

   // Check if there's anything received by the TAP emulator
   always @(posedge clk) if (U_emu.poll())
     begin
	ether_frame_t frame;
	$display("TAP Emulator received a frame!");

	U_emu.receive(frame);
	dump_frame_header("EmuB RX: ", frame);

	frame.hdr.src  = 'h010203040506; // modify the MAC address and send the frame back to tap interface
	U_emu.send(frame.hdr, frame.payload, frame.size);
     end

      
   


endmodule // main
