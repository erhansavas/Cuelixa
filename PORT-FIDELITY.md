# Native Port Fidelity Contract

## Authoritative product baseline

The behavioral baseline is the verified Cuelixa 0.6.65-r6 Linux/GNOME source. Its supplied archive SHA-256 is `bbb094e2f04818a749e34bd235b53eb75950bdcb64c88e46ca48faa56cb22a96`; the supplied installer SHA-256 is `d991c477c8942184c4e20c55001d93679dd2f642ca1fa8c293e4deee937eb42e`. The native-port qualification history reverified both uploaded baseline artifacts before the overlay contract was frozen.

The macOS port preserves Cuelixa's purpose and interaction contract while using native macOS implementation primitives. Pixel imitation of GTK is not required; product semantics are.

## Core playback philosophy

The r6 source establishes these behaviors:

- Selecting Play starts audio and, when available, synchronized subtitles.
- The library window hides when playback starts.
- Playback is represented by a separate compact floating overlay rather than a permanently attached library player.
- Subtitle text is the dominant visual surface.
- Transport controls (timeline, -10, play/pause, +10, stop/close) are secondary and auto-hide after inactivity.
- The playback surface is movable.
- Right-click/pointer/keyboard activity can reveal controls.
- Global shortcuts provide play/pause, ±10, ±30 and Show Library while the user works elsewhere.
- Stopping playback returns to the library.

The native macOS implementation carries that contract without making the overlay own AVPlayer.

## Native macOS mapping

| Product concern | Native implementation |
|---|---|
| Library lifecycle | SwiftUI `App` + system `Window` scene |
| Library navigation | `NavigationSplitView` + sidebar `List(selection:)` |
| Search | `.searchable(..., placement: .toolbar)` |
| Lesson list | SwiftUI `List` + native menus/context menus |
| Batch status | toolbar action + native popover |
| Playback engine | AVFoundation `AVPlayer` |
| Floating playback surface | pure-AppKit borderless/nonactivating `NSPanel` |
| Subtitle rendering | AppKit text label over transparent window content |
| Timeline | AppKit `NSSlider`, exact seek on commit |
| Playback controls | SF Symbols by runtime name + standard AppKit controls |
| On-device transcription | SpeechAnalyzer / SpeechTranscriber |
| Now Playing/media keys | MediaPlayer |
| Global shortcuts | Carbon hot-key adapter |
| Library observation | FSEvents |
| State/cache | Foundation application-support/cache paths + SQLite |

The overlay is intentionally nonactivating so it can coexist with work in another app. It can join Spaces and fullscreen as an auxiliary surface. It contains no AVPlayer, no recurring polling timer, no SwiftUI hosting tree, and no process-global event monitor.

## macOS 26 design discipline

The main window relies on standard SwiftUI/AppKit controls so Xcode 26/macOS 26 supplies the current system materials, metrics, focus behavior, menus, toolbar grouping, and accessibility. Cuelixa's exact AppIcon coral `#FF645A` is reserved for app-owned identity emphasis; native structural surfaces remain system-owned.

The floating overlay uses a restrained system visual-effect surface only for transport legibility. When controls auto-hide, the subtitle text remains visually primary and no permanent player chrome remains.

## Performance / energy contract

- Normal library monitoring is FSEvents-driven.
- The fallback scan timer exists only when the FSEvents stream cannot start.
- Playback has one 10 Hz periodic observer only after actual playback is proven.
- Subtitle handoff uses the shared timeline and AVFoundation events; the overlay adds no playback polling loop.
- Control auto-hide is one reusable one-shot timer with tolerance.
- Scrubbing updates the UI/subtitle timeline in memory and performs one exact AVPlayer seek on commit.
- Transcription remains single-worker and cancellation-aware.
- No third-party UI/runtime dependency, custom thread pool, ARM intrinsic, or machine-specific compiler flag is added.

## Fidelity rejection criteria

A macOS revision is not faithful if it:

- replaces the overlay workflow with a permanently attached media-player bar;
- requires the library window to stay visible during normal playback;
- removes movable subtitle-first playback;
- makes UI presentation own or gate AVPlayer lifetime;
- loses exact seek, global shortcuts, resume/completion, subtitle-cache integrity, Prepare All, cancellation, or safe quit;
- hand-paints system chrome when a standard macOS control/container is available.
