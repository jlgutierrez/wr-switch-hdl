library ieee;
use ieee.std_logic_1164.all;
use ieee.NUMERIC_STD.all;

library work;
use work.endpoint_private_pkg.all;      -- dirty hack, again
use work.genram_pkg.all;
use work.wr_fabric_pkg.all;



entity nic_elastic_buffer is
  
  generic (
    g_depth : integer := 64);

  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    snk_i : in  t_wrf_sink_in;
    snk_o : out t_wrf_sink_out;

    fab_o  : out t_ep_internal_fabric;
    dreq_i : in  std_logic
    );

end nic_elastic_buffer;

architecture rtl of nic_elastic_buffer is

  function log2 (A : natural) return natural is
  begin
    for I in 1 to 64 loop               -- Works for up to 32 bits
      if (2**I > A) then
        return(I-1);
      end if;
    end loop;
    return(63);
  end function log2;


  constant c_fifo_width : integer := 16 + 2 + 5;

  signal fifo_write   : std_logic;
  signal fifo_read    : std_logic;
  signal fifo_in_ser  : std_logic_vector(c_fifo_width-1 downto 0);
  signal fifo_out_ser : std_logic_vector(c_fifo_width-1 downto 0);
  signal fifo_full    : std_logic;
  signal fifo_empty   : std_logic;
  signal fifo_almost_empty : std_logic;
  signal fifo_almost_full  : std_logic;

  signal output_valid : std_logic;
  signal got_empty    : std_logic;

  signal cyc_d0 : std_logic;

  signal fifo_in   : t_ep_internal_fabric;
  signal fifo_out  : t_ep_internal_fabric;
  signal snk_out   : t_wrf_sink_out;
  signal stall_int : std_logic;
  
begin  -- rtl

  p_delay_cyc : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        cyc_d0 <= '0';
      else
        cyc_d0 <= snk_i.cyc;
      end if;
    end if;
  end process;

  snk_o <= snk_out;

  snk_out.err <= fifo_full and snk_i.cyc and snk_i.stb;
  snk_out.rty <= '0';

  p_gen_ack : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        snk_out.ack <= '0';
      else
        snk_out.ack <= snk_i.cyc and snk_i.stb and not snk_out.stall;
      end if;
    end if;
  end process;

  fifo_in.sof    <= not cyc_d0 and snk_i.cyc;
  fifo_in.eof    <= cyc_d0 and not snk_i.cyc;
  fifo_in.data   <= snk_i.dat;
  fifo_in.dvalid <= snk_i.stb and snk_i.cyc and not snk_out.stall;
  fifo_in.addr   <= snk_i.adr;
  fifo_in.error  <= '1' when (fifo_in.dvalid = '1') and
                   snk_i.adr = c_WRF_STATUS and
                   (f_unmarshall_wrf_status(snk_i.dat).error = '1') else '0';
  fifo_in.bytesel <= not snk_i.sel(0);

  fifo_write  <= fifo_in.sof or fifo_in.eof or fifo_in.dvalid or fifo_in.error;
  fifo_in_ser <= fifo_in.bytesel & fifo_in.sof & fifo_in.eof & fifo_in.dvalid & fifo_in.error & fifo_in.addr & fifo_in.data;

  p_gen_stall : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' or fifo_almost_empty = '1' then
        stall_int <= '0';
      elsif fifo_almost_full = '1' then
        stall_int <= '1';
      end if;
    end if;
  end process;

  snk_out.stall <= fifo_in.sof or stall_int;
  fifo_read     <= not fifo_empty and dreq_i;

  p_gen_valid_flag : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        output_valid <= '0';
      else
        output_valid <= fifo_read;
      end if;
    end if;
  end process;

  U_fifo : generic_sync_fifo
    generic map (
      g_data_width => c_fifo_width,
      g_size       => g_depth,
      g_with_almost_empty => true,
      g_with_almost_full  => true,
      g_almost_empty_threshold  => g_depth/2,
      g_almost_full_threshold   => g_depth-5,
      g_with_count => false)
    port map (
      rst_n_i => rst_n_i,
      clk_i   => clk_sys_i,
      we_i    => fifo_write,
      d_i     => fifo_in_ser,
      rd_i    => fifo_read,
      q_o     => fifo_out_ser,
      empty_o => fifo_empty,
      full_o  => fifo_full,
      almost_empty_o  => fifo_almost_empty,
      almost_full_o   => fifo_almost_full
      );

  fab_o.data   <= fifo_out_ser(15 downto 0);
  fab_o.addr   <= fifo_out_ser(17 downto 16);
  fab_o.error  <= fifo_out_ser(18) and output_valid;
  fab_o.dvalid <= fifo_out_ser(19) and output_valid;
  fab_o.eof    <= fifo_out_ser(20) and output_valid;
  fab_o.sof    <= fifo_out_ser(21) and output_valid;
  fab_o.bytesel <= fifo_out_ser(22);
  
end rtl;
