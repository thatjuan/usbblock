# usbblock

Hides chosen USB devices from macOS, so they never reach CoreAudio or any other driver. For example, it can drop the speakers and mic built into an LG UltraFine display while keeping the display, camera and brightness controls.

It captures each matching device the way VM apps do for USB passthrough. Capturing detaches every macOS driver from that one device; root doesn't need the `com.apple.vm.device-access` entitlement for it. Devices are matched by vendor and product ID and captured again whenever they reappear (replug, sleep/wake, reboot). Stop the daemon and macOS resets them, and they come back.

On macOS 27, USB audio runs in a userspace driver (`usbaudiod`) that doesn't notice when its clients are removed, so CoreAudio keeps listing stale devices. After capturing, usbblock restarts `usbaudiod` once; other USB audio devices blip for under a second.

When the thing you want gone is its own USB device, usbblock captures the whole device. The LG display audio is (`043e:9a4b`, separate from the camera and controls).

When audio shares a device with something you want to keep, such as a camera or capture card with a built-in mic, add `:audio` to the ID (`046d:082d:audio` for a Logitech C920 webcam). usbblock then claims only that device's USB Audio interfaces, and the video keeps working. `usbaudiod` holds those interfaces and ignores requests to close them, so usbblock kills it and opens them in the few milliseconds before macOS starts it again. On exit it restarts `usbaudiod` once more so the audio comes back.

`launchd` starts `usbaudiod` again at most once every 10 seconds. Two restarts within that window (for example, stopping usbblock right after it started) leave every USB audio device offline for a few seconds.

## Use

Build and install the daemon from source:

```sh
swift build -c release && sudo .build/release/usbblock enable
```

Use `.build/release/usbblock` for the commands below, or put that binary on your `PATH`.

```sh
usbblock list                              # attached devices and their hex IDs
usbblock list --all                        # include hubs
usbblock add                               # pick a device interactively
usbblock add 043e:9a4b                      # block the whole display audio device
usbblock add 046d:082d:audio                 # block the webcam mic, keep video
usbblock status                            # daemon and live blocking state
usbblock remove 046d:082d                   # remove either blocking mode
usbblock logs -n 50                         # recent daemon log
usbblock logs -f                            # follow the log
usbblock disable                           # stop and remove the daemon, keep config
```

Commands that change the configuration or control the daemon ask for root access through `sudo`. Blocking a whole device with keyboard/mouse interfaces requires `--force`; the interactive picker asks for confirmation instead. Use `--name "Device name"` with `add` to supply a name for a device that isn't attached.

Rules live in `/etc/usbblock.conf`, one `vendor:product[:audio]` ID per line, with optional `#` comments. Missing config means no devices are blocked. You can edit it by hand and run `sudo usbblock enable` to reload. Run `enable` again after building a new version to install it into the daemon; it also imports device IDs from a pre-CLI install on first use.

Adding or removing a rule reloads an installed daemon. A reload can leave other USB audio devices offline for a few seconds: the exiting daemon restarts `usbaudiod`, and the new instance restarts it again after its claims settle. `launchd` limits those restarts to once every 10 seconds.

For foreground blocking, use `usbblock run 043e:9a4b` or `usbblock run 046d:082d:audio`; Ctrl-C releases the device. With no IDs, `usbblock run` reads the config and stays alive even when it is empty. Log: `/var/log/usbblock.log`.
