//
//  PastePlan.swift
//  Woodcase
//

import Foundation

/// What a paste writes: the operations that take a clip into a document, and what they
/// decided along the way.
///
/// ``PenClip/plan(into:at:)`` makes one without touching the document. Apply
/// ``operations`` in order and together — through a ``DocumentSession`` as one
/// ``LocalEdit``, which makes the paste one undo step:
///
/// ```swift
/// let plan = try clip.plan(into: session.document, at: .inside(containerID: "Card1"))
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// select(plan.insertedRootIDs)
/// ```
public struct PastePlan: Friendly {
    /// A name a paste changed so it would not collide with one the target already has.
    public struct Rename: Friendly {
        /// Creates a rename.
        ///
        /// - Parameters:
        ///   - from: The name the clip carried.
        ///   - to: The name it has in the target.
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }

        /// The name the clip carried.
        public var from: String

        /// The name it has in the target.
        public var to: String
    }

    /// Creates a plan from its parts.
    ///
    /// - Parameters:
    ///   - operations: The operations, in the order they apply.
    ///   - insertedRootIDs: The new ids of the copied roots, in clip order.
    ///   - reusedComponents: Clip component id → the target component used in its place.
    ///   - renamedComponents: The components that came along under a new name.
    ///   - reusedVariables: The clip's variables the target already had, sorted.
    ///   - renamedVariables: The variables that came along under a new name.
    public init(
        operations: [EditOperation],
        insertedRootIDs: [String],
        reusedComponents: [String: String] = [:],
        renamedComponents: [Rename] = [],
        reusedVariables: [String] = [],
        renamedVariables: [Rename] = []
    ) {
        self.operations = operations
        self.insertedRootIDs = insertedRootIDs
        self.reusedComponents = reusedComponents
        self.renamedComponents = renamedComponents
        self.reusedVariables = reusedVariables
        self.renamedVariables = renamedVariables
    }

    /// The operations, in the order they apply: theme axes, then variables, then the
    /// component definitions the target lacked (as roots), then the copied roots.
    public var operations: [EditOperation]

    /// The new ids of the copied roots, in clip order — what an editor selects after
    /// the paste.
    public var insertedRootIDs: [String]

    /// Each carried component the target already had, with the same name and the same
    /// definition: clip id → the target's id. Nothing is inserted for one of these; every
    /// instance in the paste points at the target's.
    public var reusedComponents: [String: String]

    /// The components that came along under a new name because the target already had
    /// one by theirs (`Button` → `Button 2`), in the order they are inserted.
    public var renamedComponents: [Rename]

    /// The clip's variables the target already had with the same definition, sorted.
    public var reusedVariables: [String]

    /// The variables that came along under a new name because the target already had a
    /// different one by theirs (`primary` → `primary-2`), sorted by the clip's name.
    public var renamedVariables: [Rename]
}
