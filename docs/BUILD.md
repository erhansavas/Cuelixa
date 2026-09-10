# Build and validation

These instructions apply to Cuelixa 0.7.2 (build 55).

## Requirements

- Apple silicon Mac
- macOS 27.0 or later
- Full Xcode 27

The 0.7.2 release qualification target is macOS 27 Release Candidate (`26A428`), Xcode 27 Release Candidate (`27A266a`), and Swift 6.4. The deployment target is macOS 27.0 and the shipping architecture is `arm64`.

## Xcode

Open `CuelixaMac.xcodeproj`, select **Cuelixa → My Mac**, then build the Debug or Release configuration. Complete strict-concurrency checking and warnings-as-errors are enabled for the application target.

## Complete local qualification

Select the documented Xcode 27 installation and run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./VALIDATE-MAC.sh
```

The default validator is a release gate and must run on the supported macOS 27 runtime. It uses fresh DerivedData, verifies toolchain/project/source invariants, runs deterministic smoke checks, executes the configured runtime/integration/performance/native UI tests, clean-builds Debug and Release, runs Analyze, and inspects the resulting `arm64` application metadata.

Validation builds set `CODE_SIGNING_ALLOWED=NO` where signing is not part of the behavior under test; native UI tests use local ad-hoc signing. The validator does not change project signing settings and does not publish a release.

Native UI tests use isolated temporary libraries. The `DEBUG` compilation condition enables that isolation only in Debug/test builds; the Release application uses the normal process-wide `AppPaths` resolution.

## Hosted GitHub validation

The permanent `macos-arm64-release` job uses GitHub's Apple silicon `xcode-27` image, requires an arm64 macOS 27.0 host and Xcode 27.0 with Swift 6.4, records the exact hosted macOS/Xcode builds, and runs the complete validator against that hosted environment. The hosted image can differ from or lag the exact qualification toolchain, so hosted CI is an independent compatibility gate rather than the source of the RC build identity.

Release qualification additionally requires the immutable candidate to pass the complete validator on the maintainer's exact macOS 27 RC (`26A428`) / Xcode 27 RC (`27A266a`) environment. Both gates must correspond to the same candidate tree before release.

## Release-note extraction

`Scripts/extract-release-notes.sh` extracts one exact `CHANGELOG.md` release section by version/build and fails if the expected heading is absent or duplicated. Permanent CI exercises this script directly and the release workflow uses the same implementation rather than maintaining separate parsing logic.

## Source integrity

`SOURCE-SHA256SUMS.txt` covers every tracked release-tree file except itself. It detects accidental tree drift but is stored with the source and is therefore not an independent trust root.

Verify both the path set and file digests with:

```sh
./Scripts/verify-source-manifest.sh
```
