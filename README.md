# usbblock

usbblock hides chosen USB devices, or just their audio, from macOS.

Displays, docks, webcams and capture cards add speakers and microphones you never use. macOS keeps selecting them, and there is no setting to hide them. usbblock makes them disappear at the USB level and keeps them gone across replugs, sleep and reboots.

## Install

Requires macOS 14 or later. Tested on macOS 27. Release binaries support Apple silicon and Intel Macs.

```sh
brew install thatjuan/tap/usbblock
```

Or install the latest release with the script:

```sh
curl -fsSL https://raw.githubusercontent.com/thatjuan/usbblock/main/install.sh | sh
```

The script checks the archive's SHA-256 checksum and installs to `/usr/local/bin/usbblock`. To build it yourself, see [Build from source](#build-from-source).

## Quick start

The output below is a hand-written example. Your device names, version, process ID and start time will differ.

1. Find the device you want to hide:

   ```sh
   usbblock list
   ```

   ```text
   ID         NAME                       VENDOR    INTERFACES    STATUS
   043e:9a4b  LG UltraFine Display Audio  LG        audio         -
   046d:082d  Logitech C920              Logitech  audio, video  -
   ```

2. Pick it from the interactive list:

   ```sh
   sudo usbblock add
   ```

   ```text
   1  043e:9a4b  LG UltraFine Display Audio  audio
   2  046d:082d  Logitech C920               audio, video
   Block which device? 1
   Added 043e:9a4b (LG UltraFine Display Audio).
   The daemon isn't running. Start it with: sudo usbblock enable
   ```

   For a device with audio and other interfaces, the picker asks whether to block audio only or the whole device.

3. Install and start the daemon:

   ```sh
   sudo usbblock enable
   ```

   ```text
   Installed /usr/local/libexec/usbblock (0.1.0).
   Daemon started. Blocking 1 devices from /etc/usbblock.conf.
   ```

4. Wait five seconds, then check the result:

   ```sh
   usbblock status
   ```

   ```text
   usbblock 0.1.0
   Daemon:  running (pid 1234, started 01/01/2026, 12:00 PM)
   Config:  /etc/usbblock.conf

   ID         NAME                       STATE
   043e:9a4b  LG UltraFine Display Audio  blocked
   ```

That's it. The daemon starts at boot and re-blocks the device whenever it reappears.

## Whole device or audio only

Use `vvvv:pppp` when the unwanted function is its own USB device. For example, `sudo usbblock add 043e:9a4b` hides the LG UltraFine display's audio device. Its camera and brightness controls are separate USB devices and keep working.

Use `vvvv:pppp:audio` when audio shares a USB device with something you want to keep. For example, `sudo usbblock add 046d:082d:audio` hides a Logitech C920 webcam's microphone while keeping its video. The IDs are hexadecimal; a rule applies to every attached device with that vendor and product ID.

To undo one rule, run `sudo usbblock remove` and pick it, or use `sudo usbblock remove 046d:082d`. Removing by ID works for either blocking mode. Adding or removing a rule reloads an installed daemon.

## Commands

| Command | What it does | Needs sudo |
| --- | --- | --- |
| `usbblock list` | List attached devices, interfaces and blocking state. | No |
| `usbblock list --all` | Include USB hubs. | No |
| `usbblock add` | Pick a device and blocking mode interactively. | Yes |
| `usbblock add 043e:9a4b` | Add a rule directly by ID; append `:audio` for audio only. | Yes |
| `usbblock remove` | Pick a configured rule to remove. | Yes |
| `usbblock remove 046d:082d` | Remove the rule for this ID in either blocking mode. | Yes |
| `usbblock enable` | Install this binary and start or reload the boot daemon. | Yes |
| `usbblock disable` | Stop and remove the daemon; keep config and logs. | Yes |
| `usbblock status` | Show daemon version and each rule's live state. | No |
| `usbblock logs` | Show the last 50 lines of `/var/log/usbblock.log`. | No |
| `usbblock logs -n 100` | Choose how many log lines to show. | No |
| `usbblock logs -f` | Follow new log messages; Ctrl-C stops following. | No |
| `usbblock run` | Block saved rules in the foreground; Ctrl-C releases devices. | Yes |
| `usbblock run 046d:082d:audio` | Block explicit IDs in the foreground, ignoring config; accepts several IDs. | Yes |
| `usbblock --help` | Show commands and options; each command also accepts `--help`. | No |
| `usbblock --version` | Print the CLI version. | No |

