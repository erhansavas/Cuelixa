# Cuelixa architecture

This document describes the Cuelixa 0.7.2 implementation. It is a source-of-truth overview, not an aspirational design document.

## System overview

Cuelixa is a local-first, unsandboxed macOS application for lesson-audio playback and subtitle-assisted listening. SwiftUI owns the library window, AppKit supplies focused window/sheet/overlay behavior, AVFoundation owns playback, Apple Speech performs on-device transcription, and SQLite stores library/playback state.

`AppModel` is the `@MainActor` application coordinator. It connects filesystem reconciliation, persistence, transcription, playback, imports, and UI presentation while leaving subsystem work to narrower owners.

## Decision rationale

### Local-first and platform frameworks

The current product operates on local lesson audio and produces local playback/transcript state, so it does not require an application-managed backend, account, analytics path, or cloud synchronization service. Keeping that boundary local avoids making ordinary listening or transcript reuse depend on Cuelixa-operated network infrastructure and keeps application-managed lesson state on the Mac. Apple Speech assets may still be installed by macOS when required; that is an Apple-managed platform dependency rather than a Cuelixa backend.

Shipping code prefers frameworks already present on supported macOS releases. This avoids adding runtime package managers, helper binaries, Rosetta requirements, extra signing surfaces, or independently versioned media/transcription runtimes to a small native app. The trade-off is deliberate platform coupling: Cuelixa targets current Apple silicon/macOS APIs rather than providing a portable cross-platform runtime. See [Privacy architecture](PRIVACY.md) and [Dependency policy](DEPENDENCY-POLICY.md).

### Persistence and content identity

SQLite is used for the structured relationship between canonical file paths, content hashes, file signatures, lesson metadata, playback position, and completion state. A complete scanner reconciliation needs atomic database publication, and the current single-process design benefits from one durable local store rather than several loosely synchronized files. The SQLite connection is therefore confined to `LibraryDatabase` and one serial queue; FULLMUTEX is a second line of defense, not a substitute for that ownership rule. The trade-off is that `@unchecked Sendable` relies on this confinement remaining true.

Tracks and managed transcript artifacts are content-addressed because a path is not a durable description of audio bytes. Binding reusable transcripts to an audio SHA-256 prevents a rename or path alias from silently redefining transcript identity. Managed SRT/manifest pairs are staged and atomically replaced so an interrupted publication does not intentionally expose a half-written pair as valid cache state. The cost is extra hashing/staging I/O at the trust transitions where durable byte identity matters.

### Filesystem reconciliation and trust boundaries

FSEvents is treated as an invalidation signal, not as an authoritative change log. Events can be coalesced or dropped, and a symlink target outside the watched hierarchy can change without a useful event for the symlink entry. The scanner therefore reconciles the filesystem, resolves physical targets, and requires scanner-owned regular files to remain strictly within the canonical library root. This keeps the watched hierarchy and the persisted source identity aligned.

Internal symlinks can resolve to a canonical in-library target and are deduplicated there. External symlinks are not accepted as persistent scanner identities; user-selected external symlinks are supported only as import inputs because `ImportCoordinator` first copies and verifies their bytes into the owned library. Nonregular scanner/managed targets are rejected where opening them could block or cross an ownership boundary. The trade-off is intentional: Cuelixa does not directly track arbitrary external symlink targets as live library files.

### Concurrency and playback ownership

UI coordination and AVFoundation playback state stay on `@MainActor`; scanner/import/Speech work has actor owners; SQLite has its dedicated serial owner. These boundaries make mutation ownership explicit and allow generation/token/identity checks to reject stale callbacks after a scan, cancellation, track change, or shutdown. The trade-off is more explicit cancellation and handoff code than a shared mutable singleton design.

`PlaybackController` does not treat `AVPlayerItem.readyToPlay` as proof that playback is actually progressing. It validates the asset asynchronously, waits for item readiness, requests playback, and presents the playback surface only after the timebase has demonstrably advanced. This avoids hiding the library or presenting a successful-playing UI for a player that never started. The trade-off is a larger state machine with observers and bounded watchdogs.

### Distribution and release integrity

App Sandbox remains disabled for the current direct-GitHub line because the existing persistent library contract includes a legacy `~/podcast` location that cannot be preserved correctly by merely enabling the sandbox entitlement; a real sandbox migration would require user consent, security-scoped persistence, lifecycle handling, and regression qualification. Hardened Runtime remains enabled independently. The complete reasoning and reconsideration triggers are maintained in [App Sandbox decision](SANDBOX-DECISION.md).

The public build is ad-hoc signed because the project does not currently use a paid Developer ID distribution identity. That provides a code-signing seal but not Apple developer authentication or notarization, so the release documentation states those limits explicitly. The release pipeline uses exact-tree manifests, exact-version notes, checksum verification, attestations, and both hosted and independent local qualification to detect different classes of build/release drift; none is documented as an independent trust root. See [Release procedure](RELEASE.md).

Swift CodeQL was evaluated for 0.7.1 using GitHub's documented Swift/manual-build compatibility settings. Initialization succeeded, but the traced Xcode build remained unreliable without an actionable supported correction while ordinary native validation was independent of CodeQL. The optional workflow was therefore removed rather than retained as a permanently failing security signal. This reduces one source of static-analysis coverage; compiler diagnostics, Xcode Analyze, tests, release integrity gates, and manual review remain required, but are not claimed to be equivalent CodeQL coverage. The repository policy is recorded in [GitHub repository controls](GITHUB-SETTINGS.md).

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
