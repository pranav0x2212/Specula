#define TOHOST (*(volatile int *)0x00100000)

__attribute__((noreturn)) void main(void){
  volatile unsigned *magic    = (volatile unsigned *)0x10001000;
  volatile unsigned *version  = (volatile unsigned *)0x10001004;
  volatile unsigned *devId    = (volatile unsigned *)0x10001008;
  volatile unsigned *vendor   = (volatile unsigned *)0x1000100c;
  volatile unsigned *features = (volatile unsigned *)0x10001010;
  volatile unsigned *qNumMax  = (volatile unsigned *)0x10001034;
  volatile unsigned *status   = (volatile unsigned *)0x10001070;
  volatile unsigned *qSel     = (volatile unsigned *)0x10001030;
  volatile unsigned *qNum     = (volatile unsigned *)0x10001038;
  volatile unsigned *qPfn     = (volatile unsigned *)0x10001040;
  volatile unsigned *pageSize = (volatile unsigned *)0x10001028;
  volatile unsigned *drvFeat  = (volatile unsigned *)0x10001020;

  unsigned m = *magic;
  unsigned v = *version;
  unsigned d = *devId;
  unsigned ven = *vendor;
  unsigned f = *features;
  unsigned q = *qNumMax;

  *status  = 1;
  *status  = 3;
  *drvFeat = 0;
  *status  = 0xb;
  *status  = 0xf;
  *pageSize = 4096;
  *qSel    = 0;
  *qNum    = 8;
  *qPfn    = 0x12345;

  int ok = (m == 0x74726976u)
        && (v == 1)
        && (d == 2)
        && (ven == 0x554d4551u)
        && (f == 0)
        && (q >= 8);

  TOHOST = ok ? 1 : 2;
  __builtin_unreachable();
}
