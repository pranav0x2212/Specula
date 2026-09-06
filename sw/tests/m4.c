#define TOHOST (*(volatile int *)0x00100000)

static int __attribute__((noinline)) sgn(int v){
  if (v < 0) return -1;
  if (v > 0) return  1;
  return 0;
}

__attribute__((noreturn)) void main(void){
  volatile int *r = (volatile int *)0x80020000;

  int a = r[0]; if (a == 0) a = 9;
  int b = r[1]; if (b == 0) b = 4;

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
  for (int i = 0; i < 8; i++) buf[i] = (i - 3) * 5;

  int idx  = (a + b) & 7;
  int pick = buf[idx];

  int *p = buf, *e = buf + (b & 7);
  int cnt = 0;
  while (p < e) { cnt += sgn(*p); p++; }

  int big = pick + 200000;

  r[2]=d; r[3]=x; r[4]=shl; r[5]=sra; r[6]=(int)lg; r[7]=msk;
  r[8]=cx; r[9]=cs; r[10]=cu; r[11]=ci; r[12]=pick; r[13]=cnt; r[14]=big;

  if (d==5 && x==13 && shl==8 && sra==4 && lg==6 && msk==41 && cx==2
      && cs==1 && cu==0 && ci==0 && pick==10 && cnt==-3 && big==200010)
    TOHOST = 1;
  else
    TOHOST = 2;
  __builtin_unreachable();
}
