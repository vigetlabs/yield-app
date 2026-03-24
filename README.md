# Yield

A macOS menu bar app that compares **logged hours** (Harvest) against **booked hours** (Forecast) for the current week. See remaining time per project and start/stop Harvest timers — all without leaving the menu bar.

## Features

- **Weekly overview** — Logged vs. booked hours per project with color-coded progress bars
- **Today's total** — Quick glance at hours logged today across all projects
- **Timer control** — Start, stop, and restart Harvest timers; drill into individual time entries per project
- **Status indicators** — On track / under / over based on ±10% of booked hours (min 0.5h threshold)
- **Auto-refresh** — Polls APIs every 5 minutes; local elapsed timer ticks every minute between refreshes
- **Notifications** — Alerts when you reach your booked hours on a project
- **Unbooked tracking** — Hours logged to projects without Forecast bookings are shown separately

## Requirements

- macOS 14.0 (Sonoma) or later
- A [Harvest](https://www.getharvest.com/) account with [Forecast](https://www.getharvest.com/forecast) enabled
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Getting Started

### 1. Generate the Xcode project

The Xcode project is defined in `project.yml` and should be regenerated after any changes to that file:

```bash
xcodegen generate
```

### 2. Build

```bash
xcodebuild -project Yield.xcodeproj -scheme Yield -configuration Debug build
```

Or open `Yield.xcodeproj` in Xcode and build with Cmd+B.

### 3. Sign in

Launch the app — it lives in the menu bar. Click the icon and sign in with your Harvest account (OAuth). This automatically connects your Forecast data as well.

Alternatively, open Settings from the gear menu and expand "Advanced: Personal Access Token" to use a Harvest PAT directly.

## Tech Stack

- **Swift 5.9** / **SwiftUI** — menu-bar-only app (`LSUIElement: true`)
- **XcodeGen** — `project.yml` is the source of truth; `Yield.xcodeproj` is generated
- **No external dependencies** — URLSession, Network.framework, Keychain Services, and native frameworks only

## Architecture

```
Yield/
├── YieldApp.swift                  # @main entry, MenuBarExtra, AppState singleton
├── Models/
│   ├── ProjectStatus.swift         # Per-project state, time entry info, status enum
│   ├── HarvestModels.swift         # Harvest API response types
│   └── ForecastModels.swift        # Forecast API response types
├── Services/
│   ├── APIClient.swift             # Generic REST client (Bearer auth, snake_case decoding)
│   ├── HarvestService.swift        # Harvest API (time entries, timers, tasks, users)
│   ├── ForecastService.swift       # Forecast API (assignments, projects, people, clients)
│   ├── OAuthService.swift          # OAuth 2.0 flow with local callback server (NWListener)
│   ├── KeychainHelper.swift        # Secure token storage with in-memory cache
│   └── DateHelpers.swift           # Week bounds, weekday counting, date formatting
├── ViewModels/
│   └── TimeComparisonViewModel.swift  # Core logic: fetch, merge, sort, timer management
└── Views/
    ├── MenuBarContentView.swift    # Main dropdown: project list, totals, inline settings, gear menu
    ├── ProjectRowView.swift        # Project row with progress bar, expandable time entries
    ├── SettingsView.swift          # Settings window (OAuth + PAT configuration)
    └── StatusIndicator.swift       # Color-coded status dot
```

## Project Conventions

### Source of truth

- `project.yml` defines the Xcode project. Run `xcodegen generate` after editing it. Do not hand-edit `Yield.xcodeproj` for structural changes.

### Authentication

- **OAuth (default)** — Tokens stored in Keychain via `KeychainHelper`. Account IDs in UserDefaults.
- **PAT (advanced)** — Personal access token and account IDs stored in UserDefaults.
- OAuth takes priority when both are configured. A single Harvest token is shared with the Forecast API.

### State management

- `AppState` is a singleton holding the shared `TimeComparisonViewModel` and `OAuthService`.
- `@Observable` (Observation framework) is used for all observable types — no Combine or `ObservableObject`.

### Time display

- Hours are shown in `h:mm` format (e.g., `3:30` not `3.5h`) throughout the UI.
- The menu bar label shows remaining time as `X:XX left` or `X:XX over`.

### Sorting

- Tracking projects first, then most recently tracked, then alphabetical.

### APIs

| Service  | Base URL                            | Auth Header            |
|----------|-------------------------------------|------------------------|
| Harvest  | `https://api.harvestapp.com/v2`     | `Harvest-Account-Id`   |
| Forecast | `https://api.forecastapp.com`       | `Forecast-Account-Id`  |

Both use the same `Authorization: Bearer <token>` header.

### Code style

- SwiftUI views are broken into computed properties by section (content, states, footer, etc.)
- `// MARK: -` comments to organize sections within files
- No third-party dependencies — everything is built on Apple frameworks
