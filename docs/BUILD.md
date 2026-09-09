# Build and validation

These instructions apply to Cuelixa 0.7.1 (build 54).

## Requirements

- Apple silicon Mac
- macOS 27.0 or later
- Full Xcode 27

The 0.7.1 qualification target is macOS 27 beta 8 (`26A5425a`), Xcode 27 beta 6 (`27A5252f`), and Swift 6.4. The deployment target is macOS 27.0 and the shipping architecture is `arm64`.

## Xcode

Open `CuelixaMac.xcodeproj`, select **Cuelixa → My Mac**, then build the Debug or Release configuration. Complete strict-concurrency checking and warnings-as-errors are enabled for the application target.

## Complete local qualification

Select the documented Xcode 27 installation and run:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./VALIDATE-MAC.sh
```

The default validator is a release gate and must run on the supported macOS 27 runtime. It uses fresh DerivedData, verifies toolchain/project/source invariants, runs deterministic smoke checks, executes the configured runtime/integration/performance/native UI tests, clean-builds Debug and Release, runs Analyze, and inspects the resulting `arm64` application metadata.

Validation builds set `CODE_SIGNING_ALLOWED=NO` where signing is not part of the behavior under test; native UI tests use local ad-hoc signing. The validator does not change project signing settings and does not publish a release.

Native UI tests use isolated temporary libraries. The `DEBUG` compilation condition enables that isolation only in Debug/test builds; the Release application uses the normal process-wide `AppPaths` resolution.

## Hosted GitHub validation

The permanent `macos-arm64-release` job uses GitHub's Apple silicon `xcode-27` image, selects Xcode 27 beta 6 explicitly, and fails unless the actual host reports macOS major version 27. It then runs the complete validator without build-only mode. The final candidate Actions log is the evidence for the exact hosted macOS version; this document does not substitute a mutable platform claim for that run evidence.

Hosted success is still independent of the required exact-SHA qualification on the user's own supported Mac. Both gates must correspond to the immutable candidate before release.

## Release-note extraction

`Scripts/extract-release-notes.sh` extracts one exact `CHANGELOG.md` release section by version/build and fails if the expected heading is absent or duplicated. Permanent CI exercises this script directly and the release workflow uses the same implementation rather than maintaining separate parsing logic.

## Source integrity

`SOURCE-SHA256SUMS.txt` covers every tracked release-tree file except itself. It detects accidental tree drift but is stored with the source and is therefore not an independent trust root.

Verify both the path set and file digests with:

```sh
./Scripts/verify-source-manifest.sh
```
