#define TOHOST (*(volatile int *)0x00100000)

static int __attribute__((noinline)) add1(int x) { return x + 1; }
static int __attribute__((noinline)) mul3(int x) { return x + x + x; }

static int __attribute__((noinline)) sum_to(int n) {
  int s = 0;
  for (int i = 1; i <= n; i++) s += i;    
  return s;
}

static unsigned __attribute__((noinline)) straddle_probe(void) {
  unsigned v;
  asm volatile(
    ".option push\n"
    ".option rvc\n"
    ".p2align 2\n"
    "   c.li   %0, 0\n"           
    "   lui    %0, 0x20304\n"     
    "   addi   %0, %0, 0x506\n"   
    "   c.addi %0, 1\n"          
    ".option pop\n"
    : "=r"(v));
  return v;                       
}

__attribute__((noreturn)) void main(void) {
  volatile int *r = (volatile int *)0x80020000;

  int a = 7;
  int b = a << 2;              /* c.slli  -> 28 */
  int c = b & 7;              /* c.andi  -> 4  */
  int d = (int)((unsigned)b >> 1); /* c.srli -> 14 */
  int e = b - a;              /* c.sub   -> 21 */
  int f = a + b;              /* c.add   -> 35 */
  int g = c;                  /* c.mv          */

  int h = sum_to(10);        

  int (*fp)(int) = (h & 1) ? add1 : mul3;  /* c.beqz / c.bnez */
  int k = fp(h);              /* c.jalr : h odd -> add1 -> 56 */

  int m;
  if (k == 56) m = 100;       /* branch */
  else         m = 1;

  unsigned s = straddle_probe();

  int big;
  { volatile int local[4];
    local[0] = 0x1111; local[1] = 0x2222; local[2] = 0; local[3] = 0;
    big = local[0] + local[1]; }           /* c.swsp/c.lwsp + c.addi4spn */

  r[0]=a;  r[1]=b;  r[2]=c;  r[3]=d;  r[4]=e;  r[5]=f;
  r[6]=g;  r[7]=h;  r[8]=k;  r[9]=m;  r[10]=(int)s; r[11]=big;

  int ok = (a==7) && (b==28) && (c==4) && (d==14) && (e==21) && (f==35)
        && (g==4) && (h==55) && (k==56) && (m==100)
        && (s==0x20304507u) && (big==0x3333);

  TOHOST = ok ? 1 : 2;
  __builtin_unreachable();
}
