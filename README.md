# Record Power AC400 controller

This repository contains a drop-in replacement PCB and firmware for the Record Power AC400 Air Filter controller.

The original AC400 controller is prone to failure due to its simplistic power supply design, which often results in various failures. While the company's support is very good, the replacement controller is still prone to the same issues.

This design aims to provide a solution that is more robust, and tries to keep using original parts where possible. It also uses an ATmega88pa-pu microcontroller, as existing refurbishment stock.

## Firmware

The firmware is written in C using AVR-GCC toolchain. It is based on the original firmware functionality, with some improvements and bug fixes.

## Flashing the firmware

To flash the firmware onto the ATmega88pa-pu microcontroller, you will need an AVR programmer (e.g., USBasp, [ATMEL-ICE](https://www.microchip.com/en-us/development-tool/atatmel-ice)) and AVRDUDE software.

## Similar projects

- [AC400Controller](https://github.com/thikone/AC400Controller): drop-in replacement PCB, firmware, and 3D printed enclosure. It uses Arduino Nano as the controller.
