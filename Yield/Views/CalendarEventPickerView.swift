import SwiftUI

/// Inline-replacement picker shown in place of the new-timer form
/// when the user taps the calendar icon. Lists today's primary-
/// calendar events; tapping one returns the event to the form via
/// `onSelect` so the form can pre-fill duration + title.
///
/// Lives inside `NewTimerFormView`'s body (not a sheet/popover —
/// MenuBarExtra panels can't host either) so the panel reflows to
/// the picker's natural height.
struct CalendarEventPickerView: View {
    let onSelect: (CalendarEvent) -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .loading

    /// The picker's render state. `loaded` carries the events so the
    /// view can switch on a single value rather than juggling parallel
    /// `events` + `isLoading` flags.
    private enum Phase {
        case loading
        case loaded([CalendarEvent])
        case empty
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch phase {
            case .loading:
                loadingState
            case .loaded(let events):
                eventList(events)
            case .empty:
                emptyState
            case .error(let message):
                errorState(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadEvents()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onCancel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Back")
                        .font(YieldFonts.dmSans(11, weight: .medium))
                }
                .foregroundStyle(YieldColors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Today's events")
                .font(YieldFonts.dmSans(13, weight: .semibold))
                .foregroundStyle(YieldColors.textPrimary)

            Spacer()

            // Symmetry spacer so the title stays centered.
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                Text("Back")
                    .font(YieldFonts.dmSans(11, weight: .medium))
            }
            .hidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading today's events…")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(YieldColors.textSecondary)
            Text("No events on your calendar today.")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
            Button("Back to form", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(YieldColors.greenAccent)
                .font(YieldFonts.dmSans(11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.red.opacity(0.8))
            Text(message)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await loadEvents() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(YieldColors.greenAccent)
            .font(YieldFonts.dmSans(11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func eventList(_ events: [CalendarEvent]) -> some View {
        // Size the scroll view to its content's ideal height, only
        // capping when the day's calendar is genuinely huge. Same
        // pattern the main panel + Settings use: `fixedSize(vertical:)`
        // collapses unused space when events fit, while
        // `frame(maxHeight:)` keeps the panel from overflowing the
        // screen on a 30-meeting day.
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events) { event in
                    EventRow(event: event) {
                        onSelect(event)
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Cap on the list's height so the menu bar panel can't grow past
    /// the screen on short displays. The `48` accounts for the back-
    /// button header + a touch of breathing room; the `300` floor
    /// protects the very first frame before `NSScreen.main` is
    /// meaningful.
    private var maxListHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(300, visible - 48)
    }

    // MARK: - Loading

    private func loadEvents() async {
        phase = .loading
        let auth = AppState.shared.googleAuthService
        let service = GoogleCalendarService(tokenProvider: { try await auth.getAccessToken() })
        do {
            let events = try await service.fetchTodayEvents()
            phase = events.isEmpty ? .empty : .loaded(events)
        } catch APIError.unauthorized {
            phase = .error("Reconnect Google Calendar in Settings.")
        } catch APIError.notConfigured {
            phase = .error("Google Calendar isn't connected. Connect it in Settings.")
        } catch {
            phase = .error("Couldn't reach Google Calendar.\n\(error.localizedDescription)")
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: CalendarEvent
    let onSelect: () -> Void

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private var timeRange: String {
        let start = Self.timeFormatter.string(from: event.start)
        let end = Self.timeFormatter.string(from: event.end)
        return "\(start) – \(end)"
    }

    private var displayTitle: String {
        event.summary.isEmpty ? "(No title)" : event.summary
    }

    private var durationLabel: String {
        let (h, m) = event.durationHours.roundedHM
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Time range column — fixed width so titles align.
                Text(timeRange)
                    .font(YieldFonts.monoXS)
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(YieldFonts.titleSmall)
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(durationLabel)
                        .font(YieldFonts.labelTimeRemaining)
                        .foregroundStyle(YieldColors.textSecondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? YieldColors.surfaceDefault : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }
}
