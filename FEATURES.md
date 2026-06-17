# xmos_dfu

Command-line firmware flasher for XMOS-based JDS Labs USB DACs (Atom DAC(+), EL DAC II(+), Element II/III/IV). A single C++ source (`xmosdfu.cpp`) drives libusb to send a vendor firmware `.bin` to the device over the USB DFU 1.0 protocol plus XMOS vendor-specific control requests. Forked from the XMOS USB Audio 2.0 Reference Software v6.15.2 (MIT-style license, © 2011 XMOS Ltd).

## Stack
C++ (compiled with `g++`), libusb-1.0 for raw USB control transfers. No other deps. Builds on Linux, macOS (Intel/Apple Silicon), Windows (MSYS2/MinGW-w64). Firmware images are opaque binary blobs; the tool does no validation of them.

## Architecture (DFU/USB flow)
Device match: scans `libusb_get_device_list` for VID `0x20b1` (XMOS) or `0x152A` (Thesycon), then a hardcoded `pidList[]` of JDS Labs PIDs (e.g. EL4=`0x88fa`, EL4-DFU=`0x88fc`, Atom=`0x30E1`). The DFU interface is found by scanning config descriptors for `bInterfaceClass==0xFE`/`bInterfaceSubClass==0x1`. Firmware version is decoded from `bcdDevice`.

Control-transfer constants: host→dev `bmRequestType=0x21`, dev→host `0xa1`. Standard DFU requests: `DNLOAD=1`, `UPLOAD=2`, `GETSTATUS=3`, `CLRSTATUS=4`, `GETSTATE=5`, `DETACH=0`, `ABORT=6`. XMOS vendor requests: `RESETINTODFU=0xf2`, `RESETFROMDFU=0xf3`, `RESETDEVICE=0xf0`, `REVERTFACTORY=0xf1`, `SAVESTATE=0xf5`, `RESTORESTATE=0xf6`.

Download sequence (`--download`): claim DFU interface → send `RESETINTODFU` (vendor 0xf2) → release/close → `sleep(3)` while device reboots into DFU-mode PID → re-find & re-open device → `write_dfu_image()`: read file in 64-byte blocks, each via `DFU_DNLOAD(block_num, 64 bytes)` followed by `DFU_GETSTATUS` (6-byte status: state/timeout/nextState/strIndex); a final zero-length `DFU_DNLOAD` terminates → `RESETFROMDFU` (0xf3) returns the DAC to application mode. `--upload` reverses this (`DFU_UPLOAD` until 0 bytes). `--revertfactory` sends `REVERTFACTORY` then resets; `--savecustomstate`/`--restorecustomstate` skip DFU mode entirely.

## Run/Build
Build (in `xmos_dfu/xmos_dfu/`):
```sh
make -f Makefile linux     # Linux: pkg-config --libs libusb-1.0
make -f Makefile mac       # macOS: links $(brew --prefix libusb)/lib/libusb-1.0.0.dylib
make windows               # MSYS2 MinGW64 -> xmosdfu.exe
```
Linux dep: `sudo apt-get install libusb-1.0-0-dev`. macOS: `brew install libusb`. macOS also needs `source setup.sh` (sets `DYLD_LIBRARY_PATH=$PWD`).

Invoke:
```sh
./xmosdfu --listdevices                          # list DACs + firmware versions (no sudo path-out on -1)
sudo ./xmosdfu --download "/path/to/firmware.bin"  # flash (Linux/macOS need sudo unless udev rule installed)
sudo ./xmosdfu --upload   "/path/out.bin"
sudo ./xmosdfu --revertfactory
xmosdfu.exe --download "C:\path\firmware.bin"      # Windows
```
Install Linux udev rule (grants non-root access via `uaccess`):
```sh
sudo cp packaging/linux/70-jdslabs.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```
Windows GUI helper: double-click `windows/flash-element4.bat` — fetches the live firmware catalog from `https://dsp.api.jdslabs.com/api/firmware/` (+ `/beta-firmware/`), downloads the chosen `.bin` to `%TEMP%`, and shells out to `xmosdfu.exe --download`.

## Key files
- `/home/andrei/dev/xmos_dfu/xmos_dfu/xmosdfu.cpp` — entire tool: device discovery, DFU/XMOS control transfers, image read/send loop, CLI parsing.
- `/home/andrei/dev/xmos_dfu/xmos_dfu/Makefile` — `linux`/`mac`/`mac-m1`/`windows`/`clean` targets.
- `/home/andrei/dev/xmos_dfu/xmos_dfu/setup.sh` — exports `DYLD_LIBRARY_PATH` (macOS dylib lookup).
- `/home/andrei/dev/xmos_dfu/packaging/linux/70-jdslabs.rules` — udev rules tagging all JDS VID/PID pairs with `uaccess`.
- `/home/andrei/dev/xmos_dfu/windows/flash-element4.bat` — interactive Windows batch flasher hitting the JDS firmware API.
- `/home/andrei/dev/xmos_dfu/windows/xmosdfu.exe` — precompiled Windows binary; `libusb-1.0.dll` (1.0.22, LGPL-2.1) shipped alongside.
- `/home/andrei/dev/xmos_dfu/windows/el4-firwmare/el4-v151-upgrade.bin`, `el4-v174-upgrade.bin` — bundled Element IV firmware images (note misspelled dir name "firwmare").
- `/home/andrei/dev/xmos_dfu/README.md` — per-OS build/flash instructions. `LICENSE.txt` — XMOS MIT-style license.

## Gotchas
- No firmware validation: the tool only checks VID/PID, never the `.bin` contents or model match — wrong firmware loads silently. Recover by re-flashing the correct image (or factory revert).
- Connect exactly one DAC; require a direct USB 2.0/3.0 port — hubs and some USB-C/3.1 ports break DFU.
- Linux/macOS need `sudo` unless the udev rule is installed (so libusb can claim the interface).
- The 3-second post-`RESETINTODFU` sleep is hardcoded; slow re-enumeration can cause "Could not find/open DFU device".
- Element IV below v1.4.0 must flash v1.5.1 first, then jump to latest (firmware >v1.5.3 fails from old versions). The Windows tool exists because some EL4 units stall/corrupt on WinUSB; libusb is an alternative but not guaranteed.
- `main()` returns `1` on the success path (non-standard exit code).
- macOS includes `libusb.h` locally (`#include "libusb.h"`) while Linux/Windows use the system `<libusb-1.0/libusb.h>`.
