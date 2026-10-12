//
//  IncrementalLayoutEquivalenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Proves that incremental layout answers exactly what a full layout of the same
/// document does, over every fixture and a spread of writes (leaf `bDA99O`).
///
/// Each fixture is read once and laid out; then each write lands in turn, the document
/// is laid out incrementally — keeping its rects and measurement cache from the write
/// before, as an editor does — and the result is compared with ``LayoutOracle``, a full
/// layout of a fresh copy. The comparison is exact, rect by rect, and runs on every
/// incremental path: ``EditableDocument/computeLayout(textMeasurer:)``; a host's own
/// pipeline calling
/// ``PenLayoutEngine/layoutIncremental(_:previousRects:invalidation:textMeasurer:options:measurementCache:)``
/// with ``EditableDocument/layoutInvalidation``, as Penumbra does; and a host holding a
/// ``PenLayoutState``, whose reported change must name exactly the rects that differ.
///
/// Text is measured by a deterministic stand-in: the question is which nodes each side
/// laid out, not what Core Text answers.
@MainActor
struct IncrementalLayoutEquivalenceTests {
    /// One representative write.
    enum Write: String, CaseIterable {
        case nudge, editText, resize, reorder, insertChild, disable, theme
        case editDefinition, resizeDefinition, overrideInstance, toggleReusable
        case moveToAnotherRoot, editVariable, addRoot, deleteRoot, deleteChild
    }

    /// Which incremental path lays the document out.
    enum Path: CaseIterable {
        /// ``EditableDocument/computeLayout(textMeasurer:)``.
        case document
        /// A host's pipeline: its own rects and measurement cache, and the engine's call.
        case host
        /// A host holding a ``PenLayoutState``: node-granular, with the change it reports
        /// checked against the rects that actually differ.
        case state
    }

    /// A host pipeline's layout state between runs.
    struct Host {
        var rects: [String: PenRect] = [:]
        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        var state: PenLayoutState?
        /// What is wrong with the last change a ``Path/state`` run reported, if anything.
        var changeProblem: String?
    }

    /// What the comparisons covered, so a corpus that stopped exercising a write fails
    /// rather than passing vacuously.
    struct Coverage {
        var documents = 0
        var comparisons: [Write: Int] = [:]
    }

    /// Writes some fixtures have nothing to apply to, compared less often.
    private static let rarer: Set<Write> = [.theme, .toggleReusable, .resizeDefinition]

    @Test("every write to every fixture lays out exactly what a full layout gives", arguments: Path.allCases)
    func everyFixture(path: Path) throws {
        var coverage = Coverage()
        for url in try FixtureFlatStore.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            coverage.documents += 1
            compareWrites(to: parsed, at: url, path: path, coverage: &coverage)
        }

