#!/bin/sh
# Remove the daemon and a curl-installed binary, keeping config and logs.
# USBBLOCK_PREFIX selects the install prefix (default /usr/local).
# USBBLOCK_SKIP_DAEMON=1 skips daemon removal when testing a temporary prefix.

main() {
    set -eu

    prefix=${USBBLOCK_PREFIX:-/usr/local}
    case "$prefix" in /*) ;; *) printf 'Error: USBBLOCK_PREFIX must be an absolute path.\n' >&2; exit 1 ;; esac
    binary=$prefix/bin/usbblock
    if [ "${USBBLOCK_SKIP_DAEMON:-0}" != 1 ] && [ -f /Library/LaunchDaemons/com.thatjuan.usbblock.plist ]; then
        # Prefer this prefix, including when its bin directory is not on PATH.
        if [ -x "$binary" ]; then
            daemon_cli=$binary
        else
            daemon_cli=$(command -v usbblock || true)
            if [ -z "$daemon_cli" ]; then
                printf '%s\n' "Error: usbblock is not on PATH; run \`sudo /usr/local/libexec/usbblock disable\` first." >&2
                exit 1
            fi
        fi
        if [ -w /Library/LaunchDaemons ] && [ -w /usr/local/libexec ]; then
            "$daemon_cli" disable
        else
            printf 'usbblock needs your password to remove the daemon.\n'
            sudo "$daemon_cli" disable
        fi
    fi

    homebrew=0
    if [ -L "$binary" ]; then
        target=$(readlink "$binary")
        case "$target" in /*) ;; *) target=$(dirname "$binary")/$target ;; esac
        case "$target" in
            */Cellar/usbblock/*|*/opt/usbblock/*) homebrew=1 ;;
        esac
        if command -v brew >/dev/null 2>&1; then
            brew_prefix=$(brew --prefix)
            case "$target" in "$brew_prefix"/*) homebrew=1 ;; esac
        fi
    fi
    if [ "$homebrew" -eq 1 ]; then
        printf '%s\n' "usbblock is installed with Homebrew; run \`brew uninstall usbblock\`."
    elif [ -e "$binary" ] || [ -L "$binary" ]; then
        if [ -w "$prefix/bin" ]; then
            rm -f "$binary"
        else
            printf 'usbblock needs your password to write %s/bin.\n' "$prefix"
            sudo rm -f "$binary"
        fi
        printf 'Removed %s.\n' "$binary"
    else
        printf 'No usbblock binary at %s.\n' "$binary"
    fi
    printf 'Configuration and logs were kept. For a full cleanup, run:\n  sudo rm /etc/usbblock.conf /var/log/usbblock.log\n'
}

main "$@"
