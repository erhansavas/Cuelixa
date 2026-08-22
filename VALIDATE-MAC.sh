#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "$(dirname "$0")"

expected_macos="${CUELIXA_MACOS_VERSION:-26.6.2}"
expected_ci_macos_series="${CUELIXA_CI_MACOS_SERIES:-26}"
expected_xcode="${CUELIXA_XCODE_VERSION:-26.6}"
expected_xcode_build="${CUELIXA_XCODE_BUILD:-17F113}"
expected_swift="${CUELIXA_SWIFT_VERSION:-6.3.3}"
expected_build="51"
ci_mode="${CUELIXA_CI_MODE:-0}"

fail() { print -u2 -- "ERROR: $*"; exit 1; }
pass() { print -- "$1=PASS"; }

[[ "$ci_mode" == "0" || "$ci_mode" == "1" ]] || fail 'CUELIXA_CI_MODE must be 0 or 1'

print '=== Environment ==='
sw_vers
xcodebuild -version
xcrun swiftc --version
[[ "$(uname -m)" == "arm64" ]] || fail 'qualification must run on arm64'
actual_macos="$(sw_vers -productVersion)"
if [[ "$ci_mode" == "1" ]]; then
  [[ "$actual_macos" == "$expected_ci_macos_series" || "$actual_macos" == "$expected_ci_macos_series".* ]] \
    || fail "CI validation expects macOS ${expected_ci_macos_series}.x, found $actual_macos"
  print -- "CI compatibility mode: macOS $actual_macos is accepted for build/static validation only."
  print -- "Exact target macOS $expected_macos runtime qualification remains NOT ESTABLISHED."
else
  [[ "$actual_macos" == "$expected_macos" ]] || fail "expected macOS $expected_macos, found $actual_macos"
fi
[[ "$(xcodebuild -version | sed -n '1s/^Xcode //p')" == "$expected_xcode" ]] || fail "expected Xcode $expected_xcode"
[[ "$(xcodebuild -version | sed -n '2s/^Build version //p')" == "$expected_xcode_build" ]] || fail "expected Xcode build $expected_xcode_build"
swift_version_line="$(xcrun swiftc --version | head -n 1)"
[[ "$swift_version_line" == *"Swift version $expected_swift"* ]] || fail "expected Swift $expected_swift from selected Xcode; found: $swift_version_line"

print '=== Source / formatting / resource checks ==='
for source in CuelixaMac/*.swift Tests/*.swift; do
  xcrun swiftc -frontend -parse "$source" >/dev/null
done
xcrun swift-format lint --strict CuelixaMac/*.swift Tests/*.swift
plutil -lint CuelixaMac.xcodeproj/project.pbxproj

# Every shipping Swift source must be represented in the Xcode project and Sources phase.
for swift_file in CuelixaMac/*.swift; do
  swift_name="${swift_file:t}"
  grep -Fq "path = ${swift_name};" CuelixaMac.xcodeproj/project.pbxproj || fail "Xcode project is missing file reference: ${swift_name}"
  grep -Fq "/* ${swift_name} in Sources */" CuelixaMac.xcodeproj/project.pbxproj || fail "Xcode target Sources phase is missing: ${swift_name}"
done
pass 'XCODE_SWIFT_SOURCE_MEMBERSHIP'

# macOS 26 native overlay contract: first-party Liquid Glass with restrained
# Cuelixa identity tint only where playback meaning benefits from color.
overlay_source='CuelixaMac/SubtitleOverlay.swift'
grep -Fq 'NSGlassEffectView' "$overlay_source" || fail 'Subtitle overlay is not using native NSGlassEffectView'
grep -Fq 'controlsEffect.contentView = content' "$overlay_source" || fail 'Liquid Glass content is not attached through contentView'
grep -Fq 'slider.trackFillColor = CuelixaDesign.identityAccentNS' "$overlay_source" || fail 'Playback progress lost the identity accent'
grep -Fq 'playPauseButton.contentTintColor = CuelixaDesign.identityAccentNS' "$overlay_source" || fail 'Primary playback control lost the identity accent'
if grep -Fq 'NSVisualEffectView(frame: .zero)' "$overlay_source"; then fail 'Legacy custom visual-effect overlay returned'; fi
pass 'NATIVE_GLASS_OVERLAY'

