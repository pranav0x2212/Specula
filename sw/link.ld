ENTRY(_start)

SECTIONS
{
  . = 0x00000000;

  .text : {
    *(.text.init)       /* sw/start.S : _start must be at 0x0 */
    *(.text .text.*)
  }

  .rodata : { *(.rodata .rodata.*) }
  .data   : { *(.data .data.*) }
  .bss    : { *(.bss .bss.*) *(COMMON) }

  _end = .;
}
