library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wr_fabric_pkg.all;
use work.wishbone_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.wdog_wbgen2_pkg.all;

entity xwrsw_watchdog is
  generic(
    g_interface_mode      : t_wishbone_interface_mode := PIPELINED;
    g_address_granularity : t_wishbone_address_granularity := BYTE;
    g_num_ports : integer := 18);
  port(
    rst_n_i : in  std_logic;
    clk_i   : in  std_logic;
    
    swc_nomem_i : in  std_logic;
    swc_fsms_i  : in  t_swc_fsms_array(g_num_ports-1 downto 0);

    swcrst_n_o  : out std_logic;
    epstop_o    : out std_logic;

    rtu_ack_i   : in  std_logic_vector(g_num_ports-1 downto 0);
    rtu_ack_o   : out std_logic_vector(g_num_ports-1 downto 0);

    snk_i       : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
    snk_o       : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
    src_o       : out t_wrf_source_out_array(g_num_ports-1 downto 0);
    src_i       : in  t_wrf_source_in_array(g_num_ports-1 downto 0);

    wb_i  : in  t_wishbone_slave_in;
    wb_o  : out t_wishbone_slave_out);
end xwrsw_watchdog;

architecture behav of xwrsw_watchdog is

  component wdog_wishbone_slave
    port (
      rst_n_i                                  : in     std_logic;
      clk_sys_i                                : in     std_logic;
      wb_adr_i                                 : in     std_logic_vector(1 downto 0);
      wb_dat_i                                 : in     std_logic_vector(31 downto 0);
      wb_dat_o                                 : out    std_logic_vector(31 downto 0);
      wb_cyc_i                                 : in     std_logic;
      wb_sel_i                                 : in     std_logic_vector(3 downto 0);
      wb_stb_i                                 : in     std_logic;
      wb_we_i                                  : in     std_logic;
      wb_ack_o                                 : out    std_logic;
      wb_stall_o                               : out    std_logic;
      regs_i                                   : in     t_wdog_in_registers;
      regs_o                                   : out    t_wdog_out_registers
    );
  end component;
  
  type t_act_array is array(integer range <>) of std_logic_vector(6 downto 0);

  constant c_RST_TIME    : integer := 16384;
  constant c_SWCRST_TIME : integer := 8;
  constant c_NOMEM_THR   : integer := 10000; --62500000;
  constant c_SWC_FSMS_ZERO : t_swc_fsms :=
    (x"0", x"0", x"0", x"0", x"0", x"0", x"0");

  signal wb_regs_in  : t_wdog_in_registers;
  signal wb_regs_out : t_wdog_out_registers;
  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;
  signal sel_port : integer range 0 to g_num_ports-1;
  signal fsm_act  : t_act_array(g_num_ports-1 downto 0);
  signal fsm_act_frozen  : t_act_array(g_num_ports-1 downto 0);

  signal nomem_cnt  : unsigned(25 downto 0);
  signal nomem_trig : std_logic;
  signal rst_cnt  : unsigned(15 downto 0);
  signal watchdog_cnt  : unsigned(31 downto 0);
  signal rst_trig : std_logic;
  signal rst_trig_d0 : std_logic;
  signal reset_mode : std_logic;
  signal swc_fsms_prev : t_swc_fsms_array(g_num_ports-1 downto 0);
