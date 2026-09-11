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

expected_build=$(sed -nE 's/.*CURRENT_PROJECT_VERSION = ([^;]+);.*/\1/p' CuelixaMac.xcodeproj/project.pbxproj | head -n 1)
expected_version=$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);.*/\1/p' CuelixaMac.xcodeproj/project.pbxproj | head -n 1)
if [ -z "$expected_build" ] || [ -z "$expected_version" ]; then
    echo "SOURCE CONTRACT ERROR: project version metadata missing" >&2
    exit 1
fi

security_line=$(printf 'Security and integrity fixes target Cuelixa `%s` (build `%s`) on its supported macOS release line.' "$expected_version" "$expected_build")
if ! grep -Fqx "$security_line" SECURITY.md; then
    echo "SOURCE CONTRACT ERROR: SECURITY.md version/build drift" >&2
    exit 1
fi

playback_source=CuelixaMac/PlaybackController.swift
grep -Fq 'private func installPeriodicObserver(on player: AVPlayer, generation: UInt64)' "$playback_source" ||
{
    echo "SOURCE CONTRACT ERROR: generation-bound periodic observer missing" >&2
    exit 1
}
grep -Fq 'guard observer == nil, playbackGeneration == generation, self.player === player else { return }' "$playback_source" ||
{
    echo "SOURCE CONTRACT ERROR: periodic observer stale-session guard missing" >&2
    exit 1
}
grep -Fq 'self.sample(CMTimeGetSeconds(time), generation: generation, player: player)' "$playback_source" ||
{
    echo "SOURCE CONTRACT ERROR: periodic callback does not carry generation/player identity" >&2
    exit 1
}
grep -Fq 'private func sample(_ value: Double, generation: UInt64, player observedPlayer: AVPlayer)' "$playback_source" ||
{
    echo "SOURCE CONTRACT ERROR: generation/player-aware sampler missing" >&2
    exit 1
}
grep -Fq 'guard playbackGeneration == generation, player === observedPlayer, isRunning, value.isFinite' "$playback_source" ||
{
    echo "SOURCE CONTRACT ERROR: stale periodic samples are not rejected" >&2
    exit 1
}

echo "SOURCE MANIFEST VERIFIED"
echo "CURRENT SOURCE CONTRACTS VERIFIED"
