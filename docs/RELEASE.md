# Cuelixa 0.7.1 release procedure

This is the source of truth for preparing, qualifying, packaging, and publishing the GitHub release.

Cuelixa's public build is distributed without a paid Apple Developer ID identity. The release therefore uses an ad-hoc-signed application with Hardened Runtime inside a read-only DMG. It does **not** claim Apple notarization or verified developer identity.

## Release identity

- Marketing version: `0.7.1`
- Build: `54`
- Tag: `v0.7.1`
- Application identifier: `io.github.erhansavas.Cuelixa`
- Architecture: `arm64`
- Minimum system: macOS `27.0`
- DMG: `Cuelixa-0.7.1-macOS-arm64.dmg`
- Checksum: `Cuelixa-0.7.1-macOS-arm64.dmg.sha256`

During the 0.7.1 qualification window, macOS 27 remains beta software. The permanent release workflow must therefore create 0.7.1 as a GitHub **Pre-release**. This is encoded in the workflow rather than corrected manually afterward.

## Release gates

A tag must not be created until all of these are true for the exact candidate tree:

1. The complete source/documentation/repository review is finished and the candidate diff is intentional.
2. `SOURCE-SHA256SUMS.txt` exactly covers the tracked release tree and `Scripts/verify-source-manifest.sh` passes.
3. GitHub hosted CI passes with the documented Xcode 27 build-only limitation.
4. The full `VALIDATE-MAC.sh` run passes on an Apple silicon Mac running the supported macOS 27 runtime and documented Xcode 27 toolchain.
5. Any included CodeQL workflow has demonstrated a successful Swift analysis; otherwise CodeQL is omitted rather than kept as a broken ceremonial check.
6. Branch protection requirements are satisfied and the PR is merged without bypassing the `main` ruleset.
7. The merged `main` tree is verified to correspond to the qualified candidate before tagging.
8. Repository-facing presentation intended for the release (README, description, topics, and social preview when used) is complete.

Any source or documentation change after full macOS 27 qualification creates a new candidate SHA and requires requalification.

## Packaging and publication

The permanent `.github/workflows/release-dmg.yml` performs the package-side evidence after `v0.7.1` is created:

1. Derive marketing version/build from Xcode and require the tag to equal `v$VERSION`.
2. Verify the complete source manifest, `arm64` runner/toolchain assumptions, and macOS 27 deployment target.
3. Run the repository validator in build-only mode on the hosted Xcode 27 runner; this is compile/build/Analyze evidence, not macOS 27 runtime qualification.
4. Build the Release application with project Hardened Runtime settings preserved.
5. Apply an ad-hoc signature and verify the bundle, metadata, architecture, minimum system, signature, and absence of `get-task-allow`.
6. Create a read-only DMG containing `Cuelixa.app` and an Applications symlink; verify, mount, and re-check the packaged app.
7. Generate SHA-256 only after the DMG is frozen, then verify the checksum file.
8. Request GitHub artifact attestations for the frozen DMG and checksum.
9. Extract **only** the exact current `CHANGELOG.md` section using `Scripts/extract-release-notes.sh`; extraction fails if the current heading is absent or duplicated.
10. Publish the matching assets and current notes under the immutable tag as a GitHub Pre-release.

The tag and published artifacts are not moved or rewritten. A correction uses a new version/build, tag, and checksums.

## First launch

Because the free build has no Developer ID/notarization ticket, macOS can block its first launch. The supported path is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**.

Release documentation must never ask users to disable Gatekeeper or System Integrity Protection, clear quarantine globally, modify Secure Boot, or use Recovery mode as an installation workaround.

## Trust boundary

An ad-hoc signature provides a code-signing seal for the packaged application; it is not developer authentication or notarization. The SHA-256 file and GitHub attestation provide release evidence, but users still obtain them from the same GitHub release channel. `SOURCE-SHA256SUMS.txt` detects accidental tree drift and likewise is not an independent trust root.
