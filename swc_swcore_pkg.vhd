library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

package swc_swcore_pkg is


-- number of switch ports
  constant c_swc_num_ports       : integer := 11;
-- size of the packet memory in words (1 word = 1 ctrl + data sequence)
  constant c_swc_packet_mem_size : integer := 65536;

  constant c_swc_packet_mem_multiply : integer := 16;
  constant c_swc_data_width          : integer := 16;
  constant c_swc_ctrl_width          : integer := 4; --16;
  constant c_swc_page_size           : integer := 64;

  constant c_swc_output_fifo_size    : integer := 16;
  constant c_swc_output_prio_num     : integer := 8;
  
  constant c_swc_max_pck_size        : integer := 10 * 1024; -- 10 kB
  

  -- 
  constant c_swc_num_ports_width       : integer := integer(CEIL(LOG2(real(c_swc_num_ports-1))));
  constant c_swc_packet_mem_num_pages  : integer := (c_swc_packet_mem_size / c_swc_page_size);
  constant c_swc_page_addr_width       : integer := integer(CEIL(LOG2(real(c_swc_packet_mem_num_pages-1))));
  constant c_swc_usecount_width        : integer := integer(CEIL(LOG2(real(c_swc_num_ports-1))));
  constant c_swc_page_offset_width     : integer := integer(CEIL(LOG2(real(c_swc_page_size / c_swc_packet_mem_multiply))));
  constant c_swc_packet_mem_addr_width : integer := c_swc_page_addr_width + c_swc_page_offset_width;
  constant c_swc_pump_width            : integer := c_swc_data_width + c_swc_ctrl_width;

  constant c_swc_output_fifo_addr_width : integer := integer(CEIL(LOG2(real(c_swc_output_fifo_size-1))));
  constant c_swc_output_prio_num_width  : integer := integer(CEIL(LOG2(real(c_swc_output_prio_num -1)))); 
  
  constant c_swc_max_pck_size_width     : integer := integer(CEIL(LOG2(real(c_swc_max_pck_size -1))));-- 14 bits

  -- TODO: probably need later to use the global constant
  constant c_swc_prio_width : integer := 3;

  type t_slv_array is array(integer range <>, integer range <>) of std_logic;