for asset_json in \
  CuelixaMac/Assets.xcassets/Contents.json \
  CuelixaMac/Assets.xcassets/AppIcon.appiconset/Contents.json \
  CuelixaMac/Assets.xcassets/AccentColor.colorset/Contents.json; do
  ASSET_JSON_PATH="$asset_json" xcrun swift -e 'import Foundation; let path = ProcessInfo.processInfo.environment["ASSET_JSON_PATH"]!; let data = try Data(contentsOf: URL(fileURLWithPath: path)); _ = try JSONSerialization.jsonObject(with: data)' >/dev/null
done
pass 'ASSET_CATALOG_JSON_PARSE'
plutil -lint CuelixaMac/PrivacyInfo.xcprivacy
grep -Fq 'path = PrivacyInfo.xcprivacy;' CuelixaMac.xcodeproj/project.pbxproj || fail 'privacy manifest file reference missing'
grep -Fq 'PrivacyInfo.xcprivacy in Resources' CuelixaMac.xcodeproj/project.pbxproj || fail 'privacy manifest target Resources membership missing'
grep -Fq '<key>NSPrivacyTracking</key>' CuelixaMac/PrivacyInfo.xcprivacy || fail 'privacy tracking declaration missing'
grep -Fq '<false/>' CuelixaMac/PrivacyInfo.xcprivacy || fail 'privacy tracking must remain disabled'
xmllint --noout CuelixaMac.xcodeproj/xcshareddata/xcschemes/Cuelixa.xcscheme

if grep -R -nE '/Users/|/opt/homebrew|DerivedData|(-march|-mcpu)=native|arm64e|x86_64|ffmpeg|whisper|python' \
  CuelixaMac CuelixaMac.xcodeproj --exclude='*.png'; then
  fail 'machine-specific or prohibited shipping dependency pattern found'
fi
if grep -R -nE 'import[[:space:]]+AppIntents|AppIntents\.framework|AppShortcutsProvider|AppShortcut|NSUserActivity|INIntent|NSSiri' \
  CuelixaMac CuelixaMac.xcodeproj --exclude='*.png'; then
  fail 'unintended App Intents/Shortcuts registration path found'
fi
appintents_absence_verified=1
if grep -R -nE 'nonisolated\(unsafe\)|MainActor\.assumeIsolated|@preconcurrency[[:space:]]+import|try!|as!' CuelixaMac Tests; then
  fail 'unsafe/suppression pattern found'
fi
if grep -R -nE 'for[[:space:]]*\([^,]+,[^)]+\)[[:space:]]+in[[:space:]].*\.runs' CuelixaMac Tests; then
  fail 'AttributedString.runs tuple-destructuring regression reintroduced'
fi
if grep -nE 'static[[:space:]]+(let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*FileManager\.default' CuelixaMac/AppPaths.swift; then
  fail 'stored static FileManager reintroduced'
fi
grep -q 'sqlite3_busy_timeout(db, 30_000) == SQLITE_OK' CuelixaMac/Database.swift || fail 'SQLite busy-timeout validation missing'
grep -q 'PRAGMA journal_mode = WAL' CuelixaMac/Database.swift || fail 'SQLite WAL configuration missing'
grep -q 'PRAGMA foreign_keys = ON' CuelixaMac/Database.swift || fail 'SQLite foreign-key configuration missing'

