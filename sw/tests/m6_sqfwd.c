#define TOHOST (*(volatile int *)0x00100000)

#define BASE 0x80030000u
#define W(i)  (*(volatile unsigned      *)(BASE + ((i)<<2)))
#define B(o)  (*(volatile unsigned char *)(BASE + (o)))
#define H(o)  (*(volatile unsigned short*)(BASE + (o)))

__attribute__((noreturn)) void main(void){
  int ok = 1;

  /* 1. store then immediate load, same word */
  W(0) = 0xAABBCCDD;
  ok &= (W(0) == 0xAABBCCDD);

  /* 2. multiple older matching stores to the same word -> youngest wins */
  W(1) = 0x11111111;
  W(1) = 0x22222222;
  W(1) = 0x33333333;
  ok &= (W(1) == 0x33333333);

  /* 3. non-matching store between two matching stores */
  W(2) = 0x0000BEEF;
  W(9) = 0xDEADDEAD;                 /* different word */
  W(2) = 0xCAFE1234;
  ok &= (W(2) == 0xCAFE1234);
  ok &= (W(9) == 0xDEADDEAD);

  /* 4. byte / halfword masked stores into word 3, then word load */
  W(3) = 0x00000000;
  B(12) = 0x7F;                      /* BASE+0x0C = word 3, byte 0 */
  B(15) = 0x81;                      /* word 3, byte 3            */
  H(14) = 0x1234;                    /* word 3, bytes 2..3 (overwrites byte 3) */
  ok &= (W(3) == 0x1234007Fu);

  /* 5. SQ wraparound: 12-store burst into words 16..27, then read back */
  for (unsigned i = 0; i < 12; i++) W(16 + i) = 0xA0000000u + i;
  unsigned acc = 0;
  for (unsigned i = 0; i < 12; i++) acc += W(16 + i);
  ok &= (acc == (12u * 0xA0000000u + 66u));

  /* 6. mispredicted branch with a store in the shadow, then recovery */
  volatile unsigned guard = W(0);   /* 0xAABBCCDD */
  W(4) = 0x600D600D;
  if (guard == 0x12345678u) {
    W(4) = 0xBADBAD00;              /* squashed store - must NOT forward */
  }
  ok &= (W(4) == 0x600D600D);

  /* 7. AMOSWAP surrounded by stores/loads to the same word */
  W(5) = 0x0000000A;
  unsigned nv = 0x000000B0, old;
  __atomic_exchange(&W(5), &nv, &old, __ATOMIC_SEQ_CST);
  ok &= (old == 0x0000000A);
  ok &= (W(5) == 0x000000B0);
  W(5) = 0x000000C0;
  ok &= (W(5) == 0x000000C0);

  /* 8. loop-carried store->load dependence through memory */
  W(6) = 1;
  for (int i = 0; i < 10; i++) W(6) = W(6) * 2 + 1;   /* -> 2047 */
  ok &= (W(6) == 2047);

  TOHOST = ok ? 1 : 2;
  __builtin_unreachable();
}
