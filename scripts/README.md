# Release & notarization scripts

Scripts for building a **Developer ID–signed** macOS build of **Canvas Library** for distribution outside the Mac App Store, then optionally notarizing with Apple.

These are **maintainer-oriented**. Forks should substitute their own team, identities, and Apple ID.

## Prerequisites

- Xcode with command-line tools
- Signing identities in the login keychain (examples for this repo’s maintainer):
  - **Apple Development** — local Debug
  - **Developer ID Application** — Release distribution
- Your Apple Developer **Team ID**
- For notarization: Apple ID + [app-specific password](https://appleid.apple.com) (or a stored `notarytool` profile)

**Do not put Apple ID passwords, app-specific passwords, or API keys in this repo.** Use environment variables or Keychain profiles only.

## Project signing settings

| Configuration | `DEVELOPMENT_TEAM` | `CODE_SIGN_STYLE` | `CODE_SIGN_IDENTITY` |
|---------------|--------------------|-------------------|----------------------|
| **Debug**     | `44N969GC55`       | Automatic         | `-` (ad-hoc / local) |
| **Release**   | `44N969GC55`       | Automatic         | `Developer ID Application` |

`build-release.sh` additionally forces **Manual** style + the full Developer ID identity string so the Release artifact is consistently signed for distribution, without changing day-to-day Debug builds in Xcode.

## Scripts

| Path | Purpose |
|------|---------|
| [`build-release.sh`](./build-release.sh) | Release build → Developer ID codesign → DMG/zip in `dist/` |
| [`notarize.sh`](./notarize.sh) | `notarytool submit` + `stapler staple` (credentials via env/Keychain) |

Artifacts land in **`dist/`** (gitignored). Intermediate build products go under **`build/release/`**.

## How to run

From the repo root:

```bash
# 1) Build, sign, package
chmod +x scripts/build-release.sh scripts/notarize.sh   # once
./scripts/build-release.sh

# Prefer zip only, or force DMG
./scripts/build-release.sh --zip
./scripts/build-release.sh --dmg
```

Uses `CanvasLibrary.xcodeproj` when present. Adjust `DEVELOPMENT_TEAM` / signing identity in the scripts or Xcode project for your own developer account.

### Notarization

```bash
# Option A — environment (placeholders only; use your real values locally)
export APPLE_ID="your-apple-id@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export TEAM_ID="44N969GC55"
./scripts/notarize.sh

# Option B — Keychain profile (recommended)
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD"
export NOTARY_PROFILE="AC_PASSWORD"
./scripts/notarize.sh

# Or pass an explicit artifact
./scripts/notarize.sh dist/Canvas-Library-1.0.dmg
```

`notarize.sh` picks the newest `dist/*.dmg`, then `dist/*.zip`, if no path is given. For a bare `.app`, it zips temporarily for submit and staples the app.

## Output layout

```text
dist/
  Canvas-Library-<version>.dmg   # default packaging
  Canvas-Library-<version>.zip   # with --zip, or DMG fallback

build/release/
  DerivedData/                   # xcodebuild derived data for this run
  export/CanvasLibrary.app       # signed app copy used for packaging
```

## Hardened runtime & Gatekeeper

Release builds use **Hardened Runtime** (enabled in the Xcode project) and codesign with `--options runtime --timestamp`, which is required for successful notarization. `spctl` may report issues on a signed-but-not-yet-notarized app; that is expected until `./scripts/notarize.sh` completes and staples.

## Local Debug (unchanged)

Open `CanvasLibrary.xcodeproj` in Xcode and run the **Debug** scheme as usual. Debug keeps Automatic signing with team `44N969GC55` and ad-hoc-friendly settings so local iteration is not forced through Developer ID.
