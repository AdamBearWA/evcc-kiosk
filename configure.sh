#!/bin/bash
set -euo pipefail

# Clone Cog and check out pinned commit
# Pinned to commit 3d7ca00 which includes the touch coordinate rotation fix
# required for portrait displays. Release 0.18.5 does not include this fix.
git clone https://github.com/Igalia/cog.git ~/cog
git -C ~/cog checkout 3d7ca00

# Update package lists
sudo apt update

# Verify pinned libudev-dev version is available before attempting install
LIBUDEV_VERSION="254.26-1~bpo12+1"
if ! apt-cache show "libudev-dev=${LIBUDEV_VERSION}" > /dev/null 2>&1; then
	echo "ERROR: Required package libudev-dev=${LIBUDEV_VERSION} not found in apt cache."
	echo "Run 'apt-cache policy libudev-dev' to see available versions."
	exit 1
fi

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

# Create dedicated unprivileged user for kiosk service
sudo useradd -r -s /bin/false -G video,render,input kiosk 2>/dev/null || true

# Create kiosk systemd service to start Cog on boot
sudo tee /etc/systemd/system/kiosk.service << 'EOF'
[Unit]
Description=EVCC Kiosk Browser
After=network.target evcc.service

[Service]
User=kiosk
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

# Verify the kiosk service started successfully
echo ""
if systemctl is-active --quiet kiosk.service; then
	echo "============================================"
	echo "  Kiosk service is running successfully."
	echo "============================================"
else
	echo "ERROR: Kiosk service failed to start."
	echo "Run 'sudo journalctl -u kiosk.service' for details."
	exit 1
fi
