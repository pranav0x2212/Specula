#define TOHOST (*(volatile int *)0x00100000)

__attribute__((noreturn)) void main(void){
  volatile unsigned *lo   = (volatile unsigned *)0x80010000;
  volatile unsigned *mid  = (volatile unsigned *)0x84000000;
  volatile unsigned *high = (volatile unsigned *)0x87fffff0;

  lo[0]   = 0x0000abcd;
  mid[0]  = 0xdeadbeef;
  mid[1]  = mid[0] ^ 0xffffffffu;
  high[0] = 0x87ffffffu;

  int ok = (lo[0]   == 0x0000abcd)
        && (mid[0]  == 0xdeadbeef)
        && (mid[1]  == 0x21524110u)
        && (high[0] == 0x87ffffffu);

  TOHOST = ok ? 1 : 2;
  __builtin_unreachable();
}
