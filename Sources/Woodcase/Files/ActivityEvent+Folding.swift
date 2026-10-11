//
//  ActivityEvent+Folding.swift
//  Woodcase
//

import Foundation

public extension ActivityEvent {
    /// Folds runs of rows into one row each: what an app that commits every keystroke
    /// logs for one typing step (see ``CommittedChange/folding(_:)``).
    ///
    /// A run is consecutive rows by the same identity, on the same file, of the same
    /// ``Kind``, naming the same nodes. Its row is the run's last — its time, revision
    /// and paths — with every row's operations:
    ///
    /// - ``inverse`` is the rows' inverses in the order that takes the run back, newest
    ///   row's first, so applied to the run's end it restores the run's start;
    /// - ``forward`` is the rows' forwards in order, so applied to the start it gives
    ///   the end;
    /// - in both, a property write another write later in the list fully covers is
    ///   dropped, so ten keystrokes into one text keep one write each way. Only a write
    ///   of node properties or instance overrides is dropped, and only by another such
    ///   write of at least the same keys; every structural operation stays.
    ///
    /// The run's row keeps the batch id of its first row.
    ///
    /// - Parameter rows: The rows, oldest first.
    /// - Returns: One row per run, oldest first.
    static func folding(_ rows: [ActivityEvent]) -> [ActivityEvent] {
        var runs: [[ActivityEvent]] = []
        for row in rows {
            if let last = runs.last?.last, last.continuesRun(with: row) {
                runs[runs.count - 1].append(row)
            } else {
                runs.append([row])
            }
        }
        return runs.compactMap { run in
            guard var folded = run.last, let first = run.first else { return nil }
            folded.inverse = collapsingCoveredWrites(run.reversed().flatMap(\.inverse))
            folded.forward = collapsingCoveredWrites(run.flatMap(\.forward))
            folded.batch = first.batch
            return folded
        }
    }

    /// Whether `next` belongs to the same run as this row.
    private func continuesRun(with next: ActivityEvent) -> Bool {
        identity == next.identity && file == next.file && op == next.op && nodes == next.nodes
    }

    /// `operations`, in application order, without each property write that a later one
    /// writes at least the same keys of: the later write leaves the same values whether
    /// the earlier one ran or not.
    private static func collapsingCoveredWrites(_ operations: [EditOperation]) -> [EditOperation] {
        let keys = operations.map(writtenKeys(of:))
        return operations.indices.compactMap { index in
            guard let own = keys[index] else { return operations[index] }
            let covered = keys[(index + 1)...].contains { later in
                later.map { own.isSubset(of: $0) } ?? false
            }
            return covered ? nil : operations[index]
        }
    }

    /// The keys an operation writes when it only writes values — node properties,
    /// descendant or root overrides — or `nil` for any other operation.
    private static func writtenKeys(of operation: EditOperation) -> Set<ChangeKey>? {
        switch operation {
        case let .setProperties(op):
            Set(op.properties.keys.map { .property(node: op.nodeID, path: $0) })
        case let .overrideDescendant(op):
            Set(Set(op.properties.keys).union(op.unset).map {
                .override(ref: op.refNodeID, descendant: op.descendantID, key: $0)
            })
        case let .overrideRoot(op):
            Set(Set(op.properties.keys).union(op.unset).map { .rootOverride(ref: op.refNodeID, key: $0) })
        default:
            nil
        }
    }
}
