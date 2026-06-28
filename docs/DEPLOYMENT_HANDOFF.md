# Deployment handoff — run Bruno on a real Apple TV + iPhone

> **Audience:** the next thread, which will walk the owner through installing Bruno on their
> own **Apple TV** and **iPhone** hardware (not the simulator).
> **State:** `bruno` is merged to `main`, green on Xcode 26.3 (tvOS + iOS). All sim verification
> is done (see the "Already verified" section below). The remaining work is purely real-device signing + install.

---

## 0. Start by asking the owner three things

1. **Apple Developer account type?** Free Apple ID (7-day sideload, no TestFlight) vs. paid
   Apple Developer Program ($99/yr, enables TestFlight + 1-year provisioning). This decides the path.
2. **Their Team ID** (Xcode ▸ Settings ▸ Accounts, or developer.apple.com ▸ Membership).
3. **Are the Apple TV and iPhone on the same LAN as the Jellyfin server** `http://192.168.50.19:8899`?
   They must be, or sign-in/playback won't reach it.

---

## 1. One-time signing setup (applies to both devices)

Signing is driven by a **gitignored** local file so real credentials never get committed:
`XcodeConfig/DevelopmentTeam.xcconfig` (currently a placeholder). Edit it to the owner's real values:
```
DEVELOPMENT_TEAM = <THEIR_REAL_TEAM_ID>
PRODUCT_BUNDLE_IDENTIFIER = com.diplomacymusic.bruno
```
- It's `#include?`-ed by `XcodeConfig/Shared.xcconfig`, overriding the stock `org.jellyfin.swiftfin`.
- `git check-ignore XcodeConfig/DevelopmentTeam.xcconfig` confirms it's ignored — **never commit it.**
- A **free** Apple ID can't use `com.diplomacymusic.bruno` if it's already registered to another team;
  if Xcode complains the bundle ID is unavailable, change it to something unique like
  `com.<owner>.bruno` (only affects the app identity, not the code).
- In Xcode, open `Swiftfin.xcodeproj`, select each target (Swiftfin tvOS, Swiftfin) ▸ Signing &
  Capabilities ▸ **Automatically manage signing**, pick the owner's team. Let Xcode create the
  provisioning profiles. (Capabilities already declared incl. the keychain access group — that's
  what makes sign-in persist on real hardware, unlike the unsigned sim build.)

> The DEBUG-only Bruno test harnesses (`BRUNO_SNAPSHOT` / `BRUNO_AUTOSIGNIN` /
> `BRUNO_COLLECTION_PROBE`) are `#if DEBUG` **and** env-gated, so they're completely inert in a
> normal Debug run and absent from Release/TestFlight. Real sign-in on device uses the normal UI.

---

## 2. Apple TV install (the main event — Bruno's custom Home is tvOS-only)

1. **Pair the Apple TV with Xcode:** Apple TV ▸ Settings ▸ Remotes and Devices ▸ Remote App and
   Devices (leave it open). In Xcode ▸ Window ▸ Devices and Simulators ▸ pair, enter the PIN.
   Both must be on the same network. (First pairing copies a debug symbols set — takes a minute.)
2. Scheme **"Swiftfin tvOS"**, destination = the paired Apple TV, **Run** (▶). First launch installs
   + trusts; on tvOS you may need Settings ▸ General ▸ (Device Management) to trust the developer.
3. Sign in normally through the UI (server `http://192.168.50.19:8899`, the BrunelleHouse user).
   Real signing persists the token, so it survives relaunch — no keychain crash.
4. Expected result: the **Bruno Home** (wordmark, ambient gloss backdrop, seeded hero, shelves),
   collections as the new multi-line grid. Playback should be smooth (hardware decode — unlike the
   sim stutter we diagnosed).

CLI alternative (no Xcode UI): `xcodebuild -scheme "Swiftfin tvOS" -destination 'platform=tvOS,name=<Apple TV name>' build`, then install via Xcode/`devicectl`.

## 3. iPhone install

1. Scheme **"Swiftfin"**, plug in the iPhone (or wireless), select it as destination, **Run**.
2. Trust the developer cert: iPhone ▸ Settings ▸ General ▸ VPN & Device Management ▸ trust the team.
3. **Set expectation:** the **Bruno custom Home is tvOS-only** (`TabItem.home` is swapped only under
   `#if os(tvOS)`). On iPhone the app is **stock Swiftfin** with the shared Bruno **rebrand**
   (accent `#A1CCE0`, Oswald/Inter fonts) — not the Bruno hero/shelves/grid. If the owner wants the
   Bruno experience on iOS too, that's a new port (out of current scope) — flag it, don't assume.

## 4. If they have a paid account → TestFlight (best for ongoing use)

- Xcode ▸ scheme ▸ **Any iOS/tvOS Device** ▸ Product ▸ Archive ▸ Distribute App ▸ App Store Connect.
- Needs the bundle IDs registered + an app record per platform on App Store Connect. Internal
  TestFlight testers get it without review. This avoids the free-account 7-day re-sign treadmill.

