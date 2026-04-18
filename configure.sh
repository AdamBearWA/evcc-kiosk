#!/bin/bash

# Clone Cog master branch
git clone --branch master https://github.com/Igalia/cog.git ~/cog

# Update package lists
sudo apt update

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