print '=== Architecture regression gates ==='
grep -q 'Window("Cuelixa", id: "library")' CuelixaMac/CuelixaApp.swift || fail 'SwiftUI-owned library Window scene missing'
grep -q 'NavigationSplitView' CuelixaMac/MainView.swift || fail 'native split-view shell missing'
grep -q 'List(model.tracks, selection:' CuelixaMac/MainView.swift || fail 'native lesson selection semantics missing'
grep -q 'onKeyPress(.space)' CuelixaMac/MainView.swift || fail 'Space activation for selected lesson missing'
grep -Fq 'model.playTrack(track)' CuelixaMac/MainView.swift || fail 'lesson Play action does not invoke model.playTrack(track)'
grep -Fq 'play.fill' CuelixaMac/MainView.swift || fail 'discoverable lesson Play glyph missing'
grep -q 'case preparing' CuelixaMac/PlaybackController.swift || fail 'truthful playback preparing state missing'
grep -q 'case ready' CuelixaMac/PlaybackController.swift || fail 'truthful playback ready state missing'
grep -q 'case .readyToPlay:' CuelixaMac/PlaybackController.swift || fail 'AVPlayerItem readiness gate missing'
grep -q 'var onPlaybackStarted: (() -> Void)?' CuelixaMac/PlaybackController.swift || fail 'verified playback-start presentation callback missing'
grep -q 'private func presentStartedPlayback()' CuelixaMac/AppModel.swift || fail 'verified playback-start presentation gate missing'
grep -q 'AVURLAsset(url: fileURL)' CuelixaMac/PlaybackController.swift || fail 'AVURLAsset preparation path missing'
grep -q 'asset.load(.isPlayable)' CuelixaMac/PlaybackController.swift || fail 'async asset isPlayable load missing'
grep -q 'asset.load(.duration)' CuelixaMac/PlaybackController.swift || fail 'async asset duration load missing'
grep -q 'asset.loadTracks(withMediaType: .audio)' CuelixaMac/PlaybackController.swift || fail 'async audio-track load missing'
grep -q 'assetPreparationWatchdogTask' CuelixaMac/PlaybackController.swift || fail 'asset preparation watchdog missing'
grep -q 'itemPreparationWatchdogTask' CuelixaMac/PlaybackController.swift || fail 'item preparation watchdog missing'
grep -q 'playbackStartWatchdogTask' CuelixaMac/PlaybackController.swift || fail 'first playback-start watchdog missing'
grep -q 'addBoundaryTimeObserver' CuelixaMac/PlaybackController.swift || fail 'event-driven first-timebase progression proof missing'
grep -q 'PlaybackResumePolicy.normalizedPosition' CuelixaMac/PlaybackController.swift || fail 'near-end resume normalization missing'
grep -q 'enum PlaybackResumePolicy' CuelixaMac/Models.swift || fail 'resume policy contract missing'
grep -q 'min(5.0, max(1.0, duration \* 0.02))' CuelixaMac/Models.swift || fail 'documented bounded near-end resume threshold missing'
grep -q 'import OSLog' CuelixaMac/PlaybackController.swift || fail 'unified playback Logger missing'
grep -q 'reasonForWaitingToPlay' CuelixaMac/PlaybackController.swift || fail 'AVPlayer waiting-reason diagnostics missing'
grep -q 'let fileName = activeFileName' CuelixaMac/PlaybackController.swift || fail 'Swift 6-safe OSLog file-name snapshot missing'
grep -q 'let fileExtension = activeFileExtension' CuelixaMac/PlaybackController.swift || fail 'Swift 6-safe OSLog file-extension snapshot missing'
grep -q 'let fileSize = activeFileSize' CuelixaMac/PlaybackController.swift || fail 'Swift 6-safe OSLog file-size snapshot missing'
grep -q 'uninstallRemoteCommands()' CuelixaMac/PlaybackController.swift || fail 'per-session remote integration teardown missing'
if awk '/func start\(track:/{flag=1} flag{print} /private func beginAssetPreparation/{exit}' CuelixaMac/PlaybackController.swift | grep -q 'AVPlayer('; then
  fail 'AVPlayer is constructed before async asset validation'
fi
if awk '/private func handleItemStatus/{flag=1} flag{print} /private func requestVerifiedPlaybackStart/{exit}' CuelixaMac/PlaybackController.swift | grep -q 'onPlaybackStarted'; then
  fail 'player presentation callback occurs at readyToPlay instead of verified timebase advancement'
fi
if awk '/private func requestVerifiedPlaybackStart/{flag=1} flag{print} /private func confirmPlaybackStartIfProven/{exit}' CuelixaMac/PlaybackController.swift | grep -q 'installRemoteCommands'; then
  fail 'optional remote integration is installed before verified playback progression'
