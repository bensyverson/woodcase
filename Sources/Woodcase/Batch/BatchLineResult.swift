//
//  BatchLineResult.swift
//  Woodcase
//

import Foundation

/// What happened to one line of a batch.
///
/// One of these per operation, in the order the operations were written, so a
/// caller can print a report that lines up with the file it was given.
public struct BatchLineResult: Friendly {
    /// Creates a line result.
    ///
    /// - Parameters:
    ///   - line: The operation's 0-based index in the batch.
    ///   - status: What became of it.
    ///   - error: Why it failed or cascaded, in one sentence.
    ///   - isRevisionConflict: Whether `error` is a stale-revision refusal.
    ///   - created: The subtrees it created, in the order it made them.
    ///   - path: The full name path of the node it acted on.
    ///   - inverse: Operations that undo this line, in application order.
    ///   - id: The id of the node it acted on.
    ///   - node: That node as the line left it.
    ///   - divergences: How the result differs from the line as it was written.
    public init(
        line: Int,
        status: BatchLineStatus,
        error: String? = nil,
        isRevisionConflict: Bool = false,
        created: [CreatedNode] = [],
        path: String? = nil,
        inverse: [EditOperation] = [],
        id: String? = nil,
        node: PenNode? = nil,
        divergences: [WriteDivergence] = []
    ) {
        self.line = line
        self.status = status
        self.error = error
        self.isRevisionConflict = isRevisionConflict
        self.created = created
        self.path = path
        self.inverse = inverse
        self.id = id
        self.node = node
        self.divergences = divergences
    }

    /// The operation's 0-based index in the batch it came from.
    ///
    /// ``BatchApplier/retry(_:report:to:atomic:identity:recorder:)`` indexes the same
    /// array with it, so it stays put across runs.
    public var line: Int

    /// What became of the line.
    public var status: BatchLineStatus

    /// Why the line failed or cascaded, in one sentence, or `nil` when it applied.
    ///
    /// The sentence names the node by path and says what to do next; see
    /// ``BatchErrorMessage``.
    public var error: String?

    /// Whether `error` is a stale-revision refusal —
    /// ``EditingError/revisionConflict(nodeID:expected:actual:)`` or
    /// ``BatchError/documentRevisionConflict(expected:actual:)`` — rather than any
    /// other reason a line was rejected.
    ///
    /// A caller turning a report into an exit code needs this distinction without
    /// parsing ``error``'s prose: a conflict means "the world moved, re-read and
    /// retry"; every other failure means the batch itself is wrong. Always `false`
    /// for a line that applied or cascaded — only a line that was attempted and
    /// rejected on its own or its parent's revision sets this.
    public var isRevisionConflict: Bool

    /// The subtrees the line created, empty for a line that created nothing.
    ///
    /// Almost every creating line makes exactly one. A `cp` with an `each` list makes
    /// one per row, and they are all here, in row order — the ids a caller cannot get
    /// any other way.
    public var created: [CreatedNode]

    /// The full name path of the node the line acted on, or `nil` for a
    /// document-level line.
    ///
    /// For a line that created a node this is where the node landed; for a
    /// line that changed one, where it was.
    public var path: String?

    /// The operations that undo this line, in the order they should be applied.
    ///
    /// Empty for anything but an ``BatchLineStatus/applied`` line. This is what
    /// an activity log records so the edit can be reversed later; it comes from
    /// ``EditableDocument/prepareInverse(of:)``, captured before each edit ran.
    public var inverse: [EditOperation]

    /// The id of the node the line acted on, or `nil` for a document-level line.
    ///
    /// Present even for a line that removed the node: the id is what was removed, and
    /// a caller reconciling its own model needs it whether or not the node survived.
    public var id: String?

    /// The node as the line left it, or `nil` when the line removed it or acted on the
    /// document rather than a node.
    ///
    /// This is the stored node — the flat-store entry, children stripped — which is the
    /// same shape `woodcase get` prints, so a caller that reads with `get` and writes
    /// with `apply` diffs like against like. The subtree a line *created* is in
    /// ``created``; the structural read is `woodcase tree`.
    public var node: PenNode?

    /// How the result differs from the line as it was written, or empty when it does
    /// not.
    ///
    /// Only ever populated for an ``BatchLineStatus/applied`` line: a line that failed
    /// changed nothing, so it has nothing to diverge from. See ``WriteDivergence``.
    public var divergences: [WriteDivergence]
}
