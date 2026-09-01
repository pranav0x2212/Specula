#define TOHOST (*(volatile int *)0x10000000)

static int __attribute__((noinline)) sum_sb(signed char *p){        /* LB  x4 */
  int s = 0; for (int i = 0; i < 4; i++) s += p[i]; return s; }
static int __attribute__((noinline)) sum_sh(short *p){              /* LH  x4 */
  int s = 0; for (int i = 0; i < 4; i++) s += p[i]; return s; }
static unsigned __attribute__((noinline)) sum_ub(unsigned char *p){ /* LBU x4 */
  unsigned s = 0; for (int i = 0; i < 4; i++) s += p[i]; return s; }
static unsigned __attribute__((noinline)) sum_uh(unsigned short *p){/* LHU x4 */
  unsigned s = 0; for (int i = 0; i < 4; i++) s += p[i]; return s; }

__attribute__((noreturn)) void main(void){
  volatile int   *r  = (volatile int   *)0x80020000;
  signed char    *sb = (signed char    *)0x80020100;
  unsigned char  *ub = (unsigned char  *)0x80020110;
  short          *sh = (short          *)0x80020120;
  unsigned short *uh = (unsigned short *)0x80020130;

  for (int i = 0; i < 4; i++) sb[i] = (signed char)(i*40 - 60);          /* SB: -60,-20,20,60 */
  for (int i = 0; i < 4; i++) ub[i] = (unsigned char)(i*50 + 10);        /* SB: 10,60,110,160 */
  for (int i = 0; i < 4; i++) sh[i] = (short)(i*400 - 600);              /* SH: -600,-200,200,600 */
  for (int i = 0; i < 4; i++) uh[i] = (unsigned short)(i*10000 + 5000);  /* SH: 5000,15000,25000,35000 */

  int      a = sum_sb(sb);
  unsigned b = sum_ub(ub);
  int      c = sum_sh(sh);
  unsigned d = sum_uh(uh);

  volatile unsigned char *v = (volatile unsigned char *)0x80020140;
  v[0] = 0x11; v[1] = 0x22; v[2] = 0x33; v[3] = 0x44;
  unsigned merged = *(volatile unsigned *)0x80020140;   
  unsigned byte1  = *(volatile unsigned char *)0x80020141; 

  r[0]=a; r[1]=(int)b; r[2]=c; r[3]=(int)d; r[4]=(int)merged; r[5]=(int)byte1;

  if (a==0 && b==340 && c==0 && d==80000
      && merged==0x44332211u && byte1==0x22u)
    TOHOST = 1;
  else
    TOHOST = 2;
  __builtin_unreachable();
}
