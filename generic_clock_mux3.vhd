-------------------------------------------------------------------------------
-- Title      : Generic platform-independent 4-input clock mux
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : generic_clock_mux.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-06-21
-- Last update: 2010-06-21
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 4 input clock multiplexer - a wrapper for ALTCLKCTRL component.
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-06-21  1.0      twlostow        Created
-------------------------------------------------------------------------------

 LIBRARY cycloneiii;
 USE cycloneiii.all;

--synthesis_resources = clkctrl 1 reg 3 
 LIBRARY ieee;
 USE ieee.std_logic_1164.all;

 ENTITY  clkmux2_altera_altclkctrl_0fi IS 
	 PORT 
	 ( 
		 clkselect	:	IN  STD_LOGIC_VECTOR (1 DOWNTO 0) := (OTHERS => '0');
		 ena	:	IN  STD_LOGIC := '1';
		 inclk	:	IN  STD_LOGIC_VECTOR (3 DOWNTO 0) := (OTHERS => '0');
		 outclk	:	OUT  STD_LOGIC
	 ); 
 END clkmux2_altera_altclkctrl_0fi;

 ARCHITECTURE RTL OF clkmux2_altera_altclkctrl_0fi IS

	 ATTRIBUTE synthesis_clearbox : natural;
	 ATTRIBUTE synthesis_clearbox OF RTL : ARCHITECTURE IS 2;
	 ATTRIBUTE ALTERA_ATTRIBUTE : string;
	 SIGNAL	 ena_reg	:	STD_LOGIC
	 -- synopsys translate_off
	  := '1'
	 -- synopsys translate_on
	 ;
	 ATTRIBUTE ALTERA_ATTRIBUTE OF ena_reg : SIGNAL IS "POWER_UP_LEVEL=HIGH";

	 SIGNAL  wire_ena_reg_w_lg_q6w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL	 select_reg	:	STD_LOGIC_VECTOR(1 DOWNTO 0)
	 -- synopsys translate_off
	  := (OTHERS => '0')
	 -- synopsys translate_on
	 ;
	 ATTRIBUTE ALTERA_ATTRIBUTE OF select_reg : SIGNAL IS "POWER_UP_LEVEL=LOW";

	 SIGNAL  wire_select_reg_w_q_range12w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_select_reg_w_q_range17w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_clkctrl1_w_lg_outclk5w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_clkctrl1_clkselect	:	STD_LOGIC_VECTOR (1 DOWNTO 0);
	 SIGNAL  wire_vcc	:	STD_LOGIC;
	 SIGNAL  wire_clkctrl1_outclk	:	STD_LOGIC;
	 SIGNAL  wire_w_lg_w_select_enable_wire_range15w20w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_w_lg_w_clkselect_wire_range13w14w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_w_lg_w_clkselect_wire_range18w19w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  clkselect_wire :	STD_LOGIC_VECTOR (1 DOWNTO 0);
	 SIGNAL  inclk_wire :	STD_LOGIC_VECTOR (3 DOWNTO 0);
	 SIGNAL  select_enable_wire :	STD_LOGIC_VECTOR (1 DOWNTO 0);
	 SIGNAL  wire_w_clkselect_wire_range13w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_w_clkselect_wire_range3w	:	STD_LOGIC_VECTOR (1 DOWNTO 0);
	 SIGNAL  wire_w_clkselect_wire_range18w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 SIGNAL  wire_w_select_enable_wire_range15w	:	STD_LOGIC_VECTOR (0 DOWNTO 0);
	 COMPONENT  cycloneiii_clkctrl
	 GENERIC 
	 (
		clock_type	:	STRING;
		ena_register_mode	:	STRING := "falling edge";
		lpm_type	:	STRING := "cycloneiii_clkctrl"
	 );
	 PORT
	 ( 
		clkselect	:	IN STD_LOGIC_VECTOR(1 DOWNTO 0);
		ena	:	IN STD_LOGIC;
		inclk	:	IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		outclk	:	OUT STD_LOGIC
	 ); 
	 END COMPONENT;
 BEGIN

	wire_vcc <= '1';
	wire_w_lg_w_select_enable_wire_range15w20w(0) <= wire_w_select_enable_wire_range15w(0) OR wire_w_lg_w_clkselect_wire_range18w19w(0);
	wire_w_lg_w_clkselect_wire_range13w14w(0) <= wire_w_clkselect_wire_range13w(0) XOR wire_select_reg_w_q_range12w(0);
	wire_w_lg_w_clkselect_wire_range18w19w(0) <= wire_w_clkselect_wire_range18w(0) XOR wire_select_reg_w_q_range17w(0);
	clkselect_wire <= ( clkselect);
	inclk_wire <= ( inclk);
	outclk <= (wire_clkctrl1_outclk AND ena_reg);
	select_enable_wire <= ( wire_w_lg_w_select_enable_wire_range15w20w & wire_w_lg_w_clkselect_wire_range13w14w);
	wire_w_clkselect_wire_range13w(0) <= clkselect_wire(0);
	wire_w_clkselect_wire_range3w <= clkselect_wire(1 DOWNTO 0);
	wire_w_clkselect_wire_range18w(0) <= clkselect_wire(1);
	wire_w_select_enable_wire_range15w(0) <= select_enable_wire(0);
	PROCESS (wire_clkctrl1_outclk)
	BEGIN
		IF (wire_clkctrl1_outclk = '0' AND wire_clkctrl1_outclk'event) THEN ena_reg <= (ena AND (NOT select_enable_wire(1)));
		END IF;
	END PROCESS;
	PROCESS (wire_clkctrl1_outclk)
	BEGIN
		IF (wire_clkctrl1_outclk = '0' AND wire_clkctrl1_outclk'event) THEN 
			IF (ena_reg = '0') THEN select_reg <= wire_w_clkselect_wire_range3w;
			END IF;
		END IF;
	END PROCESS;
	wire_select_reg_w_q_range12w(0) <= select_reg(0);
	wire_select_reg_w_q_range17w(0) <= select_reg(1);
	wire_clkctrl1_w_lg_outclk5w(0) <= NOT wire_clkctrl1_outclk;
	wire_clkctrl1_clkselect <= ( select_reg);
	clkctrl1 :  cycloneiii_clkctrl
	  GENERIC MAP (
		clock_type => "Global Clock"
	  )
	  PORT MAP ( 
		clkselect => wire_clkctrl1_clkselect,
		ena => wire_vcc,
		inclk => inclk_wire,
		outclk => wire_clkctrl1_outclk
	  );

 END RTL; --clkmux2_altera_altclkctrl_0fi
--VALID FILE


LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY clkmux2_altera IS
	PORT
	(
		clkselect		: IN STD_LOGIC  := '0';
		inclk0x		: IN STD_LOGIC ;
		inclk1x		: IN STD_LOGIC ;
		outclk		: OUT STD_LOGIC 
	);
END clkmux2_altera;


ARCHITECTURE RTL OF clkmux2_altera IS

	ATTRIBUTE synthesis_clearbox: natural;
	ATTRIBUTE synthesis_clearbox OF RTL: ARCHITECTURE IS 2;
	ATTRIBUTE clearbox_macroname: string;
	ATTRIBUTE clearbox_macroname OF RTL: ARCHITECTURE IS "altclkctrl";
	ATTRIBUTE clearbox_defparam: string;
	ATTRIBUTE clearbox_defparam OF RTL: ARCHITECTURE IS "ena_register_mode=falling edge;intended_device_family=Cyclone III;use_glitch_free_switch_over_implementation=ON;clock_type=Global Clock;";
	SIGNAL sub_wire0	: STD_LOGIC ;
	SIGNAL sub_wire1	: STD_LOGIC ;
	SIGNAL sub_wire2	: STD_LOGIC ;
	SIGNAL sub_wire3	: STD_LOGIC_VECTOR (3 DOWNTO 0);
	SIGNAL sub_wire4	: STD_LOGIC ;
	SIGNAL sub_wire5_bv	: BIT_VECTOR (1 DOWNTO 0);
	SIGNAL sub_wire5	: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL sub_wire6	: STD_LOGIC ;
	SIGNAL sub_wire7	: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL sub_wire8_bv	: BIT_VECTOR (0 DOWNTO 0);
	SIGNAL sub_wire8	: STD_LOGIC_VECTOR (0 DOWNTO 0);



	COMPONENT clkmux2_altera_altclkctrl_0fi
	PORT (
			ena	: IN STD_LOGIC ;
			outclk	: OUT STD_LOGIC ;
			inclk	: IN STD_LOGIC_VECTOR (3 DOWNTO 0);
			clkselect	: IN STD_LOGIC_VECTOR (1 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	sub_wire1    <= '1';
	sub_wire5_bv(1 DOWNTO 0) <= "00";
	sub_wire5    <= To_stdlogicvector(sub_wire5_bv);
	sub_wire8_bv(0 DOWNTO 0) <= "0";
	sub_wire8    <= To_stdlogicvector(sub_wire8_bv);
	sub_wire4    <= inclk1x;
	outclk    <= sub_wire0;
	sub_wire2    <= inclk0x;
	sub_wire3    <= sub_wire5(1 DOWNTO 0) & sub_wire4 & sub_wire2;
	sub_wire6    <= clkselect;
	sub_wire7    <= sub_wire8(0 DOWNTO 0) & sub_wire6;

	clkmux2_altera_altclkctrl_0fi_component : clkmux2_altera_altclkctrl_0fi
	PORT MAP (
		ena => sub_wire1,
		inclk => sub_wire3,
		clkselect => sub_wire7,
		outclk => sub_wire0
	);



END RTL;

library cycloneiii;
use cycloneiii.all;

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.platform_specific.all;


entity generic_clock_mux3 is
  
  port (
-- clock select
    clk_sel_i : in std_logic_vector(1 downto 0);

-- clock inputs
    inclk0_i : in std_logic;
    inclk1_i : in std_logic;
    inclk2_i : in std_logic;

-- clock MUX output
    outclk_o : out std_logic
    );

end generic_clock_mux3;


architecture rtl of generic_clock_mux3 is

  component clkmux2_altera
    port (
      clkselect : IN  STD_LOGIC := '0';
      inclk0x   : IN  STD_LOGIC;
      inclk1x   : IN  STD_LOGIC;
      outclk    : OUT STD_LOGIC);
  end component;

  signal clk_01_muxed : std_logic;
  
begin

  mux01: clkmux2_altera
    port map (
      clkselect => clk_sel_i(1),
      inclk0x   => inclk0_i,
      inclk1x   => inclk1_i,
      outclk    => outclk_o);

  
end rtl;
