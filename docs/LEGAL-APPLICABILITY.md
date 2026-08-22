# Legal and standards applicability record — 21 August 2026

This document is an engineering applicability record, not legal advice and not a certification claim.

## Apache License 2.0

Cuelixa first-party source is intended to remain Apache-2.0. Public releases must preserve the official `LICENSE`, applicable `NOTICE`, third-party notices, and provenance records for non-code assets.

## Privacy / GDPR / KVKK

The current application is local-first: it has no account, analytics SDK, advertising SDK, tracking domains, cloud sync, application-managed backend, or telemetry path. Audio, content hashes, generated subtitles, preferences, and listening state remain on the Mac. The application privacy manifest declares no tracking and no collected-data categories.

If any networking, analytics, crash reporting, accounts, sync, or remote processing is introduced, GDPR/KVKK applicability must be reassessed before release.

## EU Cyber Resilience Act

CRA applicability depends on how the software is made available and whether activity falls within the regulation's commercial/open-source scope. Apache-2.0 by itself is not a universal exemption or a universal trigger. Before a commercial EU distribution, reassess the current CRA text/guidance, vulnerability handling, update/support commitments, technical documentation, and any SBOM/reporting obligations that actually apply.

## Accessibility

Cuelixa should follow Apple accessibility guidance and WCAG/EN 301 549 principles as engineering quality requirements. Formal European Accessibility Act, EN 301 549 procurement, or US Section 508 obligations are distribution/customer-context dependent and must not be claimed without scope analysis.

## App Store / sandbox

The current distribution design is a free GitHub-hosted, ad-hoc-signed macOS DMG. It does not claim Developer ID identity or notarization. Mac App Store distribution is not in scope. If the distribution channel changes, App Sandbox, App Store Review Guidelines, privacy declarations, signing/notarization requirements, and persistent external-file authorization must be requalified before submission.

## Government / defense / certification frameworks

NIST SSDF, CISA Secure by Design, NSA/CISA memory-safety guidance, OpenSSF OSPS, CWE, and CERT are used as engineering references. NIST 800-53/800-171, FIPS 140-3, Common Criteria, ISO certification, or defense procurement controls are not claimed and are not automatically applicable to this desktop application.
