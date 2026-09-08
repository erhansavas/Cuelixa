<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cuelixa-icon-dark.png">
    <img src="docs/assets/cuelixa-icon.png" width="148" height="148" alt="Cuelixa app icon">
  </picture>
  <h1>Cuelixa</h1>
  <p><strong>Local-first listening practice for Apple silicon Macs.</strong></p>
  <p>Play local lesson audio, resume where you left off, create synchronized subtitles on-device, and keep them visible in a compact floating overlay while you work.</p>
  <p><strong>Current version: Cuelixa 0.6.66 (build 52)</strong></p>
</div>

## Screenshots

Cuelixa 0.6.66 on macOS 27, shown with sample lessons.

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

## Highlights

- Native macOS application built with SwiftUI, AppKit, AVFoundation, Speech, and MediaPlayer.
- Designed for Apple silicon (`arm64`) and macOS 26 or later.
- Local-first: no account, advertisements, analytics, telemetry, cloud backend, updater, or bundled third-party runtime.
- Resume and completion tracking, synchronized subtitles, local transcript cache, Now Playing integration, global shortcuts, and filesystem observation.
- On-device subtitle preparation with cancellation and batch processing.

## Install

Download **`Cuelixa-0.6.66-macOS-arm64.dmg`** and its matching **`.sha256`** file from the [latest release](https://github.com/erhansavas/Cuelixa/releases/latest). The application must report **version 0.6.66, build 52**.

1. Open the DMG.
2. Drag **Cuelixa** to **Applications**.
3. Open Cuelixa from Applications.

### First launch

Cuelixa uses a free distribution model without a paid Apple Developer ID certificate, so the downloaded build is not notarized by Apple. If macOS blocks the first launch, try to open Cuelixa once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm **Open**.

No Terminal command, Gatekeeper disablement, or SIP change is required or recommended.

## Library and data

New installations use `~/Music/Cuelixa`. Existing `~/podcast` libraries remain supported without destructive migration.

Supported source extensions are `mp3`, `m4a`, `aac`, `flac`, `wav`, `ogg`, and `opus`; actual decoding depends on AVFoundation support in the installed macOS release.

Application-owned data is stored under:

- `~/Library/Application Support/Cuelixa/`
- `~/Library/Application Support/Cuelixa/Transcripts/`
- `~/Library/Caches/Cuelixa/`

Same-basename `.srt` sidecars remain usable in place. Cuelixa does not rename source audio.

## Build and test

Cuelixa 0.6.66 targets Apple silicon and macOS 26 or later. The current audit build is validated on macOS 27 with Xcode 27 (`27A5252f`) and Swift 6.4. Open `CuelixaMac.xcodeproj`, select **Cuelixa / My Mac**, and build.

Run the full local test sequence with the installed Xcode 27 beta:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CUELIXA_MACOS_VERSION=27.0 \
CUELIXA_XCODE_VERSION=27.0 \
CUELIXA_XCODE_BUILD=27A5252f \
CUELIXA_SWIFT_VERSION=6.4 \
./VALIDATE-MAC.sh
```

See [Build](docs/BUILD.md) and [Testing](docs/QUALIFICATION.md).

## Privacy and security

Cuelixa contains no application-managed network service, analytics, tracking, advertising, helper daemon, Full Disk Access requirement, Accessibility permission requirement, or Input Monitoring requirement. Apple Speech may ask macOS to obtain Apple-managed on-device speech assets when needed.

See [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and the [sandbox decision record](docs/SANDBOX-DECISION.md).

## Release integrity

`SOURCE-SHA256SUMS.txt` detects accidental source-tree drift; it is not an independent trust root. The release workflow verifies the manifest, builds and tests the application, creates an ad-hoc-signed read-only DMG, verifies the mounted result, publishes a matching SHA-256 checksum, and records GitHub build-provenance attestations for both artifacts.

Ad-hoc signing is not Developer ID signing or notarization, and the project does not claim otherwise.

See [Release](docs/RELEASE.md) and [Publication](docs/PUBLICATION.md).

## License

Cuelixa first-party source is licensed under the Apache License 2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
