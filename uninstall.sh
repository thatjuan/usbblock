#!/bin/sh
# Removes the daemon; macOS resets the blocked devices and they come back.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
plist=/Library/LaunchDaemons/com.thatjuan.usbblock.plist
launchctl bootout system "$plist" 2>/dev/null || true
rm -f "$plist" /usr/local/libexec/usbblock
echo "uninstalled"
