#define TOHOST (*(volatile int *)0x00100000)

__attribute__((noreturn)) void main(void){
  unsigned a, b, c;

  asm volatile("auipc %0, 0\n\t"
               "auipc %1, 1"
               : "=r"(a), "=r"(b));
  asm volatile("auipc %0, 0" : "=r"(c));

  volatile unsigned *r = (volatile unsigned *)0x80020000;
  r[0] = a;
  r[1] = b;
  r[2] = c;

  asm volatile("fence rw, rw" ::: "memory");
  r[3] = 0xC0FFEEu;
  asm volatile("fence rw, w" ::: "memory");

  int ok = ((b - a) == 0x1004u)
        && (c >= 0x80000000u && c < 0x80040000u)
        && (r[3] == 0xC0FFEEu)
        && (r[0] == a);

  TOHOST = ok ? 1 : 2;
  __builtin_unreachable();
}
