//
//  ThreeWayPropertyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The three-way merge's per-key rules (`project/2026-10-04-three-way-diff-design.md`,
/// algorithm step 2): only theirs changed takes theirs; only ours, or both alike, needs
/// nothing; both differently keeps ours and reports it.
@MainActor
struct ThreeWayPropertyTests {
    private typealias F = MergeFixture

    // MARK: - Node properties

    @Test("A key only theirs changed takes theirs' value")
    func theirsOnly() throws {
        let theirs = try F.document(F.frame("page", F.rect("a", #""opacity":0.5"#)))
        var resolver = try ThreeWayResolver(
            base: F.document(F.frame("page", F.rect("a"))),
            ours: F.document(F.frame("page", F.rect("a"))),
            theirs: theirs
        )
        let result = resolver.run()
        #expect(result.nodes["a"]?.node == theirs.nodes["a"])
        #expect(Set(result.nodes.keys) == ["a"])
        #expect(result.conflicts.isEmpty)
    }

    @Test("A key only ours changed, or both changed alike, needs nothing")
    func oursOnlyOrAlike() throws {
        let oursOnly = try F.resolve(
            base: F.frame("page", F.rect("a")),
            ours: F.frame("page", F.rect("a", #""opacity":0.5"#)),
            theirs: F.frame("page", F.rect("a"))
        )
        #expect(oursOnly.nodes.isEmpty)
        #expect(oursOnly.conflicts.isEmpty)

        let alike = try F.resolve(
            base: F.frame("page", F.rect("a")),
            ours: F.frame("page", F.rect("a", #""opacity":0.5"#)),
            theirs: F.frame("page", F.rect("a", #""opacity":0.5"#))
        )
        #expect(alike.nodes.isEmpty)
        #expect(alike.conflicts.isEmpty)
    }

    @Test("A same-key edit keeps ours and reports base, ours and theirs")
    func sameKeyKeepsOurs() throws {
        let result = try F.resolve(
            base: F.frame("page", F.rect("a", #""name":"Base""#)),
            ours: F.frame("page", F.rect("a", #""name":"Ours""#)),
            theirs: F.frame("page", F.rect("a", #""name":"Theirs""#))
        )
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts == [MergeConflict(
            subject: .property(nodeID: "a", path: "common.name"), kind: .bothChanged,
            base: .string("Base"), ours: .string("Ours"), theirs: .string("Theirs")
        )])
    }

    @Test("Different keys of one node merge, each side's edit kept")
    func differentKeys() throws {
        let result = try F.resolve(
            base: F.frame("page", F.rect("a")),
            ours: F.frame("page", F.rect("a", #""name":"Ours""#)),
            theirs: F.frame("page", F.rect("a", #""opacity":0.5"#))
        )
        let merged = try #require(result.nodes["a"]?.node)
        #expect(merged.common.name == "Ours")
        #expect(merged.common.opacity == .literal(0.5))
        #expect(result.conflicts.isEmpty)
    }

    @Test("Node extras merge per key")
    func extras() throws {
        let result = try F.resolve(
            base: F.frame("page", F.rect("a", #""shared":0"#)),
            ours: F.frame("page", F.rect("a", #""shared":1,"mine":1"#)),
            theirs: F.frame("page", F.rect("a", #""shared":2,"yours":2"#))
        )
        let merged = try #require(result.nodes["a"]?.node)
        #expect(merged.extras["mine"] == .int(1))
        #expect(merged.extras["yours"] == .int(2))
        #expect(merged.extras["shared"] == .int(1))
        #expect(result.conflicts == [MergeConflict(
            subject: .property(nodeID: "a", path: "extras.shared"), kind: .bothChanged,
            base: .int(0), ours: .int(1), theirs: .int(2)
        )])
    }

    // MARK: - Ref overrides

    /// A component with a label, and an instance of it written with `members`.
    private func instance(_ members: String) -> String {
        let component = #"{"type":"frame","id":"comp","reusable":true,"children":[{"type":"text","id":"label","content":"A"}]}"#
        return F.frame("page", #"\#(component),{"type":"ref","id":"inst","ref":"comp"\#(members.isEmpty ? "" : ",\(members)")}"#)
    }

    @Test("Descendant overrides merge per descendant and key")
    func descendantOverrides() throws {
        let result = try F.resolve(
            base: instance(#""descendants":{"label":{"content":"A","name":"N"}}"#),
            ours: instance(#""descendants":{"label":{"content":"B","name":"O"}}"#),
            theirs: instance(#""descendants":{"label":{"content":"A","name":"T","fontSize":20}}"#)
        )
        guard case let .ref(ref)? = result.nodes["inst"]?.node.kind else {
            Issue.record("the instance should change")
            return
        }
        #expect(ref.descendants?["label"]?.properties == ["content": .string("B"), "name": .string("O"), "fontSize": .int(20)])
        #expect(result.conflicts == [MergeConflict(
            subject: .descendantOverride(nodeID: "inst", descendant: "label", key: "name"), kind: .bothChanged,
            base: .string("N"), ours: .string("O"), theirs: .string("T")
        )])
    }

    @Test("Root overrides merge per key")
    func rootOverrides() throws {
        let result = try F.resolve(
            base: instance(#""width":50"#),
            ours: instance(#""width":60"#),
            theirs: instance(#""width":50,"height":70"#)
        )
        guard case let .ref(ref)? = result.nodes["inst"]?.node.kind else {
            Issue.record("the instance should change")
            return
        }
        #expect(ref.rootOverrides == ["width": .int(60), "height": .int(70)])
        #expect(result.conflicts.isEmpty)
    }

    // MARK: - Placement

    @Test("A move only theirs made is taken")
    func theirsMove() throws {
        let result = try F.resolve(
            base: "\(F.frame("page", F.rect("a"))),\(F.frame("side"))",
            ours: "\(F.frame("page", F.rect("a"))),\(F.frame("side"))",
            theirs: "\(F.frame("page")),\(F.frame("side", F.rect("a")))"
        )
        #expect(result.nodes["a"]?.parentID == "side")
        #expect(result.nodes["page"]?.children == [])
        #expect(result.nodes["side"]?.children == ["a"])
        #expect(result.conflicts.isEmpty)
    }

    @Test("Two moves of one node keep ours' and report the parent")
    func bothMove() throws {
        let result = try F.resolve(
            base: "\(F.frame("page", F.rect("a"))),\(F.frame("left")),\(F.frame("right"))",
            ours: "\(F.frame("page")),\(F.frame("left", F.rect("a"))),\(F.frame("right"))",
            theirs: "\(F.frame("page")),\(F.frame("left")),\(F.frame("right", F.rect("a")))"
        )
        #expect(result.nodes["a"] == nil)
        #expect(result.nodes["right"] == nil, "right never gains a")
        #expect(result.conflicts == [MergeConflict(
            subject: .parent(nodeID: "a"), kind: .bothChanged,
            base: .string("page"), ours: .string("left"), theirs: .string("right")
        )])
    }

    @Test("Moves that would nest two nodes in each other keep ours' and report theirs'")
    func crossedMoves() throws {
        let result = try F.resolve(
            base: F.frame("page", "\(F.frame("a")),\(F.frame("b"))"),
            ours: F.frame("page", F.frame("b", F.frame("a"))),
            theirs: F.frame("page", F.frame("a", F.frame("b")))
        )
        #expect(result.nodes["b"] == nil, "b stays where ours has it")
        #expect(result.nodes["a"] == nil)
        #expect(result.conflicts == [MergeConflict(
            subject: .parent(nodeID: "b"), kind: .bothChanged,
            base: .string("page"), ours: .string("page"), theirs: .string("a")
        )])
    }

    @Test("A declared `children: []` only theirs wrote is taken")
    func declaredChildren() throws {
        let result = try F.resolve(
            base: F.frame("page", F.frame("box", nil)),
            ours: F.frame("page", F.frame("box", nil)),
            theirs: F.frame("page", F.frame("box"))
        )
        #expect(result.nodes["box"]?.children == [])
        #expect(result.conflicts.isEmpty)
    }

    // MARK: - Sibling order

    /// A list of one-letter ids as a conflict carries it.
    private func ids(_ letters: String) -> AnyCodable {
        .array(letters.map { .string(String($0)) })
    }

    @Test("A reorder only theirs made is taken; one both made differently keeps ours and is reported")
    func reorders() throws {
        let three = { (order: String) in F.frame("page", order.map { F.rect(String($0)) }.joined(separator: ",")) }
        let theirsOnly = try F.resolve(base: three("abc"), ours: three("abc"), theirs: three("cab"))
        #expect(theirsOnly.nodes["page"]?.children == ["c", "a", "b"])
        #expect(theirsOnly.conflicts.isEmpty)

        let both = try F.resolve(base: three("abc"), ours: three("bac"), theirs: three("cab"))
        #expect(both.nodes["page"] == nil)
        #expect(both.conflicts == [MergeConflict(
            subject: .childOrder(parentID: "page"), kind: .bothChanged,
            base: ids("abc"), ours: ids("bac"), theirs: ids("cab")
        )])
    }

    @Test("The root order merges like a child list")
    func rootOrder() throws {
        let result = try F.resolve(
            base: "\(F.frame("one")),\(F.frame("two"))",
            ours: "\(F.frame("one")),\(F.frame("two")),\(F.frame("mine"))",
            theirs: "\(F.frame("two")),\(F.frame("one"))"
        )
        // mine follows two, its nearest preceding sibling on ours' side
        #expect(result.rootOrder == ["two", "mine", "one"])
    }

    // MARK: - Document keys

    @Test("Document keys follow the same rules: theirs-only is taken, a same-key edit keeps ours")
    func documentKeys() throws {
        let variables = { (shared: String, extra: String) in
            #""variables":{"shared":{"type":"string","value":"\#(shared)"}\#(extra)}"#
        }
        let result = try F.resolve(
            base: F.frame("page"), ours: F.frame("page"), theirs: F.frame("page"),
            baseRoot: variables("base", ""),
            oursRoot: variables("ours", ""),
            theirsRoot: variables("theirs", #","new":{"type":"string","value":"n"}"#) + #","fileToken":"t2""#
        )
        #expect(result.document == [.variable("new"), .fileToken])
        #expect(result.conflicts == [MergeConflict(
            subject: .variable("shared"), kind: .bothChanged,
            base: .dictionary(["type": .string("string"), "value": .string("base")]),
            ours: .dictionary(["type": .string("string"), "value": .string("ours")]),
            theirs: .dictionary(["type": .string("string"), "value": .string("theirs")])
        )])
    }
}
