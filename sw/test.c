/* Specula milestone-2 bring-up test program.
 *
 * Same arithmetic / memory workload as M1, plus an explicit termination
 * signal. Uses ONLY the RV32I subset the core implements:
 *   addi (li), add, lw, sw   -- no lui / jal / jalr / branch / sub / shift.
 *
 * Termination (M2): a store to the simulator's "tohost" MMIO address ends
 * the run. Value 1 == PASS, anything else == FAIL. The program self-checks
 * branchlessly: it reads its four results back and writes (sum - 99) to
 * tohost, which is exactly 1 iff every value is correct (12+19+31+38 = 100).
 *
 * Build: see the Makefile `program.hex` / `sw/ProgramImage.bsv` rules.
 * Expected committed stores (data memory, word-addressed):
 *   [0x100] = 12   [0x104] = 19   [0x108] = 31   [0x10c] = 38
 * Expected tohost write: 1  (PASS)
 */
#define TOHOST (*(volatile int *)0x700)

__attribute__((noreturn)) void _start(void)
{
    volatile int *ram = (volatile int *)0x100;   /* data window, clear of .text */

    int a = 7;
    int b = 5;

    ram[0] = a + b;               /* [0x100] = 12 */
    ram[1] = a + a + b;           /* [0x104] = 19 */
    ram[2] = ram[0] + ram[1];     /* [0x108] = 31  (load-use of its own stores) */
    ram[3] = ram[2] + a;          /* [0x10c] = 38 */

    int sum = ram[0] + ram[1] + ram[2] + ram[3];   /* 100 iff all correct */

    TOHOST = sum - 99;           /* 1 => PASS ; any other value => FAIL */

    __builtin_unreachable();
}
