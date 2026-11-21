# SIGNING GUIDE — Private Judges Workspace

The delivered IPA is **unsigned** and is NOT directly installable. The project
owner signs it personally with their own Apple identity — that is the
intended, legitimate delivery path. Choose one of the routes below.

The app identity to sign with: bundle id `com.privatejudges.workspace`,
display name "Private Judges Workspace", version 1.0.0 (1).

## Route 1 — Build & run directly from Xcode (recommended, no IPA needed)

1. On a Mac: install Xcode 15+ from the Mac App Store.
2. `brew install xcodegen && xcodegen generate --spec project.yml`
   (or unzip `Private_Judges_Workspace_source.zip`, which contains the same tree).
3. Open `PrivateJudgesWorkspace.xcodeproj`, plug in the iPhone.
4. Signing & Capabilities → enable "Automatically manage signing",
   select your personal team (free Apple ID works).
5. Change the bundle id to any personal suffix if your team requires it
   (e.g. `com.yourname.privatejudgesworkspace`), then Product → Run.

## Route 2 — Sign the delivered IPA with a personal signing tool

The unsigned IPA (`Private_Judges_Workspace_unsigned.ipa`) can be re-signed
and installed with widely used, legitimate personal-signing tools:

- **AltStore / AltServer** (free, uses your Apple ID through Apple's official
  provisioning): open AltServer on the Mac/PC → install AltStore on the
  iPhone → drag the IPA into AltStore on the device. AltStore signs with your
  Apple ID and installs. Apps signed this way are valid for 7 days and can be
  refreshed by AltStore.
- **Sideloadly** (free): connect the iPhone, drag in the IPA, enter your
  Apple ID, press Start. Sideloadly signs and installs through Apple's
  provisioning servers.
- **Apple Developer certificate** (paid programme): with a provisioning
  profile for your device,
  `codesign -f -s "Apple Development: YOU" --entitlements ent.plist Payload/*.app`
  then re-zip and install via Xcode's Devices & Simulators window
  (Window → Devices and Simulators → drag the signed IPA onto the device) or
  `cfgutil`/Apple Configurator.

## Route 3 — Apple Developer distribution (TestFlight / Ad Hoc)

With a paid Apple Developer account you can import the source project and
distribute through TestFlight, Ad Hoc, or directly to devices with a
distribution profile. This is the most durable route for long-term use.

## Verification before installing

```bash
shasum -a 256 Private_Judges_Workspace_unsigned.ipa     # compare with IPA_SHA256.txt
unzip -t Private_Judges_Workspace_unsigned.ipa          # archive integrity
```

The IPA contains `Payload/Private Judges Workspace.app` (bundle id
`com.privatejudges.workspace`). After signing, verify the signature:

```bash
codesign -dv Payload/"Private Judges Workspace.app" 2>&1 | head -5
```

## What the unsigned archive is NOT

- It is not installable as-is — do not attempt to open it on the device
  without signing.
- It is not the original BOTB application; it contains no BOTB code, assets
  or entitlements.
- It contains no embedded provisioning profile or certificate by design —
  the owner's personal signing identity is the only authority that stamps it.
