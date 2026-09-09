# Cuelixa architecture

This document describes the Cuelixa 0.7.1 implementation. It is a source-of-truth overview, not an aspirational design document.

## System overview

Cuelixa is a local-first, unsandboxed macOS application for lesson-audio playback and subtitle-assisted listening. SwiftUI owns the library window, AppKit supplies focused window/sheet/overlay behavior, AVFoundation owns playback, Apple Speech performs on-device transcription, and SQLite stores library/playback state.

`AppModel` is the `@MainActor` application coordinator. It connects filesystem reconciliation, persistence, transcription, playback, imports, and UI presentation while leaving subsystem work to narrower owners.

## Major subsystems

- **`AppModel`** — MainActor coordination and published UI state. It starts library monitoring/scanning, validates track identity before playback or preparation, coordinates batch transcription/import tasks, owns shutdown sequencing, and mediates AppKit presentation.
- **`AppPaths` / `AppDirectories`** — immutable process-wide filesystem identity. New installations use `~/Music/Cuelixa`; a valid legacy `~/podcast` directory can remain the library. Application Support, transcript, cache, and staging locations are derived once per process.
- **`LibraryChangeMonitor`** — FSEvents notification source. Events are treated as a trigger for reconciliation rather than as a complete filesystem history. Root-change and dropped-event conditions force recovery behavior.
- **`LibraryScanner`** — actor-owned reconciliation. It resolves the physical library root and candidate files, accepts only regular audio targets contained within the canonical root, deduplicates canonical targets, reuses unchanged `(size, mtime, ctime)` signatures, hashes changed files, loads metadata, and applies one database scan transaction.
- **`LibraryDatabase`** — SQLite persistence behind one serial dispatch queue, with a FULLMUTEX connection, WAL mode, a busy timeout, foreign keys, and transactional schema/scan updates. `tracks` are keyed by content hash; `files` map canonical paths to hashes plus file signatures.
- **`LocalFileAccess`** — descriptor-oriented local-file checks used for bounded reads, no-follow opens where ownership requires them, private application directories, atomic replacement, canonical directory resolution, and import locking. Shared file-signature/hash helpers live with this filesystem boundary.
- **`ImportCoordinator`** — actor-serialized import pipeline. It can follow a user-selected external symlink as an input source, but copies and verifies bytes into the owned library before the scanner/database can treat them as library content. Import staging names are application-owned and collision handling is fail-safe.
- **`TranscriptCache`** — content-addressed transcript storage. Managed SRT/manifest pairs are keyed by the audio SHA-256, verified before reuse, serialized by a recursive lock, and published with same-volume atomic replacement. Legacy managed cache pairs remain readable when they pass the same verification rules.
- **`NativeTranscriber`** — MainActor queue/deduplication layer for subtitle requests and watcher cancellation. Before Speech processing, it creates a stable staging snapshot and verifies that snapshot against the track content hash.
- **`TranscriptionExecutor` / `AppleSpeechExecutor`** — actor-owned adapter around Apple Speech. It resolves supported on-device Speech assets, runs `SpeechAnalyzer`, converts timed results into deterministic subtitle fragments, and supports explicit cancellation/cleanup.
- **`PlaybackController`** — MainActor AVFoundation state machine. It asynchronously validates an `AVURLAsset`, waits for item readiness, verifies actual playback progression before presenting the playback surface, owns seeks/watchdogs/observers/Now Playing integration, and uses generation checks to reject stale callbacks.
- **Subtitle parsing/presentation** — `SubtitleSegmenter` shapes Apple Speech timing into readable cues; `SRT` bounds and parses local SRT input; `SubtitleTimeline` supplies deterministic cue selection; `SubtitleBalancer` shapes displayed lines.
- **UI / overlay** — SwiftUI owns the library/navigation UI. AppKit sheet controllers provide focused modal tasks. `SubtitleOverlayController` owns only the nonactivating floating playback UI; it never owns AVPlayer or persistence state.

## Data flow

### Import

`external file` → source validation → verified staging copy → library destination → scanner reconciliation → SQLite

The external source may be reached through a symlink. What becomes trusted library state is the copied, verified file inside the selected library.

### Library reconciliation