        #expect(coverage.documents > 100, "Only \(coverage.documents) fixtures parsed.")
        for write in Write.allCases {
            let floor = Self.rarer.contains(write) ? 2 : 10
            #expect(coverage.comparisons[write, default: 0] > floor, "\(write) was compared too rarely.")
        }
    }

    // MARK: - One fixture

    /// Lays a fixture out, then lands each write and compares the incremental layout
    /// after it with a full one.
    private func compareWrites(to parsed: PenDocument, at url: URL, path: Path, coverage: inout Coverage) {
        let measurer = SettledTreeReuseTests.measurer
        let document = PenFileTransaction.editableDocument(from: parsed, at: url, fonts: nil)
        var host = Host()
        _ = layOut(document, path: path, host: &host, measurer: measurer)
        for write in Write.allCases {
            guard (try? apply(write, to: document)) == true else { continue }
            let incremental = layOut(document, path: path, host: &host, measurer: measurer)
            let full = LayoutOracle.fullLayout(of: document, textMeasurer: measurer)
            let differences = LayoutOracle.differences(incremental, full)
            #expect(
                differences.isEmpty,
                "\(url.lastPathComponent) after \(write) (\(path)): \(differences.joined(separator: "; "))"
            )
            #expect(host.changeProblem == nil, "\(url.lastPathComponent) after \(write): \(host.changeProblem ?? "")")
            coverage.comparisons[write, default: 0] += 1
            if !differences.isEmpty {
                // Start the next write from a correct layout, so each failure names its own write.
                resynchronize(document, path: path, host: &host, full: full, measurer: measurer)
            }
        }
    }

    /// Replaces the incremental state with a full layout's.
    private func resynchronize(
        _ document: EditableDocument, path: Path, host: inout Host,
        full: [String: PenRect], measurer: @escaping TextMeasurer
    ) {
        switch path {
        case .document:
            document._layoutCache = nil
            _ = layOut(document, path: path, host: &host, measurer: measurer)
        case .host:
            host = Host(rects: full)
        case .state:
            host = Host()
            _ = layOut(document, path: path, host: &host, measurer: measurer)
        }
    }

    /// Lays the document out by one path and takes its dirty tracking, as a host does.
    private func layOut(
        _ document: EditableDocument, path: Path, host: inout Host, measurer: @escaping TextMeasurer
    ) -> [String: PenRect] {
        switch path {
        case .document:
            document.computeLayout(textMeasurer: measurer)
            let rects = document.layoutRects
            document.clearDirtyNodes()
            return rects
        case .host:
            let invalidation = document.layoutInvalidation
            let resolved = PenVariableResolver.resolve(document.expandedDocument().0)
            document.primeLayoutCache(with: [:])
            document.clearDirtyNodes()
            if host.rects.isEmpty {
                host.rects = PenLayoutEngine.layout(resolved, textMeasurer: measurer)
            } else {
                host.rects = PenLayoutEngine.layoutIncremental(
                    resolved, previousRects: host.rects, invalidation: invalidation,
                    textMeasurer: measurer, measurementCache: &host.measurementCache
                )
            }
            return host.rects
        case .state:
            let invalidation = document.layoutInvalidation
            let resolved = PenVariableResolver.resolve(document.expandedDocument().0)
            document.primeLayoutCache(with: [:])
            document.clearDirtyNodes()
            guard var state = host.state else {
                host.state = PenLayoutState(document: resolved, textMeasurer: measurer)
                return host.state?.rects ?? [:]
            }
            let before = state.rects
            let change = state.update(to: resolved, invalidation: invalidation)
            host.changeProblem = Self.problem(with: change, from: before, to: state.rects)
            host.state = state
            return state.rects
        }
    }

    /// What is wrong with a reported change, or `nil` when it names exactly the ids
    /// whose rect differs and merges over the old rects into the new.
    private static func problem(
        with change: PenLayoutChange, from before: [String: PenRect], to after: [String: PenRect]
    ) -> String? {
        let differing = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        let named = Set(change.rects.keys).union(change.removed)
        if named != differing {
            let extra = named.subtracting(differing).sorted().prefix(4)
            let missing = differing.subtracting(named).sorted().prefix(4)
            return "change names \(Array(extra)) that did not change and misses \(Array(missing))"
        }
        return change.applied(to: before) == after ? nil : "the change does not merge into the new rects"
    }

    // MARK: - The writes

    /// Applies one write, when the document has something it applies to.
    ///
    /// - Returns: `true` when the document was written.
    private func apply(_ write: Write, to document: EditableDocument) throws -> Bool {
        let order = FixtureFlatStore.documentOrder(of: document)
        let placed = order.filter { !FixtureFlatStore.isInsideDefinition($0, in: document) }
        let placedChildren = placed.filter { document.parents[$0] != nil }
        switch write {
        case .nudge:
            guard let node = placedChildren.first else { return false }
            let x = document.nodes[node]?.common.x?.literalValue ?? 0
            try setProperty("common.x", .double(x + 7), on: node, in: document)
        case .editText:
            guard let text = placed.first(where: { FixtureFlatStore.isText($0, in: document) }) else { return false }
            try setProperty("kind.content", .string("An edited text, long enough to wrap"), on: text, in: document)
        case .resize:
            guard let frame = placedChildren.first(where: { FixtureFlatStore.isFrame($0, in: document) }) else { return false }
            try setProperty("kind.width", .double(237), on: frame, in: document)
        case .reorder:
            guard let parent = placed.first(where: { (document.children[$0]?.count ?? 0) > 1 }),
                  let last = document.children[parent]?.last
            else { return false }
            try document.apply(.moveNode(EditOperation.MoveNode(nodeID: last, newParentID: parent, index: 0)))
        case .insertChild:
            guard let frame = placed.first(where: { FixtureFlatStore.isFrame($0, in: document) }) else { return false }
            try document.apply(.insertNode(EditOperation.InsertNode(
                node: PenNode(
                    id: "Ins01", common: PenNodeCommon(),
                    kind: .text(PenNode.TextData(content: .literal("An inserted text")))
                ),
                parentID: frame, index: 0
            )))
        case .disable:
            guard let node = placedChildren.last else { return false }
            try setProperty("common.enabled", .bool(false), on: node, in: document)
        case .theme:
            return try changeTheme(in: document, placed: placed)
        case .editDefinition:
            guard let text = order.first(where: {
                FixtureFlatStore.isText($0, in: document) && FixtureFlatStore.isInsideDefinition($0, in: document)
            }) else { return false }
            try setProperty("kind.content", .string("An edited definition text"), on: text, in: document)
        case .resizeDefinition:
            guard let component = order.first(where: {
                document.nodes[$0]?.common.reusable == true && FixtureFlatStore.isFrame($0, in: document)
            }) else { return false }
            try setProperty("kind.width", .double(333), on: component, in: document)
        case .overrideInstance:
            return try overrideInstance(in: document, placed: placed)
        case .toggleReusable:
            guard let component = document.rootOrder.first(where: { document.nodes[$0]?.common.reusable == true })
            else { return false }
            try setProperty("common.reusable", .bool(false), on: component, in: document)
        case .moveToAnotherRoot:
            guard let node = placedChildren.first,
                  let from = FixtureFlatStore.root(of: node, in: document),
                  let target = document.rootOrder.first(where: { id in
                      id != from && FixtureFlatStore.isFrame(id, in: document) && !FixtureFlatStore.isInsideDefinition(id, in: document)
                  })
            else { return false }
            try document.apply(.moveNode(EditOperation.MoveNode(nodeID: node, newParentID: target)))
        case .editVariable:
            return try editVariable(in: document)
        case .addRoot:
            try document.apply(.insertNode(EditOperation.InsertNode(node: PenNode(
                id: "Add01",
                common: PenNodeCommon(name: "Added", x: .literal(5000), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: nil), height: .fitContent(fallback: nil), layout: .vertical,
                    children: [PenNode(
                        id: "AddT1",
                        common: PenNodeCommon(name: "Added text"),
                        kind: .text(PenNode.TextData(content: .literal("Added text")))
                    )]
                ))
            ))))
        case .deleteChild:
            guard let node = placedChildren.last(where: { document.nodes[$0]?.common.reusable != true })
            else { return false }
            try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: node)))
        case .deleteRoot:
            guard let root = document.rootOrder.first(where: { document.nodes[$0]?.common.reusable != true })
            else { return false }
            try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: root)))
        }
        return true
    }

    /// Pins the first frame on the canvas to a theme value other than the default.
    private func changeTheme(in document: EditableDocument, placed: [String]) throws -> Bool {
        guard let (axis, values) = document.themes?.min(by: { $0.key < $1.key }), values.count > 1,
              let frame = placed.first(where: { FixtureFlatStore.isFrame($0, in: document) })
        else { return false }
        try setProperty("common.theme", .dictionary([axis: .string(values[1])]), on: frame, in: document)
        return true
    }

    /// Overrides the first text an instance on the canvas draws.
    private func overrideInstance(in document: EditableDocument, placed: [String]) throws -> Bool {
        for id in placed {
            guard case let .ref(data) = document.nodes[id]?.kind else { continue }
            let drawn = FixtureFlatStore.subtree(of: data.ref, in: document)
            guard let text = drawn.first(where: { FixtureFlatStore.isText($0, in: document) }) else { continue }
            try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: id, descendantID: text, properties: ["content": .string("Overridden text, rather longer")]
            )))
            return true
        }
        return false
    }

    /// Changes the first variable's value, or adds one to a document without any.
    private func editVariable(in document: EditableDocument) throws -> Bool {
        guard let (name, variable) = document.variables?.min(by: { $0.key < $1.key }) else {
            try document.apply(.addVariable(EditOperation.AddVariable(
                name: "added", variable: PenVariable(type: .number, value: .simple(.int(4)))
            )))
            return true
        }
        var changed = variable
        switch (variable.type, variable.value) {
        case let (.number, .simple(.int(value))): changed.value = .simple(.int(value + 9))
        case let (.number, .simple(.double(value))): changed.value = .simple(.double(value + 9))
        case (.color, _): changed.value = .simple(.string("#123456"))
        case (.string, _): changed.value = .simple(.string("A changed string value"))
        default: changed.value = .simple(.int(12))
            changed.type = .number
        }
        try document.apply(.updateVariable(EditOperation.UpdateVariable(name: name, variable: changed)))
        return true
    }

    private func setProperty(
        _ path: String, _ value: AnyCodable, on node: String, in document: EditableDocument
    ) throws {
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: node, properties: [path: value])))
    }
}
