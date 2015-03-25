-------------------------------------------------------------------------------
-- Title      : WR NIC - RX descriptor management unit
-- Project    : WhiteRabbit Switch
-------------------------------------------------------------------------------
-- File       : nic_descriptor_manager.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-24
-- Last update: 2012-01-13
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 - 2012 CERN / BE-CO-HT
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
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-11-24  1.0      twlostow        Created
-- 2010-11-27  1.0      twlostow        Unified RX and TX descriptor mgmt
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.NUMERIC_STD.all;

library work;
use work.nic_constants_pkg.all;
use work.nic_descriptors_pkg.all;

entity nic_descriptor_manager is
  generic (
    g_desc_mode            : string := "tx";
    g_num_descriptors      : integer;
    g_num_descriptors_log2 : integer;
    g_port_mask_bits       : integer := 32);  --worth using only in TX mode
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    enable_i       : in  std_logic;
    bna_o          : out std_logic;
    bna_clear_i    : in  std_logic;
    cur_desc_idx_o : out std_logic_vector(g_num_descriptors_log2-1 downto 0);

-------------------------------------------------------------------------------
-- Descriptor RAM interface
-------------------------------------------------------------------------------

    dtbl_addr_o : out std_logic_vector(g_num_descriptors_log2+1 downto 0);
    dtbl_data_i : in  std_logic_vector(31 downto 0);
    dtbl_rd_o   : out std_logic;
    dtbl_data_o : out std_logic_vector(31 downto 0);
    dtbl_wr_o   : out std_logic;

-------------------------------------------------------------------------------
-- RX/TX FSM Interface
-------------------------------------------------------------------------------           

    desc_reload_current_i : in  std_logic;
    desc_request_next_i   : in  std_logic;
    desc_grant_o          : out std_logic;

    rxdesc_current_o : out t_rx_descriptor;
    rxdesc_new_i     : in  t_rx_descriptor;

    txdesc_current_o : out t_tx_descriptor;
    txdesc_new_i     : in  t_tx_descriptor;

    desc_write_i      : in  std_logic;
    desc_write_done_o : out std_logic
    );

end nic_descriptor_manager;


architecture behavioral of nic_descriptor_manager is

  type t_desc_arb_state is (ARB_START_SCAN, ARB_CHECK_EMPTY, ARB_FETCH, ARB_GRANT, ARB_UPDATE, ARB_WRITE_DESC);


  signal state : t_desc_arb_state;

  signal granted_desc_tx : t_tx_descriptor;
  signal granted_desc_rx : t_rx_descriptor;

  signal desc_idx         : unsigned(g_num_descriptors_log2-1 downto 0);
  signal desc_subreg      : unsigned(1 downto 0);

  impure function f_write_marshalling(index : integer)
    return std_logic_vector is
  begin
    if(g_desc_mode = "rx") then
      return f_marshall_rx_descriptor(granted_desc_rx, index);
    elsif (g_desc_mode = "tx") then
      return f_marshall_tx_descriptor(granted_desc_tx, index);
    end if;
  end function;

begin  -- behavioral

  dtbl_addr_o <= std_logic_vector(desc_idx & desc_subreg);
  dtbl_rd_o   <= '1';

  cur_desc_idx_o <= std_logic_vector(desc_idx);

  --GD can do that, those outputs are validated by desc_grant_o
  --and nic_rx_fsm stores it in internal register too
  GEN_TXDESC_CUR: if g_desc_mode = "tx" generate
    txdesc_current_o <= granted_desc_tx;
  end generate;
  GEN_RXDESC_CUR: if g_desc_mode = "rx" generate
    rxdesc_current_o <= granted_desc_rx;
  end generate;

  p_rxdesc_arbiter : process(clk_sys_i, rst_n_i)
    variable tmp_desc_rx : t_rx_descriptor;
    variable tmp_desc_tx : t_tx_descriptor;
    --  variable l:line ;
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i = '0' or enable_i = '0') then
        desc_write_done_o <= '0';
        desc_grant_o      <= '0';
        state             <= ARB_START_SCAN;
        desc_idx          <= (others => '0');
        desc_subreg       <= (others => '0');
        dtbl_wr_o         <= '0';
