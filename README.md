<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cuelixa-icon-dark.png">
    <img src="docs/assets/cuelixa-icon.png" width="148" height="148" alt="Cuelixa app icon">
  </picture>
  <h1>Cuelixa</h1>
  <p><strong>Local-first listening practice for Apple silicon Macs.</strong></p>
  <p>Listen to local lesson audio, resume where you left off, and follow synchronized subtitles in a compact floating overlay.</p>
  <p><strong>Cuelixa 0.7 · Build 53</strong></p>
</div>

## Screenshots

Cuelixa on macOS 27, shown with sample lessons. The library preview follows your light or dark appearance.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/cuelixa-library.png">
    <img src="docs/screenshots/cuelixa-library-light.png" alt="Cuelixa lesson library with completion tracking and prepared subtitles" width="100%">
  </picture>
  <br>
  <sub>Manage lessons in a native library that follows your Mac’s appearance</sub>
</p>

<p align="center">
  <img src="docs/screenshots/cuelixa-subtitle-options.png" alt="Cuelixa subtitle preparation options" width="100%">
  <br>
  <sub>Prepare subtitles on-device or start listening without them</sub>
</p>

<p align="center">
  <img src="docs/screenshots/cuelixa-playback-overlay.png" alt="Cuelixa subtitle-first playback overlay" width="100%">
  <br>
  <sub>Keep synchronized subtitles visible while you work</sub>
</p>

## Features

- **Organize your listening.** Browse and search local lessons, track completion, and resume from your saved position.
- **Follow along with subtitles.** Use existing SRT files or prepare subtitles on-device, individually or in a batch.
- **Keep playback within reach.** Use the floating subtitle overlay, keyboard shortcuts, and macOS Now Playing controls.
- **Keep your library local.** No account, advertisements, analytics, or cloud backend.

Requires an Apple silicon Mac and macOS 27 or later. Current validation covers macOS 27; see [testing status](docs/QUALIFICATION.md) for coverage and limitations.

## Install

Download **Cuelixa 0.7 (build 53)** from [GitHub Releases](https://github.com/erhansavas/Cuelixa/releases/tag/v0.7). Choose `Cuelixa-0.7-macOS-arm64.dmg` and its matching `.sha256` checksum file. The app requires **macOS 27 or later** and **Apple silicon**.

To install:

1. Open the DMG.
2. Drag **Cuelixa** to **Applications**.
3. Open Cuelixa from Applications.

### First launch

Public builds are ad-hoc signed and are not notarized by Apple. If macOS blocks the first launch, try to open Cuelixa once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. No Terminal command or change to Gatekeeper or System Integrity Protection is required.

## Library and data

New installations use `~/Music/Cuelixa`. Existing `~/podcast` libraries remain supported without destructive migration.

Supported source extensions are `mp3`, `m4a`, `aac`, `flac`, `wav`, `ogg`, and `opus`; actual decoding depends on AVFoundation support in the installed macOS release.

Application-owned data is stored under:

- `~/Library/Application Support/Cuelixa/`
- `~/Library/Application Support/Cuelixa/Transcripts/`
- `~/Library/Caches/Cuelixa/`

Same-basename `.srt` sidecars remain usable in place. Cuelixa does not rename source audio.

## Build and test

Cuelixa uses SwiftUI, AppKit, AVFoundation, and Apple Speech, with no third-party package dependencies. Open `CuelixaMac.xcodeproj` in full Xcode, select **Cuelixa / My Mac**, and build.

The current validation environment is macOS 27, Xcode 27 beta 6 (`27A5252f`), and Swift 6.4. Run the complete checks with:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./VALIDATE-MAC.sh
```

The validator runs unit, integration, performance, and native UI tests, clean Debug and Release builds, static analysis, playback checks, and source-integrity checks. See [build instructions](docs/BUILD.md) and [testing status](docs/QUALIFICATION.md) for details.

## Privacy and security

Audio, listening progress, and prepared subtitles remain on your Mac. Apple Speech may ask macOS to download on-device speech assets when needed. Cuelixa does not require Full Disk Access, Accessibility, or Input Monitoring permission.

See [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and the [sandbox decision record](docs/SANDBOX-DECISION.md).

## Release integrity

The release workflow verifies source checksums, compiles the app and test targets, runs static analysis, and packages an ad-hoc-signed app in a read-only DMG. Runtime and UI qualification run on macOS 27 before release. Published packages include a SHA-256 checksum and GitHub build-provenance attestations. `SOURCE-SHA256SUMS.txt` detects accidental source changes; it is not an independent trust root.

See [Release](docs/RELEASE.md) and [Publication](docs/PUBLICATION.md).

## License

Cuelixa first-party source is licensed under the Apache License 2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
