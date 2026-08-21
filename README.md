# Cuelixa 0.6.65 for macOS

Repository: `https://github.com/erhansavas/Cuelixa`  
Maintainer: `erhansavas`

Cuelixa is a local-first listening-practice application for macOS. It plays local lesson audio, preserves resume/completion state, prepares synchronized subtitles on-device, and presents those subtitles in a lightweight movable overlay so the learner can keep working in another app or Space without carrying a permanent media-player window.

The native macOS port preserves the verified Cuelixa 0.6.65-r6 product contract while replacing Linux/GNOME implementation details with first-party SwiftUI/AppKit/AVFoundation/Speech equivalents.

This repository targets Apple Silicon Macs running macOS 26 or later. The current 0.6.65-r51 final-qualification candidate targets Xcode 26.6 / Swift 6.3.3. Xcode 27 beta and macOS 27-only APIs are intentionally out of scope.

## Product contract

- The library window is for finding, preparing, organizing, and starting lessons.
- Once playback is **actually confirmed** by AVFoundation, the library yields and playback continues in a small movable nonactivating overlay.
- The overlay shows synchronized subtitle text and a compact native transport. Its controls auto-hide after inactivity, leaving the subtitle itself as the primary surface.
- The overlay owns no `AVPlayer` state. Hiding, moving, or failing the overlay cannot stop the audio engine.
- `Control-Option-S` shows the library without stopping playback. Global play/pause and seek shortcuts continue to work while another app is frontmost.
- Closing/stopping the floating playback surface returns to the library. Normal macOS `Command-Q` remains application Quit.

This is deliberately **not** a Music-style application with a permanently attached player bar. It is the native macOS expression of Cuelixa's original subtitle-overlay workflow.

## Architecture

- SwiftUI `App` / single library `Window` scene with AppKit lifecycle/termination integration.
- Native `NavigationSplitView`, sidebar `List`, toolbar search, menus, popovers, and `ContentUnavailableView`.
- Pure-AppKit floating `NSPanel` for subtitle/transport presentation; borderless, movable, nonactivating, and able to accompany fullscreen/Space workflows.
- Native AppKit `NSSlider` interaction with one exact AVPlayer seek on scrub commit.
- AVFoundation `AVPlayer` playback with asynchronous local-asset validation, bounded readiness/start watchdogs, and actual time-advance confirmation before presentation.
- Shared subtitle timeline sampled by the existing 10 Hz active-playback observer; no additional playback polling loop is introduced by the overlay.
- Apple Speech `SpeechAnalyzer` / `SpeechTranscriber` for on-device subtitle generation.
- MediaPlayer Now Playing and remote-command integration.
- SQLite3 WAL state, FSEvents library observation, CryptoKit SHA-256 identity, and Carbon `RegisterEventHotKey` for the fixed shortcut set.

No external player, Whisper model, Python environment, Homebrew binary, ffmpeg executable, Rosetta helper, or bundled third-party runtime framework is required by the macOS source tree.

## Build

Requirements:

- Apple Silicon Mac
- macOS 26.6.2 for exact qualification
- Xcode 26.6 (17F113) / Swift 6.3.3

Open `CuelixaMac.xcodeproj`, select **Cuelixa / My Mac**, then perform **Product → Clean Build Folder** and build Debug first. The candidate is not qualified unless Debug and Release both produce **0 errors / 0 warnings**.

For the exact target validation sequence, run:

```sh
./VALIDATE-MAC.sh
```

## Library and data

New installations use `~/Music/Cuelixa`, resolved through Foundation. Existing `~/podcast` libraries are preserved in place and remain active non-destructively. Supported source extensions are mp3, m4a, aac, flac, wav, ogg, and opus; actual decoding depends on AVFoundation support on the target macOS release.

Application state is stored under:

- `~/Library/Application Support/Cuelixa/`
- `~/Library/Application Support/Cuelixa/Transcripts/`
- `~/Library/Caches/Cuelixa/`

Valid same-basename sidecar `.srt` files remain usable in place. Source audio is never renamed.

## Privacy

Cuelixa is local-first. It contains no analytics, advertising, telemetry, tracking domains, or application-managed network service. Audio, library state, and generated subtitles remain on the Mac. Apple Speech may ask macOS to install Apple-managed on-device speech assets when required. `PrivacyInfo.xcprivacy` explicitly declares no tracking and no collected-data categories for the application target.

## Distribution status

The project is prepared for future Developer ID direct distribution, but this engineering candidate is not claimed to be signed or notarized. App Sandbox remains disabled for the current direct-distribution recursive-library contract pending a complete authorization/security-scoped-bookmark migration design. No Full Disk Access, Accessibility, Input Monitoring, helper daemon, updater, analytics, or telemetry requirement is introduced.

See `docs/BUILD.md`, `docs/RELEASE.md`, `docs/PRIVACY.md`, `docs/LEGAL-APPLICABILITY.md`, `docs/SANDBOX-DECISION.md`, `SECURITY.md`, and `THIRD_PARTY_NOTICES.md`.

## License

First-party Cuelixa source material is licensed under the Apache License 2.0. See `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`.

## Release readiness

See `docs/PUBLICATION.md` for the frozen public artifact naming and the evidence required before publishing.
