## Releasing

Releases are built locally on macOS with the Swift toolchain and GitHub CLI.
Sign in with `gh auth login`, then run from a clean, up-to-date `main`:

```sh
scripts/release.sh 0.1.0 --dry-run
scripts/release.sh 0.1.0
```

The dry run builds and checks a stripped, ad-hoc signed universal binary, writes
the archive and checksum to `dist/`, and restores `Version.swift`. It publishes
nothing. If `LICENSE` is missing, the dry run warns and omits it; publishing
requires the file.

The release command commits the version, tags and pushes it, uploads
`usbblock-macos.tar.gz` and its `.sha256` file to GitHub, then updates `usbblock.rb`
at the root of `thatjuan/homebrew-tap` using `packaging/usbblock.rb.in`.
You need push access to both repositories. Make the source repository public
before the first release so installers can download the assets anonymously.
