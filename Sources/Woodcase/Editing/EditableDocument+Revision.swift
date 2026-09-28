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
    /// A component graph may cycle — a definition holding an instance of itself, or of
    /// something that holds one of it. A component already being folded on the current
    /// chain is skipped, and a revision whose computation skipped one is deliberately
    /// **not** memoized, so every cached value is one no cut took part in and therefore
    /// one that does not depend on which node was asked for first.
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
    /// The authored `ref` is the answer for an instance on a page. It is not the whole
    /// answer for an instance that has repointed one of its component's nested refs —
    /// the natural way to say "this tab is the current one" — because what it draws
    /// there is the component it repointed *at*, which its authored payload never
    /// names. Nor for an instance that fills a slot: slot content is a `children` list
    /// inside a `descendants` entry (or the root overrides), stored on the ref as plain
    /// values rather than nodes of the store, and an instance written there draws its
    /// component. So every override value is searched, at any depth, for an object whose
    /// `ref` is a string, and each one names a component folded into the ref's revision.
    /// A name that is no component folds in nothing, so searching wide costs no
    /// precision.
    ///
    /// - Parameter node: The node to read.
    /// - Returns: The component ids, the authored one first, the others sorted so the
    ///   hash never depends on dictionary order. Empty for anything but a `ref`.
    func componentsRendered(by node: PenNode) -> [String] {
        guard case let .ref(refData) = node.kind else { return [] }
        var named: Set<String> = []
        // A work list, not recursion: slot content can nest instances in instances.
        var pending: [AnyCodable] = (refData.descendants ?? [:]).values.map { .dictionary($0.properties) }
        if let rootOverrides = refData.rootOverrides { pending.append(.dictionary(rootOverrides)) }
        while let value = pending.popLast() {
            switch value {
            case let .dictionary(fields):
                if case let .string(target)? = fields["ref"] { named.insert(target) }
                pending.append(contentsOf: fields.values)
            case let .array(items):
                pending.append(contentsOf: items)
            default:
                continue
            }
        }
        return [refData.ref] + named.subtracting([refData.ref]).sorted()
    }

    /// The revision of a node, folding in its subtree and the components it renders.
    ///
    /// A computation that skipped a component because it was already on the chain of
    /// components being folded depends on where the walk started, so it is not
    /// memoized, and neither is anything above it. Everything else is chain-independent
    /// by construction — the chain is read nowhere else — which is what lets a cached
    /// value be returned whatever chain asks for it.
    ///
    /// The fold runs from a work list rather than by recursion: a debug build reserved
    /// 2.2 KB a level, and a deep tree overflowed a Swift task's stack
    /// (`project/2026-09-26-debug-stack-depth.md`). Each node is still finished — and
    /// memoized — before its next sibling starts, as a recursive fold would.
    ///
    /// - Parameter nodeID: The node to hash.
    /// - Returns: The revision, or `nil` for a node that is not in the document.
    private func foldedRevision(of nodeID: String) -> String? {
        var stack: [RevisionFold] = []
        switch beginFold(of: nodeID, folding: []) {
        case let .finished(revision, _): return revision
        case let .pending(fold): stack.append(fold)
        }

        while let last = stack.indices.last {
            guard stack[last].next < stack[last].steps.count else {
                let (revision, cachable) = finishFold(stack.removeLast())
                guard !stack.isEmpty else { return revision }
                stack[stack.count - 1].absorb(revision, cachable: cachable)
                continue
            }
            let step = stack[last].steps[stack[last].next]
            stack[last].next += 1

            let folding: Set<String>
            switch step {
            case .child:
                folding = stack[last].folding
            case let .component(id):
                guard !stack[last].folding.contains(id) else {
                    stack[last].cachable = false
                    continue
                }
                folding = stack[last].folding.union([id])
            }
            switch beginFold(of: step.id, folding: folding) {
            case let .finished(revision, cachable): stack[last].absorb(revision, cachable: cachable)
            case let .pending(fold): stack.append(fold)
            }
        }
        return nil
    }

    /// Starts folding one node: its memoized revision, `nil` for a node not in the
    /// document, or the fold still to run over what it contains.
    private func beginFold(of nodeID: String, folding: Set<String>) -> RevisionFold.Start {
        if let cached = _revisionCache?.entries[nodeID] { return .finished(cached, cachable: true) }
        guard let node = nodes[nodeID] else { return .finished(nil, cachable: true) }

        var hasher = FNV1aHasher()
        hasher.combine(Self.revisionEncoder.encodeCanonical(node))
        let steps = (children[nodeID] ?? []).map(RevisionFold.Step.child)
            + componentsRendered(by: node).map(RevisionFold.Step.component)
        return .pending(RevisionFold(nodeID: nodeID, folding: folding, hasher: hasher, steps: steps))
    }

    /// Ends a node's fold, memoizing the revision when it may be.
    private func finishFold(_ fold: RevisionFold) -> (revision: String, cachable: Bool) {
        let revision = fold.hasher.hexString
        if fold.cachable {
            if _revisionCache == nil {
                _revisionCache = RevisionCache()
            }
            _revisionCache?.store(revision, for: fold.nodeID)
        }
        return (revision, fold.cachable)
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

    /// A `JSONEncoder` that produces canonical bytes for revision hashing: sorted keys, no
    /// whitespace, and a non-throwing strategy for non-conforming floats so revision
    /// computation can never fail on a pathological NaN/Infinity value.
    private static let revisionEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return encoder
    }()
}

extension EditableDocument {
    /// The revision cache, created by the first ``revision(of:)`` and `nil` until then.
    ///
    /// Internal because nothing outside the library should read a revision from
    /// anywhere but ``revision(of:)``, which is what keeps the cached and the computed
    /// answer the same answer.
    var revisionCache: RevisionCache? {
        _revisionCache
    }
}

private extension JSONEncoder {
    /// Encodes a value to canonical JSON bytes, guaranteed not to throw for any
    /// value ``EditableDocument`` stores (see `nonConformingFloatEncodingStrategy`).
    func encodeCanonical(_ value: some Encodable) -> [UInt8] {
        // swiftlint:disable:next force_try
        Array(try! encode(value))
    }
}