Commands that need root also invoke `sudo` themselves if you omit it. `add` accepts `--name "Device name"` to save a name, including for an unplugged device. Adding the same ID with a different mode replaces its previous rule.

Rules live in `/etc/usbblock.conf`, one ID per line. Blank lines and `#` comments are allowed; an inline comment stores the device name:

```text
# Hide display audio and the webcam mic.
043e:9a4b         # LG UltraFine Display Audio
046d:082d:audio   # Logitech C920
```

After editing by hand, run `sudo usbblock enable` to apply the changes. A missing or empty config blocks nothing. The daemon writes its live state to `/var/run/usbblock.json` for `list` and `status`.

## How it works

Whole devices are captured with `IOUSBHostDevice`'s device-capture option, the mechanism VM apps use for USB passthrough. Capture detaches every macOS driver from that one device. Root can do this without the `com.apple.vm.device-access` entitlement.

Audio-only rules claim the device's USB Audio interfaces (class 1) with `IOUSBHostInterface`. `usbaudiod` holds those interfaces and ignores close requests, so usbblock kills it and opens them in the few milliseconds before launchd restarts it. Other interfaces, such as video, stay available.

On recent macOS, USB audio runs in the userspace `usbaudiod`, which doesn't notice its devices going away. usbblock restarts it after blocking so CoreAudio drops stale entries. It waits five seconds after the latest capture or pending audio claim to batch arrivals, so a display and its hub share one restart. If another client wins an audio interface back, usbblock retries, up to three restarts.

The daemon watches for matching devices and blocks them again after a replug or sleep. When the daemon stops, macOS resets captured devices and they come back. usbblock releases audio-only claims and restarts `usbaudiod` so their audio comes back too.

## Caveats

- Other USB audio devices drop out for under a second when `usbaudiod` restarts. Adding or removing rules while the daemon runs can cause a few seconds' gap because launchd limits `usbaudiod` restarts to one per 10 seconds.
- Blocking a whole device with keyboard or mouse interfaces disables them across reboots. An explicit ID requires `--force`; the interactive picker asks for confirmation. Recover with another keyboard or SSH, then run `sudo usbblock disable`.
- usbblock runs as root through `/Library/LaunchDaemons/com.thatjuan.usbblock.plist`, using a copy of the binary at `/usr/local/libexec/usbblock`.
- After `brew upgrade usbblock`, run `sudo usbblock enable` again to update the daemon's copy. Do the same after updating a script or source install. `status` warns if the daemon and CLI versions differ.

## Troubleshooting

### Device still shows up

Check `usbblock status`: `waiting` means the device is attached but has not been blocked; `not attached` means it is unplugged. Read `usbblock logs` for capture or claim failures. Wait five seconds for the audio restart, then replug the device if it still appears in Sound settings.

### Which device is my speaker?

Run `usbblock list`, unplug the display, dock or webcam, then run it again. The missing row identifies the device. Plug it back in before using the interactive picker.

### Other audio cut out briefly

This is expected when `usbaudiod` restarts. See [Caveats](#caveats) for the restart timing and longer gaps after rule changes.

### Finding IDs without the CLI

```sh
ioreg -p IOUSB -l -w0 | grep -E '"USB Product Name"|"idVendor"|"idProduct"'
```

`ioreg` prints IDs in decimal; usbblock takes hexadecimal (`1086` becomes `043e`).

## Uninstall

For Homebrew:

```sh
sudo usbblock disable && brew uninstall usbblock
```

For a script install:

```sh
curl -fsSL https://raw.githubusercontent.com/thatjuan/usbblock/main/uninstall.sh | sh
```

Both keep the config and log. After uninstalling, remove those too if you want a full cleanup:

```sh
sudo rm -f /etc/usbblock.conf /var/log/usbblock.log
```

## Build from source

Requires the Swift 6 toolchain on macOS.

```sh
git clone https://github.com/thatjuan/usbblock.git
cd usbblock
swift build -c release
sudo .build/release/usbblock enable
```

Use `.build/release/usbblock` in place of `usbblock` for the other commands, or put the binary on your `PATH`. Run `.build/release/usbblock list` and `sudo .build/release/usbblock add` to choose a device; an empty config blocks nothing.

Run the tests with:

```sh
swift test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks and release steps.

## Security

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE), copyright 2026 thatjuan.
