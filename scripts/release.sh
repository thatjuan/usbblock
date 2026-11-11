#!/bin/sh
# Build and publish universal macOS releases and the Homebrew formula locally.
set -eu

cd "$(dirname "$0")/.."

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail 'Usage: scripts/release.sh <version> [--dry-run]'
version=$1
case "$version" in ''|*[!0-9.]*) fail 'Version must have the form 0.1.0.' ;; esac
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail 'Version must have the form 0.1.0.'
dry_run=0
if [ "$#" -eq 2 ]; then
    [ "$2" = '--dry-run' ] || fail 'Usage: scripts/release.sh <version> [--dry-run]'
    dry_run=1
fi

if [ "$dry_run" -eq 0 ]; then
    [ -f LICENSE ] || fail 'LICENSE is missing; add it before publishing a release.'
    [ -z "$(git status --porcelain)" ] || fail 'Release requires a clean working tree.'
    [ "$(git branch --show-current)" = main ] || fail 'Release must run on main.'
    git fetch origin main --tags
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail 'main must be up to date with origin/main.'
    if git rev-parse --verify --quiet "refs/tags/v$version" >/dev/null; then
        fail "Tag v$version already exists."
    fi
    gh auth status
else
    git diff --quiet HEAD -- Sources/usbblock/Version.swift || fail 'Commit or restore Version.swift before a dry run.'
fi

tmp=$(mktemp -d)
restore_version=1
cleanup() {
    if [ "$restore_version" -eq 1 ]; then
        git checkout -- Sources/usbblock/Version.swift
    fi
    rm -rf "$tmp"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

printf '// Set by scripts/release.sh.\nlet usbblockVersion = "%s"\n' "$version" > Sources/usbblock/Version.swift
swift build -c release --arch arm64 --arch x86_64 \
    -Xswiftc -file-prefix-map -Xswiftc "$PWD=/usbblock" \
    -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/usbblock"
# SwiftPM's output directory differs between the native and Swift Build engines.
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/usbblock
mkdir -p dist
strip -x "$bin" -o dist/usbblock
codesign --force --sign - dist/usbblock

archs=$(lipo -archs dist/usbblock)
case "$archs" in *arm64*) ;; *) fail 'Release binary is missing arm64.' ;; esac
case "$archs" in *x86_64*) ;; *) fail 'Release binary is missing x86_64.' ;; esac
strings -a dist/usbblock > "$tmp/strings"
if grep -F -e '/Users/' -e '/private/var/folders' -e "${HOME:?HOME must be set}" -e "$PWD" "$tmp/strings"; then
    fail 'Release binary contains local paths (shown above).'
fi
printf '%s\n' "$version" > "$tmp/expected-version"
dist/usbblock --version > "$tmp/actual-version"
cmp -s "$tmp/expected-version" "$tmp/actual-version" || fail 'Release binary does not print exactly the requested version.'

cp README.md dist/
set -- usbblock
if [ -f LICENSE ]; then
    cp LICENSE dist/
    set -- "$@" LICENSE
else
    printf 'Warning: LICENSE is missing; this dry-run archive omits it.\n' >&2
fi
set -- "$@" README.md
COPYFILE_DISABLE=1 tar -C dist --format ustar --no-mac-metadata --no-xattrs --no-acls --no-fflags \
    --uid 0 --gid 0 --uname root --gname wheel \
    -czf dist/usbblock-macos.tar.gz "$@"
(cd dist && shasum -a 256 usbblock-macos.tar.gz > usbblock-macos.tar.gz.sha256)
tar -tvzf dist/usbblock-macos.tar.gz > "$tmp/archive-list"
cat "$tmp/archive-list"
awk '$3 != "root" || $4 != "wheel" { exit 1 }' "$tmp/archive-list" || fail 'Archive owners must be root wheel.'

if [ "$dry_run" -eq 1 ]; then
    printf 'Dry run complete: dist/usbblock-macos.tar.gz and dist/usbblock-macos.tar.gz.sha256\n'
    cat dist/usbblock-macos.tar.gz.sha256
    exit 0
fi

git add Sources/usbblock/Version.swift
git commit -m "Release v$version"
restore_version=0
git tag -a "v$version" -m "Release v$version"
git push origin main "v$version"
gh release create "v$version" dist/usbblock-macos.tar.gz dist/usbblock-macos.tar.gz.sha256 \
    --title "v$version" --generate-notes

gh repo clone thatjuan/homebrew-tap "$tmp/tap" -- --depth 1
sha=$(cut -d' ' -f1 dist/usbblock-macos.tar.gz.sha256)
sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$sha/g" packaging/usbblock.rb.in > "$tmp/tap/usbblock.rb"
git -C "$tmp/tap" add usbblock.rb
git -C "$tmp/tap" -c user.name=thatjuan -c user.email=389677+thatjuan@users.noreply.github.com \
    commit -m "usbblock $version"
git -C "$tmp/tap" push
