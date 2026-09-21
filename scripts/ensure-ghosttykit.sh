#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
vendor_dir="$project_dir/Vendor"
framework="$vendor_dir/GhosttyKit.xcframework"
ghostty_sha="c5c31ce819131ebb2deb4c4d4a75beffe4340c8d"
release_tag="xcframework-${ghostty_sha}-crashsubdir-cmux-crash-sentry-off-noi18n-v2"
archive_url="https://github.com/manaflow-ai/ghostty/releases/download/${release_tag}/GhosttyKit.xcframework.tar.gz"
archive_sha="4f75749a168712a2b456840309d9603a94039e97a453bd3f98c3ed945826fe7a"

if [[ -d "$framework" ]]; then
    exit 0
fi

mkdir -p "$vendor_dir"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/simple-cmux-ghostty.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
archive="$tmp_dir/GhosttyKit.xcframework.tar.gz"

echo "Downloading the embedded Ghostty terminal renderer..."
curl --fail --location --retry 3 --retry-delay 2 -o "$archive" "$archive_url"
actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha" != "$archive_sha" ]]; then
    echo "GhosttyKit checksum mismatch" >&2
    echo "expected: $archive_sha" >&2
    echo "actual:   $actual_sha" >&2
    exit 1
fi

tar -xzf "$archive" -C "$tmp_dir"
mv "$tmp_dir/GhosttyKit.xcframework" "$framework"
echo "Installed $framework"
