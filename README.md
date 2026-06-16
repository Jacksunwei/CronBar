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
- **Launch at login** toggle in Settings.
- **Disabled agents are hidden** (those marked disabled in launchd's database).

## Install

Requires macOS 14+.

```sh
brew install --cask jacksunwei/tap/cronbar
```

## License

MIT © 2026 Wei (Jack) Sun — see [LICENSE](LICENSE).
