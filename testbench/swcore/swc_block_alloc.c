#include <stdio.h>


#define NUM_PAGES 2048
#define BITMAP_SIZE 2048/32

int use_count[NUM_PAGES];
int l0_bitmap[BITMAP_SIZE];
int l1_bitmap[BITMAP_SIZE];
int free_pages = NUM_PAGES;

int prio_enc(int *p, int count) {
 int i;
 for(i=0;i<count;i++)
	if(p[i]) return i;
	
 return -1;
}

int prio_enc_bin(int val, int bit_count) {
 int i;
 for(i=0;i<bit_count;i++)
	if(val & (1<<i)) return i;
	
 return -1;
}

int alloc_page(int ucnt)
{
 if(!free_pages) return -1;
 
 int l1_lookup = prio_enc(l1_bitmap, BITMAP_SIZE);
 int l0_lookup = prio_enc_bin(l0_bitmap[l1_lookup], 32);

 int newval = l0_bitmap[l1_lookup];
 int pageaddr = l1_lookup * 32 + l0_lookup;
 
 newval ^= (1<< l0_lookup); // clear the free page

 l0_bitmap[l1_lookup] = newval;
 if(!newval)
	l1_bitmap[l1_lookup] = 0;
	
	use_count[pageaddr] = ucnt;

 printf("pageaddr: %d\n", pageaddr);
}

int free_page(int pageaddr)
{
 if(use_count[pageaddr] > 1) {
	use_count[pageaddr]--;
 } else {
	l0_bitmap[pageaddr >> 5] ^= (1 << (pageaddr & 0x1f));
  l1_bitmap[pageaddr >> 5] = 1;
  free_pages ++;
 }
}

int alloc_init()
{
 int i, j;
 
 free_pages  = NUM_PAGES;
 
 for(i = 0; i<  BITMAP_SIZE;i++)
 {
	l1_bitmap[i] = 1;
	l0_bitmap[i] = 0xffffffff;
 }
}

main()
{
 alloc_init();
 int i;
 
 for (i=0;i<100;i++) alloc_page(1);
 
 free_page(50);
 
 alloc_page(1);
}