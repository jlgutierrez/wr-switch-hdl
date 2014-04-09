-------------------------------------------------------------------------------
-- Title      : WRF Interface transmission logic for WR NIC
-- Project    : WhiteRabbit Switch
-------------------------------------------------------------------------------
-- File       : nic_tx_fsm.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-24
-- Last update: 2012-01-24
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: The NIC transmit FSM
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
-------------------------------------------------------------------------------

library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;

use work.nic_constants_pkg.all;
use work.nic_descriptors_pkg.all;
use work.wr_fabric_pkg.all;
use work.nic_wbgen2_pkg.all;


entity nic_tx_fsm is
  generic(
    g_port_mask_bits  : integer := 32;
    g_cyc_on_stall    : boolean := false);
  port (
    clk_sys_i : in  std_logic;
    rst_n_i   : in  std_logic;
-------------------------------------------------------------------------------
-- WRF source
-------------------------------------------------------------------------------
    src_o     : out t_wrf_source_out;
    src_i     : in  t_wrf_source_in;

-------------------------------------------------------------------------------
-- "Fake" RTU interface
-------------------------------------------------------------------------------

    rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
    rtu_prio_o          : out std_logic_vector(2 downto 0);
    rtu_drop_o          : out std_logic;
    rtu_rsp_valid_o     : out std_logic;
    rtu_rsp_ack_i       : in  std_logic;

-------------------------------------------------------------------------------
-- Wishbone regs & IRQs
-------------------------------------------------------------------------------           

    regs_i : in  t_nic_out_registers;
    regs_o : out t_nic_in_registers;

    irq_tcomp_o      : out std_logic;
    irq_tcomp_ack_i  : in  std_logic;
    irq_tcomp_mask_i : in  std_logic;

    irq_txerr_o      : out std_logic;
    irq_txerr_ack_i  : in  std_logic;
    irq_txerr_mask_i : in  std_logic;

-------------------------------------------------------------------------------
-- TX Descriptor Manager I/F
-------------------------------------------------------------------------------           

    txdesc_reload_current_o : out std_logic;
    -- 1 requests next available (empty) TX descriptor
    txdesc_request_next_o   : out std_logic;
    -- 1 indicates that an empty descriptor has been granted and it's available
    -- on rxdesc_current_i
    txdesc_grant_i          : in  std_logic;
    -- currently granted TX descriptor
    txdesc_current_i        : in  t_tx_descriptor;
    -- updated RX descriptor (with new length, error flags, timestamp, etc.)
    txdesc_new_o            : out t_tx_descriptor;
    -- 1 requests an update of the current TX descriptor with the values
    -- given on rxdesc_new_o output
    txdesc_write_o          : out std_logic;
    -- 1 indicates that the TX descriptor update is done
    txdesc_write_done_i     : in  std_logic;

    bna_i : in std_logic;

-------------------------------------------------------------------------------
-- Packet buffer RAM
-------------------------------------------------------------------------------

    -- 1 indicates that we'll have the memory access in the following clock
    -- cycle
    buf_grant_i : in  std_logic;
    -- buffer address, data and write enable lines.
    buf_addr_o  : out std_logic_vector(c_nic_buf_size_log2-3 downto 0);
    buf_data_i  : in  std_logic_vector(31 downto 0)
  );
end nic_tx_fsm;


