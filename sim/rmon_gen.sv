module rmon_gen (rst_n_i, clk_i, trig_o);

  parameter g_trig_width = 10;
  parameter g_time = 25;

  input rst_n_i;
  input clk_i;
  output [g_trig_width-1:0]trig_o;

  integer num[g_trig_width-1:0], rnd[g_trig_width-1:0];
  reg [g_trig_width-1:0]trig_o;

  reg stop;

  initial
  begin
    fork
    begin
      stop = 1'b1;
      #24us
      stop = 1'b0;
    end
    join_none
  end

  genvar n;
  generate
    for(n=0; n<g_trig_width; n=n+1) begin
      initial
      begin
        for(rnd[n]=$urandom()%10; rnd[n]>0; rnd[n]=rnd[n]-1)
          #20ns;
      end
      always //@(posedge clk_i)
      begin
        trig_o[n] = 1'b0;
        //#100ns;
        rnd[n] = $urandom() %100;
        num[n] = $urandom() %100;
        if(num[n]<rnd[n]) 
        begin
            trig_o[n] = 1'b1 & stop;
            #10ns; 
            trig_o[n] = 1'b0;
            #310ns;   //310 + 10 = 320 -> minimum frame size
        end
        for(rnd[n]=$urandom()%10; rnd[n]>0; rnd[n]=rnd[n]-1)
          #20ns;
      end 
    end
  endgenerate


endmodule
