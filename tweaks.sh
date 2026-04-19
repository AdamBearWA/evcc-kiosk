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

# Performance tweak - maximise use of zram swap
echo 'vm.swappiness=80' | sudo tee /etc/sysctl.d/99-swappiness.conf

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
