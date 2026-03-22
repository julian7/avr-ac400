PROGRAMMER := env("AVR_PROGRAMMER", "usbasp-clone")
AVR_PART   := env("AVR_PART", "m328p")
AVR_PORT   := env("AVR_PORT", "")
AVR_FREQ   := env("AVR_FREQ", "") # lower when needed, like "128kHz"
TARGET     := "ac400"

avrdude_programmer_flag := if PROGRAMMER != "" { f"-c {{PROGRAMMER}}" } else {""}
avrdude_port_flag := if AVR_PORT != "" { f"-P {{AVR_PORT}}" } else {""}
avrdude_freq_arg := if AVR_FREQ != "" { f"-B {{AVR_FREQ}}" } else {""}

AVRDUDE_CMD := f"avrdude {{avrdude_programmer_flag}} -p {{AVR_PART}} {{avrdude_port_flag}} {{avrdude_freq_arg}}"

[private]
@default:
    echo "Configure avrdude with the following variables:"
    echo "  AVRDUDE_PROGRAMMER (default: {{PROGRAMMER}})"
    echo "  AVR_PART (default: {{AVR_PART}})"
    echo "  AVR_PORT (default: {{AVR_PORT}})"
    echo "  AVR_FREQ (default empty, set frequency if needed, like \"128kHz\")"
    echo
    just -l

# Builds the firmware
@build:
    make all

# Flashes the firmware (run with sudo if needed)
@flash:
    {{AVRDUDE_CMD}} -U flash:w:{{TARGET}}.hex:i -v

# Read fuses
@read-fuses:
    {{AVRDUDE_CMD}} -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h -v

# m88a default hfuse=0xdf, m328 default hfuse=0xd9
# Set fuses
[arg("lfuse", short="l"), arg("hfuse", short="h"), arg("efuse", short="e")]
@set-fuses lfuse="0xe2" hfuse="0xd9" efuse="0xff":
    {{AVRDUDE_CMD}} -U lfuse:w:{{lfuse}}:m -U hfuse:w:{{hfuse}}:m -U efuse:w:{{efuse}}:m -v
