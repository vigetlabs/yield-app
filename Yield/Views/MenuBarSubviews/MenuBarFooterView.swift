import SwiftUI

struct MenuBarFooterView: View {
    let viewModel: TimeComparisonViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        HStack {
            Button {
                openBugReport()
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Report a bug")

            Spacer()

            Menu {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                Button("Settings...") {
                    onOpenSettings()
                }

                Divider()

                Button("Quit Yield") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            // Pull up by 1pt so this divider paints into the same pixel
            // row as the last project's bottom border (when a row sits
            // directly above) — otherwise the two adjacent 1pt borders
            // read as a 2pt double line. When the section above has no
            // border (empty state, chart tab) the divider still shows.
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
                .offset(y: -1)
        }
    }

    /// Open a new GitHub issue with a body pre-populated with the
    /// app version, macOS version, last error, last refresh time,
    /// and the local log path. Without this, every report arrives
    /// blank and we have to ask the user for these details — most
    /// will skip filing.
    private func openBugReport() {
        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let lastRefresh = viewModel.lastUpdated
            .map { ISO8601DateFormatter().string(from: $0) }
            ?? "(never)"
        let lastError = LogStore.shared.lastError ?? "(none)"
        let logPath = LogStore.shared.fileURLDescription ?? "(unavailable)"

        let body = """
        ## What happened?
        <!-- Describe what you saw, what you expected, and the steps to reproduce. -->


        ## Environment (auto-filled)
        - **Yield**: \(appVersion) (build \(buildNumber))
        - **macOS**: \(osVersion)
        - **Last refresh**: \(lastRefresh)
        - **Last error**: \(lastError)

        ## Logs
        Log file location: `\(logPath)`
        <!-- Open Settings → About → Reveal Logs in Finder, then drag-and-drop the log into this issue. -->
        """

        var components = URLComponents(string: "https://github.com/vigetlabs/yield-app/issues/new")
        components?.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }
}
