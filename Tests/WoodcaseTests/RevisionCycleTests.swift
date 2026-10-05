//
//  RevisionCycleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A component that renders itself — directly, or through another that renders it — has
/// a revision that is defined once, memoized like any other, and the same whichever node
/// is asked for first.
@MainActor
struct RevisionCycleTests {
    // MARK: - Helpers

    private static func frame(_ id: String, reusable: Bool = false, _ children: [PenNode]) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: id, reusable: reusable ? true : nil), kind: .frame(PenNode.FrameData(children: children)))
    }

    private static func ref(_ id: String, to component: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: id), kind: .ref(PenNode.RefData(ref: component)))
    }

    private static func text(_ id: String, _ content: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: id), kind: .text(PenNode.TextData(content: .literal(content))))
    }

    /// `CmpA` holds an instance of itself; `CmpB` and `CmpC` hold one of each other;
    /// `CmpD` uses `CmpB` without being in its cycle; `Page` holds an instance of each.
    private static let cyclic = PenDocument(children: [
        frame("CmpA", reusable: true, [text("TA", "a"), ref("AinA", to: "CmpA")]),
        frame("CmpB", reusable: true, [text("TB", "b"), frame("BBox", [ref("CinB", to: "CmpC")])]),
        frame("CmpC", reusable: true, [text("TC", "c"), ref("BinC", to: "CmpB")]),
        frame("CmpD", reusable: true, [text("TD", "d"), ref("BinD", to: "CmpB")]),
        frame("Page", [ref("IA", to: "CmpA"), ref("IB", to: "CmpB"), ref("IC", to: "CmpC"), ref("ID", to: "CmpD")]),
    ])

    /// Every node's revision, asked in sorted order after `first`.
    private static func revisions(of document: EditableDocument, askingFirst first: String? = nil) -> [String: String] {
        if let first { _ = document.revision(of: first) }
        return Dictionary(uniqueKeysWithValues: document.allNodeIDs.sorted().compactMap { id in
            document.revision(of: id).map { (id, $0) }
        })
    }

    // MARK: - Tests

    @Test("Every revision in a document with self and mutual component cycles is memoized, whichever node is asked first")
    func cyclicRevisionsAreMemoizedAndEntryIndependent() {
        let reference = EditableDocument(from: Self.cyclic)
        let expected = Self.revisions(of: reference)
        #expect(reference.revisionCache?.entries.count == reference.nodes.count)

        for first in reference.allNodeIDs.sorted() {
            let document = EditableDocument(from: Self.cyclic)
            #expect(Self.revisions(of: document, askingFirst: first) == expected, "asking \(first) first")
        }
    }

    @Test("An edit inside one member of a cycle moves every member, every instance of one, and nothing else")
    func editInsideACycleMovesItsMembers() throws {
        let document = EditableDocument(from: Self.cyclic)
        let before = Self.revisions(of: document)

        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "TC", properties: ["kind.content": "changed"])))
        let after = Self.revisions(of: document)

        for moved in ["TC", "CmpC", "CmpB", "BBox", "CinB", "BinC", "BinD", "CmpD", "IB", "IC", "ID", "Page"] {
            #expect(after[moved] != before[moved], "\(moved) should move")
        }
        for still in ["CmpA", "TA", "AinA", "IA", "TB", "TD"] {
            #expect(after[still] == before[still], "\(still) should not move")
        }
        #expect(document.revisionCache?.entries.count == document.nodes.count)
        #expect(after == Self.revisions(of: EditableDocument(from: document.materialize())))
    }

    /// A document shaped like the one fuzz seed 12581 grew: 2,244 nodes and 228 nested
    /// components, every one of them on a cycle. `C0 … C222` each hold three leaves and
    /// instances of the next two, the last two wrapping round to the first, so the whole
    /// chain is one cyclic group full of diamonds; `Self` holds an instance of itself;
    /// `MA`/`MB` and `MC`/`MD` each hold an instance of the other.
    private static func seed12581Shaped() -> PenDocument {
        let chain = 223
        var roots: [PenNode] = (0 ..< chain).map { index in
            frame("C\(index)", reusable: true, [
                text("C\(index)a", "a\(index)"), text("C\(index)b", "b\(index)"), text("C\(index)c", "c\(index)"),
                ref("C\(index)n1", to: "C\((index + 1) % chain)"), ref("C\(index)n2", to: "C\((index + 2) % chain)"),
            ])
        }
        roots.append(frame("Self", reusable: true, [text("SelfT", "s"), ref("SelfI", to: "Self")]))
        roots.append(frame("MA", reusable: true, [text("MAT", "a"), ref("MAI", to: "MB")]))
        roots.append(frame("MB", reusable: true, [text("MBT", "b"), ref("MBI", to: "MA")]))
        roots.append(frame("MC", reusable: true, [text("MCT", "c"), ref("MCI", to: "MD")]))
        roots.append(frame("MD", reusable: true, [text("MDT", "d"), ref("MDI", to: "MC")]))
        let pageInstances = (0 ..< 890).map { index in
            ref("P\(index)", to: ["C\(index % chain)", "Self", "MA", "MC"][index % 4])
        }
        roots.append(frame("Page", pageInstances))
        return PenDocument(children: roots)
    }

    @Test("A seed-12581-shaped document, with self and mutual component cycles, hashes every node memoized and promptly")
    func seed12581ShapedHashesPromptly() {
        let document = EditableDocument(from: Self.seed12581Shaped())
        #expect(document.nodes.count == 2244)
        #expect(document.componentRegistry.count == 228)

        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = Self.revisions(of: document) }
        #expect(document.revisionCache?.entries.count == document.nodes.count)
        #expect(Self.revisions(of: EditableDocument(from: Self.seed12581Shaped()), askingFirst: "C100") == Self.revisions(of: document))
        // "Not hung" scale: the parallel suite stretches wall time; the figure under no
        // load is in the leaf's report.
        #expect(elapsed < .seconds(30), "every revision took \(elapsed)")
    }
}
