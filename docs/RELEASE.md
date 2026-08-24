# Cuelixa 0.6.66 release procedure

Cuelixa's public GitHub build is distributed without a paid Apple Developer ID certificate. The release therefore uses an ad-hoc-signed application inside a read-only DMG and does not claim Apple notarization or verified developer identity.

## Public identity

- Release title, tag, package name and checksum are derived from the Xcode project's marketing version.
- The application build is derived from `CURRENT_PROJECT_VERSION`.
- The release identity is `0.6.66` / build `52`.

## Release checks

1. Freeze the source revision and verify version, build, deployment target, and `arm64` architecture.
2. Verify the complete source manifest.
3. Run the supported local validator and GitHub CI.
4. Build Release with Hardened Runtime enabled.
5. Apply an ad-hoc code signature and verify it with `codesign`.
6. Create and verify a read-only DMG containing `Cuelixa.app` and an Applications symlink.
7. Mount the DMG read-only and recheck the packaged architecture, metadata, and signature.
8. Generate and verify SHA-256 only after the DMG is frozen.
9. Generate GitHub build-provenance attestations for the frozen DMG and checksum.
10. Publish `Cuelixa-0.6.66-macOS-arm64.dmg` and `Cuelixa-0.6.66-macOS-arm64.dmg.sha256` together under tag `v0.6.66`.

## First launch

Because the free build has no Apple Developer ID/notarization ticket, macOS can block its first launch. The supported path is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**. Users should not be asked to disable Gatekeeper or SIP or clear quarantine through Terminal.

## Release immutability

Published release tags and packages are not moved or rewritten. A later correction must use a new version and new checksums.
