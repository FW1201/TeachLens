# AGENTS.md — TeachLens

Guide for coding and testing agents (Codex, Claude Code). Read this first to avoid searching the whole repo.

## Current task pointers

- **Hands-on test plan (1.3.0-beta.3):** [`docs/test-plans/1.3.0-beta.3-test-plan.md`](docs/test-plans/1.3.0-beta.3-test-plan.md)
  - Read §0 first. Some TeachLens windows are invisible to screenshots on purpose.
  - Write results to `docs/test-reports/2026-11-24-1.3.0-beta.3.md` (format in §6).
- Previous manual report: `docs/test-reports/2026-11-24-teachlens-manual-test.md`

## What TeachLens is

A native macOS menu-bar app (Swift 6, SwiftUI + AppKit, macOS 14+) for online teaching: keystroke overlay, spotlight, live captions, whiteboard, zoom and draw, recording, a floating toolbar and course modes. It is a fork of ZoomIt for Mac (MIT) and a Swift port of Keyviz (GPL-3.0).

## Build and test

- macOS only: `swift build` and `swift run TeachLensSelfTest` (all self-tests).
- Package a dev app: `TEACHLENS_VERSION="$(cat VERSION)" zsh Scripts/build-app.sh release`, which builds `.build/TeachLens (Dev).app`.
- CI (`.github/workflows/build.yml`) runs on macOS 26 only (the app still targets macOS 14+). Each run produces a DMG artifact named `TeachLens-Dev-dmg-<os>`.
- `VERSION` drives releases. A suffix such as `-beta.N` publishes a GitHub pre-release (`.github/workflows/release.yml`).

## Code map (Sources/TeachLensCore)

| Area | Entry point |
|---|---|
| App wiring, menu bar, Start/End Class, hide-all | `App/AppDelegate.swift` (`makeStatusItem`, `toggleHideOverlays`) |
| Start/End Class | `App/ClassSession.swift` |
| Floating toolbar | `App/GraphicalTools.swift` (`ToolbarTool`, `GraphicalTools`, `GraphicalToolsView`) |
| Shared Liquid Glass chrome | `App/TeachLensChrome.swift` |
| Glass notices | `App/GlassToast.swift` |
| Welcome guide | `App/Onboarding.swift` |
| Shared-screen choice | `App/PresentationDisplay.swift` |
| Keystroke engine (timing) | `Keystroke/KeystrokeEngine.swift` (`visibleGroups`, `tick`) |
| Keystroke HUD and Windows-first | `Keystroke/KeystrokeHUDView.swift` (`windowsPrimary`), `Keystroke/KeystrokeController.swift` |
| Keystroke settings | `Keystroke/KeystrokeSettings.swift`, `Keystroke/KeystrokeSettingsPane.swift` |
| Mac↔Windows table and handout | `Keystroke/WindowsEquivalent.swift` |
| Captions | `Captions/CaptionController.swift` |
| Whiteboard | `Whiteboard/WhiteboardController.swift` (canvas, toolbars, pages), `Whiteboard/WhiteboardModel.swift` (data, renderer) |
| Class countdown, shortcut card | `Overlay/ClassCountdown.swift`, `Overlay/ShortcutCard.swift` |
| Course modes | `Modes/CourseMode.swift` |
| Global shortcuts | `Hotkeys/HotkeyService.swift` (ids 1–24), `Hotkeys/HotkeyConflicts.swift` |
| Settings window (8 groups) | `Settings/SettingsWindowController.swift` (`paneGroups`) |
| Tool settings panes (SwiftUI) | `Settings/ToolSettingsPanes.swift` (`ToolSettingsModel`) |
| Check & Test pane | `Settings/CheckAndTestPane.swift`, `App/TestCenter.swift` |
| Zoom, draw, snip, record, panorama | `Core/ModeCoordinator.swift`, `Overlay/`, `Capture/` |
| Self-tests | `SelfTest/` (`TeachingSelfTests`, `KeystrokeSelfTests`, `SelfTestRunner`) |

## Conventions

- UI strings are bilingual: `L10n.t("English", "繁體中文")`.
- New floating UI uses `chromeSurface(...)` and `ChromeIconButtonStyle`. Respect Reduce Transparency and Reduce Motion.
- Teacher-only windows set `sharingType = .none`. Student-visible ones (keystroke pills, captions, countdown) stay capturable.
- Add a self-test for new logic. Keep `Package.swift` targets unchanged.
