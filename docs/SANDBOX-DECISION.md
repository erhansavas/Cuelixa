# App Sandbox decision record — 21 August 2026

## Status

**Current decision: App Sandbox remains disabled for the current direct GitHub distribution line. Hardened Runtime remains enabled.**

This is a product-architecture decision, not a claim that unsandboxed software is inherently preferable. Re-evaluate it before changing distribution channels or library-access behavior.

## Distribution channel in scope

The current release plan is direct GitHub distribution of a free ad-hoc-signed macOS build with Hardened Runtime and least privilege. It does not claim Developer ID identity or Apple notarization. A Mac App Store build is not currently in scope.

Apple requires App Sandbox for Mac App Store distribution. If Cuelixa targets the Mac App Store later, this decision must change and the complete sandboxed file-access architecture must be implemented and migrated before release.

## Current filesystem contract

Cuelixa currently uses one persistent recursive library root:

- an existing `~/podcast` library is preserved and remains active non-destructively; otherwise
- a clean profile uses `~/Music/Cuelixa`.

The application recursively discovers media, monitors the hierarchy with FSEvents, imports files into that root, reads sidecar subtitles, and persists content-hash identity/state. Existing libraries must remain usable without destructive migration.

## Why Sandbox is not flipped on mechanically

A sandboxed app receives unrestricted access primarily to its container. Apple supports access to standard folders through entitlements, ephemeral access to user-selected resources, and persistent external access through security-scoped bookmarks.

`~/Music/Cuelixa` could be represented within a sandbox capability model, but the legacy `~/podcast` contract is outside that standard folder. Preserving it would require an explicit consent/persistent-access flow, security-scoped bookmark storage and renewal, balanced `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` lifetime handling, migration behavior, and target testing of recursive FSEvents/import/subtitle workflows under the granted scope. Enabling the checkbox without that work would knowingly regress existing users.

Cuelixa does **not** request Full Disk Access, Accessibility, or Input Monitoring for its current feature set. Global playback shortcuts use Carbon's hot-key API rather than broad keyboard-event surveillance.

## Security benefit and cost

Sandboxing would reduce the filesystem/resource impact of a successful compromise. That is a meaningful security benefit. The current cost is a nontrivial change to persistent library authorization and migration semantics, with direct risk to the project's strongest data-safety invariant: existing libraries must not be broken or destructively moved.

For the current direct-distribution line, the proportionate controls are:

- Hardened Runtime;
- ad-hoc signing plus explicit signature verification for the free build;
- SHA-256 verification of the frozen DMG;
- no unnecessary entitlements/permissions;
- no Full Disk Access request;
- strict Swift concurrency and narrow audited C/Objective-C boundaries;
- local data paths with non-destructive migration rules;
- explicit release verification of the final signed entitlements.

## Reconsideration triggers

Re-open this decision if any of the following becomes true:

1. Mac App Store distribution is required.
2. Cuelixa gains a user-selectable persistent library root.
3. The legacy `~/podcast` compatibility contract is retired through an explicit non-destructive migration plan.
4. New privileges, helpers, XPC services, or external-process behavior are introduced.
5. Target testing demonstrates a complete sandboxed design with no library/FSEvents/import/subtitle regression.

## Primary Apple references

- https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- https://developer.apple.com/documentation/security/hardened-runtime
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