architecture behavioral of nic_tx_fsm is

  type t_tx_fsm_state is (TX_DISABLED, TX_REQUEST_DESCRIPTOR, TX_MEM_FETCH, TX_START_PACKET, TX_HWORD, TX_LWORD, TX_END_PACKET, TX_OOB1, TX_OOB2, TX_PAD, TX_UPDATE_DESCRIPTOR, TX_ERROR, TX_STATUS);

  signal cur_tx_desc : t_tx_descriptor;

  function f_buf_swap_endian_32
    (
      data : std_logic_vector(31 downto 0)
      ) return std_logic_vector is
  begin
    if(c_nic_buf_little_endian = true) then
      return data(7 downto 0) & data(15 downto 8) & data(23 downto 16) & data(31 downto 24);
    else
      return data;
    end if;
  end function f_buf_swap_endian_32;

  signal state        : t_tx_fsm_state;
  signal tx_remaining : unsigned(c_nic_buf_size_log2-2 downto 0);
  signal odd_length   : std_logic;

  signal tx_buf_addr      : unsigned(c_nic_buf_size_log2-3 downto 0);
  signal tx_data_reg      : std_logic_vector(31 downto 0);
  signal tx_done          : std_logic;

  signal ignore_first_hword : std_logic;
  signal tx_cntr_expired    : std_logic;
  signal needs_padding      : std_logic;
  signal padding_size       : unsigned(4 downto 0);

  signal rtu_valid_int    : std_logic;
  signal rtu_valid_int_d0 : std_logic;

  signal tx_err : std_logic;
  signal default_status_reg : t_wrf_status_reg;

  signal ack_count : unsigned(3 downto 0);
	signal src_stb_int	:	std_logic;

