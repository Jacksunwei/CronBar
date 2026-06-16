# CronBar

A lightweight macOS menu bar app for viewing and managing your user
**LaunchAgents** — especially the ones you use as cron-style scheduled jobs.

CronBar lives in the menu bar (no Dock icon) and shows every agent in
`~/Library/LaunchAgents` with its live status, what triggers it, and when it's
expected to run next.

## Features

- **At-a-glance status** for each agent — a colored dot and label:
  - 🟢 Running (has a live PID)
  - ⚪ Loaded (idle) — armed and waiting for its next trigger
  - 🔴 Failed (non-zero last exit code)
  - 🟠 Not loaded
- **Trigger badges** showing *why* each agent runs: `every 15m`, `calendar`,
  `keep-alive`, `watch path`, `queue dir`, `on-demand (xpc/socket)`, `on mount`,
  `at load`.
- **Next-run time** for scheduled jobs (`in 12m`, `~in 1h 5m`):
  - exact for `StartCalendarInterval`
  - approximate (`~`) for `StartInterval`, anchored on observed runs
- **Running / Scheduled sections** — live processes are grouped on top; the rest
  are sorted by soonest next run.
- **Actions** (hover a row, or right-click):
  - **Load** / **Unload** (`launchctl bootstrap` / `bootout`)
  - **Start** ⇄ **Kill** the running process (`kickstart` / `kill`)
  - **Edit config** (opens the plist)
  - **Reveal plist in Finder**
- **Auto-refresh** every 5s while the panel is open.
- **Disabled agents are hidden** (those marked disabled in launchd's database).

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 16+ / Swift 6.x)

## Install

Via Homebrew:

```sh
brew install --cask jacksunwei/tap/cronbar
```

Or build from source:

```sh
git clone https://github.com/Jacksunwei/CronBar.git
cd CronBar
./scripts/build-app.sh        # produces CronBar.app
open CronBar.app
```

## Build & run

Quick run during development:

```sh
swift run            # build and launch
```

Build a double-clickable, icon-bearing app bundle:

```sh
./scripts/build-app.sh   # produces CronBar.app
open CronBar.app
```

The app appears as a clock icon in the menu bar (no Dock icon — it's a menu-bar
accessory). Click it to open the panel; quit with the **Quit** button (⌘Q).

## Design

- **Look:** refined native style with translucent menu material, rounded rows,
  status dots, and pill badges. Adapts to light and dark mode.
- **Accent:** indigo/violet, used for highlights, hover states, scheduled-trigger
  badges, and the app icon.
- **App icon:** an indigo→violet glossy squircle with a clock. Source artwork
  lives at `Sources/CronBar/Resources/AppIcon.png` (1024×1024, transparent).
  - **Dropdown header:** full-color icon, loaded at runtime via `Bundle.module`.
  - **App/Finder icon:** `scripts/make-icon.sh` resizes it into an `.iconset` and
    runs `iconutil` to produce `Resources/AppIcon.icns`.
  - **Menu bar:** a monochrome *template* clock glyph (drawn in
    `IconAssets.swift`) that macOS tints for light/dark menu bars.
  - (`scripts/clean-icon.swift` strips a baked-in checkerboard background from a
    flattened export.)

## How it works

CronBar shells out to `launchctl` and reads your plists; it makes no system
modifications beyond the explicit Load/Unload/Start/Kill actions you trigger.

| Data | Source |
|------|--------|
| Agent list & triggers | `~/Library/LaunchAgents/*.plist` |
| Loaded state, PID, last exit | `launchctl list` |
| Enabled/disabled | `launchctl print-disabled gui/<uid>` |
| Run counter (for next-run anchoring) | `launchctl print gui/<uid>/<label>` |

### A note on next-run accuracy

launchd does **not** expose a "next run" or "last run" timestamp. CronBar
therefore:

- computes calendar schedules itself (exact), and
- estimates interval schedules by detecting when a job's `runs` counter
  increments (an observed run) and projecting forward by the interval — falling
  back to the log file's modification time until a run is observed.

Interval estimates are marked with `~`. They can drift if the Mac sleeps
(launchd coalesces missed firings), and observed-run history resets when the app
is quit.

## Project layout

```
Sources/CronBar/
  CronBarApp.swift          # @main MenuBarExtra app, accessory activation
  ContentView.swift         # menu panel UI, rows, badges, next-run labels
  Theme.swift               # design tokens: accent, status & trigger colors
  IconAssets.swift          # color icon loader + menu-bar template glyph
  LaunchAgent.swift         # model: status, triggers, next-run
  LaunchAgentManager.swift  # scanning, launchctl integration, actions
  Resources/AppIcon.png     # source icon artwork (bundled at runtime)
Resources/
  Info.plist                # app bundle metadata (LSUIElement menu-bar app)
  AppIcon.icns              # generated app icon (.icns)
scripts/
  make-icon.sh              # builds AppIcon.icns from AppIcon.png
  clean-icon.swift          # strips baked-in checkerboard from a flat export
  build-app.sh              # packages CronBar.app
  dev.sh                    # rebuild + relaunch for development
```

## Releasing

Releases are automated by [`.github/workflows/release.yml`](.github/workflows/release.yml),
triggered by pushing a version tag:

```sh
# 1. Bump the version in Resources/Info.plist (CFBundleShortVersionString)
# 2. Commit, then tag and push:
git tag v0.2.0
git push origin v0.2.0
```

The workflow builds `CronBar.app`, attaches `CronBar.app.zip` to a new GitHub
Release, and updates the Homebrew cask (`version` + `sha256`) in
`Jacksunwei/homebrew-tap`. The tag must match the Info.plist version or the
build fails.

Updating the tap requires a repository secret **`HOMEBREW_TAP_TOKEN`** — a token
with `contents: write` on `Jacksunwei/homebrew-tap`. Without it, the release is
still created and only the tap-update step is skipped.

## License

MIT © 2026 Wei (Jack) Sun — see [LICENSE](LICENSE).
