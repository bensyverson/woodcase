import Foundation

/// Thread-safe collector for pipeline diagnostics.
///
/// Pass an instance through the pipeline to accumulate notices, warnings and errors.
/// After rendering, inspect `diagnostics` to report issues, and ask
/// ``contains(atLeast:)`` whether to fail in strict mode.
public final class PenDiagnosticCollector: Sendable {
    private let storage = _DiagnosticStorage()

    public init() {}

    /// Appends a diagnostic.
    public func add(_ diagnostic: PenDiagnostic) {
        storage.append(diagnostic)
    }

    /// Convenience to emit a notice — something worth knowing that is not a problem.
    public func notice(
        _ message: String,
        stage: PenDiagnostic.Stage,
        nodeID: String? = nil
    ) {
        add(PenDiagnostic(severity: .notice, stage: stage, message: message, nodeID: nodeID))
    }

    /// Convenience to emit a warning.
    public func warn(
        _ message: String,
        stage: PenDiagnostic.Stage,
        nodeID: String? = nil
    ) {
        add(PenDiagnostic(severity: .warning, stage: stage, message: message, nodeID: nodeID))
    }

    /// Convenience to emit an error.
    public func error(
        _ message: String,
        stage: PenDiagnostic.Stage,
        nodeID: String? = nil
    ) {
        add(PenDiagnostic(severity: .error, stage: stage, message: message, nodeID: nodeID))
    }

    /// All collected diagnostics.
    public var diagnostics: [PenDiagnostic] {
        storage.all
    }

    /// Whether any diagnostics have been collected.
    public var hasIssues: Bool {
        !storage.all.isEmpty
    }

    /// Whether any diagnostic at or above `severity` has been collected.
    ///
    /// `contains(atLeast: .warning)` is the question a strict run asks: a notice is
    /// something to read, never a reason to fail.
    ///
    /// - Parameter severity: The lowest severity that counts.
    /// - Returns: `true` when at least one diagnostic meets it.
    public func contains(atLeast severity: PenDiagnostic.Severity) -> Bool {
        storage.all.contains { $0.severity.meetsOrExceeds(severity) }
    }

    /// Whether any error-severity diagnostics have been collected.
    public var hasErrors: Bool {
        storage.all.contains { $0.severity == .error }
    }
}

/// Internal storage using a lock for thread safety.
private final class _DiagnosticStorage: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _diagnostics: [PenDiagnostic] = []

    func append(_ diagnostic: PenDiagnostic) {
        lock.lock()
        defer { lock.unlock() }
        _diagnostics.append(diagnostic)
    }

    var all: [PenDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return _diagnostics
    }
}
