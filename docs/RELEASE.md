# Cuelixa 0.7.3 release procedure

This is the source of truth for preparing, qualifying, packaging, and publishing the GitHub release.

Cuelixa's public build is distributed without a paid Apple Developer ID identity. The release therefore uses an ad-hoc-signed application with Hardened Runtime inside a read-only DMG. It does **not** claim Apple notarization or verified developer identity.

## Release identity

- Marketing version: `0.7.3`
- Build: `56`
- Tag: `v0.7.3`
- Application identifier: `io.github.erhansavas.Cuelixa`
- Architecture: `arm64`
- Minimum system: macOS `27.0`
- DMG: `Cuelixa-0.7.3-macOS-arm64.dmg`
- Checksum: `Cuelixa-0.7.3-macOS-arm64.dmg.sha256`

Cuelixa 0.7.3 was qualified while macOS 27 and Xcode 27 were in Release Candidate phase, so it is published as a GitHub **Pre-release**.

## Release gates

A tag must not be created until all of these are true for the exact candidate tree:

1. The complete source/documentation/repository review is finished and the candidate diff is intentional.
2. `SOURCE-SHA256SUMS.txt` exactly covers the tracked release tree and `Scripts/verify-source-manifest.sh` passes.
3. GitHub hosted CI proves an arm64 macOS 27.0 / Xcode 27.0 environment, records its exact hosted builds, and passes the complete validator for the immutable candidate. The hosted image is an independent compatibility gate and may lag the qualification toolchain.
4. The full `VALIDATE-MAC.sh` run independently passes for that exact SHA on the maintainer's Apple silicon Mac running macOS 27 Release Candidate build `26A428` with Xcode 27 Release Candidate build `27A266a`.
5. Any included CodeQL workflow has demonstrated a successful Swift analysis; otherwise CodeQL is omitted rather than kept as a broken ceremonial check.
6. Branch protection requirements are satisfied and the PR is merged without bypassing the `main` ruleset.
7. The merged `main` tree is verified to correspond to the qualified candidate before tagging.
8. Repository-facing presentation intended for the release (README, description, topics, and social preview when used) is complete.

Any source or documentation change after full macOS 27 qualification creates a new candidate SHA and requires requalification.

## Packaging and publication

GitHub's hosted `xcode-27` image can lag the qualification toolchain, so the 0.7.3 DMG is built only on the exact RC qualification environment. After the immutable candidate has passed both release gates:

1. Check out the exact qualified candidate in an isolated worktree and verify `SOURCE-SHA256SUMS.txt`.
2. Re-run the complete validator on macOS 27 RC build `26A428` with `/Applications/Xcode.app` reporting Xcode 27.0 build `27A266a`.
3. Build the Release app from that exact tree, verify version `0.7.3`, build `56`, identifier `io.github.erhansavas.Cuelixa`, minimum macOS `27.0`, and `arm64` architecture.
4. Apply an ad-hoc signature with Hardened Runtime, verify it strictly, and require that `get-task-allow` is absent.
5. Create a read-only DMG containing `Cuelixa.app` and an Applications symlink; verify and remount it, then repeat bundle/architecture/signature checks from the mounted image.
6. Generate `Cuelixa-0.7.3-macOS-arm64.dmg.sha256` only after the DMG is frozen and verify the checksum.
7. Extract only `## Cuelixa 0.7.3 (build 56)` from `CHANGELOG.md` for the release notes.
8. After the protected PR is merged, prove the merged `main` tree equals the qualified candidate tree and create `v0.7.3` at that merged commit.
9. Create the GitHub release as a draft, attach exactly the frozen DMG and checksum, then publish that draft as a **Pre-release**. Immutable releases must be enabled before publication.

Publishing the immutable release locks the tag and attached release assets and causes GitHub to generate a release attestation that binds the release tag, commit SHA, and assets. That release attestation is **not** presented as build provenance for the locally built DMG.

After publication, `.github/workflows/release-dmg.yml` runs with read-only repository permissions. It independently checks out the immutable tag, verifies the source manifest, exact release identity and notes, requires exactly the two expected assets, downloads them, verifies the checksum, remounts the DMG, and re-checks bundle metadata, `arm64` architecture, ad-hoc signature, Hardened Runtime, and absence of `get-task-allow`. It deliberately does not rebuild or attest the local build as if GitHub Actions had produced it.

The tag and published assets are not moved or rewritten. A correction uses a new version/build, tag, and checksums.

## First launch

Because the free build has no Developer ID/notarization ticket, macOS can block its first launch. The supported path is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**.

Release documentation must never ask users to disable Gatekeeper or System Integrity Protection, clear quarantine globally, modify Secure Boot, or use Recovery mode as an installation workaround.

## Trust boundary

An ad-hoc signature provides a code-signing seal for the packaged application; it is not developer authentication or notarization. The checksum detects byte changes when compared against a trusted expected value. GitHub's immutable-release attestation binds the GitHub release tag, commit SHA, and attached assets, but it does not prove that the local RC machine built those bytes. `SOURCE-SHA256SUMS.txt` detects accidental source-tree drift and likewise is not an independent trust root.
