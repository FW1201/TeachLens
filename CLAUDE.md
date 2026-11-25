# CLAUDE.md

Read [`AGENTS.md`](AGENTS.md) first: build commands, code map and conventions.

## Status (2026-11-25)

- `VERSION` is **`1.3.0-beta.5`**: spotlight Esc/fade/toolbar layering and click-ripple fixes on top of
  beta.4. beta.4 was the last round before a small external test. It fixed the
  2026-11-25 QA findings (I-03 English menu values, Trim Video title, toolbar edge margin,
  eye-marker spacing) and makes the app icon a rounded square everywhere (Dock, welcome
  guide, DMG volume). `1.3.0-beta.3` is the previous pre-release (PR #11, `9037f4f`).
- Work branch: `claude/kind-wright-s320u2`, restarted from `main` after each merge.
  Open a draft PR for new work; merge only when the owner asks.
- CI (`.github/workflows/build.yml`) builds on **macOS 26 only**. The macOS 15 job was dropped
  on 2026-11-24: its hosted runners stopped being assigned (cancelled after 15 minutes in the
  queue, six runs in a row). The app still targets macOS 14+.
- Before pushing, run `swift build && swift run TeachLensSelfTest` when a Mac is available.

## What beta.3 shipped

- The 11 ZoomIt settings panes rewritten as SwiftUI grouped forms; hotkey conflicts name the
  feature that owns the shortcut; optional shortcuts can be cleared.
- Keystrokes: teacher-defined custom shortcuts (always shown, caption under the pill, Windows
  override; test case E-14); "Shortcuts only" no longer shows a lone modifier.
- Toolbar: Small / Medium / Large buttons; the open column fits its content; tighter spacing.
- Fixes and performance: Settings no longer overwrites values changed elsewhere; video editor
  uses the async AVFoundation `load…` APIs; about 1,450 lines of dead code removed.

## Phase: polish

The overall structure is frozen: no new panes, windows, modules or settings architecture
changes. Only fixes, wording, spacing, icons and small behavior tweaks.

## Next round

1. The owner tests the beta.4 DMG by hand (Codex is no longer used). Plan:
   `docs/test-plans/1.3.0-beta.3-test-plan.md`; report:
   `docs/test-reports/2026-11-24-1.3.0-beta.3.md`.
2. Fix what they report and update the report. Bump `VERSION` for the next pre-release;
   the release workflow publishes on a `VERSION` change.

## Owner preferences

- Reply in Traditional Chinese; be direct and use lists.
- Keep the UI simple and in the Liquid Glass style (`TeachLensChrome`).
- Merge only when asked; a `-beta.N` VERSION publishes a pre-release.
