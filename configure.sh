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

# Create dedicated unprivileged user for the kiosk service, with a persistent home directory.
# The home is where WPEWebKit stores its browser profile, so the one-off dark-mode preference
# (see README) survives both the nightly restart and reboots.
sudo useradd -r -m -d /var/lib/kiosk -s /usr/sbin/nologin -G video,render,input kiosk 2>/dev/null || true

# Create kiosk systemd service to start Cog on boot
sudo tee /etc/systemd/system/kiosk.service << 'EOF'
[Unit]
Description=EVCC Kiosk Browser
After=network.target evcc.service

[Service]
User=kiosk
# Persistent home so WPEWebKit stores its profile (incl. the dark-mode preference) on disk
Environment=HOME=/var/lib/kiosk
WorkingDirectory=/var/lib/kiosk
Environment=COG_PLATFORM_DRM_VIDEO_DEVICE=/dev/dri/card0
# Tell WPEWebKit this is a small device so it sizes its internal caches conservatively (256 MiB)
Environment=WPE_RAM_SIZE=268435456
ExecStart=/usr/local/bin/cog --platform=drm --platform-params=renderer=gles,rotation=3 http://localhost:7070
Restart=always
RestartSec=5
# Bound browser memory: WebKit's memory-pressure handler reacts to MemoryHigh by shedding
# caches; MemoryMax is a hard ceiling so a runaway browser is restarted instead of triggering
# a system-wide OOM that could kill evcc.
MemoryAccounting=yes
MemoryHigh=200M
MemoryMax=260M

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the kiosk service
sudo systemctl daemon-reload
sudo systemctl enable kiosk.service
sudo systemctl start kiosk.service

# Install unattended-upgrades for automatic security + evcc updates, plus needrestart to restart
# services affected by library upgrades (so security patches take effect without a full reboot)
# and to detect when a kernel reboot is genuinely required.
sudo apt install -y unattended-upgrades needrestart

# Let needrestart restart affected services automatically (this is a non-interactive kiosk).
sudo mkdir -p /etc/needrestart/needrestart.conf.d
sudo tee /etc/needrestart/needrestart.conf.d/99-kiosk.conf << 'EOF'
$nrconf{restart} = 'a';
EOF

# Restrict unattended-upgrades to Debian security plus the evcc apt repo. The Armbian image's
# default Origins-Pattern allows the entire Debian archive and all Armbian packages (including the
# kernel), so clear it and redefine it narrowly - this keeps kernel/BSP and general package churn
# out of the automatic upgrades, protecting the hand-built Cog. Rebooting is handled by the
# update service below, not here.
sudo tee /etc/apt/apt.conf.d/52kiosk-unattended << 'EOF'
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=bookworm,label=Debian-Security";
    "origin=Debian,codename=bookworm-security,label=Debian-Security";
    "origin=cloudsmith/evcc/stable,codename=bookworm";
};
EOF

# Drive the update from a single timer at 04:00 instead of the default apt-daily timers, so it
# lands in one predictable maintenance window.
sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

# One ordered nightly job: update package lists, apply security + evcc upgrades (needrestart
# restarts any affected services so patches take effect), then recycle the browser exactly once -
# reboot if needrestart reports a kernel reboot is required (which also clears the WPEWebKit
# leak), otherwise just restart the kiosk browser. The leading '-' on the apt steps makes them
# non-fatal, so the browser is recycled even if an update step fails.
sudo tee /etc/systemd/system/kiosk-update.service << 'EOF'
[Unit]
Description=Nightly apt update, unattended security/evcc upgrades, and browser recycle
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=-/usr/bin/apt-get update -qq
ExecStart=-/usr/bin/unattended-upgrade -v
ExecStart=/usr/bin/bash -c 'if needrestart -bk 2>/dev/null | grep -q "^NEEDRESTART-KSTA: 3"; then systemctl reboot; else systemctl restart kiosk.service; fi'
EOF

sudo tee /etc/systemd/system/kiosk-update.timer << 'EOF'
[Unit]
Description=Nightly EVCC kiosk update check at 04:00

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now kiosk-update.timer

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
