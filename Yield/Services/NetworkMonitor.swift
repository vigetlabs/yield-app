import Foundation
import Network

/// Observes the system's network path and reports when connectivity
/// transitions from unavailable to available. Consumers register a callback
/// that fires once per reconnect — so the view model can trigger a fresh
/// fetch the moment the machine gets back online instead of waiting up to
/// a full refresh-timer interval.
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.viget.yield.network-monitor")
    private var lastPathWasSatisfied: Bool = true  // optimistic default
    private var onReconnect: (() -> Void)?
    private var isStarted: Bool = false

    /// Start monitoring. The callback fires on the main actor each time the
    /// path transitions from unsatisfied → satisfied. Safe to call more
    /// than once — subsequent calls replace the callback without starting
    /// the underlying NWPathMonitor a second time (which Apple documents
    /// as a programmer error).
    @MainActor
    func start(onReconnect: @escaping () -> Void) {
        self.onReconnect = onReconnect
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let wasSatisfied = self.lastPathWasSatisfied
            self.lastPathWasSatisfied = satisfied
            if satisfied && !wasSatisfied {
                Task { @MainActor in
                    self.onReconnect?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
