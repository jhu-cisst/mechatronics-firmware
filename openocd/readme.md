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

## Download the bitstream

From the repository root, enter the `openocd` directory:

```bash
cd openocd
```

Download the bitstream for your board from the [latest firmware release](https://github.com/jhu-cisst/mechatronics-firmware/releases/latest).

For FPGA1394 V1 (without Ethernet):

```bash
wget -O FPGA1394V1-QLA.bit https://github.com/jhu-cisst/mechatronics-firmware/releases/latest/download/FPGA1394V1-QLA.bit
```

For FPGA1394 V2 (with Ethernet):

```bash
wget -O FPGA1394V2-QLA.bit https://github.com/jhu-cisst/mechatronics-firmware/releases/latest/download/FPGA1394V2-QLA.bit
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

1. Follow the [`pgm1394` instructions](https://github.com/jhu-cisst/mechatronics-firmware/wiki/FPGA-Program) to reprogram the PROM.
2. Turn off the board or controller power.
3. Disconnect the JTAG adapter from the board.
4. Turn on the board or controller power.
