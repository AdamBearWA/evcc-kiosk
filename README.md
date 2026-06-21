# evcc-kiosk
Configuration for a Raspberry Pi Zero 2 W with a Waveshare ZERO-DISP-7a display running EVCC server and UI in kiosk mode

## Pre-requisites

### Hardware

* [Rasbperry Pi Zero 2 W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/)
* [Waveshare 7" Display Zero-DISP-7A](https://www.waveshare.com/wiki/Zero-DISP-7A)
* Micro SD Card
* USB-C power supply
  * 5V 3A+ so it powers both the display and Pi reliably
* Ethernet cable (this guide does not include WiFi configuration)

### Software

Download and install [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
When you run it follow the options below to load the EVCC specific version to your SD card.

1. Device: Raspberry Pi Zero 2 W `Next`
2. OS: Other specific-purpose OS > Home automation > evcc > evcc `Next`
3. Storage: Choose your SD card `Next`

## Configuration

1. Insert the SD card with the EVCC software into the Pi
2. Install the Pi on the back of the display
3. Plug in ethernet and USB-C power
4. Wait for the device to boot
5. SSH into the device
   1. Run this command on your local machine (bash & PowerShell): `ssh admin@evcc`
   2. When prompted for the password enter `admin`
   3. When prompted, change the password
6. Reconnect to the device via SSH with the new password
7. Apply the tweaks script to the device by running this command:
   - `sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/AdamBearWA/evcc-kiosk/main/tweaks.sh | sudo bash`
8. Wait for the device to reboot
9. Reconnect to the device via SSH with the new password
10. Configure the device by running this command":
    - `curl -sSL https://raw.githubusercontent.com/AdamBearWA/evcc-kiosk/main/configure.sh | sudo bash`
11. Set the display to dark mode (one-off):
    1. On the device's touchscreen, open the evcc menu and switch the theme to **Dark**
    2. This only needs to be done once. The preference is saved to the kiosk user's browser profile under `/var/lib/kiosk`, so it persists across the nightly browser restart and across reboots.

## Maintenance

The device maintains itself nightly at 04:00 via the `kiosk-update.timer` systemd timer, which runs a single ordered job:

1. Refreshes the apt package lists.
2. Applies unattended upgrades, scoped to **Debian security updates** and **evcc** only. `needrestart` restarts any services affected by a library update so the patches take effect without a reboot.
3. Recycles the browser exactly once: it **reboots** if a kernel update requires it (which also clears the gradual WPEWebKit memory growth), otherwise it just **restarts the browser** (which clears that growth on its own).

The kernel, Armbian board-support packages, and general OS packages are deliberately **excluded** from the automatic upgrades to keep the pinned, hand-built Cog browser stable. Apply those manually when needed:

```
sudo apt update && sudo apt full-upgrade
sudo reboot
```

## Performance

The Pi Zero 2 W is a modest device (quad-core Cortex-A53 at 1 GHz, 512 MB RAM), so `tweaks.sh` and `configure.sh` deliberately tune it for kiosk responsiveness:

* **CPU governor** is pinned to `performance` so all cores stay at full clock instead of idling at 600 MHz and ramping up only after load appears.
* **Swappiness** is kept at 100, which is correct for the zram swap device: cheap, compressed anonymous pages go to zram while executable code pages stay resident in RAM (a lower value forces code to be re-read from the slow SD card).
* **Browser memory limits** (`MemoryHigh`/`MemoryMax` on `kiosk.service`) are sized to sit above the browser's transient per-interaction memory spike, so the kernel's cgroup throttle does not stall the render thread on every touch.

Note that the **local touchscreen UI is inherently CPU-bound**: the Pi renders EVCC's full web app on a weak core, so on-screen updates are slower than the same EVCC instance viewed from a remote browser (which renders on more powerful hardware). The tuning above removes the avoidable stalls, but the device's CPU is the ultimate limit on local touch responsiveness.
