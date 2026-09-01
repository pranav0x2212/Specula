#define TOHOST (*(volatile int *)0x00100000)

static int __attribute__((noinline)) addfn(int x, int y){ return x + y; }

__attribute__((noreturn)) void main(void){
  volatile int      *ram  = (volatile int      *)0x80010000;   /* DATA region */
  volatile unsigned *code = (volatile unsigned *)0x80000000;   /* _start, read as DATA via the LSU */

  ram[0] = 0x1234;                  /* store into unified memory                 */
  ram[1] = ram[0] + 0x1111;        /* load-use of ram[0], then store  -> 0x2345 */
  int s  = addfn(ram[0], ram[1]);  /* call: fetch addfn from unified mem, operands from data */
  ram[2] = s;                      /* 0x1234 + 0x2345 = 0x3579                   */

  unsigned entry1 = code[1];       /* 2nd instruction word of _start, fetched here AS DATA */
  ram[3] = (int)entry1;

  int ok = (ram[0] == 0x1234)
        && (ram[1] == 0x2345)
        && (ram[2] == 0x3579)
        && ((entry1 & 0x7f) == 0x6f)
        && ((unsigned)&main >= 0x80000000)
        && ((unsigned)&main <  0x80040000);

  TOHOST = ok ? 1 : 2;
  __builtin_unreachable();
}