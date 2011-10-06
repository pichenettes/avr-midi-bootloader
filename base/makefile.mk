# Copyright 2009 Olivier Gillet.
#
# Author: Olivier Gillet (ol.gillet@gmail.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

TOOLCHAIN_PATH = /usr/local/CrossPack-AVR/bin/
TOOLCHAIN_ETC_PATH   = /usr/local/CrossPack-AVR/etc/
BUILD_ROOT     = build/
BUILD_DIR      = $(BUILD_ROOT)$(TARGET)/
PROGRAMMER     = avrispmkII

MCU            = atmega$(MCU_NAME)p
DMCU           = m$(MCU_NAME)p
MCU_DEFINE     = ATMEGA$(MCU_NAME)P
F_CPU          = 20000000

VPATH          = $(PACKAGES)
CC_FILES       = $(notdir $(wildcard $(patsubst %,%/*.cc,$(PACKAGES))))
C_FILES        = $(notdir $(wildcard $(patsubst %,%/*.c,$(PACKAGES))))
AS_FILES       = $(notdir $(wildcard $(patsubst %,%/*.as,$(PACKAGES))))
OBJ_FILES      = $(CC_FILES:.cc=.o) $(C_FILES:.c=.o) $(AS_FILES:.S=.o)
OBJS           = $(patsubst %,$(BUILD_DIR)%,$(OBJ_FILES))
DEPS           = $(OBJS:.o=.d)

TARGET_BIN     = $(BUILD_DIR)$(TARGET).bin
TARGET_ELF     = $(BUILD_DIR)$(TARGET).elf
TARGET_HEX     = $(BUILD_DIR)$(TARGET).hex
TARGETS        = $(BUILD_DIR)$(TARGET).*
DEP_FILE       = $(BUILD_DIR)depends.mk

CC             = $(TOOLCHAIN_PATH)avr-gcc
CXX            = $(TOOLCHAIN_PATH)avr-g++
OBJCOPY        = $(TOOLCHAIN_PATH)avr-objcopy
OBJDUMP        = $(TOOLCHAIN_PATH)avr-objdump
AR             = $(TOOLCHAIN_PATH)avr-ar
SIZE           = $(TOOLCHAIN_PATH)avr-size
NM             = $(TOOLCHAIN_PATH)avr-nm
AVRDUDE        = $(TOOLCHAIN_PATH)avrdude
REMOVE         = rm -f
CAT            = cat

CPPFLAGS      = -mmcu=$(MCU) -I. \
			-g -Os -w -Wall \
			-DF_CPU=$(F_CPU) \
			-fdata-sections \
			-ffunction-sections \
			-fshort-enums \
			-fno-move-loop-invariants \
			$(EXTRA_DEFINES) \
			$(MMC_CONFIG) \
			-D$(MCU_DEFINE) \
			-mcall-prologues
CXXFLAGS      = -fno-exceptions
ASFLAGS       = -mmcu=$(MCU) -I. -x assembler-with-cpp
LDFLAGS       = -mmcu=$(MCU) -lm -Os -Wl,--gc-sections$(EXTRA_LD_FLAGS)

# ------------------------------------------------------------------------------
# Source compiling
# ------------------------------------------------------------------------------

$(BUILD_DIR)%.o: %.cc
	$(CXX) -c $(CPPFLAGS) $(CXXFLAGS) $< -o $@

$(BUILD_DIR)%.o: %.c
	$(CC) -c $(CPPFLAGS) $(CXXFLAGS) $< -o $@

$(BUILD_DIR)%.o: %.s
	$(CC) -c $(CPPFLAGS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)%.d: %.cc
	$(CXX) -MM $(CPPFLAGS) $(CXXFLAGS) $< -MF $@ -MT $(@:.d=.o)

$(BUILD_DIR)%.d: %.c
	$(CC) -MM $(CPPFLAGS) $(CXXFLAGS) $< -MF $@ -MT $(@:.d=.o)

$(BUILD_DIR)%.d: %.s
	$(CC) -MM $(CPPFLAGS) $(ASFLAGS) $< -MF $@ -MT $(@:.d=.o)


# ------------------------------------------------------------------------------
# Object file conversion
# ------------------------------------------------------------------------------

$(BUILD_DIR)%.hex: $(BUILD_DIR)%.elf
	$(OBJCOPY) -O ihex -R .eeprom $< $@

$(BUILD_DIR)%.bin: $(BUILD_DIR)%.elf
	$(OBJCOPY) -O binary -R .eeprom $< $@

$(BUILD_DIR)%.eep: $(BUILD_DIR)%.elf
	-$(OBJCOPY) -j .eeprom --set-section-flags=.eeprom="alloc,load" \
		--change-section-lma .eeprom=0 -O ihex $< $@

$(BUILD_DIR)%.lss: $(BUILD_DIR)%.elf
	$(OBJDUMP) -h -S $< > $@

$(BUILD_DIR)%.sym: $(BUILD_DIR)%.elf
	$(NM) -n $< > $@

# ------------------------------------------------------------------------------
# AVRDude
# ------------------------------------------------------------------------------

AVRDUDE_CONF     = $(TOOLCHAIN_ETC_PATH)avrdude.conf
AVRDUDE_COM_OPTS = -V -p $(DMCU)
AVRDUDE_COM_OPTS += -C $(AVRDUDE_CONF)
AVRDUDE_ISP_OPTS = -c $(PROGRAMMER) -P usb

# ------------------------------------------------------------------------------
# Main targets
# ------------------------------------------------------------------------------

all:    $(BUILD_DIR) $(TARGET_HEX)

$(BUILD_DIR):
		mkdir -p $(BUILD_DIR)

$(TARGET_ELF):  $(OBJS)
		$(CC) $(LDFLAGS) -o $@ $(OBJS) $(SYS_OBJS)

$(DEP_FILE):  $(BUILD_DIR) $(DEPS)
		cat $(DEPS) > $(DEP_FILE)

bin:	$(TARGET_BIN)

upload:    $(TARGET_HEX)
		$(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) \
			-U flash:w:$(TARGET_HEX):i -U lock:w:0x$(LOCK):m

clean:
		$(REMOVE) $(OBJS) $(TARGETS) $(DEP_FILE) $(DEPS)

depends:  $(DEPS)
		cat $(DEPS) > $(DEP_FILE)

$(TARGET).size:  $(TARGET_ELF)
		$(SIZE) $(TARGET_ELF) > $(TARGET).size

$(BUILD_DIR)$(TARGET).top_symbols: $(TARGET_ELF)
		$(NM) $(TARGET_ELF) --size-sort -C -f bsd -r > $@

size: $(TARGET).size
		cat $(TARGET).size | awk '{ print $$1+$$2 }' | tail -n1

ramsize: $(TARGET).size
		cat $(TARGET).size | awk '{ print $$2+$$3 }' | tail -n1

size_report:  build/$(TARGET)/$(TARGET).lss build/$(TARGET)/$(TARGET).top_symbols

.PHONY: all clean depends upload

include $(DEP_FILE)

# ------------------------------------------------------------------------------
# Set fuses
# ------------------------------------------------------------------------------

terminal:
		$(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) -e -tuF

fuses:
		$(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) -e -u \
			-U efuse:w:0x$(EFUSE):m \
			-U hfuse:w:0x$(HFUSE):m \
			-U lfuse:w:0x$(LFUSE):m \
			-U lock:w:0x$(LOCK):m

# ------------------------------------------------------------------------------
# Program (fuses + firmware) a blank chip
# ------------------------------------------------------------------------------

bootstrap: bake

bake:	$(FIRMWARE)
		echo "sck 10\nquit\n" | $(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) -e -tuF
		$(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) -e -u \
			-U efuse:w:0x$(EFUSE):m \
			-U hfuse:w:0x$(HFUSE):m \
			-U lfuse:w:0x$(LFUSE):m \
			-U lock:w:0x$(LOCK):m
		echo "sck 1\nquit\n" | $(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) -e -tuF
		$(AVRDUDE) $(AVRDUDE_COM_OPTS) $(AVRDUDE_ISP_OPTS) \
			-U flash:w:$(TARGET_HEX):i -U lock:w:0x$(LOCK):m