fi
awk '/private func confirmPlaybackStartIfProven/{flag=1} flag{print} /private func installPeriodicObserver/{exit}' CuelixaMac/PlaybackController.swift | grep -q 'onPlaybackStarted' || fail 'verified playback-start callback is not issued from progression-confirmed path'
grep -q 'startObservedPlaying, startObservedProgress' CuelixaMac/PlaybackController.swift || fail 'playback confirmation does not require both playing state and time advancement'
if awk '/private func startPlayback/{flag=1} flag{print} /private func presentStartedPlayback/{exit}' CuelixaMac/AppModel.swift | grep -q 'orderOut'; then
  fail 'library window is hidden before verified playback-start presentation'
fi
python3 - <<'PY_DISCLOSURE'
import re
from pathlib import Path
src = Path('CuelixaMac/MainView.swift').read_text()
required = {
    'hover state': r'@State\s+private\s+var\s+hovering\s*=\s*false',
    'selection input': r'let\s+selected:\s*Bool',
    'native hover tracking': r'\.onHover\s*\{\s*hovering\s*=\s*\$0\s*\}',
    'row action menu': r'TrackActionsMenu\(track:\s*track\)',
    'hover/selection disclosure': r'\.opacity\s*\(\s*hovering\s*\|\|\s*selected\s*\?',
}
missing = [name for name, pattern in required.items() if not re.search(pattern, src)]
if missing:
    raise SystemExit('native hover/selection disclosure contract missing: ' + ', '.join(missing))
print('ROW_DISCLOSURE_CONTRACT=PASS')
PY_DISCLOSURE
if grep -q 'buttonBorderShape(.circle)' CuelixaMac/PlayerPanel.swift; then
  fail 'circle-wrapped custom transport controls reintroduced'
fi
if grep -q 'CuelixaDesign.identityAccent' CuelixaMac/PlayerPanel.swift; then
  fail 'identity tint reintroduced into neutral transport controls'
fi
if grep -q 'toolbarBackgroundVisibility(.hidden, for: .windowToolbar)' CuelixaMac/MainView.swift; then
  fail 'forced window-toolbar background override reintroduced'
fi
if grep -R -nE 'WindowAttachmentView|WindowAttachmentNSView|layoutSubtreeIfNeeded' CuelixaMac; then
  fail 'layout-reentrant window attachment/chrome mutation path reintroduced'
fi
if grep -R -nE 'GlassEffectContainer|\.glassEffect\(|buttonStyle\(\.glass' CuelixaMac; then
  fail 'decorative Liquid Glass wrapper reintroduced'
fi
if grep -R -nE 'NSCursor\.(hide|unhide|setHiddenUntilMouseMoves)|add(Global|Local)MonitorForEvents' CuelixaMac; then
  fail 'cursor hiding or process-wide NSEvent monitor reintroduced'
fi
if grep -R -nE 'NSAppearance\(named:.*(darkAqua|aqua)' CuelixaMac; then
  fail 'forced application appearance reintroduced'
fi

grep -q '\.musicDirectory' CuelixaMac/AppPaths.swift || fail 'standard Music-directory resolution missing'
grep -q 'static let transcripts = support.appendingPathComponent' CuelixaMac/AppPaths.swift || fail 'durable transcript directory missing'
grep -q 'verifiedSRTURL' CuelixaMac/TranscriptCache.swift || fail 'verified transcript resolution missing'
grep -q 'validSidecarURL' CuelixaMac/Subtitle.swift || fail 'sidecar SRT compatibility missing'
grep -q 'SubtitleTimeline.activeCueIndex' CuelixaMac/PlaybackController.swift || fail 'player does not use shared subtitle timeline'
grep -q 'remoteCommandTargets' CuelixaMac/PlaybackController.swift || fail 'RemoteCommandCenter token ownership missing'
grep -q 'attributeOptions: \[.audioTimeRange\]' CuelixaMac/NativeTranscriber.swift || fail 'Speech audioTimeRange attributes missing'
grep -q 'for run in attributed.runs' CuelixaMac/NativeTranscriber.swift || fail 'correct AttributedString Run iteration missing'
grep -q 'String(attributed\[run.range\].characters)' CuelixaMac/NativeTranscriber.swift || fail 'run.range extraction missing'
grep -q 'SubtitleSegmenter.cues' CuelixaMac/NativeTranscriber.swift || fail 'timed Speech segmentation missing'
if awk '/private static func collectCues/{flag=1} flag{print} /async throws -> \[SubtitleCue\]/{exit}' CuelixaMac/NativeTranscriber.swift | grep -q 'Job'; then
  fail 'mutable NativeTranscriber.Job crossed into Speech result collector'
