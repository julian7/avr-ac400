PROGRAMMER := env("AVRDUDE_PROGRAMMER", "linuxspi")
AVR_PART   := env("AVR_PART", "m88")
AVR_PORT   := env("AVR_PORT", "/dev/spidev0.0")
AVR_BAUD   := env("AVR_BAUD", "1000000")
TARGET     := "ac400"

[private]
@default:
    just -l

# Flashes the firmware (run with sudo if needed)
@flash:
    avrdude -c {{PROGRAMMER}} -p {{AVR_PART}} -P {{AVR_PORT}} -b {{AVR_BAUD}} -U flash:w:{{TARGET}}.hex:i -v

# Read fuses
@read-fuses:
    avrdude -c {{PROGRAMMER}} -p {{AVR_PART}} -P {{AVR_PORT}} -b {{AVR_BAUD}} -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h -v

# Set fuses
[arg("lfuse", short="l"), arg("hfuse", short="h"), arg("efuse", short="e")]
@set-fuses lfuse="0xe2" hfuse="0xdf" efuse="0xff":
    avrdude -c {{PROGRAMMER}} -p {{AVR_PART}} -P {{AVR_PORT}} -b {{AVR_BAUD}} -U lfuse:w:{{lfuse}}:m -U hfuse:w:{{hfuse}}:m -U efuse:w:{{efuse}}:m -v
