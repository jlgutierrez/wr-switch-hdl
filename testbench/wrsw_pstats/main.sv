`include "pstats_gen.sv"

`define TRIG_WIDTH 64

module main;

  reg clk_sys = 1'b0;
  reg rst_n = 1'b0;

  wire [`TRIG_WIDTH-1:0]trigs;

  always #5ns clk_sys <= ~clk_sys;
  initial begin
    repeat(3) @(posedge clk_sys);
    rst_n <= 1'b1;
  end

  pstats_gen 
  #(
    .g_trig_width(`TRIG_WIDTH))
  TRIG_GEN
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .trig_o(trigs)
  );

  port_cntr
  #(
    .g_cnt_pp(`TRIG_WIDTH),
    .g_cnt_pw(4))
  DUT
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .events_i(trigs)
  );

  dummy_rmon
  #(
    .g_nports(1),
    .g_cnt_pp(`TRIG_WIDTH))
  DUMMY
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .events_i(trigs)
  );

   
endmodule // main