fi
grep -q '@concurrent' CuelixaMac/NativeTranscriber.swift || fail 'concurrent Speech result collector missing'
grep -q 'progress: @escaping @MainActor @Sendable' CuelixaMac/NativeTranscriber.swift || fail 'MainActor Sendable Speech progress boundary missing'
grep -q 'job.id == jobID' CuelixaMac/NativeTranscriber.swift || fail 'stable transcription job identity lookup missing'
grep -q 'func liveScrub' CuelixaMac/PlaybackController.swift || fail 'event-driven scrub path missing'
if awk '/func liveScrub/{flag=1} flag{print} /func endScrub/{exit}' CuelixaMac/PlaybackController.swift | grep -q 'seek('; then
  fail 'live scrub decoder seek storm reintroduced'
fi
# Contracted global hotkeys must stay J/L/U/O for -10/+10/-30/+30.
grep -q 'register(3, key: UInt32(kVK_ANSI_J)' CuelixaMac/HotKeyManager.swift || fail 'Ctrl+Option+J hotkey missing'
grep -q 'register(4, key: UInt32(kVK_ANSI_L)' CuelixaMac/HotKeyManager.swift || fail 'Ctrl+Option+L hotkey missing'
grep -q 'register(6, key: UInt32(kVK_ANSI_U)' CuelixaMac/HotKeyManager.swift || fail 'Ctrl+Option+U hotkey missing'
grep -q 'register(7, key: UInt32(kVK_ANSI_O)' CuelixaMac/HotKeyManager.swift || fail 'Ctrl+Option+O hotkey missing'
grep -q 'guard !shuttingDown else { return }' CuelixaMac/LibraryScanner.swift || fail 'scanner shutdown enqueue guard missing'
grep -q 'shuttingDown = true' CuelixaMac/LibraryScanner.swift || fail 'scanner shutdown latch missing'

print '=== Swift status-description return regression gate ==='
python3 - <<'PY2'
import re
from pathlib import Path
src = Path('CuelixaMac/PlaybackController.swift').read_text()
for name in ('itemStatusDescription', 'playerStatusDescription', 'timeControlDescription'):
    m = re.search(r'private func ' + re.escape(name) + r'\b[\s\S]*?\n  }', src)
    if not m:
        raise SystemExit(f'missing {name}')
    body = m.group(0)
    branches = re.findall(r'(?:case [^:]+|@unknown default):\s*([^\n]+)', body)
    if not branches or any(not branch.lstrip().startswith('return ') for branch in branches):
        raise SystemExit(f'{name} contains a switch branch without explicit return')
print('PLAYBACK_STATUS_RETURN_GUARD=PASS')
PY2

print '=== Foundation AttributedString API smoke ==='
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cuelixa-smoke.XXXXXX")"
DD_DEBUG="$(mktemp -d "${TMPDIR:-/tmp}/cuelixa-debug-deriveddata.XXXXXX")"
DD_RELEASE="$(mktemp -d "${TMPDIR:-/tmp}/cuelixa-release-deriveddata.XXXXXX")"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cuelixa-validation.XXXXXX")"
trap 'rm -rf "$SMOKE_DIR" "$DD_DEBUG" "$DD_RELEASE" "$LOG_DIR"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors Tests/AttributedStringRunSmoke.swift -o "$SMOKE_DIR/attributed-run-smoke"
"$SMOKE_DIR/attributed-run-smoke"

print '=== Swift 6 transcription concurrency typecheck ==='
xcrun swiftc -swift-version 6 -strict-concurrency=complete -typecheck -warnings-as-errors Tests/TranscriptionConcurrencySmoke.swift

