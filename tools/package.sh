#!/usr/bin/env bash
# Package Aetheris Shaders into a zip that can be dropped straight into
# .minecraft/shaderpacks/ .
#
# The layout matters, and it is copied from Nova Shaders, which loads on the target
# machine: the archive root holds shaders/ plus pack.mcmeta, LICENSE and the notices.
# A pack whose shaders/ directory is nested inside another folder is not found at all,
# and a zip carrying only shaders/ is missing the metadata every other pack in that
# folder ships.
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
zip -r -X -q "$out" shaders pack.mcmeta LICENSE THIRD-PARTY-NOTICES.md \
    -x '*.DS_Store' \
    -x '*/.git/*' \
    -x '*/Thumbs.db' \
    -x '*.swp'

# Never publish an archive that is missing something the loader or a pack folder expects.
missing=0
for required in pack.mcmeta LICENSE THIRD-PARTY-NOTICES.md \
                shaders/shaders.properties shaders/composite.fsh shaders/final.fsh \
                shaders/gbuffers_terrain.fsh shaders/gbuffers_water.fsh \
                shaders/lang/en_us.lang; do
    if ! unzip -l "$out" | grep -qE " ${required}$"; then
        echo "error: ${required} is missing from the archive" >&2
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    exit 1
fi

echo "$out"
unzip -l "$out" | tail -n 3
