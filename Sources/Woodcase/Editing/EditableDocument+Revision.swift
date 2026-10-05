//
//  EditableDocument+Revision.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// A stable content hash for what a node renders, as 16 lowercase hex characters.
    ///
    /// Computed with 64-bit FNV-1a over the canonical JSON encoding of the node
    /// itself (children already stripped in the flat store), then each child's own
    /// revision in ``children`` order, then — for a `ref` node — the revision of every
    /// component it renders. So an edit anywhere in a subtree changes the revision of
    /// every ancestor up to the root, while leaving unrelated siblings untouched.
    /// A container written `"children": []` is hashed with that empty list, so it
    /// differs from one written without the key: equal revisions mean equal bytes.
    ///
    /// Because the hash mixes in the children's revisions, a node's revision is a
    /// pin on its **whole subtree**: two documents whose subtrees under a node hold
    /// the same content agree on that node's revision, whatever else differs about
    /// them, and whatever process computed it.
    ///
    /// ## Instances are pinned by what they draw
    ///
    /// A `ref` stores the component's id and its overrides, not the component — so
    /// hashing only what the file stores under a node would leave a frame full of
    /// instances unmoved by the definition edit that redraws every one of them. The
    /// hash therefore folds in ``revision(of:)`` for the component the ref names, and
    /// for every component one of the ref's own `descendants` overrides *repoints* a
    /// nested ref at (``componentsRendered(by:)``): a rev is a **rendered**-premise
    /// pin, so one token on a frame covers what the frame draws. A definition edit
    /// moves the definition's spine and every instance's spine alike.
    ///
    /// ## Components that render themselves
    ///
    /// A component graph may cycle — a definition holding an instance of itself, or of
    /// something that holds one of it — and then no member can be hashed before the
    /// others. So the members of each cyclic group (``ComponentRenderGraph``) share one
    /// *group revision*: each member is hashed with every reference to a member written
    /// as a marker naming it, and the group revision folds those hashes in id order. A
    /// ref to a member then folds in the group revision with the member's id, where a
    /// ref to any other component folds in that component's revision. An edit inside any
    /// member therefore moves every member and every instance of one, as it would
    /// without the cycle.
    ///
    /// The definition reads only the document — never the order nodes were asked for,
    /// nor the process — so every revision, cyclic or not, is memoized, and a document
    /// with no cycle hashes exactly as it did before cycles had a definition. The fold
    /// finds a cycle when it meets a component already on its chain; it then works out
    /// that component's group, and every group below it, from the graph, and starts
    /// again with those group revisions known.
    ///
    /// This is unrelated to ``contentHash(for:)``: that one mixes in layout
    /// rects and uses Swift's per-process-seeded `Hasher`, so it is neither
    /// content-only nor stable across processes. `revision(of:)` is Foundation-only,
    /// computed on demand, and intended for optimistic-concurrency checks
    /// (see ``apply(_:expecting:)``) that must agree across peers.
    ///
    /// Results are memoized in the ``RevisionCache``, which
    /// ``invalidatingCaches(touching:_:)`` forgets along an edit's spine — so this is
    /// O(subtree) the first time and O(1) afterwards, and a listing that asks for
    /// every node's revision costs one pass over the document rather than one walk
    /// per row.
    ///
    /// - Parameter nodeID: The node to hash.
    /// - Returns: The node's revision, or `nil` if no node with that ID exists.
    func revision(of nodeID: String) -> String? {
        foldedRevision(of: nodeID)
    }

    /// The components a node renders through: the one a `ref` names, and every one its
    /// overrides name — a repoint of a nested ref, or an instance written as slot content
    /// or as a replacement node.
    ///
    /// The authored `ref` is the answer for an instance on a page, but not for one that
    /// has repointed a nested ref or filled a slot, so this is
    /// The node's ``PenNode/renderedComponentIDs``: every override value is searched, at
    /// any depth, for an object whose `ref` is a string, and each one names a component
    /// folded into the ref's revision. A name that is no component folds in nothing, so
    /// searching wide costs no precision. The same list is the edge set of the component
    /// graph whose loops ``componentLoops`` reports.
    ///
    /// - Parameter node: The node to read.
    /// - Returns: The component ids, the authored one first, the others sorted so the
    ///   hash never depends on dictionary order. Empty for anything but a `ref`.
    func componentsRendered(by node: PenNode) -> [String] {
        node.renderedComponentIDs
    }

    /// A stable content hash for the whole document, as 16 lowercase hex characters.
    ///
    /// Computed with 64-bit FNV-1a over each root node's ``revision(of:)``, in
    /// ``rootOrder``, followed by the canonical JSON encoding of ``version``,
    /// ``themes``, ``imports`` and ``variables``, then of ``fonts`` and of the root
    /// ``extras`` when there are any — so a document without them hashes exactly as it
    /// always has. This
    /// is what an activity log records to summarize "the document changed." A node's
    /// extras need no such line: they are part of the node's own canonical encoding.
    var documentRevision: String {
        var hasher = FNV1aHasher()
        for rootID in rootOrder {
            if let rootRevision = revision(of: rootID) {
                hasher.combine(rootRevision)
            }
        }
        hasher.combine(Self.revisionEncoder.encodeCanonical(version))
        hasher.combine(Self.revisionEncoder.encodeCanonical(themes))
        hasher.combine(Self.revisionEncoder.encodeCanonical(imports))
        hasher.combine(Self.revisionEncoder.encodeCanonical(variables))
        if let fonts {
            hasher.combine(Self.revisionEncoder.encodeCanonical(fonts))
        }
        if !extras.isEmpty {
            hasher.combine(Self.revisionEncoder.encodeCanonical(extras))
        }
        return hasher.hexString
    }

    /// Applies an operation, but only if every node it names still matches its expected revision.
    ///
    /// Every entry in `expecting` is checked against the current ``revision(of:)``
    /// before anything is applied: a node absent from the document throws
    /// ``EditingError/nodeNotFound(id:)``, and a mismatched revision throws
    /// ``EditingError/revisionConflict(nodeID:expected:actual:)`` naming the node
    /// and both revisions. Either way the document is left completely unchanged.
    /// Once every entry passes, this delegates to ``apply(_:)``.
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    ///   - expecting: Revisions the caller last observed, keyed by node ID.
    /// - Throws: ``EditingError/nodeNotFound(id:)``, ``EditingError/revisionConflict(nodeID:expected:actual:)``,
    ///   or any error ``apply(_:)`` itself throws.
    func apply(_ operation: EditOperation, expecting: [String: String]) throws {
        try checkExpectedRevisions(expecting)
        try apply(operation)
    }

    /// Applies a local operation, but only if every node it names still matches its expected revision.
    ///
    /// The same guard as ``apply(_:expecting:)``, applied before ``applyLocal(_:)``.
    ///
    /// - Parameters:
    ///   - operation: The local edit operation.
    ///   - expecting: Revisions the caller last observed, keyed by node ID.
    /// - Returns: CRDT operations to replicate to other peers.
    /// - Throws: ``EditingError/nodeNotFound(id:)``, ``EditingError/revisionConflict(nodeID:expected:actual:)``,
    ///   or any error ``applyLocal(_:)`` itself throws.
    func applyLocal(_ operation: EditOperation, expecting: [String: String]) throws -> [CRDTOperation] {
        try checkExpectedRevisions(expecting)
        return try applyLocal(operation)
    }

    /// Validates every expected revision against the document's current state, throwing on
    /// the first mismatch or missing node, before any mutation has taken place.
    private func checkExpectedRevisions(_ expecting: [String: String]) throws {
        for (nodeID, expected) in expecting {
            guard let actual = revision(of: nodeID) else {
                throw EditingError.nodeNotFound(id: nodeID)
            }
            if actual != expected {
                throw EditingError.revisionConflict(nodeID: nodeID, expected: expected, actual: actual)
            }
        }
    }
}

extension EditableDocument {
    /// A `JSONEncoder` that produces canonical bytes for revision hashing: sorted keys, no
    /// whitespace, and a non-throwing strategy for non-conforming floats so revision
    /// computation can never fail on a pathological NaN/Infinity value.
    static let revisionEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return encoder
    }()

    /// The revision cache, created by the first ``revision(of:)`` and `nil` until then.
    ///
    /// Internal because nothing outside the library should read a revision from
    /// anywhere but ``revision(of:)``, which is what keeps the cached and the computed
    /// answer the same answer.
    var revisionCache: RevisionCache? {
        _revisionCache
    }
}

extension JSONEncoder {
    /// Encodes a value to canonical JSON bytes, guaranteed not to throw for any
    /// value ``EditableDocument`` stores (see `nonConformingFloatEncodingStrategy`).
    func encodeCanonical(_ value: some Encodable) -> [UInt8] {
        // swiftlint:disable:next force_try
        Array(try! encode(value))
    }
}
