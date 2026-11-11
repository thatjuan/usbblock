# Contributing

## Building and testing

Use the Swift 6 toolchain on macOS 14 or later:

```sh
swift build
swift test
```

There is intentionally no CI. Reviewers run `swift build && swift test` locally.

For hardware changes, use a spare USB device, never a keyboard. Find its ID with `.build/debug/usbblock list`, then run `sudo .build/debug/usbblock run` followed by that ID to test in the foreground. Ctrl-C releases it. Check the block, replug, sleep/wake and recovery after stopping; test both whole-device and audio-only modes when relevant. Other USB audio can briefly drop out during these checks.

## Code layout

- `Sources/USBBlockCore/`: device IDs, config parsing and daemon state shared by the CLI and daemon.
- `Sources/usbblock/`: command entry point, USB enumeration, capture and audio claims, privileges and launchd setup.
- `Sources/usbblock/Commands/`: one file per CLI command.
- `Tests/USBBlockCoreTests/`: focused tests for IDs, config and state serialization.
- `scripts/`: local release build and publishing.
- `packaging/`: Homebrew formula template.

The root `install.sh` and `uninstall.sh` manage script installs from release archives.

## Style

Use Swift 6 strict concurrency. Keep changes simple and tests focused on behavior. Add short doc comments above types and non-trivial functions, and keep existing comments accurate when code changes.

## Pull requests

Keep pull requests small and focused. Describe what changed and why, how you tested it on hardware, and which macOS version you used. Say when hardware testing was not possible.

## Releasing

Releases are built locally on macOS with the Swift toolchain and GitHub CLI. You need push access to this repository and `thatjuan/homebrew-tap`. Make the source repository public before the first release so installers can download assets anonymously.

Sign in with `gh auth login`, then run from a clean, up-to-date `main`, replacing `0.1.0` with the release version:

```sh
scripts/release.sh 0.1.0 --dry-run
scripts/release.sh 0.1.0
```

The dry run builds a stripped, ad-hoc signed universal binary for Apple silicon and Intel. It checks the architectures, embedded paths, version and archive ownership, writes the archive and checksum to `dist/`, then restores `Sources/usbblock/Version.swift`. It publishes nothing. If `LICENSE` is missing, the dry run warns and omits it; publishing requires it.

The release command commits the version, tags and pushes it, uploads `usbblock-macos.tar.gz` and its `.sha256` file to GitHub, then updates `usbblock.rb` at the root of `thatjuan/homebrew-tap` using `packaging/usbblock.rb.in`.
