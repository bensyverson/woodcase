//
//  PollingFileWatchBackend.swift
//  Woodcase
//

import Dispatch
import Foundation
import Synchronization

/// Notices changes by comparing ``FileSignature``s on a timer.
///
/// Works on every platform and filesystem — including ones that deliver no change
/// notifications — at the price of latency up to `interval`. A missing file has no
/// signature, so a delete and a later recreate are two comparisons that differ.
final class PollingFileWatchBackend: FileWatchBackend {
    /// Creates a backend.
    ///
    /// - Parameters:
    ///   - interval: How often to compare signatures.
    ///   - onEvent: Called with each path whose signature changed.
    init(interval: Duration = .milliseconds(100), onEvent: @escaping @Sendable (String) -> Void) {
        self.interval = interval
        self.onEvent = onEvent
    }

    deinit {
        timer.withLock { $0?.cancel() }
    }

    func watch(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let parent = Self.parentDirectory(of: path)
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        signatures.withLock { $0[path] = FileSignature.read(at: path) }
        startTimerIfNeeded()
        return true
    }

    var watchedCount: Int {
        signatures.withLock(\.count)
    }

    func stop() {
        timer.withLock {
            $0?.cancel()
            $0 = nil
        }
        signatures.withLock { $0.removeAll() }
    }

    // MARK: - Private

    private let interval: Duration
    private let onEvent: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "dev.woodcase.filewatcher.polling")

    /// The last signature seen per path; `nil` means the path did not exist.
    private let signatures = Mutex<[String: FileSignature?]>([:])
    private let timer = Mutex<(any DispatchSourceTimer)?>(nil)

    private func startTimerIfNeeded() {
        timer.withLock { current in
            guard current == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            let nanoseconds = interval.components.seconds * 1_000_000_000
                + interval.components.attoseconds / 1_000_000_000
            source.schedule(deadline: .now() + .nanoseconds(Int(nanoseconds)), repeating: .nanoseconds(Int(nanoseconds)))
            source.setEventHandler { [weak self] in self?.poll() }
            source.resume()
            current = source
        }
    }

    private func poll() {
        let changed: [String] = signatures.withLock { known in
            var changed: [String] = []
            for (path, previous) in known {
                let current = FileSignature.read(at: path)
                if current != previous {
                    known[path] = current
                    changed.append(path)
                }
            }
            return changed
        }
        for path in changed {
            onEvent(path)
        }
    }
}
