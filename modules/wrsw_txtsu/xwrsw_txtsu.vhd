-------------------------------------------------------------------------------
-- Title      : TX Timestamping Unit
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : xwrsw_txtsu.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-26
-- Last update: 2012-07-12
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: Shared timestamping unit for all switch endpoints. It collects
-- TX timestamps with associated frame identifiers and puts them (along
-- with the identifier of requesting port) in a shared FIFO. Each FIFO entry
-- contains:
-- - Frame ID value (from OOB field of transmitted frame)
-- - Timestamp value (from the endpoint)
-- - Port ID value (ID of the TXTSU port to which the timstamp+frame id came).
-- FIFO is accessible from the Wishbone bus. An IRQ (level-active) is triggered
-- when the FIFO is not empty. The driver reads TX timestamps (with associated
-- port and frame identifiers) and passes them to PTP daemon.

-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-04-26  1.0      twlostow        Created
-------------------------------------------------------------------------------



library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

use work.wishbone_pkg.all;
use work.wrsw_txtsu_pkg.all;

entity xwrsw_tx_tsu is
  
  generic (
    g_num_ports           : integer                        := 10;
    g_interface_mode      : t_wishbone_interface_mode      := CLASSIC;
    g_address_granularity : t_wishbone_address_granularity := WORD);

  port (
-- reference clock / 2 (62.5 MHz). All signals below are synchronous to this clock
    clk_sys_i : in std_logic;

-- sync reset, active LO
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- TX timestamp interface (from endpoints)
-------------------------------------------------------------------------------

-- frame identifier inputs (separate for each port)
    timestamps_i     : in  t_txtsu_timestamp_array(g_num_ports-1 downto 0);
    timestamps_ack_o : out std_logic_vector(g_num_ports -1 downto 0);

-------------------------------------------------------------------------------
-- Wishbone bus
-------------------------------------------------------------------------------

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out
    );



end xwrsw_tx_tsu;


architecture syn of xwrsw_tx_tsu is


  component wrsw_txtsu_wb
    port (
      rst_n_i               : in  std_logic;
      clk_sys_i              : in  std_logic;
      wb_adr_i             : in  std_logic_vector(2 downto 0);
      wb_dat_i             : in  std_logic_vector(31 downto 0);
      wb_dat_o             : out std_logic_vector(31 downto 0);
      wb_cyc_i              : in  std_logic;
      wb_sel_i              : in  std_logic_vector(3 downto 0);
      wb_stb_i              : in  std_logic;
      wb_we_i               : in  std_logic;
      wb_ack_o              : out std_logic;
      wb_int_o              : out std_logic;
      txtsu_tsf_wr_req_i    : in  std_logic;
      txtsu_tsf_wr_full_o   : out std_logic;
      txtsu_tsf_wr_empty_o  : out std_logic;
      txtsu_tsf_val_r_i     : in  std_logic_vector(27 downto 0);
      txtsu_tsf_val_f_i     : in  std_logic_vector(3 downto 0);
      txtsu_tsf_pid_i       : in  std_logic_vector(4 downto 0);
      txtsu_tsf_fid_i       : in  std_logic_vector(15 downto 0);
      txtsu_tsf_incorrect_i : in  std_logic;
      irq_nempty_i          : in  std_logic);
  end component;


  signal txtsu_tsf_wr_req    : std_logic;
  signal txtsu_tsf_wr_full   : std_logic;
  signal txtsu_tsf_wr_empty  : std_logic;
  signal txtsu_tsf_val_r     : std_logic_vector(27 downto 0);
  signal txtsu_tsf_val_f     : std_logic_vector(3 downto 0);
  signal txtsu_tsf_pid       : std_logic_vector(4 downto 0);
  signal txtsu_tsf_fid       : std_logic_vector(15 downto 0);
  signal txtsu_tsf_incorrect : std_logic;

  signal irq_nempty : std_logic;
  signal scan_cntr  : unsigned(4 downto 0);

  type t_txtsu_state is (TSU_SCAN, TSU_ACK);

  signal state : t_txtsu_state;

  signal cur_ep : integer;

  signal wb_out : t_wishbone_slave_out;
  signal wb_in  : t_wishbone_slave_in;
  
begin  -- syn

  U_Adapter : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      master_i  => wb_out,
      master_o  => wb_in,
      slave_i   => wb_i,
      slave_o   => wb_o);

  
  cur_ep <= to_integer(scan_cntr);

  process(clk_sys_i, rst_n_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        
        state            <= TSU_SCAN;
        scan_cntr        <= (others => '0');
        txtsu_tsf_wr_req <= '0';

        timestamps_ack_o <= (others => '0');
        
      else
        case state is
          when TSU_SCAN =>

            if(timestamps_i(cur_ep).stb = '1') then
              timestamps_ack_o(cur_ep) <= '1';
              state                    <= TSU_ACK;

              if(txtsu_tsf_wr_full = '0') then
                txtsu_tsf_pid       <= timestamps_i(cur_ep).port_id(4 downto 0);
                txtsu_tsf_fid       <= timestamps_i(cur_ep).frame_id;
                txtsu_tsf_val_f     <= timestamps_i(cur_ep).tsval(31 downto 28);
                txtsu_tsf_val_r     <= timestamps_i(cur_ep).tsval(27 downto 0);
                txtsu_tsf_incorrect <= timestamps_i(cur_ep).incorrect;
                txtsu_tsf_wr_req    <= '1';
              end if;
            else
              if(scan_cntr = g_num_ports-1)then
                scan_cntr <= (others => '0');
              else
                scan_cntr <= scan_cntr + 1;
              end if;
            end if;
          when TSU_ACK =>
            timestamps_ack_o(cur_ep) <= '0';
            txtsu_tsf_wr_req         <= '0';
            state                    <= TSU_SCAN;
            if(scan_cntr = g_num_ports-1)then
              scan_cntr <= (others => '0');
            else
              scan_cntr <= scan_cntr + 1;
            end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;


  U_WB_SLAVE : wrsw_txtsu_wb
    port map (
      rst_n_i               => rst_n_i,
      clk_sys_i              => clk_sys_i,
      wb_adr_i             => wb_in.adr(2 downto 0),
      wb_dat_i             => wb_in.dat,
      wb_dat_o             => wb_out.dat,
      wb_cyc_i              => wb_in.cyc,
      wb_sel_i              => wb_in.sel,
      wb_stb_i              => wb_in.stb,
      wb_we_i               => wb_in.we,
      wb_ack_o              => wb_out.ack,
      wb_int_o              => wb_out.int,
      txtsu_tsf_wr_req_i    => txtsu_tsf_wr_req,
      txtsu_tsf_wr_full_o   => txtsu_tsf_wr_full,
      txtsu_tsf_wr_empty_o  => txtsu_tsf_wr_empty,
      txtsu_tsf_val_r_i     => txtsu_tsf_val_r,
      txtsu_tsf_val_f_i     => txtsu_tsf_val_f,
      txtsu_tsf_pid_i       => txtsu_tsf_pid,
      txtsu_tsf_fid_i       => txtsu_tsf_fid,
      txtsu_tsf_incorrect_i => txtsu_tsf_incorrect,
      irq_nempty_i          => irq_nempty);

  irq_nempty <= not txtsu_tsf_wr_empty;
  
end syn;
