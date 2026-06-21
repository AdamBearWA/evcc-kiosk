#!/bin/bash
set -euo pipefail

# Performance tweak - configure zram: double swap size, use faster compression
sudo sed -i 's/^# ZRAM_PERCENTAGE=50/# ZRAM_PERCENTAGE=50\nZRAM_PERCENTAGE=100/' /etc/default/armbian-zram-config
sudo sed -i 's/^# SWAP_ALGORITHM=lzo/# SWAP_ALGORITHM=lzo\nSWAP_ALGORITHM=lz4/' /etc/default/armbian-zram-config

# Performance tweak - disable unnecessary services
sudo systemctl disable --now avahi-daemon bluetooth rpcbind || true

# Performance tweak - set GPU memory to 32MB (sufficient for web kiosk, frees RAM for EVCC and Cog)
sudo sed -i '/^gpu_mem=/d' /boot/firmware/config.txt
echo 'gpu_mem=32' | sudo tee -a /boot/firmware/config.txt > /dev/null

# Performance tweak - keep swappiness high (100), which is correct for a zram swap device.
# With zram, swapping anonymous pages is cheap (compressed in RAM), so a high value lets the
# kernel park anon data in zram and keep file-backed pages - notably the executable code pages
# of cog and evcc - resident. Lowering swappiness instead evicts those code pages and forces
# them to be re-read from the slow SD card, which thrashes and is measurably slower on touch.
# The Armbian image appends vm.swappiness=100 to /etc/sysctl.conf, which is applied last and
# overrides anything in /etc/sysctl.d, so the value must be set there directly.
if grep -q '^vm\.swappiness=' /etc/sysctl.conf; then
	sudo sed -i 's/^vm\.swappiness=.*/vm.swappiness=100/' /etc/sysctl.conf
else
	echo 'vm.swappiness=100' | sudo tee -a /etc/sysctl.conf > /dev/null
fi

# Performance tweak - pin the CPU governor to performance. The default (ondemand) leaves the
# cores idling at 600 MHz and only ramps up *after* load appears, which adds latency to the
# bursty, CPU-bound rendering the EVCC UI does on every touch. On a mains-powered kiosk there is
# no reason to scale down, so hold all cores at their max clock. A tiny oneshot service applies
# this on every boot without depending on cpufrequtils being installed.
sudo tee /etc/systemd/system/cpu-governor.service << 'EOF'
[Unit]
Description=Pin CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g"; done'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable cpu-governor.service

# Reliability tweak - use volatile journald storage to reduce SD card wear
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/volatile.conf << 'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=10M
EOF

# Reliability tweak - move /tmp to RAM to reduce SD card wear
sudo tee /etc/systemd/system/tmp.mount << 'EOF'
[Unit]
Description=Temporary Directory
ConditionPathIsSymbolicLink=!/tmp

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
Options=mode=1777,strictatime,nosuid,nodev,size=50M

[Install]
WantedBy=local-fs.target
EOF
sudo systemctl enable tmp.mount

# Security tweak - turn off root auto-login on the console
sudo mv /etc/systemd/system/getty@.service.d/override.conf /etc/systemd/system/getty@.service.d/override.conf.disabled 2>/dev/null || true

# Reboot to apply all tweaks
sudo reboot
