//
//  ReadCostCounter.swift
//  Woodcase
//

import Foundation
import Synchronization

/// Counts the expensive steps a property read or a schema lookup takes, so a test can
/// pin what one read may cost.
///
/// A read is cheap or dear by what it *does*, not by how long one run took on one
/// machine: reading `kind.width` should never encode a frame's whole payload — its
/// children with it — and looking up one schema row should never rebuild its type's
/// table. The steps report themselves through ``record(_:)``; a test installs a counter
/// for the work it runs and reads the tallies back. With no counter installed, recording
/// is one task-local read.
///
/// ```swift
/// let counter = ReadCostCounter()
/// try ReadCostCounter.$current.withValue(counter) {
///     _ = try NodePropertyCodec.value(at: "kind.width", of: frame)
/// }
/// counter.count(of: .payloadEncode) // 0
/// ```
final class ReadCostCounter: Sendable {
    /// One expensive step.
    enum Work: Friendly {
        /// A node's whole `common` or `kind` payload encoded to a JSON dictionary.
        case payloadEncode
        /// One schema table's rows built — `nil` is the `common.*` table.
        case schemaTable(PenNode.NodeType?)
    }

    /// The counter the current task's work reports to, if a test installed one.
    @TaskLocal static var current: ReadCostCounter?

    /// The tallies so far.
    private let counts = Mutex<[Work: Int]>([:])

    /// Creates a counter with every tally at zero.
    init() {}

    /// Reports one step to the installed counter, if any.
    ///
    /// - Parameter work: The step taken.
    static func record(_ work: Work) {
        current?.counts.withLock { $0[work, default: 0] += 1 }
    }

    /// How many times a step was taken while this counter was installed.
    ///
    /// - Parameter work: The step.
    /// - Returns: Its tally.
    func count(of work: Work) -> Int {
        counts.withLock { $0[work, default: 0] }
    }
}
