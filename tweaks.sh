#!/bin/bash

# Performance tweak - double zram swap size and use faster compression method
sudo sed -i 's/^# ZRAM_PERCENTAGE=50/# ZRAM_PERCENTAGE=50\nZRAM_PERCENTAGE=100/' /etc/default/armbian-zram-config
sudo sed -i 's/^# MEM_LIMIT_PERCENTAGE=50/# MEM_LIMIT_PERCENTAGE=50\nMEM_LIMIT_PERCENTAGE=100/' /etc/default/armbian-zram-config
sudo sed -i 's/^# SWAP_ALGORITHM=lzo/# SWAP_ALGORITHM=lzo\nSWAP_ALGORITHM=lz4/' /etc/default/armbian-zram-config

# Performance tweak - disable unnecessary services
sudo systemctl disable --now avahi-daemon bluetooth rpcbind

# Performance tweak - reduce GPU memory from 64MB to 16MB to free RAM for EVCC and Cog
sudo grep -qxF 'gpu_mem=16' /boot/firmware/config.txt || echo 'gpu_mem=16' | sudo tee -a /boot/firmware/config.txt > /dev/null

# Performance tweak - reduce kernel swap aggressiveness
echo 'vm.swappiness=100' | sudo tee /etc/sysctl.d/99-swappiness.conf

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
sudo mv /etc/systemd/system/getty@.service.d/override.conf /etc/systemd/system/getty@.service.d/override.conf.disabled

# Reboot to apply all tweaks
sudo reboot
