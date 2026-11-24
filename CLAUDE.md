# CLAUDE.md

Read [`AGENTS.md`](AGENTS.md) first: build commands, code map and conventions.

## Status (2026-11-25)

- `main` is at **`1.3.0-beta.3`**, published as the GitHub pre-release `v1.3.0-beta.3`
  (PR #11, merge `9037f4f`, DMG `TeachLens-1.3.0-beta.3.dmg`).
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

1. Hands-on QA of the beta.3 DMG. Plan: `docs/test-plans/1.3.0-beta.3-test-plan.md`.
   Report: `docs/test-reports/2026-11-24-1.3.0-beta.3.md` (about 70 cases not yet run, plus E-14).
   Codex (computer use) runs the plan against the installed app.
2. Fix what QA finds and update the report.
3. Next pre-release: bump `VERSION` to `1.3.0-beta.4`, merge when CI is green and the owner
   asks. The release workflow publishes on a `VERSION` change.

## Owner preferences

- Reply in Traditional Chinese; be direct and use lists.
- Keep the UI simple and in the Liquid Glass style (`TeachLensChrome`).
- Merge only when asked; a `-beta.N` VERSION publishes a pre-release.
