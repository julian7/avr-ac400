# Firmware for the AC400 controller

## Install toolchain

- Install [just](https://github.com/casey/just/releases)
- Install the [AVR Libc](https://avrdudes.github.io/avr-libc/) toolchain. For exmple, on Debian / Ubuntu:

```shell
sudo apt update
sudo apt install -y gcc-avr binutils-avr avr-libc avrdude
```

On MacOS, you can use Homebrew:

```shell
brew install avr-gcc avrdude
```

## Build and flash

Run

```shell
make
just flash
```

The flash utility is taking a few parameters to specify your environment. The default values are for a Raspberry Pi using SPI0 from its GPIO, but you can override them with environment variables. For example:

- PROGRAMMER: The programmer to use with `avrdude`. Default is `linuxspi`.
- AVR_PART: The AVR part number to flash. Default is `m88`.
- AVR_PORT: The port to use for flashing. Default is `/dev/spidev0.0`.
- AVR_BAUD: The baud rate for flashing. Default is `1000000`.
- TARGET: The target to flash. Default is `ac400`. This will flash `ac400.hex`.

Run `sudo -E just flash` if you need root permissions to access the SPI device. You can also set up udev rules to allow non-root access to the SPI device.

Please note: `-E` is used to preserve the environment variables when running `just` with `sudo`.

## Setting Fuses

Sometimes, you may need to set the fuses on the AVR microcontroller to configure its behavior. Setting and reading fuses are easy with just recipes:

```shell
just read-fuses
```

```shell
just set-fuses [-l 0xLF] [-h 0xHF] [-e 0xEF]
```

Where:
- `-l`: Set the low fuse byte (default: 0xE2).
- `-h`: Set the high fuse byte (default: 0xDF).
- `-e`: Set the extended fuse byte (default: 0xff).

## Default fuse settings

- LFUSE: establish clock source (CKDIV8 = 1, CKOUT = 1, SUT = 10, CKSEL = 0010)
- HFUSE: RSTDISBL = 1, DWEN = 1, SPIEN = 0, WDTON = 1, EESAVE = 1, BOOTSZ = 11, BOOTRST = 1
- EFUSE: BODLEVEL = 111 (Brown-out detection disabled)
