# Privacy architecture

Cuelixa is local-first and does not operate an application-managed backend.

- No analytics or telemetry SDK.
- No advertising SDK.
- No tracking domains.
- No user account.
- No microphone capture; transcription reads local lesson files.
- Audio, generated SRT files, content hashes, resume/completion state, and preferences remain on the Mac.
- Apple Speech can request installation of Apple-managed on-device speech assets through macOS when a required asset is absent.
- `PrivacyInfo.xcprivacy` declares no tracking and no collected-data categories.

This document describes the current source tree and must be re-reviewed if networking, analytics, cloud sync, accounts, crash reporting, or third-party SDKs are introduced.
