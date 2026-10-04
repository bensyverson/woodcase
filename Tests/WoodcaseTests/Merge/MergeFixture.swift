//
//  MergeFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Small .pen builders for the three-way merge tests.
@MainActor
enum MergeFixture {
    /// Parses a document whose root holds `children`, with optional root members.
    static func document(_ children: String, root: String = "") throws -> EditableDocument {
        let members = root.isEmpty ? "" : "\(root),"
        return try EditableDocument(from: PenParser.parse(#"{"version":"2.20",\#(members)"children":[\#(children)]}"#))
    }

    /// Resolves a three-way merge of three documents written as root children.
    static func resolve(
        base: String, ours: String, theirs: String,
        baseRoot: String = "", oursRoot: String = "", theirsRoot: String = ""
    ) throws -> MergeResolution {
        var resolver = try ThreeWayResolver(
            base: document(base, root: baseRoot),
            ours: document(ours, root: oursRoot),
            theirs: document(theirs, root: theirsRoot)
        )
        return resolver.run()
    }

    /// A 10×10 rectangle, with optional extra members.
    static func rect(_ id: String, _ members: String = "") -> String {
        #"{"type":"rectangle","id":"\#(id)","width":10,"height":10\#(members.isEmpty ? "" : ",\(members)")}"#
    }

    /// A frame holding `children`, with optional extra members; `nil` children leaves the key out.
    static func frame(_ id: String, _ children: String? = "", _ members: String = "") -> String {
        let list = children.map { #","children":[\#($0)]"# } ?? ""
        return #"{"type":"frame","id":"\#(id)"\#(members.isEmpty ? "" : ",\(members)")\#(list)}"#
    }

    /// A subtree of `document` as a conflict carries it.
    static func subtree(_ id: String, of document: EditableDocument) throws -> AnyCodable {
        try NodePropertyCodec.encode(document.materializeSubtree(rootID: id))
    }
}
