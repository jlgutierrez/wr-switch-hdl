/*
 * Trivial pll programmer using an spi controoler.
 * PLL is AD9516, SPI is opencores
 * Tomasz Wlostowski, Alessandro Rubini, 2011, for CERN.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "board.h"
#include "timer.h"
#include "gpio.h"

#include "ad9516.h"

#ifndef ARRAY_SIZE
#define ARRAY_SIZE(a) (sizeof(a)/sizeof(a[0]))
#endif

struct ad9516_reg {
	uint16_t reg;
	uint8_t val;
};

#include "ad9516_config.h"

/*
 * SPI stuff, used by later code
 */

#define SPI_REG_RX0	0
#define SPI_REG_TX0	0
#define SPI_REG_RX1	4
#define SPI_REG_TX1	4
#define SPI_REG_RX2	8
#define SPI_REG_TX2	8
#define SPI_REG_RX3	12
#define SPI_REG_TX3	12

#define SPI_REG_CTRL	16
#define SPI_REG_DIVIDER	20
#define SPI_REG_SS	24

#define SPI_CTRL_ASS		(1<<13)
#define SPI_CTRL_IE		(1<<12)
#define SPI_CTRL_LSB		(1<<11)
#define SPI_CTRL_TXNEG		(1<<10)
#define SPI_CTRL_RXNEG		(1<<9)
#define SPI_CTRL_GO_BSY		(1<<8)
#define SPI_CTRL_CHAR_LEN(x)	((x) & 0x7f)

#define GPIO_PLL_RESET_N 1
#define GPIO_SYS_CLK_SEL 0
#define GPIO_PERIPH_RESET_N 3

#define CS_PLL	0 /* AD9516 on SPI CS0 */

static void *oc_spi_base;

int oc_spi_init(void *base_addr)
{
	oc_spi_base = base_addr;

	writel(100, oc_spi_base + SPI_REG_DIVIDER);
	return 0;
}

int oc_spi_txrx(int ss, int nbits, uint32_t in, uint32_t *out)
{
	uint32_t rval;

	if (!out)
		out = &rval;

	writel(SPI_CTRL_ASS | SPI_CTRL_CHAR_LEN(nbits)
		     | SPI_CTRL_TXNEG,
		     oc_spi_base + SPI_REG_CTRL);

	writel(in, oc_spi_base + SPI_REG_TX0);
	writel((1 << ss), oc_spi_base + SPI_REG_SS);
	writel(SPI_CTRL_ASS | SPI_CTRL_CHAR_LEN(nbits)
		     | SPI_CTRL_TXNEG | SPI_CTRL_GO_BSY,
		     oc_spi_base + SPI_REG_CTRL);

	while(readl(oc_spi_base + SPI_REG_CTRL) & SPI_CTRL_GO_BSY)
		;
	*out = readl(oc_spi_base + SPI_REG_RX0);
	return 0;
}

/*
 * AD9516 stuff, using SPI, used by later code.
 * "reg" is 12 bits, "val" is 8 bits, but both are better used as int
 */

static void ad9516_write_reg(int reg, int val)
{
	oc_spi_txrx(CS_PLL, 24, (reg << 8) | val, NULL);
}

static int ad9516_read_reg(int reg)
{
	uint32_t rval;
	oc_spi_txrx(CS_PLL, 24, (reg << 8) | (1 << 23), &rval);
	return rval & 0xff;
}



static void ad9516_load_regset(const struct ad9516_reg *regs, int n_regs, int commit)
{
	int i;
	for(i=0; i<n_regs; i++)
		ad9516_write_reg(regs[i].reg, regs[i].val);
		
	if(commit)
		ad9516_write_reg(0x232, 1);
}


static void ad9516_wait_lock()
{
	while ((ad9516_read_reg(0x1f) & 1) == 0);
}

int ad9516_init()
{
	TRACE("Initializing AD9516 PLL...\n");

	oc_spi_init((void *)BASE_SPI);

	gpio_out(GPIO_SYS_CLK_SEL, 0); /* switch to the standby reference clock, since the PLL is off after reset */

	/* reset the PLL */
	gpio_out(GPIO_PLL_RESET_N, 0);
	timer_delay(10);
	gpio_out(GPIO_PLL_RESET_N, 1);
	timer_delay(10);
	
	/* Use unidirectional SPI mode */
	ad9516_write_reg(0x000, 0x99);

	/* Check the presence of the chip */
	if (ad9516_read_reg(0x3) != 0xc3) {
		TRACE("Error: AD9516 PLL not responding.\n");
		return -1;
	}

	ad9516_load_regset(ad9516_base_config, ARRAY_SIZE(ad9516_base_config), 0);
	ad9516_load_regset(ad9516_ref_tcxo, ARRAY_SIZE(ad9516_ref_tcxo), 1);
	ad9516_wait_lock();

	/* sync channels */
	ad9516_write_reg(0x230, 1);
	ad9516_write_reg(0x232, 1);
	ad9516_write_reg(0x230, 0);
	ad9516_write_reg(0x232, 1);

	TRACE("AD9516 locked.\n");

	gpio_out(GPIO_SYS_CLK_SEL, 1); /* switch the system clock to the PLL reference */
	gpio_out(GPIO_PERIPH_RESET_N, 0); /* reset all peripherals which use AD9516-provided clocks */
	gpio_out(GPIO_PERIPH_RESET_N, 1);

	return 0;
}

