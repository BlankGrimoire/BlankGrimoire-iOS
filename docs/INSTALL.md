# Install Blank Grimoire on a device

Blank Grimoire targets **iOS 17 or newer**. Every release publishes an
**unsigned IPA** (`BlankGrimoire-<version>.ipa`). iOS cannot install unsigned
builds, so a signing tool has to sign it with your own Apple ID first. There is
no "unknown sources" switch on iOS: the signature is what authorises the app.

| Route | Cost | Signature lifetime | Needs a computer after setup |
| --- | --- | --- | --- |
| [SideStore](#sidestore-recommended) | free | 7 days, renewed automatically | no |
| [AltStore](#altstore-with-a-mac) | free | 7 days, renewed while AltServer runs | yes |
| [Sideloadly](#one-off-install-with-sideloadly) | free | 7 days, manual | yes |
| [Xcode](#build-from-source) | free | 7 days, manual | yes |
| [TestFlight / App Store](#testflight-and-app-store) | 99 $/year | 90 days / permanent | no |

A free Apple ID gives you **3 active apps at most**, 10 App IDs per week and a
7-day signature. SideStore itself uses one of those three slots, leaving two.

## SideStore (recommended)

SideStore installs apps with your Apple ID, then renews them on the phone
itself over a local WireGuard VPN — no computer needed after the one-time
setup.

1. **Prepare the iPhone.** Settings → Privacy & Security → Developer Mode → on,
   then restart.
2. **Install SideStore once from a computer.** Follow
   <https://sidestore.io> (macOS or Windows, requires a USB connection and a
   pairing file).
3. **Add the Blank Grimoire source.** In SideStore open *Sources* → `+` and
   paste:

   ```text
   https://raw.githubusercontent.com/BlankGrimoire/BlankGrimoire-iOS/main/repo.json
   ```

4. **Install.** Open the *Blank Grimoire* entry and tap *Install*. SideStore
   signs the IPA with your Apple ID and installs it.
5. **Renew before the 7 days expire.** Keep the SideStore VPN enabled and use
   *Refresh All* while on Wi-Fi.
6. **Automate the renewal (optional).** In Shortcuts → *Automation* → daily at a
   fixed hour, when *Charging* is on and *Wi-Fi* is connected, run the
   SideStore *Refresh All Apps* action. This keeps the app alive without
   thinking about it.

Updates appear inside SideStore as soon as a new `repo.json` entry exists: tap
*Update* and the library, settings and reading progress are preserved as long
as the bundle identifier (`com.blankgrimoire.app`) stays the same.

### If the app stops opening after 7 days

The signature expired. Reconnect to the SideStore VPN and run *Refresh All*;
the app reopens with its data intact. If more than a week passes without any
refresh, reinstall from SideStore — the library lives in the app container, so
reinstalling over the same bundle identifier keeps it.

## AltStore with a Mac

1. Install [AltServer](https://altstore.io) on the Mac and use it to install
   AltStore on the iPhone (same Developer Mode requirement).
2. Keep AltServer running and both devices on the same network. AltStore
   refreshes the app in the background while the Mac is awake.
3. Download `BlankGrimoire-<version>.ipa` from the
   [releases page](https://github.com/BlankGrimoire/BlankGrimoire-iOS/releases),
   open it with *My Apps → +* in AltStore and sign in with your Apple ID.
   Alternatively add the same `repo.json` source used for SideStore.

## One-off install with Sideloadly

Works on macOS and Windows, needs no Xcode, but the signature lasts 7 days and
must be redone by hand.

```text
1. Download BlankGrimoire-<version>.ipa from the releases page.
2. Open Sideloadly, connect the iPhone, drop the IPA in.
3. Enter your Apple ID (2FA required) and start.
4. On the iPhone: Settings → General → VPN & Device Management → trust the
   developer certificate.
```

## Build from source

Equivalent to the released build and the shortest path if you already have
Xcode:

```bash
make gen
open BlankGrimoire.xcodeproj
```

Select the `BlankGrimoire` target → *Signing & Capabilities* → your personal
team, then run on the connected device. If `com.blankgrimoire.app` is already
taken by another team, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
With an unsigned certificate the app must be rebuilt every 7 days.

## TestFlight and App Store

The only route to an installation that never expires. It requires an Apple
Developer Program membership (99 $/year), a signed archive and an upload to App
Store Connect; the build is then installable through TestFlight (90 days per
build) or the App Store.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Unable to install" from SideStore | bundle identifier already used by another team | uninstall the previous copy, or build with your own `PRODUCT_BUNDLE_IDENTIFIER` |
| App icon is grey / app closes instantly | signature expired | refresh in SideStore/AltStore |
| "Untrusted Developer" alert | certificate not trusted yet | Settings → General → VPN & Device Management → trust |
| SideStore cannot refresh | local VPN off, or more than 7 days passed | enable the SideStore VPN, then *Refresh All* |
| No update shown in SideStore | source cached | pull to refresh the source, or re-add `repo.json` |

## Why the release IPA is unsigned

`xcodebuild -exportArchive` needs a certificate and a provisioning profile,
which cannot be published. Instead the release ships the unsigned
`Payload/BlankGrimoire.app` wrapped in an IPA, which is exactly what signing
tools expect. The `.xcarchive` and dSYMs stay available for symbolication.
