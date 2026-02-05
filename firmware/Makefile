MCU      := atmega88
F_CPU    := 8000000UL
CC       := avr-gcc
OBJCOPY  := avr-objcopy

CFLAGS   := -mmcu=$(MCU) -DF_CPU=$(F_CPU) -Os -Wall -Isrc
LDFLAGS  := -mmcu=$(MCU)

SRCS     := src/main.c src/gpio.c src/ir.c
OBJS     := $(SRCS:.c=.o)
TARGET   := ac400

.PHONY: all clean flash size

all: $(TARGET).hex

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $@

%.hex: %.elf
	$(OBJCOPY) -O ihex $< $@

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).hex
