#!/bin/bash
set -euo pipefail

# Security/footprint - disable services that are unused on a headless kiosk (rpcbind in particular
# reduces attack surface). Not a performance tweak; kept for hygiene.
sudo systemctl disable --now avahi-daemon bluetooth rpcbind || true

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
