# TeachLens — Developer Guide

Building, testing, signing and releasing TeachLens. For installation and usage see the [README](../README.md).

## Architecture

| Folder | What it does |
|---|---|
| `Sources/TeachLensCore/App, Core, Overlay, Annotations, Capture, Settings, Hotkeys` | Inherited from ZoomIt for Mac: zoom, live zoom, drawing, snip/OCR, recording, panorama, break timer, DemoType/DemoMirror |
| `Sources/TeachLensCore/Keystroke/` | Swift port of Keyviz: event tap, key maps, Keyviz state machine, pill HUD (Liquid Glass on macOS 26), Windows equivalents, settings pane |
| `Sources/TeachLensCore/Spotlight/` | Spotlight, cursor highlight, shake-to-find |
| `Sources/TeachLensCore/Captions/` | Live captions (Speech framework), transcript and SRT/VTT export |
| `Sources/TeachLensCore/Modes/` | Course-mode presets |
| `Sources/TeachLensCore/SelfTest/` | `swift run TeachLensSelfTest` checks (no window server needed for most) |
| `Legacy/keyviz/` | Original Keyviz (Tauri) source kept as the porting reference |

## CI and releases

- `.github/workflows/build.yml` runs on every push/PR on macos-15 and macos-26: build, self-test, release build + DMG, then an install smoke test (install to /Applications, launch, single-instance check, logs, crash reports, screenshot).
- `.github/workflows/release.yml`: change `VERSION` on main (or push a tag `vX.Y.Z`) to build a universal `TeachLens.app` and publish `TeachLens-X.Y.Z.dmg` on GitHub Releases.

## Build, Test, Run

```sh
swift build
swift run TeachLensSelfTest
swift run TeachLens
```

The self-test covers viewport math, annotation lifecycle/rendering, settings persistence, and panorama stitcher regressions.

Run the sandbox product-surface tests with the App Store compiler condition:

```sh
swift run -Xswiftc -DTEACHLENS_APP_STORE TeachLensSelfTest
```

Launch at login requires running TeachLens as an app bundle so macOS attributes the login item to TeachLens instead of the host process used for development. Build the bundle with:

```sh
zsh Scripts/build-app.sh
open ".build/TeachLens (Dev).app"
```

