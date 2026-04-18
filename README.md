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
5. SHH into the device
    1. Host: `evcc`
    2. Username: `admin`
    3. Password: `admin`
    4. Port: `22`
6. Change the admin password for the device when prompted
7. SFTP into the device using the details from step 5 with the new password
8. Transfer `configure.sh` to the `/home/admin` directory
9. Return to your SSH terminal and run the following commands
    1. `chmod u+w configure.sh`
    2. `sudo bash ./configure.sh`

## Common issues

### Unable to login

The admin password for the device is independent to the admin password for EVCC

### Warning/Error message: `$'\r': command not found`

Run this command: `sed -i 's/\r$//' ./configure.sh`
