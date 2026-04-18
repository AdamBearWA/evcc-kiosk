#!/bin/bash

# Update package list
sudo apt update

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

# Clone Cog master branch
git clone --branch master https://github.com/Igalia/cog.git ~/cog

# Install build dependencies
sudo apt install -y cmake ninja-build pkg-config meson libwpewebkit-1.1-dev libwpe-1.0-dev libglib2.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libegl-dev libgbm-dev libinput-dev libxkbcommon-dev libwpebackend-fdo-1.0-dev libudev-dev=254.26-1~bpo12+1

# Install runtime dependencies
sudo apt install -y libgles2 libwpewebkit-1.1-0 libinput10

# Configure the Cog build for DRM platform only
cd ~/cog && meson setup build --buildtype=release -Dplatforms=drm

# Compile Cog
ninja -C ~/cog/build

# Install Cog
sudo ninja -C ~/cog/build install

# Update shared library cache
sudo ldconfig

# Create kiosk systemd service to start Cog on boot
sudo tee /etc/systemd/system/kiosk.service << 'EOF'
[Unit]
Description=EVCC Kiosk Browser
After=network.target evcc.service

[Service]
User=root
Environment=COG_PLATFORM_DRM_VIDEO_DEVICE=/dev/dri/card0
ExecStart=/usr/local/bin/cog --platform=drm --platform-params=renderer=gles,rotation=1 http://localhost:7070
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the kiosk service
sudo systemctl daemon-reload
sudo systemctl enable kiosk.service
sudo systemctl start kiosk.service

# Set EVCC admin password
echo ""
echo "============================================"
echo "  Setup complete. Please set the EVCC admin"
echo "  password when prompted below."
echo "============================================"
echo ""
sudo systemctl stop evcc.service
sudo evcc --database /var/lib/evcc/evcc.db password set
sudo systemctl start evcc.service
