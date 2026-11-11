# usbblock

Hides chosen USB devices from macOS, so they never reach CoreAudio or any other driver. For example, it can drop the speakers and mic built into an LG UltraFine display while keeping the display, camera and brightness controls.

It captures each matching device the way VM apps do for USB passthrough. Capturing detaches every macOS driver from that one device; root doesn't need the `com.apple.vm.device-access` entitlement for it. Devices are matched by vendor and product ID and captured again whenever they reappear (replug, sleep/wake, reboot). Stop the daemon and macOS resets them, and they come back.

On macOS 27, USB audio runs in a userspace driver (`usbaudiod`) that doesn't notice when its clients are removed, so CoreAudio keeps listing stale devices. After capturing, usbblock restarts `usbaudiod` once; other USB audio devices blip for under a second.

When the thing you want gone is its own USB device, usbblock captures the whole device. The LG display audio is (`043e:9a4b`, separate from the camera and controls).

When audio shares a device with something you want to keep, such as a camera or capture card with a built-in mic, add `:audio` to the ID (`046d:082d:audio` for a Logitech C920 webcam). usbblock then claims only that device's USB Audio interfaces, and the video keeps working. `usbaudiod` holds those interfaces and ignores requests to close them, so usbblock kills it and opens them in the few milliseconds before macOS starts it again. On exit it restarts `usbaudiod` once more so the audio comes back.

`launchd` starts `usbaudiod` again at most once every 10 seconds. Two restarts within that window (for example, stopping usbblock right after it started) leave every USB audio device offline for a few seconds.

## Use

```sh
swift build -c release
sudo .build/release/usbblock 043e:9a4b     # try it in the foreground; Ctrl-C releases
sudo .build/release/usbblock 046d:082d:audio   # audio only, keep the camera
sudo ./install.sh                          # run as a launchd daemon
sudo ./uninstall.sh
```

Device IDs live in `launchd/com.thatjuan.usbblock.plist`; edit them and rerun `install.sh`. Find IDs with:

```sh
ioreg -p IOUSB -l -w0 | grep -E '"USB Product Name"|"idVendor"|"idProduct"'
```

`ioreg` prints IDs in decimal; usbblock takes hex (`1086` → `043e`).

Log: `/var/log/usbblock.log`.