--        dtbl_rd_o <= '0';
        dtbl_data_o       <= (others => '0');
      else
        
        case state is

          when ARB_START_SCAN =>
            desc_subreg <= (others => '0');
            dtbl_wr_o <= '0';
            if(enable_i = '1') then
              state <= ARB_CHECK_EMPTY;
            else
              desc_idx    <= (others => '0');
            end if;

          when ARB_CHECK_EMPTY =>
            dtbl_wr_o <= '0';
            tmp_desc_rx := f_unmarshall_rx_descriptor(dtbl_data_i, 1);
            tmp_desc_tx := f_unmarshall_tx_descriptor(dtbl_data_i, 1);
            granted_desc_tx <= tmp_desc_tx;
            granted_desc_rx <= tmp_desc_rx;

            if((tmp_desc_rx.empty = '1' and g_desc_mode = "rx") or (tmp_desc_tx.ready = '1' and g_desc_mode = "tx")) then
              desc_subreg     <= "01";
              state           <= ARB_FETCH;
              bna_o           <= '0';
            else
              bna_o <= '1';
            end if;

          when ARB_FETCH =>
            dtbl_wr_o <= '0';
            case desc_subreg is
              when "10" =>              -- ignore the timestamps for RX
                                        -- descriptors (they're
                                        -- write-only by the NIC)
                tmp_desc_tx := f_unmarshall_tx_descriptor(dtbl_data_i, 2);
                granted_desc_tx.len    <= tmp_desc_tx.len;
                granted_desc_tx.offset <= tmp_desc_tx.offset;


              when "11" =>
                tmp_desc_tx := f_unmarshall_tx_descriptor(dtbl_data_i, 3);  -- TX
                granted_desc_tx.dpm(g_port_mask_bits-1 downto 0) <= tmp_desc_tx.dpm(g_port_mask_bits-1 downto 0);


                tmp_desc_rx := f_unmarshall_rx_descriptor(dtbl_data_i, 3);  -- RX
                granted_desc_rx.len    <= tmp_desc_rx.len;
                granted_desc_rx.offset <= tmp_desc_rx.offset;

                state <= ARB_GRANT;
              when others => null;
            end case;

            desc_subreg <= desc_subreg + 1;

          when ARB_GRANT =>
            dtbl_wr_o <= '0';
            desc_subreg <= "11";

            if(desc_request_next_i = '1') then
              desc_grant_o <= '1';

              state <= ARB_UPDATE;
            end if;

            desc_write_done_o <= '0';
            
          when ARB_UPDATE =>
            dtbl_wr_o <= '0';
            desc_grant_o <= '0';
            desc_subreg <= "11";

            if(desc_write_i = '1') then
              if(g_desc_mode = "rx") then
                granted_desc_rx <= rxdesc_new_i;
              elsif(g_desc_mode = "tx") then
                granted_desc_tx <= txdesc_new_i;
              end if;

              state       <= ARB_WRITE_DESC;
            end if;

          when ARB_WRITE_DESC =>
            dtbl_data_o <= f_write_marshalling(to_integer(desc_subreg));
            if(desc_subreg = "10") then
              dtbl_wr_o   <= '0';
              desc_subreg <= "00";
              state       <= ARB_START_SCAN;
              if(desc_reload_current_i = '0') then
                desc_idx <= desc_idx + 1;
              end if;
              desc_write_done_o <= '1';
            else
              dtbl_wr_o <= '1';
              desc_subreg <= desc_subreg + 1;
            end if;
            
          when others => null;
        end case;
        
      end if;
    end if;
  end process;
  
  
  

end behavioral;
