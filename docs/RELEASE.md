# macOS release procedure — 0.6.66+

Cuelixa's public GitHub build is distributed without a paid Apple Developer ID certificate. The release therefore uses an ad-hoc-signed application inside a read-only DMG and does not claim Apple notarization or verified developer identity.

## Public identity

- Release title, tag, package name and checksum are derived from the Xcode project's marketing version.
- The application build is derived from `CURRENT_PROJECT_VERSION`.
- For this development revision the intended identity is `0.6.66` / build `52`.

## Release checks

1. Freeze the source revision and verify version, build, deployment target, and `arm64` architecture.
2. Verify the complete source manifest.
3. Run the supported local validator and GitHub CI.
4. Reconfirm manual runtime, accessibility, performance, thermal, and memory testing.
5. Build Release with Hardened Runtime enabled.
6. Apply an ad-hoc code signature and verify it with `codesign`.
7. Create and verify a read-only DMG containing `Cuelixa.app` and an Applications symlink.
8. Mount the DMG read-only and recheck the packaged architecture, metadata, and signature.
9. Generate and verify SHA-256 only after the DMG is frozen.
10. Generate GitHub build-provenance attestations for the frozen DMG and checksum.
11. Publish the DMG and checksum together under the matching Git tag.

## First launch

Because the free build has no Apple Developer ID/notarization ticket, macOS can block its first launch. The supported path is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**. Users should not be asked to disable Gatekeeper or SIP or clear quarantine through Terminal.

## Release immutability

Published release tags and packages are not moved or rewritten. A later correction must use a new version and new checksums.