The contributor build is named `TeachLens (Dev).app` (bundle id `io.github.fw1201.teachlens.dev`) so it stays distinct from an installed official `TeachLens.app` in the Screen Recording list. See [Bundle identity](#bundle-identity-dev-vs-official) below.

## Distributing To Testers

Testers should run the bundled app, not `swift run`. Build a release app bundle:

```sh
zsh Scripts/build-app.sh release
```

Local bundles default to version `1.0`. Set `TEACHLENS_VERSION` to stamp a
specific dotted-numeric version into both `CFBundleShortVersionString` and
`CFBundleVersion`:

```sh
TEACHLENS_VERSION=1.2.0 zsh Scripts/build-app.sh release
defaults read "$PWD/.build/TeachLens (Dev).app/Contents/Info" CFBundleShortVersionString
defaults read "$PWD/.build/TeachLens (Dev).app/Contents/Info" CFBundleVersion
```

The official Azure DevOps build supplies `TEACHLENS_VERSION` from the version
entered when the pipeline is queued. Values must contain two or three numeric
components, such as `1.2` or `1.2.0`; malformed values fail before compilation
or signing begins.

## Build Variants

One source tree produces the standard unsandboxed application and the sandboxed
product surface used for Mac App Store releases.

| Variant | Product surface |
| --- | --- |
| Homebrew | Unsandboxed, including DemoType |
| Mac App Store | App Sandbox; DemoType is compiled out |

`TEACHLENS_DISTRIBUTION` selects the channel and defaults to `homebrew`, preserving
the existing local build command. `TEACHLENS_BUILD_NUMBER` independently stamps a
numeric `CFBundleVersion` when a specific local value is needed.

```sh
# Existing contributor/Homebrew behavior
zsh Scripts/build-app.sh release

# Explicit Homebrew variant
TEACHLENS_DISTRIBUTION=homebrew TEACHLENS_BUILD_NUMBER=101 \
  zsh Scripts/build-app.sh release

# Sandboxed local prototype (still uses the separate contributor identity)
TEACHLENS_DISTRIBUTION=appstore TEACHLENS_BUILD_NUMBER=101 \
  zsh Scripts/build-app.sh release
```

The App Store variant uses security-scoped bookmarks for the selected break
sound, break background, and automatic snip folder. Re-select a resource in
Settings if macOS reports that its authorization can no longer be restored.
Screen recording remains controlled by macOS privacy consent and has no app
entitlement. 

By default this produces `.build/TeachLens (Dev).app` with the app icon, bundled resources, and an `Info.plist` declaring the microphone, Speech Recognition, and camera usage descriptions. `release` builds are **Universal** (Apple Silicon + Intel) by default; `debug` builds are native to the build machine for speed. Override the architectures with `TEACHLENS_ARCHS` (e.g. `TEACHLENS_ARCHS=arm64`). A Universal build routes through Xcode's build system, so it requires a **full Xcode** install — with only the Command Line Tools the script warns and falls back to a native build. The build summary prints the resulting architectures.

### Create and install a local development DMG

Build the Universal development app, stage it with an Applications shortcut, and create a compressed disk image using macOS's built-in `hdiutil`:

```sh
zsh Scripts/build-app.sh release

STAGE="$(mktemp -d)"
ditto ".build/TeachLens (Dev).app" "$STAGE/TeachLens (Dev).app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "TeachLens Dev" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  ".build/TeachLens-Dev.dmg"
rm -rf "$STAGE"

hdiutil verify ".build/TeachLens-Dev.dmg"
open ".build/TeachLens-Dev.dmg"
```

Drag **TeachLens (Dev)** to the Applications shortcut in the mounted image, then launch the installed copy:

```sh
open "/Applications/TeachLens (Dev).app"
```

A `.dmg` is a disk image, not an executable; use `open path/to/file.dmg` rather than invoking the path directly. Do **not** override a local ad-hoc build to use `io.github.fw1201.teachlens` or the `TeachLens.app` name. That identity is reserved for the officially Developer ID-signed release; an ad-hoc app using it conflicts with the official app's macOS privacy (TCC) grants even when System Settings shows Screen Recording as enabled.

### Bundle identity: dev vs. official

`Scripts/build-app.sh` picks the bundle identity from the signing identity so a locally built copy never fights the officially distributed app over macOS privacy (TCC) grants, which are keyed by bundle id **and** code-signing requirement:

- **Contributor / ad-hoc build (default):** app bundle `TeachLens (Dev).app`, bundle id `io.github.fw1201.teachlens.dev`, display name “TeachLens (Dev)”, ad-hoc signed. Both the distinct file name and bundle id keep it separate from an installed official `TeachLens.app`, so its Screen Recording grant is its own row in System Settings and the two never clobber each other.
- **Official build:** pass a real Developer ID identity and it keeps the canonical `io.github.fw1201.teachlens` id:

  ```sh
  TEACHLENS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
    zsh Scripts/build-app.sh release
  ```

Override any field explicitly with `TEACHLENS_SIGN_IDENTITY`, `TEACHLENS_BUNDLE_ID`, and `TEACHLENS_DISPLAY_NAME`. Because a real signing identity has a stable, team-based designated requirement, the official app keeps its Screen Recording permission across updates; an ad-hoc build cannot share that grant since contributors don't have the certificate.

### Entitlements (camera, microphone, and Speech Recognition)

`build-app.sh` signs with camera and audio-input entitlements. The restricted `com.apple.developer.speech-recognition` entitlement needs a provisioning profile, so it is removed from ad-hoc builds (otherwise macOS refuses to launch the app); outside the sandbox, speech recognition only needs the Info.plist usage description. Screen Recording is pure TCC and needs no entitlement. Verify on the first signed build with `codesign -d --entitlements :- TeachLens.app`.

### Signing options

- **Distributing widely (recommended):** sign with a Developer ID Application certificate, notarize with Apple, and staple the ticket, then zip or wrap the app in a `.dmg`:

  ```sh
  TEACHLENS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
    zsh Scripts/build-app.sh release
  ditto -c -k --keepParent .build/TeachLens.app TeachLens.zip
  xcrun notarytool submit TeachLens.zip --apple-id you@example.com \
    --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait
  xcrun stapler staple .build/TeachLens.app
  ```

  A notarized app opens with a normal double-click and keeps its Screen Recording permission across updates.

- **Quick internal testing (unsigned/ad-hoc):** use the development identity and `TeachLens-Dev.dmg` procedure above. If another Mac downloads the unnotarized DMG, Gatekeeper may block it. After copying the app to `/Applications`, testers can clear the quarantine flag:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/TeachLens (Dev).app"
  open "/Applications/TeachLens (Dev).app"
  ```

  Note that rebuilding an ad-hoc/unsigned app can reset its Screen Recording permission, so testers may need to re-grant it after an update.

### First run

1. Move `TeachLens (Dev).app` (local testing) or `TeachLens.app` (official release) to `/Applications` and open it. It runs as a menu-bar item (no Dock icon).
2. macOS prompts for **Screen Recording** the first time a capture feature is used; enable the matching **TeachLens (Dev)** or **TeachLens** row in System Settings ▸ Privacy & Security ▸ Screen Recording, then relaunch that same app.
3. **Microphone** and **Speech Recognition** are requested when snip dictation is enabled; **Microphone** and **Camera** are otherwise requested only when their recording options are enabled.
4. Use the menu-bar icon or the default hotkeys above to drive the app, and the Settings dialog to customize shortcuts and behavior.

### Clear stale Screen Recording permissions

macOS privacy permissions (TCC) are tied to both an app's bundle identifier and its code-signing requirement. If an ad-hoc build previously used the official `io.github.fw1201.teachlens` identifier, System Settings can show **TeachLens** as enabled while macOS rejects the currently installed Developer ID-signed app. Typical symptoms are:

- `Control+1` repeatedly opens Screen Recording settings even though TeachLens is enabled.
- Closing the permission dialog and pressing `Control+1` again does nothing.
- A newly installed, correctly signed build still cannot capture the screen.

Reset only the Screen Recording record for the identity you are running. This removes the stale grant; it does not uninstall the app or clear TeachLens settings.

For the **officially signed** `/Applications/TeachLens.app`:

```sh
pkill -f "/Applications/TeachLens.app/Contents/MacOS/TeachLens" 2>/dev/null || true
tccutil reset ScreenCapture io.github.fw1201.teachlens

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "/Applications/TeachLens.app"
open "/Applications/TeachLens.app"
```

For the local **development** `/Applications/TeachLens (Dev).app`:

```sh
pkill -f "/Applications/TeachLens (Dev).app/Contents/MacOS/TeachLens" 2>/dev/null || true
tccutil reset ScreenCapture io.github.fw1201.teachlens.dev

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "/Applications/TeachLens (Dev).app"
open "/Applications/TeachLens (Dev).app"
```

After relaunching:

1. Press `Control+1` once to request Screen Recording access.
2. Enable the matching **TeachLens** or **TeachLens (Dev)** row in System Settings.
3. Use macOS's **Quit & Reopen** button, or quit and reopen that same app manually.
4. Press `Control+1` again.

Static zoom requires **Screen Recording** only. Microphone and Camera permissions are unrelated unless their optional recording features are enabled. If the problem immediately returns after the reset, verify that the installed app has the expected identity:

```sh
codesign -dv --verbose=2 "/Applications/TeachLens.app" 2>&1 \
  | grep -E "Identifier=|Authority=Developer ID Application|TeamIdentifier="
```

The official app should report identifier `io.github.fw1201.teachlens` and a Developer ID authority. Never distribute or install an ad-hoc-signed app under that official identifier; local builds must remain `TeachLens (Dev).app` with identifier `io.github.fw1201.teachlens.dev`.
