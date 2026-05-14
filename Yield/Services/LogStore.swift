import AppKit
import Foundation

/// Append-only rolling log written to
/// `~/Library/Logs/Yield/yield.log`. Entries are timestamped lines,
/// rotated when the file passes a size threshold so the log can't grow
/// without bound. Used for two things:
///
/// 1. Capturing errors the user might never notice (silent fetch
///    failures, refresh hiccups) so they show up when a bug is filed.
/// 2. Building a "last error" snapshot the bug-report URL can include
///    in the issue body.
///
/// The log is local-only; nothing leaves the user's machine unless
/// they attach the file to a GitHub issue themselves.
///
/// Callable from any thread — file I/O and `lastError` reads/writes
/// are serialized through a private queue. `ISO8601DateFormatter` is
/// thread-safe per Apple's docs.
final class LogStore {
    static let shared = LogStore()

    /// Hard cap on file size before rotation. The current file is
    /// renamed to `yield.log.1` and a fresh `yield.log` is started.
    /// Old `.1` is overwritten — only one rotation is kept.
    private static let maxFileSize: Int = 256 * 1024  // 256 KB

    private let queue = DispatchQueue(label: "com.yield.LogStore", qos: .utility)
    private let fileURL: URL?
    private let isoFormatter: ISO8601DateFormatter
    private var _lastError: String?

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter

        let fm = FileManager.default
        if let logsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Yield", isDirectory: true) {
            try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
            self.fileURL = logsDir.appendingPathComponent("yield.log")
        } else {
            self.fileURL = nil
        }
    }

    /// Log an error or noteworthy event. Safe to call from any thread.
    func log(_ message: String, category: Category = .error) {
        let timestamp = isoFormatter.string(from: Date())
        let line = "\(timestamp) [\(category.rawValue)] \(message)\n"
        queue.async { [self] in
            if category == .error {
                _lastError = message
            }
            Self.append(line, to: fileURL)
        }
    }

    /// Most recent error message, captured in memory so the
    /// bug-report URL can include it without reading the file back.
    var lastError: String? {
        queue.sync { _lastError }
    }

    /// Reveal the log file in Finder. No-op if the log directory
    /// hasn't been created yet (no errors have been logged).
    func revealInFinder() {
        guard let fileURL else { return }
        Task { @MainActor in
            // Reveal the directory rather than the file so the user
            // sees the rotated `.1` companion too.
            let target = FileManager.default.fileExists(atPath: fileURL.path)
                ? fileURL
                : fileURL.deletingLastPathComponent()
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    /// Path string suitable for inclusion in a bug-report body.
    var fileURLDescription: String? {
        fileURL?.path
    }

    enum Category: String {
        case error = "ERROR"
        case warning = "WARN"
        case info = "INFO"
    }

    // MARK: - File I/O (executes on `queue`)

    private static func append(_ line: String, to url: URL?) {
        guard let url, let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default

        // Rotate if the existing file is past the cap.
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > maxFileSize {
            let rotated = url.deletingLastPathComponent().appendingPathComponent("yield.log.1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: data)
            return
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
