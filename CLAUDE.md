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

## APIs

- **Harvest** (`https://api.harvestapp.com/v2`): header `Harvest-Account-Id`
- **Forecast** (`https://api.forecastapp.com`): header `Forecast-Account-Id`
- Both use the same Bearer token (Harvest personal access token)