begin

  -- Standard Wishbone stuff
  U_Adapter : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  wb_out.err <= '0';
  wb_out.rty <= '0';
  wb_out.int <= '0';

  U_WB_Slave : wdog_wishbone_slave
    port map(
      rst_n_i   => rst_n_i,
      clk_sys_i => clk_i,
      wb_adr_i  => wb_in.adr(1 downto 0),
      wb_dat_i  => wb_in.dat,
      wb_dat_o  => wb_out.dat,
      wb_cyc_i  => wb_in.cyc,
      wb_sel_i  => wb_in.sel,
      wb_stb_i  => wb_in.stb,
      wb_we_i   => wb_in.we,
      wb_ack_o  => wb_out.ack,
      wb_stall_o=> wb_out.stall,
      regs_i    => wb_regs_in,
      regs_o    => wb_regs_out);

  --------------------------
  wb_regs_in.rst_cnt_i <= std_logic_vector(watchdog_cnt);

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i='0') then
        sel_port <= 0;
      elsif(wb_regs_out.cr_port_load_o='1') then
        sel_port <= to_integer(unsigned(wb_regs_out.cr_port_o));
      end if;
    end if;
  end process;
  wb_regs_in.cr_port_i <= std_logic_vector(to_unsigned(sel_port, 8));

  -- FSM export for software watchdog
  GEN_PORT_EXPORT: for I in 0 to g_num_ports-1 generate
    process(clk_i)
      variable fidx  : integer range 0 to 6;
    begin
      if rising_edge(clk_i) then
        if(rst_n_i='0') then
          swc_fsms_prev(I) <= c_SWC_FSMS_ZERO;
          fsm_act(I)  <= (others=>'0');
          fsm_act_frozen(I)  <= (others=>'0');
        else
          for fidx in 0 to 6 loop
            if(swc_fsms_i(I)(fidx) /= swc_fsms_prev(I)(fidx)) then
              fsm_act(I)(fidx) <= '1';
            end if;
          end loop;
          if(wb_regs_out.cr_port_load_o='1' and
              wb_regs_out.cr_port_o = std_logic_vector(to_unsigned(I, 8))) then
            swc_fsms_prev(I) <= swc_fsms_i(I);
            fsm_act_frozen(I) <= fsm_act(I);
            fsm_act(I) <= (others=>'0');
          end if;
        end if;
      end if;
    end process;
  end generate;
  
  wb_regs_in.fsm_ib_alloc_i <= swc_fsms_i(sel_port)(c_ALLOC_FSM_IDX);
  wb_regs_in.fsm_ib_trans_i <= swc_fsms_i(sel_port)(c_TRANS_FSM_IDX);
  wb_regs_in.fsm_ib_rcv_i   <= swc_fsms_i(sel_port)(c_RCV_FSM_IDX);
  wb_regs_in.fsm_ib_ll_i    <= swc_fsms_i(sel_port)(c_LL_FSM_IDX);
  wb_regs_in.fsm_ob_prep_i  <= swc_fsms_i(sel_port)(c_PREP_FSM_IDX);
  wb_regs_in.fsm_ob_send_i  <= swc_fsms_i(sel_port)(c_SEND_FSM_IDX);
  wb_regs_in.fsm_free_i     <= swc_fsms_i(sel_port)(c_FREE_FSM_IDX);
  wb_regs_in.act_i          <= fsm_act_frozen(sel_port);

  -- Hanging detection
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i='0' or swc_nomem_i='0') then
        nomem_cnt   <= (others=>'0');
        nomem_trig  <= '0';
      elsif(swc_nomem_i='1' and nomem_cnt<c_NOMEM_THR) then
        nomem_trig <= '0';
        nomem_cnt <= nomem_cnt + 1;
      elsif(nomem_cnt = c_NOMEM_THR) then
        nomem_trig <= '1';
        nomem_cnt  <= (others=>'0');
      end if;
    end if;
  end process;

  rst_trig <= wb_regs_out.cr_rst_o or nomem_trig;

  -- Resetting SwCore and Endpoints
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_n_i = '0') then
        rst_cnt    <= (others=>'0');
        watchdog_cnt <= (others=>'0');
        rst_trig_d0   <= '0';
        reset_mode <= '0';
      else
        rst_trig_d0 <= rst_trig;
        if(rst_trig='1' and rst_trig_d0='0') then
          reset_mode <= '1';
          watchdog_cnt <= watchdog_cnt + 1;
        end if;

        if(reset_mode='1') then
          rst_cnt <= rst_cnt + 1;
          if(rst_cnt = c_RST_TIME) then
            reset_mode <= '0';
            rst_cnt <= (others=>'0');
          end if;
        end if;
      end if;
    end if;
  end process;

  -- switching core we reset only for one clk cycle
  swcrst_n_o <= '0' when(reset_mode='1' and rst_cnt < c_SWCRST_TIME) else
                rst_n_i;

  -- the rest we keep longer in reset so that SWCore has time to initialize
  epstop_o <= '1' when (reset_mode = '1') else
              '0';

  rtu_ack_o <= (others=>'1') when (reset_mode = '1') else
               rtu_ack_i;

  GEN_FABTIC_RST: for I in 0 to g_num_ports-1 generate
    snk_o(I).stall <= '0' when (reset_mode='1') else
                      src_i(I).stall;
    snk_o(I).ack   <= '1' when (reset_mode='1') else
                      src_i(I).ack;
    snk_o(I).err   <= src_i(I).err;
    snk_o(I).rty   <= src_i(I).rty;

    src_o(I).cyc   <= '0' when (reset_mode='1') else
                      snk_i(I).cyc;
    src_o(I).stb   <= '0' when (reset_mode='1') else
                      snk_i(I).stb;
    src_o(I).we    <= snk_i(I).we;
    src_o(I).sel   <= snk_i(I).sel;
    src_o(I).adr   <= snk_i(I).adr;
    src_o(I).dat   <= snk_i(I).dat;
  end generate;



end behav;