print '=== Speech API target-SDK typecheck ==='
xcrun swiftc -typecheck -warnings-as-errors Tests/SpeechAPISmoke.swift

print '=== AVFoundation local-playback target-SDK typecheck ==='
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -typecheck -warnings-as-errors Tests/LocalPlaybackSmoke.swift
if [[ "$ci_mode" == "0" ]]; then
  print '=== Exact-target generated local AVPlayer playback smoke ==='
  xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    Tests/LocalPlaybackSmoke.swift -framework AVFoundation -o "$SMOKE_DIR/local-playback-smoke"
  "$SMOKE_DIR/local-playback-smoke"
else
  print 'CI compatibility mode: generated local AVPlayer runtime smoke skipped; exact target remains required.'
fi

print '=== Playback resume-policy smoke ==='
xcrun swiftc -parse-as-library -warnings-as-errors CuelixaMac/Models.swift Tests/PlaybackPolicySmoke.swift -o "$SMOKE_DIR/playback-policy-smoke"
"$SMOKE_DIR/playback-policy-smoke"

print '=== Deterministic subtitle / utility / database smoke ==='
xcrun swiftc -parse-as-library -warnings-as-errors CuelixaMac/Subtitle.swift Tests/SubtitleSmoke.swift -o "$SMOKE_DIR/subtitle-smoke"
"$SMOKE_DIR/subtitle-smoke"
xcrun swiftc -parse-as-library -warnings-as-errors CuelixaMac/Utilities.swift Tests/UtilitySmoke.swift -o "$SMOKE_DIR/utility-smoke"
"$SMOKE_DIR/utility-smoke"
xcrun swiftc -parse-as-library -warnings-as-errors \
  CuelixaMac/AppPaths.swift CuelixaMac/Models.swift CuelixaMac/Database.swift \
  Tests/DatabaseSmokeSupport.swift Tests/DatabaseSmoke.swift -lsqlite3 -o "$SMOKE_DIR/database-smoke"
"$SMOKE_DIR/database-smoke"

build_common=(
  -project CuelixaMac.xcodeproj
  -scheme Cuelixa
  -destination 'platform=macOS,arch=arm64'
  CODE_SIGNING_ALLOWED=NO
)

print '=== Clean Debug build ==='
xcodebuild "${build_common[@]}" -configuration Debug -derivedDataPath "$DD_DEBUG" clean build 2>&1 | tee "$LOG_DIR/debug-build.log"

print '=== Clean Release build ==='
xcodebuild "${build_common[@]}" -configuration Release -derivedDataPath "$DD_RELEASE" clean build 2>&1 | tee "$LOG_DIR/release-build.log"

print '=== Release Analyze ==='
xcodebuild "${build_common[@]}" -configuration Release -derivedDataPath "$DD_RELEASE" analyze 2>&1 | tee "$LOG_DIR/analyze.log"

warnings=$(grep -hE '(^|[[:space:]])warning:' "$LOG_DIR/debug-build.log" "$LOG_DIR/release-build.log" "$LOG_DIR/analyze.log" || true)
unexpected_warnings=''
if [[ -n "$warnings" ]]; then
  while IFS= read -r warning_line; do
    warning_payload="${warning_line#*warning: }"
    if [[ "${appintents_absence_verified:-0}" == "1" \
      && "$warning_line" == *appintentsmetadataprocessor* \
      && "$warning_payload" == 'Metadata extraction skipped. No AppIntents.framework dependency found.' ]]; then
      print -- "BENIGN_XCODE_TOOL_WARNING_ALLOWED: $warning_line"
      continue
    fi
    if [[ -n "$unexpected_warnings" ]]; then
      unexpected_warnings+=$'\n'
    fi
    unexpected_warnings+="$warning_line"
  done <<< "$warnings"
fi
[[ -z "$unexpected_warnings" ]] || { print -u2 'ERROR: warnings emitted:'; print -u2 -- "$unexpected_warnings"; exit 1; }
errors=$(grep -hE '(^|[[:space:]])error:' "$LOG_DIR/debug-build.log" "$LOG_DIR/release-build.log" "$LOG_DIR/analyze.log" || true)
[[ -z "$errors" ]] || { print -u2 'ERROR: errors emitted:'; print -u2 -- "$errors"; exit 1; }

