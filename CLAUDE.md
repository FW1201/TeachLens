# CLAUDE.md

Read [`AGENTS.md`](AGENTS.md) first: build commands, code map and conventions.

## Status (handoff from the cloud session, 2026-11-24)

- Work branch: `claude/kind-wright-s320u2` → **PR #11** (`1.3.0-beta.3`, draft). Do **not** merge until the owner has finished hands-on testing and the next round of fixes.
- `main` is at `1.3.0-beta.2` (published as a GitHub pre-release).
- The latest commits on the branch, not yet verified by CI (the macOS runners were saturated):
  - toolbar button size Small/Medium/Large;
  - the open column now fits its content;
  - CI builds each PR once.

  Run `swift build && swift run TeachLensSelfTest` locally first. Fix anything that fails before other work.
- Hands-on QA: plan in `docs/test-plans/1.3.0-beta.3-test-plan.md`, first-round report in `docs/test-reports/2026-11-24-1.3.0-beta.3.md`. Codex (computer use) runs the plan against the app built by `Scripts/build-app.sh`.

## Phase (owner, 2026-11-24)

**Polish phase.** The overall structure is frozen: no new panes, windows, modules or settings
architecture changes. Only fixes, wording, spacing, icons and small behavior tweaks.

- Done since the handoff: video editor async `load…` APIs (`42f562f`, `c4bac00`); custom
  keystroke shortcuts with captions (`1921dee`, test case E-14).
- A scheduled CI re-run is set for 2026-11-25 02:00 (Asia/Taipei).

## Next round (agreed with the owner)

1. Fix whatever the hands-on QA finds; update the report.
2. ~~`Capture/VideoClipEditorController.swift`: async `load…` APIs~~ — done.
3. CI runs on macOS 26 only (macOS 15 runners stopped being assigned; owner dropped it on 2026-11-24). Merge once it is green; the release workflow publishes the pre-release.

## Owner preferences

- Reply in Traditional Chinese; be direct and use lists.
- Keep the UI simple and in the Liquid Glass style (`TeachLensChrome`).
- Merge only when asked; a `-beta.N` VERSION publishes a pre-release.