`library filesystem` → `LibraryScanner` → canonical target + containment check → file signature/hash → metadata → `LibraryDatabase.applyScan`

FSEvents initiates reconciliation; database identity is derived from the reconciliation result, not directly from event paths.

### Transcription

`verified track identity` → stable staging snapshot + SHA-256 verification → `AppleSpeechExecutor` → timed subtitle cues → `TranscriptCache.commit` → verified SRT/manifest pair

A transcript is reusable only when its managed manifest binds the SRT digest to the expected audio content hash.

### Playback

`Track` → recorded source/signature validation in `AppModel` → verified managed transcript or valid sidecar resolution → `PlaybackController` AVFoundation preparation → readiness/playback-progression proof → subtitle timeline + overlay

The lightweight source-signature preflight prevents knowingly starting work from stale scan metadata. Transcription adds a full snapshot hash because it creates durable content-addressed output.

## Concurrency model

- App/UI coordination, playback state, transcriber queue state, and window ownership are `@MainActor`.
- `LibraryScanner`, `ImportCoordinator`, `TranscriptAvailabilityWorker`, and `AppleSpeechExecutor` are actors.
- SQLite connection state is confined to `LibraryDatabase` and serialized on its private queue. Its `@unchecked Sendable` conformance is justified by that confinement plus SQLite FULLMUTEX mode.
- `TranscriptCache` is `@unchecked Sendable`; all mutable cache/publication/memo state is serialized by its documented recursive lock.
- Long file hashing/copy work uses owned utility-priority tasks with cooperative cancellation.
- Scanner, transcription, import, playback, and UI callbacks use generation/token/identity checks to reject stale asynchronous work.
- Confirmed application termination stops FSEvents/timers/playback, cancels owned work, then awaits scanner, Speech, and import cleanup before replying to AppKit's deferred termination request.

## Important invariants

1. **Canonical library containment.** Scanner-owned file identities resolve to regular physical files strictly below the canonical library root; string-prefix containment is not used.
2. **Content identity.** A track content hash describes the bytes that were hashed during reconciliation. `(size, mtime, ctime)` is a fast freshness signature, not a cryptographic replacement for the content hash.
3. **Regular-file boundary.** Hashing, bounded managed reads, scanner targets, transcript artifacts, and database/import lock files reject nonregular objects where blocking or link substitution would be unsafe.
4. **Import ownership.** External input is not library state until a verified copy has been placed inside the library.
5. **Cache ownership.** Cuelixa deletes or replaces only its managed transcript/cache artifacts; same-basename user SRT files beside lesson audio remain user-owned.
6. **Atomic publication.** Managed transcript files are staged beside their destination and published with `rename`; verification requires the final SRT/manifest pair.
7. **Database ownership.** SQLite state is changed through the serialized database owner; a complete scanner pass is applied transactionally, while an incomplete pass never marks unseen paths missing.
8. **Release-tree integrity.** The release source manifest must match every tracked release-tree path and digest. It detects accidental tree drift but is not an independent trust root.

## Security boundary

Cuelixa is an **unsandboxed local application**. It does not claim isolation from a malicious process already executing as the same macOS user, nor does it turn user-writable lesson storage into a privileged trust boundary.

The filesystem hardening is defensive correctness: it avoids blocking on special files, limits managed reads, rejects unsafe managed links where ownership requires it, keeps scanner identities inside the selected canonical library hierarchy, verifies copied/transcribed bytes at important trust transitions, and prevents ordinary path substitution or stale-metadata mistakes from silently becoming durable app state.

Cuelixa does not require Full Disk Access, Accessibility, Input Monitoring, disabling Gatekeeper, disabling System Integrity Protection, or Recovery-mode changes.

## Distribution model

Cuelixa 0.7.1 targets **Apple silicon (`arm64`) and macOS 27.0 or later**. During the 0.7.1 qualification window, macOS 27 and Xcode 27 are still beta software, so the GitHub release is a pre-release.

The free GitHub build enables Hardened Runtime and is ad-hoc signed when no Developer ID identity is available. Ad-hoc signing is not developer authentication and the build is not claimed to be notarized. The supported first-launch path is macOS **Privacy & Security → Open Anyway**; security protections are not disabled as an installation workaround.
