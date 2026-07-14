# Yield

macOS menu bar app that compares **logged hours** (Harvest) against **booked hours** (Forecast) for the current week. Shows remaining time per project and lets you start/stop Harvest timers directly from the menu bar.

## Tech Stack

- **Swift 5.9** / **SwiftUI** — macOS 14.0+, menu-bar-only app (`LSUIElement: true`)
- **XcodeGen** — project is defined in `project.yml`, generates `Yield.xcodeproj`
- No external dependencies — uses URLSession and native frameworks only

## Build

```bash
xcodebuild -project Yield.xcodeproj -scheme Yield -configuration Debug build
```

To regenerate the Xcode project after changing `project.yml`:

```bash
xcodegen generate
```

## Architecture

```
Yield/
├── YieldApp.swift              # @main entry, MenuBarExtra with leaf icon
├── Models/
│   ├── ProjectStatus.swift     # Per-project state (logged, booked, tracking, status)
│   ├── HarvestModels.swift     # Harvest API response types
│   └── ForecastModels.swift    # Forecast API response types
├── Services/
│   ├── APIClient.swift         # Generic REST client (Bearer auth, snake_case decoding)
│   ├── HarvestService.swift    # Harvest API (time entries, timers, tasks)
│   ├── ForecastService.swift   # Forecast API (assignments, projects, people)
│   └── DateHelpers.swift       # Week bounds, weekday counting, date formatting
├── ViewModels/
│   └── TimeComparisonViewModel.swift  # Core logic: fetch, merge, sort, timer management
└── Views/
    ├── MenuBarContentView.swift  # Main dropdown: project list, totals, refresh/settings/quit
    ├── ProjectRowView.swift      # Single project row with status indicator and timer toggle
    ├── SettingsView.swift        # API credential entry (token, Harvest ID, Forecast ID)
    └── StatusIndicator.swift     # Color-coded status dot (on track / under / over)
```

## Key Behaviors

- **Auto-refresh**: polls APIs every 5 minutes; local elapsed timer ticks every minute between refreshes
- **Timer control**: start/stop/restart Harvest timers; creates new time entry if none exists for today
- **Project sorting**: tracking projects first → most recently tracked → alphabetical
- **Status thresholds**: ±10% of booked hours (min 0.5h) determines on-track/under/over
- **Credentials**: stored in UserDefaults (`harvestToken`, `harvestAccountId`, `forecastAccountId`); single Harvest PAT is shared with Forecast API

## Release Process

The build/sign/notarize half of a release is a single script — don't hand-run its steps:

```bash
./scripts/release.sh 1.4.2      # preflight → test → bump → archive → export →
                                # sign → zip → notarize → staple → verify → Sparkle-sign
./scripts/release.sh --dry-run  # same machinery, no git writes, no notarize, no publish
```

It halts on the first failure (`set -euo pipefail`), the version bump is idempotent (safe to re-run after a mid-pipeline failure), and it gates on Gatekeeper accepting the build before you can publish. It prints the `edSignature` + `length` the appcast needs.

The `/release` skill wraps it and handles the judgment half: release notes, the `appcast.xml` entry, the tag, and the GitHub release (which auto-posts to Slack).

Invariants the script owns — **don't** reintroduce them by hand:

- **Zips must use `COPYFILE_DISABLE=1 ditto --norsrc`.** Without it, AppleDouble `._` files inside the Sparkle framework make Gatekeeper reject the app with "unsealed contents present in the root directory of an embedded framework" — even when notarization passes.
- **Sparkle is re-signed** under our Developer ID so the whole bundle traces to one identity.
- **`-derivedDataPath build/derived` is pinned** — it keeps stale global DerivedData from breaking the test step, and puts Sparkle's `sign_update` at a stable repo-relative path.
- **Tests run unsigned** (`CODE_SIGNING_ALLOWED=NO`) — they're pure logic, and signing only added a flaky keychain dependency to the first step of every release.

## APIs

- **Harvest** (`https://api.harvestapp.com/v2`): header `Harvest-Account-Id`
- **Forecast** (`https://api.forecastapp.com`): header `Forecast-Account-Id`
- Both use the same Bearer token (Harvest personal access token)
