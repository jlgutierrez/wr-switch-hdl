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
-- Copyright (c) 2010 Tomasz Wlostowski
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
use work.endpoint_private_pkg.all;      -- dirty hack
use work.nic_wbgen2_pkg.all;


entity nic_tx_fsm is

  port (clk_sys_i : in  std_logic;
        rst_n_i   : in  std_logic;
-------------------------------------------------------------------------------
-- WRF source
-------------------------------------------------------------------------------
        src_o     : out t_wrf_source_out;
        src_i     : in  t_wrf_source_in;

-------------------------------------------------------------------------------
-- "Fake" RTU interface
-------------------------------------------------------------------------------

        rtu_dst_port_mask_o : out std_logic_vector(31 downto 0);
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

  component ep_rx_wb_master
    generic (
      g_ignore_ack : boolean);
    port (
      clk_sys_i  : in  std_logic;
      rst_n_i    : in  std_logic;
      snk_fab_i  : in  t_ep_internal_fabric;
      snk_dreq_o : out std_logic;
      src_wb_i   : in  t_wrf_source_in;
      src_wb_o   : out t_wrf_source_out);
  end component;

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
  signal tx_start_delayed : std_logic;
  signal tx_data_reg      : std_logic_vector(31 downto 0);
  signal tx_done          : std_logic;

  signal ignore_first_hword : std_logic;
  signal tx_cntr_expired    : std_logic;
  signal is_runt_frame      : std_logic;
  signal needs_padding      : std_logic;
  signal padding_size       : unsigned(7 downto 0);

  signal rtu_valid_int    : std_logic;
  signal rtu_valid_int_d0 : std_logic;

  signal fab_dreq : std_logic;
  signal fab_out  : t_ep_internal_fabric;

  signal tx_err : std_logic;
  signal default_status_reg : t_wrf_status_reg;
begin  -- behavioral


  default_status_reg.has_smac <= '1';
  default_status_reg.has_crc <= '0';
  default_status_reg.error <= '0';
  default_status_reg.is_hp <= '0';
  
  tx_err <= src_i.err or src_i.rty;

  buf_addr_o <= std_logic_vector(tx_buf_addr);

  is_runt_frame   <= '1' when (to_integer(unsigned(cur_tx_desc.len)) < 60) else '0';
  tx_cntr_expired <= '1' when (tx_remaining = 0)                           else '0';

  txdesc_new_o <= cur_tx_desc;


  U_WB_Master : ep_rx_wb_master
    generic map(
      g_ignore_ack => true)
    port map (
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      snk_fab_i  => fab_out,
      snk_dreq_o => fab_dreq,
      src_wb_i   => src_i,
      src_wb_o   => src_o);


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

        fab_out.sof     <= '0';
        fab_out.eof     <= '0';
        fab_out.dvalid  <= '0';
        fab_out.bytesel <= '0';
        fab_out.data    <= (others => '0');
        fab_out.addr    <= (others => '0');
        fab_out.error   <= '0';

        tx_done              <= '0';
        rtu_valid_int        <= '0';
        irq_txerr_o          <= '0';
        regs_o.sr_tx_error_i <= '0';

        rtu_dst_port_mask_o <= (others => '0');
        rtu_drop_o          <= '0';
        
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
              txdesc_request_next_o <= '0';
              state                 <= TX_START_PACKET;
              tx_buf_addr           <= resize(unsigned(txdesc_current_i.offset(tx_buf_addr'length+1 downto 2)), tx_buf_addr'length);
              tx_remaining          <= unsigned(txdesc_current_i.len(tx_remaining'length downto 1));
              state                 <= TX_MEM_FETCH;
              
            end if;

            -- 1 wait cycle to make sure the 1st TX word has been successfully
            -- read from the buffer
          when TX_MEM_FETCH =>
            if(txdesc_current_i.len(0) = '1') then
              tx_remaining <= tx_remaining + 1;
            end if;

            state <= TX_START_PACKET;
            
          when TX_START_PACKET =>
            regs_o.sr_tx_error_i <= '0';

            rtu_prio_o          <= (others => '0');
            rtu_dst_port_mask_o <= cur_tx_desc.dpm;
            rtu_drop_o          <= '0';
            rtu_valid_int       <= '1';

-- check if the memory is ready, read the 1st word of the payload
            if(fab_dreq = '1' and buf_grant_i = '0') then
              tx_data_reg <= buf_data_i;
              fab_out.sof <= '1';

              tx_buf_addr        <= tx_buf_addr + 1;
              ignore_first_hword <= '1';
              state              <= TX_STATUS;
              if(is_runt_frame = '1' and cur_tx_desc.pad_e = '1') then
                odd_length    <= '0';
                needs_padding <= '1';
                if(cur_tx_desc.len(0) = '1') then
                  padding_size <= 29 - unsigned(cur_tx_desc.len(padding_size'length downto 1));
                else
                  padding_size <= 30 - unsigned(cur_tx_desc.len(padding_size'length downto 1));
                end if;
              else
                odd_length    <= cur_tx_desc.len(0);
                needs_padding <= '0';
              end if;

              tx_data_reg <= f_buf_swap_endian_32(buf_data_i);
            end if;

          when TX_STATUS =>
            fab_out.sof <= '0';
            
            if(fab_dreq = '1' and buf_grant_i = '0') then
              fab_out.dvalid <= '1';
              fab_out.addr <= c_WRF_STATUS;
              fab_out.data <= f_marshall_wrf_status(default_status_reg);
              state <= TX_HWORD;
            else
              fab_out.dvalid <= '0';
            end if;
            
          when TX_HWORD =>
            rtu_valid_int <= '0';

-- generate the control value depending on the packet type, OOB and the current
-- transmission offset.
            fab_out.addr <= c_WRF_DATA;
            fab_out.data <= tx_data_reg(31 downto 16);

            if(tx_err = '1') then
              state             <= TX_UPDATE_DESCRIPTOR;
              cur_tx_desc.error <= '1';
            elsif(fab_dreq = '1') then
              if(tx_cntr_expired = '1') then
                fab_out.bytesel <= odd_length and (not needs_padding);

                if(needs_padding = '1' and padding_size /= 0) then
                  state <= TX_PAD;
                elsif(cur_tx_desc.ts_e = '1') then
                  state <= TX_OOB1;
                else
                  state <= TX_END_PACKET;
                end if;
                fab_out.dvalid <= '1';
              else
                
                if(ignore_first_hword = '1') then
                  ignore_first_hword <= '0';
                  fab_out.dvalid     <= '0';
                  tx_remaining       <= tx_remaining - 1;
                else
                  fab_out.dvalid <= '1';
                  tx_remaining   <= tx_remaining - 1;
                end if;

                state <= TX_LWORD;
              end if;
              
            else
              fab_out.dvalid <= '0';
            end if;

            fab_out.sof <= '0';

-- check for errors


          when TX_LWORD =>

            fab_out.addr <= c_WRF_DATA;
            fab_out.data <= tx_data_reg (15 downto 0);

-- the TX fabric is ready, the memory is ready and we haven't reached the end
-- of the packet yet:

            if(tx_err = '1') then
              state             <= TX_UPDATE_DESCRIPTOR;
              cur_tx_desc.error <= '1';
            elsif(fab_dreq = '1' and buf_grant_i = '0') then
              if(tx_cntr_expired = '0') then
                fab_out.dvalid <= '1';

                tx_data_reg <= f_buf_swap_endian_32(buf_data_i);

                tx_remaining <= tx_remaining - 1;
                tx_buf_addr  <= tx_buf_addr + 1;
                state        <= TX_HWORD;

-- We're at the end of the packet. Generate an end-of-packet condition on the
-- fabric I/F
              else
                
                fab_out.bytesel <= odd_length and (not needs_padding);
                fab_out.dvalid  <= '1';
                if(needs_padding = '1' and padding_size /= 0) then
                  state <= TX_PAD;

                elsif(cur_tx_desc.ts_e = '1') then
                  state <= TX_OOB1;
                else
                  state       <= TX_END_PACKET;
                  fab_out.eof <= '0';
                end if;
              end if;
            else
-- the fabric is not ready, don't send anything
              fab_out.dvalid <= '0';
            end if;

          when TX_PAD =>

            if(tx_err = '1') then
              state             <= TX_UPDATE_DESCRIPTOR;
              cur_tx_desc.error <= '1';
            elsif(fab_dreq = '1') then
              fab_out.data   <= x"0000";
              fab_out.addr   <= c_WRF_DATA;
              fab_out.dvalid <= '1';

              padding_size <= padding_size - 1;

              if(padding_size = 0) then
                fab_out.dvalid <= '0';
                if(cur_tx_desc.ts_e = '1')then
                  state <= TX_OOB1;
                else
                  fab_out.eof <= '0';
                  state       <= TX_END_PACKET;
                end if;
              end if;
            else
              fab_out.dvalid <= '0';
            end if;


          when TX_OOB1 =>
            fab_out.bytesel <= '0';

            if(fab_dreq = '1') then
              fab_out.data   <= c_WRF_OOB_TYPE_TX & x"000";
              fab_out.addr   <= c_WRF_OOB;
              fab_out.dvalid <= '1';
              fab_out.eof    <= '0';
              state          <= TX_OOB2;
            end if;

          when TX_OOB2 =>
            fab_out.bytesel <= '0';

            if(fab_dreq = '1') then
              fab_out.data   <= cur_tx_desc.ts_id;
              fab_out.addr   <= c_WRF_OOB;
              fab_out.dvalid <= '1';
              fab_out.eof    <= '0';
              state          <= TX_END_PACKET;
            end if;

          when TX_END_PACKET =>
            fab_out.dvalid  <= '0';
            fab_out.bytesel <= '0';

            if(fab_dreq = '1') then
              fab_out.eof <= '1';
              state       <= TX_UPDATE_DESCRIPTOR;
            end if;

          when TX_UPDATE_DESCRIPTOR =>
            fab_out.eof             <= '0';
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