begin  -- behavioral


  default_status_reg.has_smac <= '1';
  default_status_reg.has_crc <= '0';
  default_status_reg.error <= '0';
  default_status_reg.is_hp <= '0';
  
  tx_err <= src_i.err or src_i.rty;

  buf_addr_o <= std_logic_vector(tx_buf_addr);

  needs_padding		<= '1' when (to_integer(unsigned(cur_tx_desc.len)) < 60 and cur_tx_desc.pad_e='1') else '0';
  odd_length			<= (not needs_padding) and cur_tx_desc.len(0);
  tx_cntr_expired <= '1' when (tx_remaining = 0) else '0';

  txdesc_new_o <= cur_tx_desc;
  src_o.stb 	 <= src_stb_int;
	--because it's validated with rtu_rsp_valid_o and sw_core stores it to internal register on rtu_rsp_valid strobe
  rtu_dst_port_mask_o <= cur_tx_desc.dpm(g_port_mask_bits-1 downto 0);
  rtu_prio_o          <= (others => '0');
  rtu_drop_o          <= '0';

  count_acks: process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i='0') then
        ack_count <= (others=>'0');
      elsif(src_stb_int = '1' and src_i.stall = '0' and src_i.ack = '0') then
        ack_count <= ack_count + 1;
      elsif(src_i.ack = '1' and not(src_stb_int = '1' and src_i.stall = '0')) then
        ack_count <= ack_count - 1;
      end if;
    end if;
  end process;

  p_gen_tcomp_irq : process(clk_sys_i, rst_n_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        irq_tcomp_o <= '0';
      else
        if(irq_tcomp_ack_i = '1') then
          irq_tcomp_o <= '0';
        else
          if(tx_done = '1' and irq_tcomp_mask_i = '1') then
            irq_tcomp_o <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  p_gen_sr_tx_done : process(clk_sys_i, rst_n_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        regs_o.sr_tx_done_i <= '0';
      else
        if(regs_i.sr_tx_done_load_o = '1' and regs_i.sr_tx_done_o = '1') then
          regs_o.sr_tx_done_i <= '0';
        else
          if(tx_done = '1' and bna_i = '1') then
            regs_o.sr_tx_done_i <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  p_fsm : process(clk_sys_i, rst_n_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        state                   <= TX_DISABLED;
        irq_txerr_o             <= '0';
        txdesc_request_next_o   <= '0';
        txdesc_write_o          <= '0';
        txdesc_reload_current_o <= '0';

        src_o.cyc   <= '0';
        src_stb_int <= '0';
        src_o.we  	<= '1';
        src_o.adr 	<= (others => '0');
        src_o.dat 	<= (others => '0');
        src_o.sel 	<= (others => '0');

        tx_done              <= '0';
        rtu_valid_int        <= '0';
        irq_txerr_o          <= '0';
        regs_o.sr_tx_error_i <= '0';

      else
        case state is
          when TX_DISABLED =>
            regs_o.sr_tx_error_i  <= '0';
            irq_txerr_o           <= '0';
            txdesc_request_next_o <= '0';

            if(regs_i.cr_tx_en_o = '1') then
              state <= TX_REQUEST_DESCRIPTOR;
            end if;

          when TX_REQUEST_DESCRIPTOR =>
            tx_done               <= '0';
            txdesc_request_next_o <= '1';

            if(txdesc_grant_i = '1') then
              cur_tx_desc           <= txdesc_current_i;
              tx_buf_addr           <= resize(unsigned(txdesc_current_i.offset(tx_buf_addr'length+1 downto 2)), tx_buf_addr'length);
              tx_remaining          <= unsigned(txdesc_current_i.len(tx_remaining'length downto 1));
              state                 <= TX_MEM_FETCH;
              
            end if;

            -- 1 wait cycle to make sure the 1st TX word has been successfully
            -- read from the buffer
          when TX_MEM_FETCH =>
            txdesc_request_next_o <= '0';
            if(txdesc_current_i.len(0) = '1') then
              tx_remaining <= tx_remaining + 1;
            end if;

            state <= TX_START_PACKET;
            
          when TX_START_PACKET =>
            regs_o.sr_tx_error_i <= '0';

            rtu_valid_int       <= '1';
            ignore_first_hword <= '1';
            if(cur_tx_desc.len(0) = '1') then
              padding_size <= 29 - unsigned(cur_tx_desc.len(padding_size'length downto 1));
            else
              padding_size <= 30 - unsigned(cur_tx_desc.len(padding_size'length downto 1));
            end if;

-- check if the memory is ready, read the 1st word of the payload
            if( ( (src_i.stall = '0' and g_cyc_on_stall = false) or g_cyc_on_stall = true)
                and buf_grant_i = '0') then

              src_o.cyc <= '1';
              tx_buf_addr        <= tx_buf_addr + 1;
              state              <= TX_STATUS;
              tx_data_reg <= f_buf_swap_endian_32(buf_data_i);
            end if;

          when TX_STATUS =>
            src_o.adr  	<= c_WRF_STATUS;
            src_o.sel  	<= "11";
            src_o.dat  	<= f_marshall_wrf_status(default_status_reg);
            
            if( src_i.stall = '0' and buf_grant_i = '0') then
              src_stb_int <= '1';
              state 			<= TX_HWORD;
						else
            	src_stb_int <= '0';
            end if;
            
          when TX_HWORD =>
            rtu_valid_int <= '0';

-- generate the control value depending on the packet type, OOB and the current
-- transmission offset.

            if(tx_err = '1') then
              state             <= TX_UPDATE_DESCRIPTOR;
              cur_tx_desc.error <= '1';
            elsif( src_i.stall = '0' ) then
              src_o.adr <= c_WRF_DATA;
              src_o.dat <= tx_data_reg(31 downto 16);
							ignore_first_hword <= '0';
							src_stb_int		<= not ignore_first_hword;

              if(tx_cntr_expired = '1') then
								-- we are at the end of transmitted frame
                src_o.sel(1) <= '1';
                src_o.sel(0) <= (not odd_length) or needs_padding;

                if(needs_padding = '1') then
                  state <= TX_PAD;
                elsif(cur_tx_desc.ts_e = '1') then
                  state <= TX_OOB1;
                else
                  state <= TX_END_PACKET;
                end if;
              else
                src_o.sel <= "11";
                tx_remaining  <= tx_remaining - 1;
                state <= TX_LWORD;
              end if;
            end if;

          when TX_LWORD =>

-- the TX fabric is ready, the memory is ready and we haven't reached the end
-- of the packet yet:

            if(tx_err = '1') then
              state             <= TX_UPDATE_DESCRIPTOR;
              cur_tx_desc.error <= '1';
            elsif( src_i.stall='0' and buf_grant_i = '0') then
              src_o.adr <= c_WRF_DATA;
              src_o.dat <= tx_data_reg(15 downto 0);
              src_stb_int <= '1';

              if(tx_cntr_expired = '0') then
                src_o.sel    <= "11";
                tx_remaining <= tx_remaining - 1;
                state        <= TX_HWORD;

                -- but we also fetch next word from the buffer
                tx_data_reg <= f_buf_swap_endian_32(buf_data_i);
                tx_buf_addr <= tx_buf_addr + 1;

-- We're at the end of the packet. Generate an end-of-packet condition on the
-- fabric I/F
              else
								-- (tx_cntr_expired=1) we are at the end of transmitted frame
                src_o.sel(1) <= '1';
                src_o.sel(0) <= (not odd_length) or needs_padding;
                if(needs_padding = '1') then
                  state <= TX_PAD;
                elsif(cur_tx_desc.ts_e = '1') then
                  state <= TX_OOB1;
                else
                  state <= TX_END_PACKET;
                end if;
              end if;
							
            elsif( src_i.stall='0' and buf_grant_i = '1') then
              --if we wait for buffer then drop stb so that we don't retransmit last data word
              src_stb_int <= '0';
            end if;

          when TX_PAD =>

            if(tx_err = '1') then
              state             <= TX_UPDATE_DESCRIPTOR;
              cur_tx_desc.error <= '1';
            elsif( src_i.stall='0' ) then
              src_o.dat   <= x"0000";
              src_o.adr   <= c_WRF_DATA;
              src_o.sel   <= "11";
              src_stb_int <= '1';

              padding_size <= padding_size - 1;

              if(padding_size = 0) then
                src_stb_int <= '0';
                if(cur_tx_desc.ts_e = '1') then
                  state <= TX_OOB1;
                else
                  state <= TX_END_PACKET;
                end if;
              end if;
            end if;


          when TX_OOB1 =>
            src_o.sel <= "11";

            if( src_i.stall='0' ) then
              src_o.dat   <= c_WRF_OOB_TYPE_TX & x"000";
              src_o.adr   <= c_WRF_OOB;
              src_stb_int <= '1';
              state       <= TX_OOB2;
            end if;

          when TX_OOB2 =>
            src_o.sel <= "11";

            if( src_i.stall='0' ) then
              src_o.dat   <= cur_tx_desc.ts_id;
              src_o.adr   <= c_WRF_OOB;
              src_stb_int <= '1';
              state       <= TX_END_PACKET;
            end if;

          when TX_END_PACKET =>
            src_stb_int <= '0';
            src_o.sel   <= "11";

            if( src_i.stall='0' and ack_count = 0) then
              state     <= TX_UPDATE_DESCRIPTOR;
            end if;

          when TX_UPDATE_DESCRIPTOR =>
            src_o.cyc 							<= '0';
            txdesc_write_o          <= '1';
            txdesc_reload_current_o <= cur_tx_desc.error;
            cur_tx_desc.ready       <= '0';

            if(txdesc_write_done_i = '1') then
              txdesc_write_o <= '0';
              if(cur_tx_desc.error = '1') then
                state <= TX_ERROR;
              else
                tx_done <= '1';
                state   <= TX_REQUEST_DESCRIPTOR;
              end if;
            end if;

          when TX_ERROR =>

            if(irq_txerr_mask_i = '1') then  -- clear the error status in
                                             -- interrupt-driver mode
              irq_txerr_o <= '1';
              if(irq_txerr_ack_i = '1') then
                irq_txerr_o <= '0';
                state       <= TX_REQUEST_DESCRIPTOR;
              end if;
            end if;

            regs_o.sr_tx_error_i <= '1';
            if(regs_i.sr_tx_error_o = '1' and regs_i.sr_tx_error_load_o = '1') then  --
              -- or in status register mode
              irq_txerr_o <= '0';
              state       <= TX_REQUEST_DESCRIPTOR;
            end if;
            
        end case;
      end if;
    end if;
  end process;

  gen_rtu_valid : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        rtu_rsp_valid_o  <= '0';
        rtu_valid_int_d0 <= '0';
      else
        rtu_valid_int_d0 <= rtu_valid_int;

        if(rtu_rsp_ack_i = '1') then
          rtu_rsp_valid_o <= '0';
        elsif(rtu_valid_int = '1' and rtu_valid_int_d0 = '0') then
          rtu_rsp_valid_o <= '1';
        end if;
      end if;
    end if;
  end process;
end behavioral;
