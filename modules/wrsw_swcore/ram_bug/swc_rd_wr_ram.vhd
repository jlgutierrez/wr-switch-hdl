library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity swc_rd_wr_ram is

  generic(
    g_data_width : integer;
    g_size       : integer;
    g_use_native : boolean := false);
  port(
    clk_i   : in std_logic;
    rst_n_i : in std_logic := '1';
    we_i    : in std_logic;
    wa_i    : in std_logic_vector(f_log2_size(g_size)-1 downto 0);
    wd_i    : in std_logic_vector(g_data_width-1 downto 0);

    ra_i : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
    rd_o : out std_logic_vector(g_data_width-1 downto 0)
    );

end swc_rd_wr_ram;


architecture rtl of swc_rd_wr_ram is
  function f_slv_resize(x : std_logic_vector; len : natural) return std_logic_vector is
    variable tmp : std_logic_vector(len-1 downto 0);
  begin
    tmp                      := (others => '0');
    tmp(x'length-1 downto 0) := x;
    return tmp;
  end f_slv_resize;

  type t_ram_type is array(0 to g_size-1) of std_logic_vector(31 downto 0);
  shared variable ram : t_ram_type;


  signal rd_addr, wr_addr                                         : std_logic_vector(9 downto 0);
  signal rd_data, wr_data, wr_data_reg, rd_array, rd_data_posedge : std_logic_vector(31 downto 0);
  signal rst                                                      : std_logic;
  signal collided                                                 : std_logic;

  component buggy_ram
    port (
      clka  : IN  STD_LOGIC;
      wea   : IN  STD_LOGIC_VECTOR(0 DOWNTO 0);
      addra : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
      dina  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      clkb  : IN  STD_LOGIC;
      web   : IN  STD_LOGIC_VECTOR(0 DOWNTO 0);
      addrb : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
      dinb  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(31 DOWNTO 0));
  end component;
  
begin  -- rtl

  --rst <= not rst_n_i;

  --RAMB36E1_inst : RAMB36E1
  --  generic map (
  --    RAM_MODE                  => "SDP",            -- "SDP" or "TDP" 
  --    RDADDR_COLLISION_HWCONFIG => "PERFORMANCE",  -- "PERFORMANCE" or
  --    SIM_COLLISION_CHECK       => "ALL",            -- "DELAYED_WRITE" 
  --    -- READ_WIDTH_A/B, WRITE_WIDTH_A/B: Read/write width per port
  --    READ_WIDTH_A              => 72,  -- 0, 1, 2, 4, 9, 18,
  --                                      -- 36, or 72
  --    READ_WIDTH_B              => 72,  -- 36
  --    WRITE_WIDTH_A             => 72,  -- 0, 1, 2, 4, 9, 18, or
  --                                     -- 36
  --    WRITE_WIDTH_B             => 72,  -- 0, 1, 2, 4, 9, 18,
  --    DOA_REG                   => 0,
  --    DOB_REG                   => 0,
  --    -- 36, or 72
  --    -- RSTREG_PRIORITY_A, RSTREG_PRIORITY_B: Reset or enable priority ("RSTREG" or "REGCE")
  --    RSTREG_PRIORITY_A         => "RSTREG",
  --    RSTREG_PRIORITY_B         => "RSTREG",
  --    -- SRVAL_A, SRVAL_B: Set/reset value for output
  --    SRVAL_A                   => X"000000000",
  --    SRVAL_B                   => X"000000000",
  --    -- WriteMode: Value on output upon a write ("WRITE_FIRST", "READ_FIRST", or "NO_CHANGE")
  --    WRITE_MODE_A              => "WRITE_FIRST",
  --    WRITE_MODE_B              => "WRITE_FIRST"
  --    )
  --  port map (
  --    DOADO         => rd_data,
  --    CASCADEINA    => '0',
  --    CASCADEINB    => '0',
  --    INJECTDBITERR => '0',
  --    INJECTSBITERR => '0',
  --    ADDRARDADDR   => rd_addr,  -- 16-bit input: A port address/Read address input

  --    CLKARDCLK     => clk_i,    -- 1-bit input: A port clock/Read clock input
  --    ENARDEN       => '1',  -- 1-bit input: A port enable/Read enable input
  --    REGCEAREGCE   => '1',  -- 1-bit input: A port register enable/Register enable input
  --    RSTRAMARSTRAM => rst,             -- 1-bit input: A port set/reset input
  --    RSTREGARSTREG => rst,  -- 1-bit input: A port register set/reset input
  --    WEA           => "0000",   -- 4-bit input: A port write enable input
  --    -- Port A Data: 32-bit (each) input: Port A data
  --    DIADI         => wr_data,  -- 32-bit input: A port data/LSB data input

  --    -- Port B Address/Control Signals: 16-bit (each) input: Port B address and control signals (write port
  --    -- when RAM_MODE="SDP")
  --    ADDRBWRADDR => wr_addr,  -- 16-bit input: B port address/Write address input
  --    CLKBWRCLK   => clk_i,    -- 1-bit input: B port clock/Write clock input
  --    ENBWREN     => we_i,     -- 1-bit input: B port enable/Write enable input
  --    REGCEB      => '1',      -- 1-bit input: B port register enable input
  --    RSTRAMB     => rst,               -- 1-bit input: B port set/reset input
  --    RSTREGB     => rst,      -- 1-bit input: B port register set/reset input
  --    WEBWE       => "11111111",  -- 8-bit input: B port write enable/Write enable input
  --    -- Port B Data: 32-bit (each) input: Port B data
  --    DIBDI       => wr_data,  -- 32-bit input: B port data/MSB data input,
  --    DIPADIP     => x"0",
  --    DIPBDIP     => x"0"

  --    );



  --p_avoid_collisions : process(clk_i)
  --begin
  --  if rising_edge(clk_i) then

  --    if(ra_i = wa_i and we_i = '1') then
  --      collided <= '1';
  --    else
  --      collided <= '0';
  --    end if;
  --    wr_data_reg <= wr_data;

  --  end if;
  --end process;

  --  rd_data_posedge <= rd_data when collided = '0' else wr_data_reg;

  
--rd_o    <= rd_data(g_data_width-1 downto 0);-- when collided = '0' else wr_data_reg(g_data_width-1 downto 0);
  wr_data <= f_slv_resize(wd_i, 32);
  rd_addr <= f_slv_resize(ra_i, 10);
  wr_addr <= f_slv_resize(wa_i, 10);

  U_Buggy_RAM: buggy_ram
    port map (
      clka  => clk_i,
      wea(0)   => (we_i),
      addra => wr_addr,
      dina  => wr_data,
      clkb  => clk_i,
      web => "0",
      addrb => rd_addr,
      dinb => x"00000000",
      doutb => rd_data);

  
  p_ram : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(we_i = '1') then
        ram(to_integer(unsigned(wa_i))) := wr_data;
      end if;

      rd_array        <= ram(to_integer(unsigned(ra_i)));

    end if;
  end process;

  gen_array : if(g_use_native = false) generate
    rd_o <= rd_array(g_data_width-1 downto 0);
  end generate gen_array;

  gen_native : if(g_use_native = true) generate

    p_avoid_collisions : process(clk_i)
    begin
      if rising_edge(clk_i) then

        if(ra_i = wa_i and we_i = '1') then
          collided <= '1';
        else
          collided <= '0';
        end if;
        wr_data_reg <= wr_data;

    end if;
  end process;

  rd_o <= rd_data(g_data_width-1 downto 0) when collided = '0' else wr_data_reg(g_data_width-1 downto 0);
    
--    rd_o <= rd_data(g_data_width-1 downto 0);
  end generate gen_native;

  
end rtl;
