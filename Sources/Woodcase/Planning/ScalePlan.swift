//
//  ScalePlan.swift
//  Woodcase
//

import Foundation

/// What one step of a proportional scale writes: the edits, and what it could not scale.
///
/// ``ScaleCapture/plan(factor:around:in:)`` makes one. Its ``operations`` are property
/// edits only — `setProperties` on nodes with storage of their own, overrides on the
/// instances that hold the rest — so they preview with
/// ``EditableDocument/previewNodes(for:)`` and commit as one ``LocalEdit``, one undo step.
public struct ScalePlan: Friendly {
    /// A value the scale left as it was because a variable supplies it.
    ///
    /// Scaling a bound value would either unbind it or change the variable, and so every
    /// other node that reads it; the scale does neither and says so, so an editor can tell
    /// the user what did not grow.
    public struct BoundValue: Friendly {
        /// Creates a report of one bound value.
        ///
        /// - Parameters:
        ///   - nodeID: The node, by its id in the expanded document.
        ///   - property: The property path the value sits in, such as `kind.padding`.
        ///   - variable: The variable's name, without `$`.
        public init(nodeID: String, property: String, variable: String) {
            self.nodeID = nodeID
            self.property = property
            self.variable = variable
        }

        /// The node, by its id in the expanded document: a stored node's own id, or
        /// `<ref id>/<key>` inside an instance.
        public var nodeID: String

        /// The property path the bound value sits in — `kind.gap`, or `kind.padding` when
        /// one side of a padding is bound.
        public var property: String

        /// The variable's name, without `$`.
        public var variable: String
    }

    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The edits, in order, to submit as one.
    ///   - unscaled: The values left unscaled because a variable supplies them.
    public init(operations: [EditOperation], unscaled: [BoundValue] = []) {
        self.operations = operations
        self.unscaled = unscaled
    }

    /// The edits, in order, to preview or to submit as one.
    public var operations: [EditOperation]

    /// The values left unscaled because a variable supplies them, in walk order.
    public var unscaled: [BoundValue]
}
