# evcc-kiosk
Configuration for a Raspberry Pi Zero 2 W with a Waveshare ZERO-DISP-7a display running EVCC server and UI in kiosk mode

## Pre-requisites

### Hardware

* [Rasbperry Pi Zero 2 W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/)
* [Waveshare 7" Display Zero-DISP-7A](https://www.waveshare.com/wiki/Zero-DISP-7A)
* Micro SD Card
* USB-C power supply
  * 5V 3A+ so it powers both the display and Pi reliably
* Ethernet cable (this guide doesn't not include WiFi configuration)

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
