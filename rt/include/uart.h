#ifndef __UART_H
#define __UART_H

int mprintf(char const *format, ...);

void uart_init();
void uart_write_byte(int b);
void uart_write_string(char *s);
int uart_poll();
int uart_read_byte();

#endif
