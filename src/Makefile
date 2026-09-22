# HomeComputer 6502 firmware. Microsoft BASIC for the 6502 (REALIO=6)
# plus the LCD and keyboard console. cc65 must be on PATH
# (CC65_HOME=/opt/cc65, see docs/system-spec.md).

CC65_HOME ?= /opt/cc65
export CC65_HOME
export PATH := $(CC65_HOME)/bin:$(PATH)

CA65 = ca65 --cpu 6502
LD65 = ld65

BUILD = ../build
CFG = firmware.cfg

OBJS = $(BUILD)/startup.o $(BUILD)/delay.o $(BUILD)/lcd.o $(BUILD)/irq.o $(BUILD)/keyboard.o $(BUILD)/m6502.o $(BUILD)/sid.o $(BUILD)/monitor.o $(BUILD)/disk.o $(BUILD)/serio.o $(BUILD)/kernal.o

.PHONY: all clean

all: $(BUILD)/firmware.bin

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/startup.o: startup.s65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/delay.o: delay.s65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/lcd.o: lcd.s65 io.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/irq.o: irq.s65 io.inc65 zp.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/keyboard.o: keyboard.s65 io.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/sid.o: sid.s65 io.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/monitor.o: monitor.s65 io.inc65 zp.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/disk.o: disk.s65 io.inc65 zp.inc65 disk.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/serio.o: serio.s65 io.inc65 zp.inc65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/kernal.o: kernal.s65 | $(BUILD)
	$(CA65) -o $@ $<

$(BUILD)/m6502.o: msbasic/m6502.s65 | $(BUILD)
	$(CA65) -I . -U --feature force_range -D REALIO=6 -o $@ $<

$(BUILD)/firmware.bin: $(OBJS) $(CFG)
	$(LD65) -C $(CFG) -m $(BUILD)/firmware.map -o $@ $(OBJS)
	@test $$(stat -c %s $@) -eq 32768

clean:
	rm -rf $(BUILD)