print '=== Release settings ==='
settings="$(xcodebuild "${build_common[@]}" -configuration Release -derivedDataPath "$DD_RELEASE" -showBuildSettings)"
print -- "$settings" | grep -E '^[[:space:]]*(ARCHS|SUPPORTED_PLATFORMS|MACOSX_DEPLOYMENT_TARGET|ENABLE_HARDENED_RUNTIME|ENABLE_APP_SANDBOX|CURRENT_PROJECT_VERSION|MARKETING_VERSION|PRODUCT_BUNDLE_IDENTIFIER|SWIFT_STRICT_CONCURRENCY|SWIFT_TREAT_WARNINGS_AS_ERRORS)[[:space:]]*='
print -- "$settings" | grep -Eq 'ARCHS = arm64$' || fail 'Release ARCHS is not arm64'
print -- "$settings" | grep -Eq 'SUPPORTED_PLATFORMS = macosx$' || fail 'Release platform is not macosx'
print -- "$settings" | grep -Eq 'MACOSX_DEPLOYMENT_TARGET = 26\.0$' || fail 'deployment target is not macOS 26.0'
print -- "$settings" | grep -Eq 'ENABLE_HARDENED_RUNTIME = YES$' || fail 'Hardened Runtime is not enabled'
print -- "$settings" | grep -Eq 'ENABLE_APP_SANDBOX = NO$' || fail 'unexpected App Sandbox setting'
print -- "$settings" | grep -Eq "CURRENT_PROJECT_VERSION = ${expected_build}$" || fail 'wrong engineering build number'
print -- "$settings" | grep -Eq 'MARKETING_VERSION = 0\.6\.65$' || fail 'wrong marketing version'
print -- "$settings" | grep -Eq 'PRODUCT_BUNDLE_IDENTIFIER = io\.github\.erhansavas\.Cuelixa$' || fail 'wrong bundle identifier'
print -- "$settings" | grep -Fq 'INFOPLIST_KEY_NSHumanReadableCopyright = Copyright 2026 erhansavas.' || fail 'human-readable copyright metadata missing'
print -- "$settings" | grep -Eq 'SWIFT_STRICT_CONCURRENCY = complete$' || fail 'strict concurrency is not complete'
print -- "$settings" | grep -Eq 'SWIFT_TREAT_WARNINGS_AS_ERRORS = YES$' || fail 'warnings-as-errors is not enabled'

APP="$DD_RELEASE/Build/Products/Release/Cuelixa.app"
BIN="$APP/Contents/MacOS/Cuelixa"
[[ -x "$BIN" ]] || fail "missing Release executable: $BIN"

print '=== Release binary ==='
file "$BIN"
[[ "$(lipo -archs "$BIN")" == "arm64" ]] || fail 'Release binary is not arm64-only'
otool -l "$BIN" | awk '/LC_BUILD_VERSION/{show=1; next} show && /minos/{print; show=0}'

print '=== Nested native payload ==='
find "$APP" -type f -print0 | while IFS= read -r -d '' candidate; do
  if file "$candidate" | grep -q 'Mach-O'; then
    arches="$(lipo -archs "$candidate")"
    printf '%s: %s\n' "$candidate" "$arches"
    [[ "$arches" == "arm64" ]] || fail "non-arm64 nested Mach-O: $candidate"
  fi
done


# Preserve the original Cuelixa product contract. The library is a
# management surface; confirmed playback hides it and uses a movable,
# nonactivating subtitle/transport overlay whose controls auto-hide. The
# overlay owns no AVPlayer and introduces no recurring playback timer.
if grep -qE 'PlayerPanelController|PlaybackAccessoryHost|NowPlayingBar|FixedPlayerBar' CuelixaMac/MainView.swift CuelixaMac/AppModel.swift; then
  echo "OVERLAY_PLAYBACK_CONTRACT=FAIL"
  exit 1
