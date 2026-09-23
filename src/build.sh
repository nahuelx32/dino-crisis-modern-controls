set -e
CF="-march=r3000 -mabi=32 -mno-abicalls -fno-pic -G0 -Os -msoft-float -mno-check-zero-division -fno-builtin -ffreestanding -nostdlib -Wall"
mipsel-linux-gnu-gcc $CF -c dcmod.c -o dcmod.o
mipsel-linux-gnu-gcc $CF -c stubs.S -o stubs.o
mipsel-linux-gnu-ld -T link.ld -o dcmod.elf stubs.o dcmod.o
mipsel-linux-gnu-objcopy -O binary -j .blob dcmod.elf dcmod.bin
ls -l dcmod.bin
mipsel-linux-gnu-nm -n dcmod.elf | grep -v ' [aA] '
