import Foundation
import Network

/// Observes the system's network path and reports connectivity edges in
/// both directions:
///   - `onReconnect` fires on unsatisfied → satisfied, so the view model
///     can refetch the moment the machine is back online instead of
///     waiting for the next refresh-timer tick.
///   - `onDisconnect` fires on satisfied → unsatisfied, so the UI can
///     show the offline state immediately instead of only learning about
///     it when the next soft refresh fails (up to a full minute later).
///
/// The disconnect edge is debounced: `NWPathMonitor` momentarily reports
/// `.unsatisfied` during routine interface handoffs (Wi-Fi ↔ Ethernet,
/// VPN reconnect, sleep/wake), and flipping the offline state on those
/// would flicker the menu bar. A real outage persists past the debounce
/// and fires; a transient blip resolves (the path returns to satisfied)
/// and the pending disconnect is cancelled. The reconnect edge is not
/// debounced — being back online is good news worth acting on instantly.
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.viget.yield.network-monitor")
    private var lastPathWasSatisfied: Bool = true  // optimistic default
    private var onReconnect: (() -> Void)?
    private var onDisconnect: (() -> Void)?
    /// Pending debounced disconnect, cancelled if the path recovers before
    /// it fires. Accessed only on `queue`, so no extra synchronization.
    private var pendingDisconnect: DispatchWorkItem?
    private var isStarted: Bool = false

    /// How long an unsatisfied path must persist before we treat it as a
    /// real disconnect rather than an interface handoff blip.
    private static let disconnectDebounce: DispatchTimeInterval = .seconds(2)

    /// Start monitoring. Callbacks fire on the main actor. `onReconnect`
    /// fires on each unsatisfied → satisfied transition; `onDisconnect`
    /// fires once an unsatisfied path has persisted past the debounce
    /// window. Safe to call more than once — subsequent calls replace the
    /// callbacks without starting the underlying NWPathMonitor a second
    /// time (which Apple documents as a programmer error).
    @MainActor
    func start(onReconnect: @escaping () -> Void, onDisconnect: @escaping () -> Void) {
        self.onReconnect = onReconnect
        self.onDisconnect = onDisconnect
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let wasSatisfied = self.lastPathWasSatisfied
            self.lastPathWasSatisfied = satisfied

            if satisfied {
                // Back online (or the drop was just a handoff blip):
                // cancel any pending disconnect and announce reconnects.
                self.pendingDisconnect?.cancel()
                self.pendingDisconnect = nil
                if !wasSatisfied {
                    Task { @MainActor in self.onReconnect?() }
                }
            } else if wasSatisfied {
                // satisfied → unsatisfied: arm a debounced disconnect.
                self.pendingDisconnect?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingDisconnect = nil
                    Task { @MainActor in self?.onDisconnect?() }
                }
                self.pendingDisconnect = work
                self.queue.asyncAfter(deadline: .now() + Self.disconnectDebounce, execute: work)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
