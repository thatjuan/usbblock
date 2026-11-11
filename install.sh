#!/bin/sh
# Install a prebuilt release. Optional: USBBLOCK_VERSION, USBBLOCK_PREFIX,
# and USBBLOCK_BASE_URL (the directory containing the two release assets).

main() {
    set -eu

    if [ "$(uname -s)" != Darwin ]; then
        printf 'Error: usbblock requires macOS 14 or later.\n' >&2
        exit 1
    fi
    major=$(sw_vers -productVersion | cut -d. -f1)
    case "$major" in ''|*[!0-9]*) major=0 ;; esac
    if [ "$major" -lt 14 ]; then
        printf 'Error: usbblock requires macOS 14 or later.\n' >&2
        exit 1
    fi

    prefix=${USBBLOCK_PREFIX:-/usr/local}
    case "$prefix" in /*) ;; *) printf 'Error: USBBLOCK_PREFIX must be an absolute path.\n' >&2; exit 1 ;; esac
    installed=$(command -v usbblock || true)
    if [ -n "$installed" ] && command -v brew >/dev/null 2>&1; then
        brew_prefix=$(brew --prefix)
        # Follow symlinks too, for a Homebrew binary linked onto another PATH.
        while :; do
            installed_dir=$(CDPATH='' cd -P "$(dirname "$installed")" && pwd)
            installed=$installed_dir/$(basename "$installed")
            case "$installed" in
                "$brew_prefix"/*)
                    printf '%s\n' "usbblock is installed with Homebrew; use \`brew upgrade usbblock\`." >&2
                    exit 1
                    ;;
            esac
            [ -L "$installed" ] || break
            target=$(readlink "$installed")
            case "$target" in
                /*) installed=$target ;;
                *) installed=$(dirname "$installed")/$target ;;
            esac
        done
    fi

    if [ -n "${USBBLOCK_VERSION:-}" ]; then
        base_url="https://github.com/thatjuan/usbblock/releases/download/v$USBBLOCK_VERSION"
    else
        base_url=https://github.com/thatjuan/usbblock/releases/latest/download
    fi
    base_url=${USBBLOCK_BASE_URL:-$base_url}
    base_url=${base_url%/}
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' 0
    trap 'exit 1' HUP INT TERM
    curl -fsSL "$base_url/usbblock-macos.tar.gz" -o "$tmp/usbblock-macos.tar.gz"
    curl -fsSL "$base_url/usbblock-macos.tar.gz.sha256" -o "$tmp/usbblock-macos.tar.gz.sha256"
    (cd "$tmp" && shasum -a 256 -c usbblock-macos.tar.gz.sha256)
    tar -xzf "$tmp/usbblock-macos.tar.gz" -C "$tmp" usbblock

    # Check the nearest existing parent before creating a new prefix/bin.
    parent=$prefix/bin
    while [ ! -d "$parent" ]; do parent=$(dirname "$parent"); done
    if [ -w "$parent" ]; then
        install -d "$prefix/bin"
        install -m 755 "$tmp/usbblock" "$prefix/bin/usbblock"
    else
        printf 'usbblock needs your password to write %s/bin.\n' "$prefix"
        sudo install -d "$prefix/bin"
        sudo install -m 755 "$tmp/usbblock" "$prefix/bin/usbblock"
    fi

    printf 'Installed usbblock to %s/bin/usbblock.\n' "$prefix"
    if [ -f /Library/LaunchDaemons/com.thatjuan.usbblock.plist ]; then
        printf '%s\n' "The usbblock daemon is installed. Run \`sudo usbblock enable\` to update it to this version."
    fi
    printf '\nPick the devices to block, then start the daemon:\n  usbblock list\n  sudo usbblock add\n  sudo usbblock enable\n'
}

main "$@"
