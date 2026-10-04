//
//  RevisionDeclarednessTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A revision pins the bytes a file writes: a declared-empty child list or document
/// table hashes apart from one the file leaves out.
@MainActor
struct RevisionDeclarednessTests {
    /// Parses a document whose root holds `children`, with optional root members.
    private func document(_ children: String, root: String = "") throws -> EditableDocument {
        let members = root.isEmpty ? "" : "\(root),"
        return try EditableDocument(from: PenParser.parse(#"{"version":"2.20",\#(members)"children":[\#(children)]}"#))
    }

    /// A page holding one container of `type`, written with or without `"children": []`.
    private func page(_ type: String, declared: Bool) -> String {
        let children = declared ? #","children":[]"# : ""
        return #"{"type":"frame","id":"page","children":[{"type":"\#(type)","id":"box"\#(children)}]}"#
    }

    @Test("A declared `children: []` and absent children hash apart, on the node and its ancestors", arguments: ["frame", "group"])
    func declaredEmptyChildren(type: String) throws {
        let declared = try document(page(type, declared: true))
        let absent = try document(page(type, declared: false))
        #expect(declared.revision(of: "box") != absent.revision(of: "box"))
        #expect(declared.revision(of: "page") != absent.revision(of: "page"))
        #expect(declared.documentRevision != absent.documentRevision)
    }

    @Test("Removing a container's last child moves its revision away from the never-declared form")
    func emptiedContainer() throws {
        let emptied = try document(#"{"type":"frame","id":"box","children":[{"type":"rectangle","id":"r"}]}"#)
        _ = emptied.revision(of: "box")
        try emptied.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "r")))
        let declared = try document(#"{"type":"frame","id":"box","children":[]}"#)
        let absent = try document(#"{"type":"frame","id":"box"}"#)
        #expect(emptied.revision(of: "box") == declared.revision(of: "box"))
        #expect(emptied.revision(of: "box") != absent.revision(of: "box"))
    }

    @Test("A declared-empty document table and an absent one hash apart", arguments: [
        #""variables":{}"#, #""imports":{}"#, #""themes":{}"#, #""fonts":[]"#,
    ])
    func declaredEmptyTable(member: String) throws {
        let declared = try document("", root: member)
        let absent = try document("")
        #expect(declared.documentRevision != absent.documentRevision)
    }
}
