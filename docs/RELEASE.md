# Cuelixa 0.7.2 release procedure

This is the source of truth for preparing, qualifying, packaging, and publishing the GitHub release.

Cuelixa's public build is distributed without a paid Apple Developer ID identity. The release therefore uses an ad-hoc-signed application with Hardened Runtime inside a read-only DMG. It does **not** claim Apple notarization or verified developer identity.

## Release identity

- Marketing version: `0.7.2`
- Build: `55`
- Tag: `v0.7.2`
- Application identifier: `io.github.erhansavas.Cuelixa`
- Architecture: `arm64`
- Minimum system: macOS `27.0`
- DMG: `Cuelixa-0.7.2-macOS-arm64.dmg`
- Checksum: `Cuelixa-0.7.2-macOS-arm64.dmg.sha256`

During the 0.7.2 qualification window, macOS 27 is in Release Candidate phase. Cuelixa 0.7.2 is therefore published as a GitHub **Pre-release**.

## Release gates

A tag must not be created until all of these are true for the exact candidate tree:

1. The complete source/documentation/repository review is finished and the candidate diff is intentional.
2. `SOURCE-SHA256SUMS.txt` exactly covers the tracked release tree and `Scripts/verify-source-manifest.sh` passes.
3. GitHub hosted CI proves an arm64 macOS 27.0 / Xcode 27.0 environment, records its exact hosted builds, and passes the complete validator for the immutable candidate. The hosted image is an independent compatibility gate and may lag Apple's current RC.
4. The full `VALIDATE-MAC.sh` run independently passes for that exact SHA on the maintainer's Apple silicon Mac running macOS 27 Release Candidate build `26A428` with Xcode 27 Release Candidate build `27A266a`.
5. Any included CodeQL workflow has demonstrated a successful Swift analysis; otherwise CodeQL is omitted rather than kept as a broken ceremonial check.
6. Branch protection requirements are satisfied and the PR is merged without bypassing the `main` ruleset.
7. The merged `main` tree is verified to correspond to the qualified candidate before tagging.
8. Repository-facing presentation intended for the release (README, description, topics, and social preview when used) is complete.

Any source or documentation change after full macOS 27 qualification creates a new candidate SHA and requires requalification.

## Packaging and publication

GitHub's hosted `xcode-27` image can lag Apple's current Release Candidate, so the 0.7.2 DMG is built only on the exact RC qualification environment. After the immutable candidate has passed both release gates:

1. Check out the exact qualified candidate in an isolated worktree and verify `SOURCE-SHA256SUMS.txt`.
2. Re-run the complete validator on macOS 27 RC build `26A428` with `/Applications/Xcode.app` reporting Xcode 27.0 build `27A266a`.
3. Build the Release app from that exact tree, verify version `0.7.2`, build `55`, identifier `io.github.erhansavas.Cuelixa`, minimum macOS `27.0`, and `arm64` architecture.
4. Apply an ad-hoc signature with Hardened Runtime, verify it strictly, and require that `get-task-allow` is absent.
5. Create a read-only DMG containing `Cuelixa.app` and an Applications symlink; verify and remount it, then repeat bundle/architecture/signature checks from the mounted image.
6. Generate `Cuelixa-0.7.2-macOS-arm64.dmg.sha256` only after the DMG is frozen and verify the checksum.
7. Extract only `## Cuelixa 0.7.2 (build 55)` from `CHANGELOG.md` for the release notes.
8. After the protected PR is merged, prove the merged `main` tree equals the qualified candidate tree, create immutable tag `v0.7.2` at that merged commit, and publish the frozen DMG/checksum with the exact notes as a GitHub Pre-release.

After publication, `.github/workflows/release-dmg.yml` independently checks out the immutable tag, verifies the source manifest/release identity/exact notes, downloads the published DMG and checksum, verifies and remounts the image, re-checks metadata/architecture/ad-hoc Hardened Runtime signature, and requests GitHub artifact attestations. It deliberately does not rebuild 0.7.2 on a hosted toolchain that may lag the RC used for the release artifact.

The tag and published artifacts are not moved or rewritten. A correction uses a new version/build, tag, and checksums.

## First launch

Because the free build has no Developer ID/notarization ticket, macOS can block its first launch. The supported path is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**.

Release documentation must never ask users to disable Gatekeeper or System Integrity Protection, clear quarantine globally, modify Secure Boot, or use Recovery mode as an installation workaround.

## Trust boundary

An ad-hoc signature provides a code-signing seal for the packaged application; it is not developer authentication or notarization. The SHA-256 file and GitHub attestation provide release evidence, but users still obtain them from the same GitHub release channel. `SOURCE-SHA256SUMS.txt` detects accidental tree drift and likewise is not an independent trust root.
