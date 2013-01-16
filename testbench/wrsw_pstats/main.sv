`include "pstats_gen.sv"
`include "if_wb_master.svh"

`define TRIG_WIDTH 16
`define NPORTS 2

module main;

  reg clk_sys = 1'b0;
  reg rst_n = 1'b0;

  wire [`NPORTS * `TRIG_WIDTH-1:0]trigs;

  always #5ns clk_sys <= ~clk_sys;
  initial begin
    repeat(3) @(posedge clk_sys);
    rst_n <= 1'b1;
  end

  pstats_gen 
  #(
    .g_trig_width(`NPORTS * `TRIG_WIDTH))
  TRIG_GEN
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .trig_o(trigs)
  );

  wrsw_pstats
  #(
    .g_nports(`NPORTS),
    .g_cnt_pp(`TRIG_WIDTH),
    .g_cnt_pw(4))
  DUT
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .events_i(trigs),

    .wb_adr_i(WB.master.adr[0]),
    .wb_dat_i(WB.master.dat_o),
    .wb_dat_o(WB.master.dat_i),
    .wb_cyc_i(WB.master.cyc),
    .wb_sel_i(4'b1111),
    .wb_stb_i(WB.master.stb),
    .wb_we_i(WB.master.we),
    .wb_ack_o(WB.master.ack),
    .wb_stall_o(WB.master.stall)
  );

  dummy_rmon
  #(
    .g_nports(1),
    .g_cnt_pp(`NPORTS * `TRIG_WIDTH))
  DUMMY
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .events_i(trigs)
  );

  IWishboneMaster WB (
    .clk_i(clk_sys),
    .rst_n_i(rst_n));

    initial begin
      CWishboneAccessor acc;
      uint64_t dat;
      integer rnd;

      acc = WB.get_accessor();
      acc.set_mode(PIPELINED);
      #2us;

      while(1)
      begin
        rnd = $urandom()%10;
        if(rnd < 5) acc.write('h0, 'h1);
        #50ns;
      end 

      //#500ns
      //acc.read('h4, dat);
      
    end 
   
endmodule // main



