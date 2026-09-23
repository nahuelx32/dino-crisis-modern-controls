OUTPUT_ARCH(mips)
ENTRY(stubPlayer)
SECTIONS {
  . = 0x800D8000;
  .blob : {
    *(.text.start) *(.text*)
    _etext = .;
    *(.rodata*)
    *(.data*) *(.sdata*)
    *(.bss*) *(.sbss*) *(COMMON)
    . = ALIGN(4);
  }
  /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.comment) *(.gnu.attributes) *(.note*) }
}
