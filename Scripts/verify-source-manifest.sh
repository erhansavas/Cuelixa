#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

manifest=SOURCE-SHA256SUMS.txt
if [ ! -f "$manifest" ]; then
    echo "SOURCE MANIFEST ERROR: $manifest is missing" >&2
    exit 1
fi

temp_root=$(mktemp -d "${TMPDIR:-/tmp}/cuelixa-source-manifest.XXXXXX")
trap 'rm -rf "$temp_root"' EXIT HUP INT TERM

awk '
{
    if (length($1) != 64 || $1 !~ /^[0-9a-f]+$/ || substr($0, 65, 2) != "  ") {
        exit 1
    }
    path = substr($0, 67)
    if (path == "" || path == "SOURCE-SHA256SUMS.txt" || path ~ /^\// || path ~ /(^|\/)\.\.(\/|$)/) {
        exit 1
    }
    print path
}
' "$manifest" > "$temp_root/manifest.paths" ||
{
    echo "SOURCE MANIFEST ERROR: malformed or unsafe entry" >&2
    exit 1
}

LC_ALL=C sort "$temp_root/manifest.paths" > "$temp_root/manifest.sorted"
LC_ALL=C uniq "$temp_root/manifest.sorted" > "$temp_root/manifest.unique"
if ! cmp -s "$temp_root/manifest.sorted" "$temp_root/manifest.unique"; then
    echo "SOURCE MANIFEST ERROR: duplicate path" >&2
    exit 1
fi

git ls-files | grep -vxF "$manifest" | LC_ALL=C sort > "$temp_root/tracked.sorted"
if ! cmp -s "$temp_root/manifest.sorted" "$temp_root/tracked.sorted"; then
    echo "SOURCE MANIFEST ERROR: manifest path set does not match tracked release tree" >&2
    diff -u "$temp_root/manifest.sorted" "$temp_root/tracked.sorted" >&2 || true
    exit 1
fi

shasum -a 256 -c "$manifest"
echo "SOURCE MANIFEST VERIFIED"
