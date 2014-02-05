`include "pstats_gen.sv"
`include "if_wb_master.svh"

`define TRIG_WIDTH 17
`define NPORTS 8

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

  //assign trigs[7:4] = 'h0;

  wrsw_pstats
  #(
    .g_nports(`NPORTS),
    .g_cnt_pp(`TRIG_WIDTH),
    .g_cnt_pw(4),
    .g_keep_ov(1))
  DUT
  (
    .rst_n_i(rst_n),
    .clk_i(clk_sys),
    .events_i(trigs),

    .wb_adr_i(WB.master.adr[3:0]),
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

      //while(1)
      //begin
      //  rnd = $urandom()%10;
        //if(rnd < 5) acc.write('h0, 'h1);
      //  #50ns;
        //acc.read('h8, dat);
        //if(dat[7:0]=='h1f)
        //begin
        #1us;
        //enable interrupts
        acc.write('h24, 'hffffffff);
        #21000us;
          //read irq state
          acc.read('h2c, dat);

          acc.write('h0, 'h000002);
          acc.read('h4, dat);
          acc.write('h2c, 'h01);
          acc.write('h0, 'h000102);
          acc.read('h4, dat);
          acc.write('h2c, 'h02);
          acc.write('h0, 'h000202);
          acc.read('h4, dat);
          acc.write('h2c, 'h04);
          acc.write('h0, 'h000302);
          acc.read('h4, dat);
          acc.write('h2c, 'h08);
          acc.write('h0, 'h000402);
          acc.read('h4, dat);
          acc.write('h2c, 'h10);
          acc.write('h0, 'h000502);
          acc.read('h4, dat);
          acc.write('h2c, 'h20);
          acc.write('h0, 'h000602);
          acc.read('h4, dat);
          acc.write('h2c, 'h40);
          acc.write('h0, 'h000702);
          acc.read('h4, dat);
          acc.write('h2c, 'h80);
          #1us;

          acc.write('h0, 'h80000000); //reset counters

          #5us;
          //acc.write('h0, 'h000002);
          acc.write('h0, 'h000001);
          acc.read('h4, dat);
          acc.read('h8, dat);
          acc.write('h0, 'h010001);
          acc.read('h4, dat);
          acc.read('h8, dat);
          acc.write('h0, 'h000101);
          acc.read('h4, dat);
          acc.read('h8, dat);
          acc.write('h0, 'h010101);
          acc.read('h4, dat);
          acc.read('h8, dat);
          acc.write('h0, 'h000201);
          acc.read('h4, dat);
          acc.read('h8, dat);
          acc.write('h0, 'h010201);
          acc.write('h0, 'h000301);
          acc.write('h0, 'h010301);
          acc.write('h0, 'h000401);
          acc.write('h0, 'h010401);
        //  acc.write('h0, 'h010001);
        //  acc.read('h4, dat);
        //  acc.write('h0, 'h020001);
        //  acc.read('h4, dat);
        //  acc.write('h0, 'h030001);
        //  acc.read('h4, dat);
        //  acc.write('h0, 'h040001);
        //  acc.read('h4, dat);
        //end
      //end 

      //#500ns
      //acc.read('h4, dat);
      
    end 
   
endmodule // main