## 5. Gotchas / decision rules

- **"Untrusted Developer" on launch** → trust the cert (steps above). **7-day expiry** (free
  account) → just re-Run from Xcode to re-sign.
- **Bundle ID unavailable** (free account) → pick a unique `PRODUCT_BUNDLE_IDENTIFIER` in the local
  xcconfig (§1).
- **Can't reach server** → same-LAN check; try the URL in the device's browser first.
- **Stutter on real Apple TV** (shouldn't happen) → then it's transcode/bitrate/network, not the sim;
  check Settings ▸ Playback (Native AVPlayer vs Swiftfin/VLC), direct-play vs server transcode.
- **A crash on device** → pull the `.ips` and apply the decision rule: a backtrace of **stock** frames
  ⇒ signing/profile/env (not a Bruno bug); `…/Bruno/…` frames ⇒ a real bug. (The one known pre-existing
  crash is the stock keychain assertion with **zero Bruno frames** — see "Already verified" below.)

## Already verified (prior overnight run)

> One-time snapshot, 2026-06-22 night. Xcode 26.3 (tvOS 26.2 SDK), Apple TV 4K sim.
> **Bruno is visibly working** on the sim: both the mock-data GUI (Track A) and the real
> live-library Home (Track B) render, and the post-login keychain crash is gone on an
> ad-hoc-signed build. Real-device install (§§1-4) is the only remaining work.

**Runnable sim build command** (ad-hoc identity embeds the keychain-access-group entitlement
so the sign-in token persists across relaunch — this is what fixes the crash; the compile
gate's `CODE_SIGNING_ALLOWED=NO` strips that entitlement and is for compile-verify only):
```bash
xcodebuild -project Swiftfin.xcodeproj -scheme "Swiftfin tvOS" \
  -destination 'generic/platform=tvOS Simulator' -skipMacroValidation build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```

- **Track A (mock GUI, no server/sign-in/keychain):** `./bruno-verify/snapshot.sh ~/Desktop`
  installs the signed build and screenshots each surface via the `BRUNO_SNAPSHOT=1` gallery
  (`BRUNO_SNAPSHOT_VIEW` = `home`|`hero`|`shelf`). Committed PNGs: `docs/screenshots/bruno-home.png`,
  `bruno-hero.png`, `bruno-shelves.png` — wordmark, accent `#A1CCE0`, Oswald/Inter, seeded hero,
  shelves over the stock `PosterHStack` with native focus (mock items show placeholder glyphs, no
  server images).
- **Track B (real end-to-end, headless):** `./bruno-verify/e2e.sh ~/Desktop`. UI typing on the
  tvOS keyboard is too brittle for unattended runs, so sign-in is driven programmatically by
  `BrunoAutoSignIn.swift` (`#if DEBUG`, `BRUNO_AUTOSIGNIN=1`) using the app's own
  `ConnectToServerViewModel`/`UserSignInViewModel`/`UserSessionManager` primitives; creds come from
  `JF_BASE`/`JF_USER_NAME`/`JF_PASS` env (gitignored `bruno_jellyfin.env`, never compiled in).
  Confirmed: process **ALIVE after relaunch — keychain persisted**; real Home identical after a
  clean relaunch (Godfather spotlight 1972 · Drama · ★8.7, real Continue Watching art). Those
  real-library screenshots were delivered out-of-band and intentionally **not committed** (personal
  content + public remote).
- **Crash analysis:** no new crash from any signed run. The pre-existing `.ips` is the stock
  keychain assertion (`SwiftfinStore.State.User.accessToken.getter` → "access token missing in
  keychain", via `UserSessionManager.resolveCurrentSession()`) with **zero Bruno frames** — confirms
  the §5 decision rule (stock frames ⇒ signing/env, not a Bruno bug). Ad-hoc signing eliminates it.
- Guardrails honored: additive only; new files under `Swiftfin tvOS/Views/BrunoHomeView/` (tvOS-only,
  file-system-synchronized group → no pbxproj edits); the only non-Bruno edits are DEBUG-gated, inert
  branches in `SwiftfinApp.swift`. swiftformat + swiftlint clean; `./bruno-verify/run.sh` green; both
  compile gates green.

## 6. Reference

- Architecture / guardrails: `docs/BRUNO_CODE_MAP.md` §2–3 + `BRUNO_NOTES.md`. Crash root-cause: the
  "Already verified" section above (stock keychain assertion, zero Bruno frames).
- Credentials: gitignored `bruno_jellyfin.env` at the repo root (`JF_BASE`/`JF_USER_NAME`/`JF_PASS`).
- Bundle id (tvOS): `com.diplomacymusic.bruno`. iOS scheme: `Swiftfin`. Min OS: iOS 16.6 / tvOS 17.