fi
grep -q 'SubtitleOverlayController' CuelixaMac/AppModel.swift || fail 'overlay playback controller missing'
grep -q 'subtitleOverlayEnabled = true' CuelixaMac/AppModel.swift || fail 'overlay playback is not enabled by default'
grep -Fq 'resolveMainWindow()?.orderOut(nil)' CuelixaMac/AppModel.swift || fail 'library does not yield to confirmed overlay playback'
grep -Fq 'styleMask: [.borderless, .nonactivatingPanel]' CuelixaMac/SubtitleOverlay.swift || fail 'overlay is not a borderless nonactivating panel'
grep -q 'isMovableByWindowBackground = true' CuelixaMac/SubtitleOverlay.swift || fail 'overlay is not movable'
grep -q 'CuelixaSeekSlider' CuelixaMac/SubtitleOverlay.swift || fail 'overlay native seek control missing'
grep -q 'timeInterval: 3.6' CuelixaMac/SubtitleOverlay.swift || fail 'one-shot control auto-hide timing missing'
if grep -qE 'scheduledTimer\(withTimeInterval:.*repeats: true|Timer\.publish|CADisplayLink|CVDisplayLink' CuelixaMac/SubtitleOverlay.swift; then
  fail 'overlay contains a recurring/polling UI timer'
fi
echo "OVERLAY_PLAYBACK_CONTRACT=PASS"

# App identity: the catalog accent and forced SwiftUI tint must stay aligned
# with the approved AppIcon coral (#FF645A), avoiding the unrelated blue system
# accent in Cuelixa-owned controls/navigation emphasis.
grep -q 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor' CuelixaMac.xcodeproj/project.pbxproj || fail 'AccentColor build setting missing'
grep -q 'CuelixaDesign.identityAccent' CuelixaMac/MainView.swift || fail 'identity tint missing from main view'
[[ -f CuelixaMac/Assets.xcassets/AccentColor.colorset/Contents.json ]] || fail 'AccentColor asset missing'
echo 'IDENTITY_ACCENT_GUARD=PASS'

if grep -R --line-number --fixed-strings 'NSColor(srgbWhite:' CuelixaMac >/dev/null; then
  fail "Unsupported NSColor(srgbWhite:alpha:) initializer present"
fi
pass 'APPKIT_COLOR_API_GUARD'

# Current-release documentation must describe the exact candidate being validated.
grep -Fq '0.6.65-r51' README.md || fail 'README revision is stale'
grep -Fq '0.6.65-r51' docs/BUILD.md || fail 'BUILD documentation revision is stale'
grep -Fq '0.6.65-r51' docs/engineering/MAC-QUALIFICATION-CHECKLIST.md || fail 'qualification checklist revision is stale'
grep -Fq '0.6.65-r51' docs/QUALIFICATION.md || fail 'qualification documentation revision is stale'
grep -Fq 'Engineering revision/build: 51' docs/engineering/SOURCE-BASELINE.txt || fail 'SOURCE-BASELINE build is stale'
pass 'CURRENT_DOCUMENTATION_SYNC'
grep -Fq 'Reset Prepared Subtitles…' CuelixaMac/MainView.swift || fail 'subtitle reset toolbar action missing'
grep -Fq 'resetManagedTranscripts' CuelixaMac/TranscriptCache.swift || fail 'managed subtitle reset implementation missing'
pass 'SUBTITLE_RESET_UI_GUARD'

# Prepare-All status must dismiss both its model summary and the SwiftUI popover
# presentation state. This prevents an empty stale popover after Cancel -> Dismiss.
grep -Fq 'BatchStatusPopover(isPresented: $showingBatchStatus)' CuelixaMac/MainView.swift || fail 'batch status popover presentation binding missing'
grep -Fq '@Binding var isPresented: Bool' CuelixaMac/MainView.swift || fail 'batch status popover dismissal binding missing'
grep -A4 -F 'Button("Dismiss") {' CuelixaMac/MainView.swift | grep -Fq 'isPresented = false' || fail 'Dismiss does not close batch status popover'
pass 'BATCH_POPOVER_DISMISS_GUARD'

if [[ "$ci_mode" == "1" ]]; then
  print 'CI VALIDATION PASSED — XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES — EXACT macOS 26.6.2 TARGET NOT ESTABLISHED'
else
  print 'VALIDATION PASSED — EXACT TARGET XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES'
fi
