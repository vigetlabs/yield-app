# Contributing to Yield

## Requirements

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Tech stack

- **Swift 5.9 / SwiftUI** — macOS 14.0+, menu-bar-only (`LSUIElement: true`)
- **XcodeGen** — `project.yml` is the source of truth
- **No external dependencies** beyond [Sparkle](https://sparkle-project.org/) for auto-updates

## Build

```bash
xcodegen generate
xcodebuild -project Yield.xcodeproj -scheme Yield -configuration Debug build
```

Or open `Yield.xcodeproj` in Xcode and hit Cmd+B.

## Architecture

```
Yield/
├── YieldApp.swift                     # @main, MenuBarExtra, AppState
├── Models/
│   ├── ProjectStatus.swift            # Per-project state and status
│   ├── HarvestModels.swift            # Harvest API types
│   └── ForecastModels.swift           # Forecast API types
├── Services/
│   ├── APIClient.swift                # REST client (Bearer auth, snake_case)
│   ├── HarvestService.swift           # Harvest API
│   ├── ForecastService.swift          # Forecast API
│   ├── OAuthService.swift             # OAuth 2.0 with local callback server
│   ├── KeychainHelper.swift           # Secure token storage
│   └── DateHelpers.swift              # Week bounds and date formatting
├── ViewModels/
│   └── TimeComparisonViewModel.swift  # Fetch, merge, sort, timer management
└── Views/
    ├── MenuBarContentView.swift       # Main dropdown UI
    ├── ProjectRowView.swift           # Project row with progress bar
    ├── SettingsView.swift             # OAuth + PAT settings
    └── StatusIndicator.swift          # Color-coded status dot
```

## Conventions

- **Version source of truth**: `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`)
- **Auth**: OAuth (default, Keychain storage) or Personal Access Token (advanced)
- **Time format**: `h:mm` everywhere (e.g., `3:30` not `3.5h`)
- **State**: `@Observable` — no Combine or `ObservableObject`
- **Releases**: Signed with Developer ID, notarized by Apple, distributed via GitHub Releases with Sparkle appcast

## Releasing

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. `xcodegen generate`
3. Build a release archive: `xcodebuild -project Yield.xcodeproj -scheme Yield -configuration Release archive -archivePath build/Yield.xcarchive`
4. Re-sign Sparkle binaries and the app with Developer ID + `--timestamp`
5. Zip: `ditto -c -k --keepParent Yield.app build/Yield-X.Y.Z.zip`
6. Notarize: `xcrun notarytool submit build/Yield-X.Y.Z.zip --apple-id <email> --team-id <team> --password <app-specific-password> --wait`
7. Staple: `xcrun stapler staple Yield.app` then re-zip
8. Sign for Sparkle: `sign_update build/Yield-X.Y.Z.zip`
9. Add entry to `appcast.xml` with the signature and length
10. Commit, push, create GitHub release with the zip attached
