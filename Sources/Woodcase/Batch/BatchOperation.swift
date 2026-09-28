//
//  BatchOperation.swift
//  Woodcase
//

import Foundation

/// One line of a batch: a single editing operation, written as one JSON object.
///
/// A batch is JSONL — one operation per line, applied in order by
/// ``BatchApplier``. Every operation names its nodes with ``NodeAddress``
/// strings, so a batch can be written entirely in names before any id exists:
///
/// ```jsonl
/// {"op":"add","parent":"Dashboard/Cards","node":{"type":"frame","name":"Hero"},"tag":"hero"}
/// {"op":"set","target":"@hero","props":{"kind.width":240}}
/// ```
///
/// The full grammar — every verb, every field, and the two property
/// vocabularies — is in ``grammar``, which is what `apply --help` prints.
///
/// ## Topics
///
/// ### Verbs
/// - ``Verb``
/// - ``verb``
///
/// ### Parameters
/// - ``SetOp``
/// - ``AddOp``
/// - ``ReplaceOp``
/// - ``CopyOp``
/// - ``MoveOp``
/// - ``RemoveOp``
/// - ``OverrideOp``
/// - ``VariableOp``
/// - ``ThemeAxisOp``
/// - ``ImportOp``
///
/// ### Reading an operation
/// - ``addresses``
/// - ``targetAddress``
/// - ``declaredTag``
/// - ``rev``
/// - ``guards``
/// - ``guardTarget``
/// - ``GuardTarget``
public enum BatchOperation: Friendly {
    /// Set properties on an existing node.
    case set(SetOp)
    /// Insert a new subtree.
    case add(AddOp)
    /// Swap an existing node's subtree for a new one, in place.
    case replace(ReplaceOp)
    /// Copy an existing subtree, or instantiate a reusable component.
    case cp(CopyOp)
    /// Move an existing node to a new parent or position.
    case mv(MoveOp)
    /// Delete a node and its descendants.
    case rm(RemoveOp)
    /// Override a property on a node inside a component instance.
    case override(OverrideOp)
    /// Add or update a document variable.
    case variable(VariableOp)
    /// Add or update a document theme axis.
    case themeAxis(ThemeAxisOp)
    /// Add a library import, or change the path an alias points at.
    case importOp(ImportOp)
}

// MARK: - Verb

public extension BatchOperation {
    /// The `"op"` field: which operation a line is.
    ///
    /// The raw values are the wire spelling — short, and the same words the CLI
    /// uses as verb names (`woodcase cp` writes `{"op":"cp",…}`).
    enum Verb: String, Friendly, CaseIterable {
        /// ``BatchOperation/set(_:)``.
        case set
        /// ``BatchOperation/add(_:)``.
        case add
        /// ``BatchOperation/replace(_:)``.
        case replace
        /// ``BatchOperation/cp(_:)``.
        case cp
        /// ``BatchOperation/mv(_:)``.
        case mv
        /// ``BatchOperation/rm(_:)``.
        case rm
        /// ``BatchOperation/override(_:)``.
        case override
        /// ``BatchOperation/variable(_:)``.
        case variable = "var"
        /// ``BatchOperation/themeAxis(_:)``.
        case themeAxis = "theme-axis"
        /// ``BatchOperation/importOp(_:)``.
        ///
        /// Spelled `importOp` in Swift because `import` is a keyword; the wire word,
        /// and the CLI verb, are both `import`.
        case importOp = "import"
    }

    /// The verb this operation is written with.
    var verb: Verb {
        switch self {
        case .set: .set
        case .add: .add
        case .replace: .replace
        case .cp: .cp
        case .mv: .mv
        case .rm: .rm
        case .override: .override
        case .variable: .variable
        case .themeAxis: .themeAxis
        case .importOp: .importOp
        }
    }
}

// MARK: - Reading an operation