-- type declarations for memory input/output registers in data pump
  subtype t_pump_entry is std_logic_vector(c_swc_pump_width-1 downto 0);
  type t_pump_reg is array (c_swc_packet_mem_multiply-1 downto 0) of t_pump_entry;

  component swc_prio_encoder
    generic (
      g_num_inputs  : integer range 2 to 64;
      g_output_bits : integer range 1 to 6);
    port (
      in_i     : in  std_logic_vector(g_num_inputs-1 downto 0);
      out_o    : out std_logic_vector(g_output_bits-1 downto 0);
      onehot_o : out std_logic_vector(g_num_inputs-1 downto 0);
      mask_o   : out std_logic_vector(g_num_inputs-1 downto 0);
      zero_o   : out std_logic);
  end component;

  component swc_page_allocator
    generic (
      g_num_pages      : integer;
      g_page_addr_bits : integer;
      g_use_count_bits : integer);
    port (
      clk_i          : in  std_logic;
      rst_n_i        : in  std_logic;
      alloc_i        : in  std_logic;
      free_i         : in  std_logic;
      force_free_i   : in std_logic;
      set_usecnt_i   : in std_logic;
      usecnt_i       : in  std_logic_vector(g_use_count_bits-1 downto 0);
      pgaddr_i       : in  std_logic_vector(g_page_addr_bits -1 downto 0);
      pgaddr_o       : out std_logic_vector(g_page_addr_bits -1 downto 0);
      pgaddr_valid_o : out std_logic;
      idle_o         : out std_logic;
      done_o         : out std_logic;
      nomem_o        : out std_logic);
  end component;

  component swc_rr_arbiter
    generic (
      g_num_ports      : natural;
      g_num_ports_log2 : natural);
    port (
      rst_n_i       : in  std_logic;
      clk_i         : in  std_logic;
      next_i        : in  std_logic;
      request_i     : in  std_logic_vector(g_num_ports -1 downto 0);
      grant_o       : out std_logic_vector(g_num_ports_log2 - 1 downto 0);
      grant_valid_o : out std_logic);
  end component;

  component swc_packet_mem_write_pump
    port (
      clk_i               : in  std_logic;
      rst_n_i             : in  std_logic;
      pgaddr_i            : in  std_logic_vector(c_swc_page_addr_width-1 downto 0);
      pgreq_i             : in  std_logic;
      pgend_o             : out std_logic;
      pckstart_i          : in std_logic;
      drdy_i              : in  std_logic;
      full_o              : out std_logic;
      flush_i             : in  std_logic;
      ll_addr_o           : out std_logic_vector(c_swc_page_addr_width -1 downto 0);
      ll_data_o           : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      ll_wr_req_o         : out std_logic;
      ll_wr_done_i        : in std_logic;
      sync_i              : in  std_logic;
      addr_o              : out std_logic_vector(c_swc_packet_mem_addr_width -1 downto 0);
      d_i                 : in  std_logic_vector(c_swc_pump_width -1 downto 0);
      q_o                 : out std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply - 1 downto 0);
      we_o                : out std_logic);
  end component;

  component swc_packet_mem_read_pump
    port (
      clk_i               : in  std_logic;
      rst_n_i             : in  std_logic;
      pgreq_i             : in  std_logic;
      pgaddr_i            : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      pgend_o             : out std_logic;
      pckend_o            : out std_logic;
      drdy_o              : out std_logic;
      dreq_i              : in  std_logic;
      sync_read_i         : in  std_logic;
      ll_read_addr_o      : out std_logic_vector(c_swc_page_addr_width -1 downto 0);
      ll_read_data_i      : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      ll_read_req_o       : out std_logic;
      ll_read_valid_data_i: in  std_logic;
      sync_i              : in  std_logic;
      d_o                 : out std_logic_vector(c_swc_pump_width - 1 downto 0);
      addr_o              : out std_logic_vector(c_swc_packet_mem_addr_width - 1 downto 0);
      q_i                 : in  std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply -1 downto 0));
  end component;
  
  component swc_multiport_linked_list is
    port (
      rst_n_i               : in  std_logic;
      clk_i                 : in  std_logic;

      write_i               : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      write_done_o          : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      write_addr_i          : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      write_data_i          : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      
      
      free_i                : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      free_done_o           : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      free_addr_i           : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      
      
      read_pump_read_i      : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      read_pump_read_done_o : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      read_pump_addr_i      : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
            
      free_pck_read_i       : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      free_pck_read_done_o  : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      free_pck_addr_i       : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      
      data_o                : out std_logic_vector(c_swc_page_addr_width - 1 downto 0)
      );
  
  end component;
  
  component swc_input_block is
    port (
      clk_i   : in std_logic;
      rst_n_i : in std_logic;
  -------------------------------------------------------------------------------
  -- Fabric I/F  
  ------------------------------------------------------------------------------
      tx_sof_p1_i   : in  std_logic;
      tx_eof_p1_i   : in  std_logic;
      tx_data_i     : in  std_logic_vector(c_swc_data_width - 1 downto 0);
      tx_ctrl_i     : in  std_logic_vector(c_swc_ctrl_width - 1 downto 0);
      tx_valid_i    : in  std_logic;
      tx_bytesel_i  : in  std_logic;
      tx_dreq_o     : out std_logic;
      tx_abort_p1_i : in  std_logic;
      tx_rerror_p1_i : in  std_logic;
  -------------------------------------------------------------------------------
  -- I/F with Page allocator (MMU)
  -------------------------------------------------------------------------------    
      mmu_page_alloc_req_o  : out  std_logic;
      mmu_page_alloc_done_i : in std_logic;
      mmu_pageaddr_i : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      mmu_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      mmu_force_free_o   : out std_logic;
      mmu_force_free_done_i : in std_logic;
      mmu_force_free_addr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      mmu_set_usecnt_o   : out std_logic;
      mmu_set_usecnt_done_i  : in  std_logic;
      mmu_usecnt_o       : out  std_logic_vector(c_swc_usecount_width - 1 downto 0);
      mmu_nomem_i         : in std_logic;
  -------------------------------------------------------------------------------
  -- I/F with Routing Table Unit (RTU)
  -------------------------------------------------------------------------------      
      rtu_rsp_valid_i     : in std_logic;
      rtu_rsp_ack_o       : out std_logic;
      rtu_dst_port_mask_i : in std_logic_vector(c_swc_num_ports  - 1 downto 0);
      rtu_drop_i          : in std_logic;
      rtu_prio_i          : in std_logic_vector(c_swc_prio_width - 1 downto 0);
  -------------------------------------------------------------------------------
  -- I/F with Multiport Memory (MPU)
  -------------------------------------------------------------------------------    
      mpm_pckstart_o : out  std_logic;
      mpm_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      mpm_pagereq_o : out std_logic;
      mpm_pageend_i  : in std_logic;
      mpm_data_o  : out  std_logic_vector(c_swc_data_width - 1 downto 0);
      mpm_ctrl_o  : out  std_logic_vector(c_swc_ctrl_width - 1 downto 0);
      mpm_drdy_o  : out  std_logic;
      mpm_full_i  : in std_logic;
      mpm_flush_o : out  std_logic;    
  -------------------------------------------------------------------------------
  -- I/F with Page Transfer Arbiter (PTA)
  -------------------------------------------------------------------------------     
      pta_transfer_pck_o : out  std_logic;
      pta_transfer_ack_i : in   std_logic;
      pta_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      pta_mask_o     : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
      pta_pck_size_o : out  std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
      pta_prio_o     : out  std_logic_vector(c_swc_prio_width - 1 downto 0)
      
      );
  end component;
  
  
  component swc_multiport_page_allocator is
    port (
      rst_n_i             : in std_logic;
      clk_i               : in std_logic;
      alloc_i             : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      free_i              : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      force_free_i        : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      set_usecnt_i        : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      alloc_done_o        : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      free_done_o         : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      force_free_done_o   : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      set_usecnt_done_o   : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      pgaddr_free_i       : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      pgaddr_force_free_i : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      pgaddr_usecnt_i     : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      usecnt_i            : in  std_logic_vector(c_swc_num_ports * c_swc_usecount_width - 1 downto 0);
      pgaddr_alloc_o      : out std_logic_vector(c_swc_page_addr_width-1 downto 0);
      nomem_o             : out std_logic
      );
  
  end component;
  
  component swc_packet_mem is
    port (
      clk_i   : in std_logic;
      rst_n_i : in std_logic;
      ------------------- writing to the shared memory --------------------------
      wr_pagereq_i  : in  std_logic_vector(c_swc_num_ports-1 downto 0);
      wr_pckstart_i : in  std_logic_vector(c_swc_num_ports-1 downto 0);
      wr_pageaddr_i : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      wr_pageend_o  : out std_logic_vector(c_swc_num_ports -1 downto 0);
      wr_ctrl_i  : in  std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
      wr_data_i  : in  std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
      wr_drdy_i  : in  std_logic_vector(c_swc_num_ports-1 downto 0);
      wr_full_o  : out std_logic_vector(c_swc_num_ports-1 downto 0);
      wr_flush_i : in  std_logic_vector(c_swc_num_ports-1 downto 0);
      ------------------- reading from the shared memory --------------------------
      rd_pagereq_i   : in  std_logic_vector(c_swc_num_ports-1 downto 0);
      rd_pageaddr_i  : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      rd_pageend_o   : out std_logic_vector(c_swc_num_ports -1 downto 0);
      rd_pckend_o    : out  std_logic_vector(c_swc_num_ports-1 downto 0);
      rd_drdy_o      : out std_logic_vector(c_swc_num_ports -1 downto 0);
      rd_dreq_i      : in  std_logic_vector(c_swc_num_ports -1 downto 0);
      rd_sync_read_i : in std_logic_vector(c_swc_num_ports -1 downto 0);
      rd_data_o      : out std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
      rd_ctrl_o      : out std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
      
--      pa_free_o              : out  std_logic_vector(c_swc_num_ports -1 downto 0);
--      pa_free_done_i         : in   std_logic_vector(c_swc_num_ports -1 downto 0);
--      pa_free_pgaddr_o       : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      
      write_o               : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
      write_done_i          : in   std_logic_vector(c_swc_num_ports - 1 downto 0);
      write_addr_o          : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      write_data_o          : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      read_pump_read_o      : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
      read_pump_read_done_i : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      read_pump_addr_o      : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      data_i                : in   std_logic_vector(c_swc_page_addr_width - 1 downto 0)
      );
      
    end component;
  
  
  component swc_pck_transfer_input is
    port (
      clk_i              : in std_logic;
      rst_n_i            : in std_logic;
      
      pto_transfer_pck_o : out  std_logic;
      pto_pageaddr_o     : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      pto_output_mask_o  : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
      pto_read_mask_i    : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      pto_prio_o         : out  std_logic_vector(c_swc_prio_width - 1 downto 0);
      pto_pck_size_o     : out  std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
      
      ib_transfer_pck_i  : in  std_logic;
      ib_pageaddr_i      : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      ib_mask_i          : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      ib_prio_i          : in  std_logic_vector(c_swc_prio_width - 1 downto 0);
      ib_pck_size_i      : in  std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
      ib_transfer_ack_o  : out std_logic;
      ib_busy_o          : out std_logic
      
      );
  end component;  
  
  
  component swc_pck_transfer_output is
    port (
      clk_i                    : in  std_logic;
      rst_n_i                  : in  std_logic;
      
      ob_transfer_data_valid_o : out std_logic;
      ob_pageaddr_o            : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      ob_prio_o                : out std_logic_vector(c_swc_prio_width - 1 downto 0);
      ob_pck_size_o            : out std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
      ob_transfer_data_ack_i   : in  std_logic;
      
      pti_transfer_data_valid_i: in  std_logic;
      pti_transfer_data_ack_o  : out std_logic;
      pti_pageaddr_i           : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      pti_prio_i               : in  std_logic_vector(c_swc_prio_width - 1 downto 0);
      pti_pck_size_i           : in  std_logic_vector(c_swc_max_pck_size_width - 1 downto 0)
      
      );
  end component;
  
  component swc_pck_transfer_arbiter is
    port (
      clk_i              : in  std_logic;
      rst_n_i            : in  std_logic;
      
      ob_data_valid_o    : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      ob_ack_i           : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      ob_pageaddr_o      : out std_logic_vector(c_swc_num_ports * c_swc_page_addr_width    - 1 downto 0);
      ob_prio_o          : out std_logic_vector(c_swc_num_ports * c_swc_prio_width         - 1 downto 0);
      ob_pck_size_o      : out std_logic_vector(c_swc_num_ports * c_swc_max_pck_size_width - 1 downto 0);
      
      ib_transfer_pck_i  : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
      ib_transfer_ack_o  : out std_logic_vector(c_swc_num_ports - 1 downto 0);
      ib_busy_o          : out std_logic_vector(c_swc_num_ports - 1 downto 0);  
      ib_pageaddr_i      : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width    - 1 downto 0);
      ib_mask_i          : in  std_logic_vector(c_swc_num_ports * c_swc_num_ports          - 1 downto 0);
      ib_prio_i          : in  std_logic_vector(c_swc_num_ports * c_swc_prio_width         - 1 downto 0);
      ib_pck_size_i      : in  std_logic_vector(c_swc_num_ports * c_swc_max_pck_size_width - 1 downto 0)
      );  
  end component;
  
  component swc_ob_prio_queue is
    port (
      clk_i             : in   std_logic;
      rst_n_i           : in   std_logic;
      write_i           : in   std_logic;
      read_i            : in   std_logic;
      not_full_o        : out  std_logic;
      not_empty_o       : out  std_logic;
      wr_en_o           : out  std_logic;
      wr_addr_o         : out  std_logic_vector(c_swc_output_fifo_addr_width - 1 downto 0);
      rd_addr_o         : out  std_logic_vector(c_swc_output_fifo_addr_width - 1 downto 0)
      );
  end component;
  
  component swc_output_block is
    port (
      clk_i                     : in std_logic;
      rst_n_i                   : in std_logic;
      pta_transfer_data_valid_i : in   std_logic;
      pta_pageaddr_i            : in   std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      pta_prio_i                : in   std_logic_vector(c_swc_prio_width - 1 downto 0);
      pta_pck_size_i            : in   std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
      pta_transfer_data_ack_o   : out  std_logic;
      mpm_pgreq_o               : out std_logic;
      mpm_pgaddr_o              : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      mpm_pckend_i              : in  std_logic;
      mpm_pgend_i               : in  std_logic;
      mpm_drdy_i                : in  std_logic;
      mpm_dreq_o                : out std_logic;
      mpm_data_i                : in  std_logic_vector(c_swc_data_width - 1 downto 0);
      mpm_ctrl_i                : in  std_logic_vector(c_swc_ctrl_width - 1 downto 0); 
      ppfm_free_o            : out  std_logic;
      ppfm_free_done_i       : in   std_logic;
      ppfm_free_pgaddr_o     : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      rx_sof_p1_o               : out std_logic;
      rx_eof_p1_o               : out std_logic;
      rx_dreq_i                 : in  std_logic;
      rx_ctrl_o                 : out std_logic_vector(c_swc_ctrl_width - 1 downto 0);
      rx_data_o                 : out std_logic_vector(c_swc_data_width - 1 downto 0);
      rx_valid_o                : out std_logic;
      rx_bytesel_o              : out std_logic;
      rx_idle_o                 : out std_logic;
      rx_rerror_p1_o            : out std_logic;
      rx_terror_p1_i            : in  std_logic;
      rx_tabort_p1_i            : in  std_logic
      );  
  end component;

