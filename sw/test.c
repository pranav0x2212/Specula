/* Specula milestone-4 test - completes the RV32I register-integer ALU.
 *
 * int / pointer only.  No char/short, no runtime '*' or '/', no array
 * initializers  ->  no libcalls, no byte/halfword memory.
 * Entry is main(); sw/start.S sets sp and calls it.
 *
 * Exercises (beyond M3):
 *   SUB, XOR, SLL, SLT, SLTU, SRA, SRL(imm), SLLI, SRAI, SLTI, XORI,
 *   ANDI, ORI, LUI, BLT / BLTU / BGEU, plus a nested function call.
 *
 * Expected committed data stores (word-addressed):
 *   [0x108]=5  [0x10c]=13 [0x110]=8  [0x114]=4  [0x118]=6  [0x11c]=41
 *   [0x120]=2  [0x124]=1  [0x128]=0  [0x12c]=0  [0x130]=10 [0x134]=-3
 *   [0x138]=200010
 * Expected tohost write: 1 (PASS)
 */
#define TOHOST (*(volatile int *)0x700)

static int __attribute__((noinline)) sgn(int v){
  if (v < 0) return -1;
  if (v > 0) return  1;
  return 0;
}

__attribute__((noreturn)) void main(void){
  volatile int *r = (volatile int *)0x100;

  int a = r[0]; if (a == 0) a = 9;             /* -> 9  */
  int b = r[1]; if (b == 0) b = 4;             /* -> 4  */

  int d   = a - b;                             /* SUB        -> 5  */
  int x   = a ^ b;                             /* XOR        -> 13 */
  int shl = b << (a & 3);                      /* SLL, ANDI  -> 8  */
  int sra = (a * 8) >> b;                      /* SLLI, SRA  -> 4  */
  unsigned lg = ((unsigned)x) >> 1;            /* SRLI       -> 6  */
  int msk = a | 0x20;                          /* ORI        -> 41 */
  int cx  = x ^ 0x0f;                          /* XORI       -> 2  */
  int cs  = (d < x);                           /* SLT        -> 1  */
  int cu  = ((unsigned)-d < (unsigned)x);      /* SLTU       -> 0  */
  int ci  = (d < 3);                           /* SLTI       -> 0  */

  int buf[8];
  for (int i = 0; i < 8; i++) buf[i] = (i - 3) * 5;  /* -15,-10,-5,0,5,10,15,20 */

  int idx  = (a + b) & 7;                      /* -> 5 */
  int pick = buf[idx];                         /* SLLI + ADD -> 10 */

  int *p = buf, *e = buf + (b & 7);            /* e = buf + 4 (runtime b) */
  int cnt = 0;
  while (p < e) { cnt += sgn(*p); p++; }       /* BLTU/BGEU + nested call */
  /* sgn(-15,-10,-5,0) = -1 -1 -1 +0 = -3 */

  int big = pick + 200000;                     /* LUI + ADDI -> 200010 */

  r[2]=d; r[3]=x; r[4]=shl; r[5]=sra; r[6]=(int)lg; r[7]=msk;
  r[8]=cx; r[9]=cs; r[10]=cu; r[11]=ci; r[12]=pick; r[13]=cnt; r[14]=big;

  if (d==5 && x==13 && shl==8 && sra==4 && lg==6 && msk==41 && cx==2
      && cs==1 && cu==0 && ci==0 && pick==10 && cnt==-3 && big==200010)
    TOHOST = 1;
  else
    TOHOST = 2;
  __builtin_unreachable();
}
