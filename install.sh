#!/bin/sh
# Installs usbblock as a launchd daemon. Build first: swift build -c release
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -x .build/release/usbblock ] || { echo "build first: swift build -c release" >&2; exit 1; }

plist=/Library/LaunchDaemons/com.thatjuan.usbblock.plist
launchctl bootout system "$plist" 2>/dev/null || true
install -d /usr/local/libexec
install -m 755 .build/release/usbblock /usr/local/libexec/usbblock
install -m 644 -o root -g wheel launchd/com.thatjuan.usbblock.plist "$plist"
launchctl bootstrap system "$plist"
echo "installed; log: /var/log/usbblock.log"