public extension BatchOperation {
    /// Every address the operation names, in the order the applier resolves them.
    ///
    /// This is what the cascade check reads: an operation naming an address a
    /// failed operation poisoned is skipped as
    /// ``BatchLineStatus/cascaded`` rather than attempted.
    var addresses: [NodeAddress] {
        switch self {
        case let .set(op): [op.target]
        case let .add(op): [op.parent].compactMap(\.self)
        case let .replace(op): [op.target]
        case let .cp(op): [op.source] + [op.parent].compactMap(\.self)
        case let .mv(op): [op.target] + [op.parent].compactMap(\.self)
        case let .rm(op): [op.target]
        case let .override(op): [op.target]
        case .variable, .themeAxis, .importOp: []
        }
    }

    /// The address of the node the operation *acts on*, when it names one.
    ///
    /// An ``add(_:)`` or ``cp(_:)`` has none — it acts on a node that does not
    /// exist yet — which is why they carry a ``declaredTag`` instead.
    var targetAddress: NodeAddress? {
        switch self {
        case let .set(op): op.target
        case let .replace(op): op.target
        case let .mv(op): op.target
        case let .rm(op): op.target
        case let .override(op): op.target
        case .add, .cp, .variable, .themeAxis, .importOp: nil
        }
    }

    /// The batch tag this operation declares for the node it creates, if any.
    ///
    /// Only ``add(_:)`` and ``cp(_:)`` create nodes, so only they can declare a
    /// tag. Later lines address that node as `@tag`.
    var declaredTag: String? {
        switch self {
        case let .add(op): op.tag
        case let .cp(op): op.tag
        case .set, .replace, .mv, .rm, .override, .variable, .themeAxis, .importOp: nil
        }
    }

    /// The revision the caller last observed, or `nil` for an unguarded line.
    ///
    /// See ``BatchOperation/grammar`` for which node each verb's `rev` guards.
    var rev: String? {
        switch self {
        case let .set(op): op.rev
        case let .add(op): op.rev
        case let .replace(op): op.rev
        case let .cp(op): op.rev
        case let .mv(op): op.rev
        case let .rm(op): op.rev
        case let .override(op): op.rev
        case .variable, .themeAxis, .importOp: nil
        }
    }

    /// The premises this line asserts at transaction entry, empty for an unguarded one.
    ///
    /// Unlike ``rev``, these are checked once for the whole transaction before any line
    /// runs — see ``BatchGuard``.
    var guards: [BatchGuard] {
        switch self {
        case let .set(op): op.guards
        case let .add(op): op.guards
        case let .replace(op): op.guards
        case let .cp(op): op.guards
        case let .mv(op): op.guards
        case let .rm(op): op.guards
        case let .override(op): op.guards
        case let .variable(op): op.guards
        case let .themeAxis(op): op.guards
        case let .importOp(op): op.guards
        }
    }

    /// What a guard written without a node pins on this line.
    ///
    /// The same scoping ``rev`` has, and for the same reason: the node the line acts on
    /// where there is one, the parent it writes into for a line that creates something,
    /// and the whole document where there is no parent either.
    var guardTarget: GuardTarget {
        switch self {
        case let .set(op): .node(op.target)
        case let .replace(op): .node(op.target)
        case let .mv(op): .node(op.target)
        case let .rm(op): .node(op.target)
        case let .override(op): .node(op.target)
        case let .add(op): op.parent.map(GuardTarget.node) ?? .document
        case let .cp(op): op.parent.map(GuardTarget.node) ?? .document
        case .variable, .themeAxis, .importOp: .nothing
        }
    }

    /// What a bare guard on a line pins.
    ///
    /// A document-level line — a variable, a theme axis, an import — has ``nothing``: it
    /// acts on no node, so a guard on it has to name what it means.
    enum GuardTarget: Friendly {
        /// The node the line acts on, or writes into.
        case node(NodeAddress)

        /// The whole document, for a line that writes at the root.
        case document

        /// No target at all: the line acts on the document's own tables.
        case nothing
    }
}
