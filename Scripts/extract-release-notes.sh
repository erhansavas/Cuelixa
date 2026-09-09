#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 VERSION BUILD OUTPUT" >&2
    exit 64
fi

version=$1
build=$2
output=$3
heading="## Cuelixa $version (build $build)"

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

count=$(grep -Fxc "$heading" CHANGELOG.md || true)
if [ "$count" -ne 1 ]; then
    echo "RELEASE NOTES ERROR: expected exactly one heading: $heading" >&2
    exit 1
fi

temp="${output}.tmp.$$"
trap 'rm -f "$temp"' EXIT HUP INT TERM

awk -v heading="$heading" '
$0 == heading {
    found = 1
    capture = 1
}
capture && $0 != heading && /^## Cuelixa / {
    exit
}
capture {
    print
}
END {
    if (!found) exit 1
}
' CHANGELOG.md > "$temp"

if [ ! -s "$temp" ] || [ "$(head -n 1 "$temp")" != "$heading" ]; then
    echo "RELEASE NOTES ERROR: extraction did not begin with the expected heading" >&2
    exit 1
fi

section_headings=$(grep -c '^## Cuelixa ' "$temp" || true)
if [ "$section_headings" -ne 1 ]; then
    echo "RELEASE NOTES ERROR: extraction crossed a release boundary" >&2
    exit 1
fi

mv "$temp" "$output"
trap - EXIT HUP INT TERM