component  swc_multiport_pck_pg_free_module is
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    ib_force_free_i         : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    ib_force_free_done_o    : out std_logic_vector(c_swc_num_ports-1 downto 0);
    ib_force_free_pgaddr_i  : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);

    ob_free_i               : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    ob_free_done_o          : out std_logic_vector(c_swc_num_ports-1 downto 0);
    ob_free_pgaddr_i        : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    ll_read_addr_o          : out std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0);
    --ll_read_data_i          : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    ll_read_data_i          : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    ll_read_req_o           : out std_logic_vector(c_swc_num_ports-1 downto 0);
    ll_read_valid_data_i    : in  std_logic_vector(c_swc_num_ports-1 downto 0);

    mmu_free_o              : out std_logic_vector(c_swc_num_ports-1 downto 0);
    mmu_free_done_i         : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    mmu_free_pgaddr_o       : out std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0);
    
    mmu_force_free_o        : out std_logic_vector(c_swc_num_ports-1 downto 0);
    mmu_force_free_done_i   : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    mmu_force_free_pgaddr_o : out std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0)
    );
 end component;
  

  component swc_pck_pg_free_module is
  
    port (
      clk_i   : in std_logic;
      rst_n_i : in std_logic;
  
      ib_force_free_i         : in  std_logic;
      ib_force_free_done_o    : out std_logic;
      ib_force_free_pgaddr_i  : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
      ob_free_i               : in  std_logic;
      ob_free_done_o          : out std_logic;
      ob_free_pgaddr_i        : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      
      ll_read_addr_o          : out std_logic_vector(c_swc_page_addr_width -1 downto 0);
      ll_read_data_i          : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      ll_read_req_o           : out std_logic;
      ll_read_valid_data_i    : in  std_logic;
  
      mmu_free_o              : out std_logic;
      mmu_free_done_i         : in  std_logic;
      mmu_free_pgaddr_o       : out std_logic_vector(c_swc_page_addr_width -1 downto 0);
          
      mmu_force_free_o        : out std_logic;
      mmu_force_free_done_i   : in  std_logic;
      mmu_force_free_pgaddr_o : out std_logic_vector(c_swc_page_addr_width -1 downto 0)
  
         
      );
  end component;
  
end swc_swcore_pkg;






package body swc_swcore_pkg is




end swc_swcore_pkg;
