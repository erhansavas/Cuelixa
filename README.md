<div align="center">
  <img src="docs/assets/cuelixa-icon.svg" width="148" height="148" alt="Cuelixa app icon">
  <h1>Cuelixa</h1>
  <p><strong>Local-first listening practice for Apple silicon Macs.</strong></p>
  <p>Play local lesson audio, resume where you left off, generate synchronized subtitles on-device, and keep subtitles in a compact floating overlay while you work in other apps.</p>
</div>

## Highlights

- Native macOS app built with SwiftUI, AppKit, AVFoundation, Speech, and MediaPlayer.
- Apple silicon (`arm64`) and macOS 26 or later.
- Local-first: no account, ads, analytics, telemetry, cloud backend, updater, or bundled third-party runtime.
- Resume/completion state, synchronized subtitles, local transcript cache, Now Playing integration, global shortcuts, and filesystem observation.
- Qualified engineering baseline: **0.6.65-r51 / build 51**.

## Install

When a public release is available, download **`Cuelixa-0.6.65-macOS-arm64.dmg`** from GitHub Releases.

1. Open the DMG.
2. Drag **Cuelixa** to **Applications**.
3. Open Cuelixa from Applications.

### First launch

Cuelixa intentionally uses a free distribution model without a paid Apple Developer ID certificate. A downloaded build therefore cannot be Apple-notarized. If macOS blocks the first launch, try to open Cuelixa once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm **Open**.

No Terminal command, `xattr` workaround, Gatekeeper disablement, or SIP change is required or recommended.

## Library and data

New installations use `~/Music/Cuelixa`. Existing `~/podcast` libraries remain supported non-destructively.

Supported source extensions are `mp3`, `m4a`, `aac`, `flac`, `wav`, `ogg`, and `opus`; actual decoding depends on AVFoundation support on the installed macOS release.

Application-owned data is stored under:

- `~/Library/Application Support/Cuelixa/`
- `~/Library/Application Support/Cuelixa/Transcripts/`
- `~/Library/Caches/Cuelixa/`

Same-basename `.srt` sidecars remain usable in place. Cuelixa does not rename source audio.

## Build and qualification

Exact qualification baseline:

- Cuelixa `0.6.65-r51` / build `51`
- macOS 26.6.2
- Xcode 26.6 (`17F113`)
- Swift 6.3.3
- Apple silicon (`arm64`)

Open `CuelixaMac.xcodeproj`, select **Cuelixa / My Mac**, and build. The canonical exact-target validator is:

```sh
./VALIDATE-MAC.sh
```

See [Build](docs/BUILD.md) and [Qualification](docs/QUALIFICATION.md).

## Artwork

The repository includes the original first-party vector master at [`docs/assets/cuelixa-icon.svg`](docs/assets/cuelixa-icon.svg). The qualified macOS `AppIcon.appiconset` remains the frozen raster shipping set used by R51.

The SVG master has SHA-256:

```text
cf456e5ee218e1db4b439b2110d992edec90546d1163e7c2f0a8de1a54d5539d
```

See [App icon provenance](docs/APP-ICON-PROVENANCE.md).

## Privacy and security

Cuelixa contains no application-managed network service, analytics, tracking, advertising, helper daemon, Full Disk Access requirement, Accessibility permission requirement, or Input Monitoring requirement. Apple Speech may ask macOS to obtain Apple-managed on-device speech assets when needed.

See [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and the [sandbox decision record](docs/SANDBOX-DECISION.md).

## Release integrity

The repository carries `SOURCE-SHA256SUMS.txt`, covering every tracked release-tree file except the manifest itself. The release workflow validates that manifest before building, validates the qualified toolchain and project metadata, runs the validator, creates an ad-hoc-signed read-only DMG, verifies the DMG, and publishes a matching SHA-256 checksum.

Ad-hoc signing is **not** Developer ID signing or notarization, and the project does not claim otherwise.

See [Release](docs/RELEASE.md) and [Publication](docs/PUBLICATION.md).

## License

Cuelixa first-party source is licensed under the Apache License 2.0. `LICENSE` is the unmodified Apache-2.0 license text; project attribution is in `NOTICE`.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
