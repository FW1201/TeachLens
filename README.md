# TeachLens

TeachLens is a macOS menu-bar toolkit for online teaching and screen-based lectures. It combines screen zoom, live zoom, on-screen drawing, a break timer, snips/OCR, and screen recording, and its roadmap adds keystroke and mouse visualization, spotlight, course-mode presets, live captions, and a multi-page whiteboard.

> **Status:** M1 (keystroke visualization). The ZoomIt for Mac feature set plus a Swift port of Keyviz's keystroke and mouse-click display, drawn as a frosted pill (Liquid Glass on macOS 26 and later). See [docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md) for the roadmap.

## Credits and open-source origins

TeachLens is a derivative work of two open-source projects:

| Project | Author | License | Used for |
|---|---|---|---|
| [ZoomIt for Mac](https://github.com/microsoft/Zoomit-Mac) | Microsoft Corporation | MIT | Application base: zoom, drawing, timer, capture, recording (imported at upstream commit `45e15ac`) |
| [Keyviz](https://github.com/mulaRahul/keyviz) | Rahul Mula | GPL-3.0 | Keystroke and mouse visualization (being ported to Swift; original Tauri source kept in [`Legacy/keyviz/`](Legacy/keyviz/)) |

TeachLens as a whole is distributed under the **GNU GPL-3.0** ([LICENSE](LICENSE)). The MIT notice for ZoomIt for Mac is kept in [ThirdParty/ZoomIt-Mac-LICENSE.txt](ThirdParty/ZoomIt-Mac-LICENSE.txt); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). TeachLens is not affiliated with or endorsed by Microsoft, Sysinternals, or the Keyviz project. The settings footer in the app shows the same credits.

## Default hotkeys

| Action | Hotkey |
|---|---|
| Static zoom | Control+1 |
| Draw without zoom | Control+2 |
| Break timer | Control+3 |
| Live zoom | Control+4 |
| Record screen / region | Control+5 / Control+Shift+5 |
| Snip to clipboard / file / OCR | Control+6 / Control+Shift+6 / Control+Option+6 |
| Panorama to clipboard / file | Control+8 / Control+Shift+8 |
| Show / hide keystrokes | Control+0 |

All hotkeys are configurable in Settings.

## Features

- Static zoom over a frozen ScreenCaptureKit display capture.
- Live zoom of the running screen, with click-through interaction when not drawing.
- Time-based, eased zoom animations for static and live zoom, with continuous
  motion when retargeting and no slowdown from delayed animation frames.
- Draw-without-zoom mode for annotating the screen at 1x.
- Pen, line, rectangle, ellipse, arrow, highlighter, undo, erase, blank-screen sketch pads, and typing annotations.
- Viewport screenshot copy/save and region snip copy/save.
- Optional snip dictation that records speech during a clipboard snip and copies the image and transcript together.
- OCR snip: select a screen region and copy its recognized text to the clipboard.
- Break timer with a configurable countdown, colors, opacity, background, and optional sound.
- MP4 screen recording for the whole screen or a selected region, with optional system audio, microphone audio, and fixed webcam picture-in-picture.
- Post-recording video editor with preview, trim, append, fades, playback controls, volume mute/slider, and export before save.
- Scrolling panorama capture with alignment, fixed header/footer suppression, progress, cancellation, and copy/save output.
- Tabbed Settings dialog for hotkeys, zoom, draw, type, snip, record, webcam, panorama, and launch-at-login preferences.
- Single-instance app behavior, menu-bar status, permission checks, and optional launch at login.

## Requirements

- macOS 14 or newer.
- Xcode command-line tools.
- Screen Recording permission for capture.
- Input Monitoring permission to show keystrokes (System Settings ▸ Privacy & Security ▸ Input Monitoring).
- Microphone and Speech Recognition permissions are required only for microphone recording and optional snip dictation; Camera is required only for the webcam option.

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

## Default Hotkeys

| Action | Shortcut |
| --- | --- |
| Static zoom | `Control+1` |
| Draw without zoom | `Control+2` |
| Break timer | `Control+3` |
| Live zoom | `Control+4` |
| Record screen | `Control+5` |
| Record region | `Control+Shift+5` |
| Snip region to clipboard | `Control+6` |
| Snip region to file | `Control+Shift+6` |
| OCR region to clipboard | `Control+Option+6` |
| Panorama to clipboard | `Control+8` |
| Panorama to file | `Control+Shift+8` |

All global hotkeys are configurable in Settings. While zoomed, use `Option+Up` and `Option+Down` to change zoom level, mouse wheel to zoom or resize tools depending on mode, `Command+S` / `Command+C` to save or copy the viewport, and `Esc` or right click to exit the active overlay mode.

## Drawing And Typing

- Left click enters drawing mode; drag to draw.
- Hold `Shift` for a line, `Control` for a rectangle, `Control+Shift` for an arrow, or `Tab` for an ellipse.
- Press `R/G/B/O/Y/P/W/K` for red, green, blue, orange, yellow, pink, white, or black; hold `Shift` with a color for highlighter ink.
- Press `T` for typing mode, `Shift+T` for right-aligned typing, and `Up` / `Down` or the mouse wheel to adjust font size.
- Use `Command+Z` to undo and `E` to erase annotations.

## Snip And OCR

Press the snip shortcut (`Control+6`) and drag a rectangle to copy that region of the screen to the clipboard; hold `Shift` (`Control+Shift+6`) to save it to a PNG file instead. Snip also works while zoomed, capturing the magnified view.

Snip dictation is off by default and can be enabled on the Snip tab in Settings. During a clipboard snip, press `Space` once while actively dragging to start listening. Releasing the mouse keeps the selection and status badge visible while transcription finishes; press `Esc` to cancel without replacing the clipboard. Extra or auto-repeated Space presses do not restart dictation.

On success, TeachLens writes one multi-representation clipboard item. Its RTFD and HTML forms contain both the image and transcript, with PNG, TIFF, and plain-text fallbacks so each destination app can choose the format it supports. An empty transcript produces the same PNG/TIFF image-only payload as a normal snip. TeachLens does not intercept paste or synthesize paste events, so this feature does not require Accessibility or Input Monitoring permission.

Dictation uses Apple's Speech and AVFoundation frameworks, prefers on-device recognition when the selected language supports it, and otherwise uses Apple's normal recognizer. It shares the configured recording microphone selection (falling back to the system default if the saved device is missing), but enabling microphone audio in recordings and enabling snip dictation are independent.

Press the OCR shortcut (`Control+Option+6`) and drag a rectangle to recognize the text inside it and copy that text to the clipboard. OCR uses Apple's on-device Vision text recognition, runs entirely on-device, and needs no extra permissions. Both shortcuts are configurable on the Snip tab in Settings.

## Recording

Recording uses ScreenCaptureKit and AVAssetWriter. Static zoom and drawing overlays are captured even when ScreenCaptureKit omits TeachLens's own windows; live zoom remains excluded from its own capture to avoid feedback. Webcam picture-in-picture stays fixed in the recorded viewport and is composited into overlay recordings instead of being zoomed into the source image.

When recording stops, TeachLens opens the built-in editor before the save panel so the clip can be trimmed, appended to another clip, faded, muted, and exported.

## Panorama

Panorama capture records a selected scroll region while you scroll, then stitches the frames into one image. It filters repeated frames, handles vertical or horizontal scrolls, suppresses fixed headers and footers, shows stitch progress, and can be canceled with `Esc`.

## Settings And Permissions

Settings are saved immediately to `UserDefaults`. The app includes permission checks for Screen Recording, Microphone, Speech Recognition, and Camera. Snip dictation requests only Microphone and Speech Recognition; it does not use Accessibility or Input Monitoring. Running from SwiftPM is supported for development; launch at login and production distribution are intended for the bundled app form.

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

`build-app.sh` signs both Homebrew and App Store variants with camera/audio-input access plus `com.apple.developer.speech-recognition`. These are required for the webcam, microphone capture, and Apple Speech transcription under their respective distribution constraints. Screen Recording is pure TCC and needs no entitlement. The entitlements are embedded even for ad-hoc builds so a later re-sign preserves them. Verify on the first signed build with `codesign -d --entitlements :- TeachLens.app`.

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
