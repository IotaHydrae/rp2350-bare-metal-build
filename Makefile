# SPDX-FileCopyrightText: 2024 Mete Balci
#
# SPDX-License-Identifier: GPL-3.0-or-later

# set debug to 0 or 1
# adjust optimization flag accordingly below
debug = 1
# set fpu to soft, softfp or hard
# soft:   software fpu, soft abi
# softfp: hardware fpu, soft abi
# hard:   harwdare fpu, hard abi
fpu = soft

ARCH ?= riscv

# specify an aarch32 bare-metal eabi toolchain
# TODO: add riscv support
ifeq ($(ARCH), riscv)
	CC = riscv32-corev-elf-gcc
	OBJCOPY = riscv32-corev-elf-objcopy
	C_OBJECTS = 
	S_OBJECTS = minimum_riscv_image_def_block.o
else
	CC = arm-none-eabi-gcc
	OBJCOPY = arm-none-eabi-objcopy
	C_OBJECTS = main.o syscalls.o
	S_OBJECTS = minimum_arm_image_def_block.o
endif

# assume default pico-sdk path
PICO_SDK_PATH ?= ~/pico-sdk

# modify these to add/remove different code/object files


ELF = program.elf
BIN = program.bin
UF2 = program.uf2

# sets DEBUGFLAGS based on debug above
ifeq ($(debug), 1)
	DEBUGFLAGS = -g3 -O0
else
	# change optimization options to whatever suits you
	DEBUGFLAGS = -O2
endif

# sets FLOATFLAGS based on fpu above
ifeq ($(fpu), softfp)
	FLOATFLAGS = -mfloat-abi=softfp -mfpu=fpv5-sp-d16
else ifeq ($(fpu), hard)
	FLOATFLAGS = -mfloat-abi=hard -mfpu=fpv5-sp-d16
else
	FLOATFLAGS = -mfloat-abi=soft
endif

ifeq ($(ARCH), riscv)
CFLAGS = -march=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs -std=gnu11
CFLAGS += -I. -I${PICO_SDK_PATH}/src/rp2_common/cmsis/stub/CMSIS/Core/Include \
			  -I${PICO_SDK_PATH}/src/rp2_common/cmsis/stub/CMSIS/Device/RP2350/Include
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -Os -Wl,--no-warn-rwx-segments

ASFLAGS = -march=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs -std=gnu11
ASFLAGS += -x assembler-with-cpp
ASFLAGS += -I. -I${PICO_SDK_PATH}/src/rp2_common/cmsis/stub/CMSIS/Core/Include \
			   -I${PICO_SDK_PATH}/src/rp2_common/cmsis/stub/CMSIS/Device/RP2350/Include
ASFLAGS += -Os -Wl,--no-warn-rwx-segments

LDFLAGS += -T"linker.ld"
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -static
LDFLAGS += -Wl,--start-group -lc -lm -Wl,--end-group
else
# cpu target and instruction set
CFLAGS = -mcpu=cortex-m33 -mthumb -std=gnu11
# floating point model
CFLAGS += $(FLOATFLAGS)
# includes
CFLAGS += -I. -I${PICO_SDK_PATH}/src/rp2_common/cmsis/stub/CMSIS/Core/Include -I${PICO_SDK_PATH}/src/rp2_common/cmsis/stub/CMSIS/Device/RP2350/Include

# use newlib nano
CFLAGS += --specs=nano.specs
# put functions and data into individual sections
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -Wall
CFLAGS += $(DEBUGFLAGS)

ASFLAGS = -mcpu=cortex-m33 -mthumb
ASFLAGS += $(FLOATFLAGS)
ASFLAGS += --specs=nano.specs
# enable c preprocessor in assembly source files
ASFLAGS += -x assembler-with-cpp
ASFLAGS += $(DEBUGFLAGS)

LDFLAGS = -mcpu=cortex-m33 -mthumb
LDFLAGS += $(FLOATFLAGS)
# use the linker script
LDFLAGS += -T"linker.ld"
# use the system call stubs
LDFLAGS += --specs=nosys.specs 
# remove empty sections only if not for debug
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -static
LDFLAGS += --specs=nano.specs
LDFLAGS += -Wl,--start-group -lc -lm -Wl,--end-group
endif

all: clean $(ELF) $(BIN) $(UF2)

clean:
	rm -rf $(ELF) $(BIN) $(UF2) *.o

%.o: %.c Makefile
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.s Makefile
	$(CC) $(ASFLAGS) -c -o $@ $<

$(ELF): $(C_OBJECTS) $(S_OBJECTS) Makefile linker.ld
	$(CC) -o $@ $(C_OBJECTS) $(S_OBJECTS) $(LDFLAGS)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $^ $@

$(UF2): $(BIN)
	picotool uf2 convert $^ -t bin $@

flash: clean $(ELF)
	openocd -f interface/cmsis-dap.cfg -f target/rp2350.cfg -c "adapter speed 5000" -c "program $(ELF) verify reset exit"

debug: clean $(ELF)
	gdb-multiarch -ex "target remote localhost:3333" -ex "monitor reset init" -ex "break Reset_Handler" $(ELF)

openocd-server:
	openocd -f interface/cmsis-dap.cfg -f target/rp2350.cfg -c "adapter speed 5000"

reset:
	openocd -f interface/cmsis-dap.cfg -f target/rp2350.cfg -c "init; reset; exit;"

pico-sdk:
	git clone --depth 1 -b 2.0.0 https://github.com/raspberrypi/pico-sdk.git $@
