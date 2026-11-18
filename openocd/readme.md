# Recover FPGA1394 V1 and V2 firmware

Use this procedure after a corrupted firmware update. It does not apply to FPGA1394 V3.

First, use a Digilent JTAG-HS3 adapter to load a temporary bitstream into the FPGA.
Then use `pgm1394` to reprogram the PROM.

Order the [Digilent JTAG-HS3 adapter](https://digilent.com/shop/jtag-hs3-programming-cable/).

## Install OpenOCD and USB rules

On Ubuntu or Debian, run these commands to install the tools and configure USB access:

```bash
sudo apt update
sudo apt install openocd wget
sudo tee /etc/udev/rules.d/52-digilent-usb.rules > /dev/null <<'EOF'
ATTR{idVendor}=="1443", MODE:="666"
ACTION=="add", ATTR{idVendor}=="0403", ATTR{manufacturer}=="Digilent", MODE:="666"
EOF
sudo udevadm control --reload-rules
```

Disconnect the JTAG adapter from USB. Reconnect it to apply the rules.

## Download the bitstream (*.bit) and programming file (*.mcs)

From the repository root, enter the `openocd` directory:

```bash
cd openocd
```

Download the files for your board from the [latest firmware release](https://github.com/jhu-cisst/mechatronics-firmware/releases/latest).

For FPGA1394 V1 (without Ethernet):

```bash
wget -O FPGA1394V1-QLA.bit https://github.com/jhu-cisst/mechatronics-firmware/releases/latest/download/FPGA1394V1-QLA.bit
wget -O FPGA1394V1-QLA.mcs https://github.com/jhu-cisst/mechatronics-firmware/releases/latest/download/FPGA1394V1-QLA.mcs
```

For FPGA1394 V2 (with Ethernet):

```bash
wget -O FPGA1394V2-QLA.bit https://github.com/jhu-cisst/mechatronics-firmware/releases/latest/download/FPGA1394V2-QLA.bit
wget -O FPGA1394V2-QLA.mcs https://github.com/jhu-cisst/mechatronics-firmware/releases/latest/download/FPGA1394V2-QLA.mcs
```

## Load the temporary firmware

OpenOCD loads the bitstream into the FPGA. It does not write the PROM.
The FPGA loses this bitstream when you remove power.

1. Connect the JTAG adapter to the board.
2. Turn on the board or controller power.
3. Run the command for your board from the `openocd` directory.

For FPGA1394 V1:

```bash
./program_fpga.sh FPGA1394V1-QLA.bit
```

For FPGA1394 V2:

```bash
./program_fpga.sh FPGA1394V2-QLA.bit
```

## Reprogram the PROM

Keep the board powered until PROM programming is complete.
Use FireWire for V1. For V2, use FireWire or Ethernet.

1. Run `pgm1394 <n>`, where `<n>` is the FPGA board number (rotary switch).
  - For Ethernet, it may be necessary to specify the `-pudpfw` or `-pudp` option.
  - If you are using ROS, `pgm1394` should be in your path; otherwise, it can be found in the `mechatronics-software` build tree.
  - Note that the `mcs` file you downloaded earlier must be in the current working directory.
2. Press `1` to program the PROM.
3. Press `2` to verify the programming.
4. Press `0` to exit (or `8` to exit and reboot).
5. Turn off the board or controller power.
6. Disconnect the JTAG adapter from the board.
7. Turn on the board or controller power.

For more details, consult the [`pgm1394` instructions](https://github.com/jhu-cisst/mechatronics-firmware/wiki/FPGA-Program).
