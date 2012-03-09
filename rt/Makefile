CROSS_COMPILE ?= /opt/gcc-lm32/bin/lm32-elf-

OBJS = main.o dev/uart.o dev/timer.o lib/mprintf.o dev/ad9516.o dev/softpll_ng.o ipc/minipc-mem-server.o ipc_test.o

CFLAGS_PLATFORM = -mmultiply-enabled -mbarrel-shift-enabled 
LDFLAGS_PLATFORM = -mmultiply-enabled -mbarrel-shift-enabled   -nostdlib -T target/lm32/ram.ld 
OBJS_PLATFORM=target/lm32/crt0.o target/lm32/irq.o

CC=$(CROSS_COMPILE)gcc
OBJCOPY=$(CROSS_COMPILE)objcopy
OBJDUMP=$(CROSS_COMPILE)objdump
CFLAGS= $(CFLAGS_PLATFORM) -ffunction-sections -fdata-sections -Os -Iinclude -include include/trace.h  -Wall -ffreestanding -Iipc
LDFLAGS= $(LDFLAGS_PLATFORM) -ffunction-sections -fdata-sections -Os -Iinclude -ffreestanding 
SIZE = $(CROSS_COMPILE)size
OBJS += $(OBJS_PLATFORM)

OUTPUT=rt_cpu

all: 		$(OBJS)
				$(SIZE) -t $(OBJS)
				${CC} -o $(OUTPUT).elf $(OBJS) $(LDFLAGS) 
				${OBJCOPY} -O binary $(OUTPUT).elf $(OUTPUT).bin

clean:	
				rm -f $(OBJS) $(OUTPUT).elf $(OUTPUT).bin $(OUTPUT).ram

scp:		all
				scp rt_cpu.bin root@pts-test03.cern.ch:/tftpboot/192.168.1.2/root

%.o:		%.c
				${CC} $(CFLAGS) $(LIB_DIR) -c $^ -o $@

