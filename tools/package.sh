#!/usr/bin/env bash
# Package Aetheris Shaders into a zip that can be dropped straight into
# .minecraft/shaderpacks/ .
#
# The zip layout is the part that matters. A shader pack zip must have the
# shaders/ directory at its root, not nested inside another folder, or Iris will
# not find the programs and the pack will silently not appear in the list.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d ' \t\r\n' < "$root/VERSION")"

if [ -z "$version" ]; then
    echo "VERSION is empty" >&2
    exit 1
fi

build="$root/build"
name="Aetheris-Shaders-${version}"
out="$build/${name}.zip"

rm -rf "$build"
mkdir -p "$build"

cd "$root"

# -X drops the extra file attributes that make a zip differ between machines, so
# building the same tree twice gives the same bytes and the release checksum is
# meaningful.
zip -r -X -q "$out" shaders \
    -x '*.DS_Store' \
    -x '*/.git/*' \
    -x '*/Thumbs.db' \
    -x '*.swp'

echo "$out"
unzip -l "$out" | tail -n 3
