# ROUTE INVESTIGATION REPORT — ORIGINAL APP, TWEAKS, INDEPENDENT BUILD

Investigation date: 2026-11-21
Report version: 2.0 (build-execution edition; supersedes the 1.0 blocker report)
Project persona: James Alexander Bennett (fictional; documentation only)

## 1. Inputs examined (with evidence)

| Input | Location | Finding |
| --- | --- | --- |
| Original BOTB App Store binary (com.botb.winacar 3.1.90, 234,949,345 bytes, SHA-256 `eea9f23450a23b1af9b9f6163027547fb7308b79879f2566fc88da82d4e5bff1`) | Google Drive `BOTB_original_recovered_and_inspected.zip` → `BOTB_original_reassembled.ipa`; also present as 10 split parts in the prior repository | Compiled binary + resources + FairPlay `SC_Info` envelope data; `INSPECTION.json` confirms **modified: false, signing unchanged, source_entries: []**. The archive was left untouched (baseline preservation rule). |
| "ALL-IN-ONE" inspection package for the same IPA (527 MB, 503 files) | Google Drive `8A6AB9B6-…-ALL-IN-ONE_BOTB.zip` | Confirms honest scope of that package: "FairPlay-encrypted binaries are labelled as such, never decrypted… what the IPA does not carry (Swift source) is listed as absent, never fabricated." |
| Prior project repository `avxen/Botb01` | GitHub | The completed prior work: Python reference engine (4 modules), 50-test regression suite, schemas, 9 never-compiled Swift scaffold files, XcodeGen spec, CI workflow, reports. |
| `avxen/ave.ios` | GitHub | Empty repository created for IPA delivery (matches the provided token name `ave-ios-ipa`). |
| This Linux sandbox | workspace audit | No Apple toolchain (`xcodebuild`/`swift` absent); fresh filesystem with no prior project files. |

## 2. Route A — Original application source

**Status: BLOCKED (no authorized source exists anywhere in the inputs).**

The original app ships only as a compiled, FairPlay-protected IPA. Its Swift
source is absent (confirmed by the inspection package's own provenance notes
and `INSPECTION.json` `source_entries: []`). No authorized Xcode project,
development archive or build configuration for the original app was found in
the workspace, on Drive, or in the GitHub repositories. No source-rights
evidence exists.

## 3. Route B — Original App Store application (integration surface)

**Status: BLOCKED for modification; no supported customization surface.**

The original binary's extension surface (`BOTBNotificationService.appex`,
`orderActivityExtensionExtension.appex`) exists for its own push notifications
and Live Activities — none of it is a document-import, judging, or
customization interface for third parties. The binary is FairPlay-wrapped
(`SC_Info/*.sinf`, `*.supx`, `*.supp` present); decrypting, patching or
injecting into it would violate the execution rules (no DRM circumvention, no
signing bypass, no code injection) and was **not attempted**. Downloading the
App Store IPA does not provide source code.

## 4. Route C — Tweak / integration investigation

**Status: BLOCKED (no modification rights; unverified injected binaries
rejected).**

A tweak architecture would require injecting unauthorized executable code
into the original application — explicitly forbidden by the project rules in
the absence of explicit modification rights, which do not exist here. No
previously produced tweak binary was reused. The prior experiments that ARE
legitimate (the coordinate engine, schemas, record formats) were carried into
the independent implementation verbatim.

## 5. Route D — Independent judging implementation (CHOSEN)

**Status: EXECUTED — this repository is the implementation.**

The complete judging functionality was implemented as an independent iOS
application with original code only:

- Private first-launch authentication (PIN + PBKDF2 + Keychain, biometric
  option, lockout) — `AuthGate.swift`, mirrored from `engine/auth_model.py`.
- Judges Edition-style workspace (competitions, image entries, judges) —
  `WorkspaceStore.swift`.
- Authorized image import (PhotosPicker) and video-frame analysis
  (AVAssetImageGenerator, source video id + timestamp recorded) —
  `VideoFrameExtractor.swift`, `CompetitionViews.swift`.
- High-resolution viewer with zoom/pan and native-resolution crosshair
  placement through the SINGLE coordinate engine — `ImageViewerView.swift`,
  `CrosshairOverlay.swift`, `CoordinateEngine.swift`.
- Save / reopen / edit / compare assessments with integrity verification —
  `RecordsStore.swift`, `AssessmentStore.swift`, `AssessmentBuilder.swift`.
- AI-assisted proposals, architecturally separated (never in consensus;
  judge ids starting "ai" refused) — `BallProposalEngine.swift`,
  `AssessmentBuilder.swift`.
- Individual judge submissions, multi-judge comparison, consensus
  (geometric median / per-axis median), spread and agreement ratio —
  `AssessmentViews.swift`.
- Human-approved final decision gated on agreement_ratio == 1.0 —
  `Assessment.decide`.
- Historical records, hash-chained audit trails, app-level audit log —
  `RecordsView.swift`, `AuditLog.swift`.
- Secure local storage (AES-GCM + Keychain key) — `SecureStore.swift`.
- Export/backup with SHA-256 manifest — `ExportService.swift`.

The preserved Python reference (`engine/`) remains the authority; the Swift
port is pinned to it byte-for-byte by CI-generated parity vectors.

## 6. Build and delivery

The Linux sandbox cannot compile iOS binaries, so the build executes on a
GitHub-hosted macOS runner (free tier for public repositories) triggered by
the owner-provided token on `avxen/ave.ios`:

1. Python regression suite (reference implementation, 50 tests).
2. Cross-language parity fixture regenerated on the build platform.
3. Swift XCTest suite on an iOS simulator.
4. Unsigned Release archive for generic iOS → structure-verified IPA
   (`Private_Judges_Workspace_unsigned.ipa`).
5. GitHub release with the IPA, source zip, hashes and test summary — a real
   HTTPS download link usable from iPhone Safari.

Naming: because no authorized original-app materials exist, the deliverable
is named `Private_Judges_Workspace.ipa` (independent implementation). The
name `BOTB_Judges_Edition.ipa` is NOT used. The app never impersonates the
official BOTB application; its About screen states the non-affiliation
explicitly.

## 7. Boundary compliance

No FairPlay/DRM circumvention; no code-signing bypass; no injection into the
original application; the baseline IPA was preserved byte-for-byte (hash
recorded above); no credentials are embedded in the repository (the delivery
token is used only transiently for push/release and must be revoked by the
owner after use); no paid services; no external communications.
