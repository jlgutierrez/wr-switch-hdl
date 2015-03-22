-------------------------------------------------------------------------------
-- Title      : Control of tx path
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : psu_tx_ctrl.vhd
-- Author     : Maciej Lip0inski
-- Company    : CERN BE-CO-HT
-- Created    : 2015-03-2
-- Last update: 2015-03-22
-- Platform   : FPGA-generic
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description:
-------------------------------------------------------------------------------

-- Copyright (c) 2015 CERN / BE-CO-HT
--
-- This source file is free software; you can redistribute it
-- and/or modify it under the terms of the GNU Lesser General
-- Public License as published by the Free Software Foundation;
-- either version 2.1 of the License, or (at your option) any
-- later version.
--
-- This source is distributed in the hope that it will be
-- useful, but WITHOUT ANY WARRANTY; without even the implied
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
-- PURPOSE.  See the GNU Lesser General Public License for more
-- details.
--
-- You should have received a copy of the GNU Lesser General
-- Public License along with this source; if not, download it
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------
-- FIXME:
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2015-03-22  1.0      mlipinsk	    Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.psu_pkg.all;
use work.wr_fabric_pkg.all;
use work.genram_pkg.all;
use work.wishbone_pkg.all;
use work.psu_wbgen2_pkg.all;
use work.swc_swcore_pkg.all;

entity psu_tx_ctrl is
  generic(
    g_port_number       : integer := 18);
  port (
    clk_sys_i           : in std_logic;
    rst_n_i             : in std_logic;

    inject_req_o        : out std_logic;
    inject_ready_i      : in  std_logic;
    inject_port_mask_o  : out std_logic_vector(g_port_number-1 downto 0);
    tx_port_mask_i      : in std_logic_vector(g_port_number-1 downto 0); 
    tx_ann_detect_mask_i : in std_logic_vector(g_port_number-1 downto 0); 
    holdover_on_i       : in  std_logic

    );

end psu_tx_ctrl;

architecture behavioral of psu_tx_ctrl is

  type t_state is (WAIT_HOLDOVER, WAIT_INJ_READY, DO_INJ, DO_IFG, IN_HOLDOVER);
  
  signal state              : t_state;
  signal holdover_on_d      : std_logic;
  signal cnt                : unsigned(2 downto 0);
  signal tx_port_mask_d     : std_logic_vector(g_port_number-1 downto 0); 
  signal inject_port_mask   : std_logic_vector(g_port_number-1 downto 0); 
  signal zeros              : std_logic_vector(g_port_number-1 downto 0);
  signal inject_req         : std_logic;
  signal tx_snooped_ports   : std_logic_vector(g_port_number-1 downto 0);
begin

  zeros <= (others => '0');
  p_ctrl_fsm : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        state                 <= WAIT_HOLDOVER;
        holdover_on_d         <= '0';
        inject_req            <= '0';
        tx_port_mask_d        <= (others =>'0');
        tx_snooped_ports      <= (others =>'0');
      else

        holdover_on_d         <= holdover_on_i;
        
        -- remember on which ports we have already sent announce (we cannot inject on others)
        tx_snooped_ports      <= (tx_snooped_ports or tx_ann_detect_mask_i) and tx_port_mask_i;

        case state is
          when WAIT_HOLDOVER  =>
            inject_req        <= '0';
            if(holdover_on_i = '1' and holdover_on_d = '0') then
              state           <= WAIT_INJ_READY;
              tx_port_mask_d  <= tx_port_mask_i and tx_snooped_ports;
            end if;
          when WAIT_INJ_READY =>
            if(inject_ready_i = '1') then
              inject_req      <= '1';
              state           <= DO_INJ;
            end if;
          when DO_INJ         => 
            inject_req        <= '0';
            if(inject_ready_i = '1' and inject_req  = '0') then
              tx_port_mask_d  <= tx_port_mask_d and not inject_port_mask;
              state           <= DO_IFG;
              cnt             <= (others => '0');
            end if;
          when DO_IFG         =>
            if(cnt = 6) then
              if(tx_port_mask_d = zeros) then
                state         <= IN_HOLDOVER;
              else 
                state         <= WAIT_INJ_READY;
              end if;
            else
              cnt             <= cnt + 1;
            end if;
          when IN_HOLDOVER    =>
            if(holdover_on_i = '0' and holdover_on_d = '1') then
              state           <= WAIT_HOLDOVER;
            end if;
          when others         =>
            state             <= WAIT_HOLDOVER;
        end case;
      end if;
    end if;
  end process;

  ENCODER : swc_prio_encoder
    generic map (
      g_num_inputs  => g_port_number,
      g_output_bits => 5)
    port map (
      in_i     => tx_port_mask_d,
      onehot_o => inject_port_mask);

  inject_port_mask_o <= inject_port_mask;
  inject_req_o       <= inject_req;

end behavioral;

