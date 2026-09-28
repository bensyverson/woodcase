import Foundation

/// A diagnostic message emitted during the .pen processing pipeline.
public struct PenDiagnostic: Friendly, CustomStringConvertible {
    /// The severity of the diagnostic.
    ///
    /// `CaseIterable` so a refusal can list the levels rather than spelling them out a
    /// second time: `woodcase lint --severity` and a script's `doc.lint({ severity })`
    /// both name them from here.
    public enum Severity: String, Friendly, CaseIterable {
        /// Worth knowing, and nothing wrong: a file from a newer Pen, say. A notice never
        /// fails `woodcase lint` or `render --strict`, and `lint` shows one only when
        /// asked with `--severity notice`.
        case notice
        /// Probably not what was meant, or a result that differs from the format's own editor.
        case warning
        /// Broken: something could not be done at all.
        case error

        /// Ordinal rank, low to high, for threshold comparisons.
        private var rank: Int {
            switch self {
            case .notice: 0
            case .warning: 1
            case .error: 2
            }
        }

        /// Whether this severity meets or exceeds `threshold` — `error` meets `warning`,
        /// but not the reverse.
        ///
        /// The ordering is a fact about the level, not about a flag, so both routes that
        /// filter by it — `woodcase lint --severity` and `doc.lint({ severity })` — ask
        /// here rather than each keeping a table.
        ///
        /// - Parameter threshold: The lowest severity to keep.
        /// - Returns: `true` when a finding at this severity should still be reported.
        public func meetsOrExceeds(_ threshold: Severity) -> Bool {
            rank >= threshold.rank
        }
    }

    /// The pipeline stage that produced this diagnostic.
    public enum Stage: String, Friendly {
        case parsing
        /// Version-gate decisions and legacy-format rewrites — see ``PenLegacyMigrator``.
        case migration
        case importResolution
        case refExpansion
        case variableResolution
        case fontResolution
        /// Downloading the images that remote image fills point at — see
        /// ``RemoteImageResolver``.
        case imageResolution
        case layout
        case codeGen
        case rendering
    }

    public let severity: Severity
    public let stage: Stage
    public let message: String
    public let nodeID: String?

    public init(
        severity: Severity,
        stage: Stage,
        message: String,
        nodeID: String? = nil
    ) {
        self.severity = severity
        self.stage = stage
        self.message = message
        self.nodeID = nodeID
    }

    public var description: String {
        let prefix = severity.rawValue
        if let nodeID {
            return "\(prefix): [\(stage.rawValue)] \(message) (node: \(nodeID))"
        }
        return "\(prefix): [\(stage.rawValue)] \(message)"
    }
}
