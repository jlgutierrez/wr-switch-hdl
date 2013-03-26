-------------------------------------------------------------------------------
-- Title      : Hardware Debugging Unit
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_hwdu.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-03-26
-- Last update: 2013-03-26
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Debugging module, allows reading the content of selected registers inside 
-- WR Switch GW through Wishbone interface.
-------------------------------------------------------------------------------
-- Copyright (c) 2013 Grzegorz Daniluk / CERN
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2013-03-26  0.1      greg.d          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hwdu_wbgen2_pkg.all;

entity wrsw_hwdu is
  generic (
    g_nregs  : integer := 1;
    g_rwidth : integer := 32);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    dbg_regs_i : in std_logic_vector(g_nregs*g_rwidth-1 downto 0);

    wb_adr_i   : in  std_logic_vector(0 downto 0);
    wb_dat_i   : in  std_logic_vector(31 downto 0);
    wb_dat_o   : out std_logic_vector(31 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_sel_i   : in  std_logic_vector(3 downto 0);
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_ack_o   : out std_logic;
    wb_stall_o : out std_logic;
    wb_int_o   : out std_logic);
end wrsw_hwdu;

architecture behav of wrsw_hwdu is

  component hwdu_wishbone_slave
    port (
      rst_n_i    : in  std_logic;
      clk_sys_i  : in  std_logic;
      wb_adr_i   : in  std_logic_vector(0 downto 0);
      wb_dat_i   : in  std_logic_vector(31 downto 0);
      wb_dat_o   : out std_logic_vector(31 downto 0);
      wb_cyc_i   : in  std_logic;
      wb_sel_i   : in  std_logic_vector(3 downto 0);
      wb_stb_i   : in  std_logic;
      wb_we_i    : in  std_logic;
      wb_ack_o   : out std_logic;
      wb_stall_o : out std_logic;
      regs_i     : in  t_hwdu_in_registers;
      regs_o     : out t_hwdu_out_registers
    );
  end component;

  signal wb_regs_in  : t_hwdu_in_registers;
  signal wb_regs_out : t_hwdu_out_registers;

  type   t_rd_st is (IDLE, READ);
  signal rd_state : t_rd_st;

  signal rd_val        : std_logic_vector(g_rwidth-1 downto 0);
  signal rd_err, rd_en : std_logic;

begin

  U_WB_Slave : hwdu_wishbone_slave
    port map(
      rst_n_i    => rst_n_i,
      clk_sys_i  => clk_i,
      wb_adr_i   => wb_adr_i,
      wb_dat_i   => wb_dat_i,
      wb_dat_o   => wb_dat_o,
      wb_cyc_i   => wb_cyc_i,
      wb_sel_i   => wb_sel_i,
      wb_stb_i   => wb_stb_i,
      wb_we_i    => wb_we_i,
      wb_ack_o   => wb_ack_o,
      wb_stall_o => wb_stall_o,
      regs_i     => wb_regs_in,
      regs_o     => wb_regs_out
    );
  wb_int_o <= '0';

  wb_regs_in.reg_val_i(g_rwidth-1 downto 0) <= rd_val;
  GEN_regval : if g_rwidth < 32 generate
    wb_regs_in.reg_val_i(31 downto g_rwidth) <= (others => '0');
  end generate;

  wb_regs_in.cr_rd_err_i <= rd_err;
  wb_regs_in.cr_rd_en_i  <= rd_en;

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_state <= IDLE;
        rd_en    <= '0';
        rd_err   <= '0';
      else
        case(rd_state) is
          when IDLE =>
            if(wb_regs_out.cr_rd_en_o = '1' and wb_regs_out.cr_rd_en_load_o = '1') then
              rd_en    <= '1';
              rd_state <= READ;
            end if;
          when READ =>
            rd_en    <= '0';
            rd_state <= IDLE;
            if(to_integer(unsigned(wb_regs_out.cr_adr_o)) > g_nregs-1) then
              rd_err <= '1';
            else
              rd_err <= '0';
              --get part of dbg_regs input vector
              rd_val <= dbg_regs_i((to_integer(unsigned(wb_regs_out.cr_adr_o))+1)*g_rwidth-1 downto
                        to_integer(unsigned(wb_regs_out.cr_adr_o))*g_rwidth);
            end if;

          when others =>
            rd_state <= IDLE;
        end case;
      end if;
    end if;
  end process;


end behav;
