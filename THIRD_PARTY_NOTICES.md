# Third-Party Notices

Cuelixa does not bundle third-party runtime frameworks, command-line executables, language runtimes, models, or package-manager dependencies in the macOS application target.

The application links against operating-system libraries and frameworks supplied by Apple/macOS, including SwiftUI, AppKit, AVFoundation, Speech, MediaPlayer, Foundation, CryptoKit, CoreServices/FSEvents, and the system SQLite library. Those components are provided as part of the Apple platform and are not redistributed by this repository as third-party binaries.

The repository's GitHub Actions workflows use GitHub's official `actions/checkout` action pinned to a specific commit. GitHub-hosted runner software, GitHub release infrastructure, and Apple/Xcode toolchains are provided by their respective vendors under their own terms.

If a future change adds a redistributed third-party component, its license, notices, version/provenance, and redistribution obligations must be reviewed and recorded here before release.
