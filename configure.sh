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
# The home is where WPEWebKit stores its browser profile and caches, kept on disk so they survive
# the nightly restart and reboots.
sudo useradd -r -m -d /var/lib/kiosk -s /usr/sbin/nologin -G video,render,input kiosk 2>/dev/null || true

# Install the lightweight kiosk UI. This is a single static page (vanilla JS, inline CSS, no
# framework, no animated SVG, no charts) that Cog loads from disk via file:// and which talks
# directly to the EVCC API and websocket on :7070. EVCC sends Access-Control-Allow-Origin: * and
# does not origin-check /ws, so a file:// page can read state and post mode changes without any
# proxy. It is far cheaper to render than EVCC's stock SPA, which is the binding constraint on
# local touch responsiveness on this weak core (see README Performance section).
sudo curl -fsSL https://raw.githubusercontent.com/AdamBearWA/evcc-kiosk/main/kiosk/index.html -o /var/lib/kiosk/index.html
sudo chown kiosk:kiosk /var/lib/kiosk/index.html
sudo chmod 0644 /var/lib/kiosk/index.html

# Create kiosk systemd service to start Cog on boot
sudo tee /etc/systemd/system/kiosk.service << 'EOF'
[Unit]
Description=EVCC Kiosk Browser
After=network.target evcc.service

[Service]
User=kiosk
# Persistent home so WPEWebKit keeps its profile and caches on disk across the nightly restart
Environment=HOME=/var/lib/kiosk
WorkingDirectory=/var/lib/kiosk
Environment=COG_PLATFORM_DRM_VIDEO_DEVICE=/dev/dri/card0
ExecStart=/usr/local/bin/cog --platform=drm --platform-params=renderer=gles,rotation=3 file:///var/lib/kiosk/index.html
Restart=always
RestartSec=5
# Hard memory ceiling as an OOM safety net. WPEWebKit's working set grows slowly over a day
# (the nightly restart clears it); without a ceiling a runaway/leak could trigger a system-wide
# OOM that kills evcc, so cap the browser cgroup and let systemd restart it instead. The
# lightweight kiosk page sits at around 62 MiB, far under this ceiling.
MemoryAccounting=yes
MemoryMax=340M

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
# restarts any affected services so patches take effect), then reboot. The unconditional reboot
# clears the WPEWebKit memory leak that accumulates over the day. The leading '-' on the apt
# steps makes them non-fatal, so the reboot happens even if an update step fails.
sudo tee /etc/systemd/system/kiosk-update.service << 'EOF'
[Unit]
Description=Nightly apt update, unattended security/evcc upgrades, and browser recycle
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=-/usr/bin/apt-get update -qq
ExecStart=-/usr/bin/unattended-upgrade -v
ExecStart=/bin/systemctl reboot
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

# Set the device timezone. The kiosk clock shows the device's local time, so if the timezone is
# unset or wrong (e.g. UTC) the clock reads incorrectly. Prompt for an IANA timezone and apply it;
# the running kiosk clock picks up the change automatically on its next tick (no restart needed).
# Read from /dev/tty so the prompt works when this script is piped via 'curl | sudo bash'.
echo ""
echo "Current device timezone: $(timedatectl show -p Timezone --value 2>/dev/null)"
echo "Enter your timezone as an IANA name, e.g. Australia/Perth or Europe/Berlin."
echo "(List every option with: timedatectl list-timezones)"
read -rp "Timezone [leave blank to keep current]: " KIOSK_TZ < /dev/tty || true
if [ -n "${KIOSK_TZ:-}" ]; then
	if sudo timedatectl set-timezone "$KIOSK_TZ"; then
		echo "Timezone set to $KIOSK_TZ."
	else
		echo "WARNING: '$KIOSK_TZ' is not a valid timezone; leaving it unchanged."
	fi
fi

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
