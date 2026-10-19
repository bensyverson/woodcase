//
//  PenNodeLockedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Whether a node is locked (``PenNode/isLocked``): its `metadata.woodcase.locked` is the
/// boolean `true`, and nothing else locks it (Penumbra spec §14).
struct PenNodeLockedTests {
    /// A rectangle whose `metadata.woodcase` holds `woodcase`, or that has no metadata.
    private func node(woodcase: String?) throws -> PenNode {
        let metadata = woodcase.map { #", "metadata": {"type": "woodcase", "woodcase": {\#($0)}}"# } ?? ""
        let json = #"{"version": "2.19", "children": [{"type": "rectangle", "id": "r", "width": 10, "height": 10\#(metadata)}]}"#
        return try #require(PenParser.parse(Data(json.utf8)).children.first)
    }

    @Test("locked: true locks the node")
    func lockedTrue() throws {
        #expect(try node(woodcase: #""locked": true"#).isLocked)
    }

    @Test("No metadata, no key, or locked: false leaves it unlocked")
    func unlocked() throws {
        #expect(try !node(woodcase: nil).isLocked)
        #expect(try !node(woodcase: "").isLocked)
        #expect(try !node(woodcase: #""locked": false"#).isLocked)
    }

    @Test("A value that is not the boolean true leaves it unlocked", arguments: ["\"true\"", "1", "null", "[true]"])
    func notABoolean(value: String) throws {
        #expect(try !node(woodcase: #""locked": \#(value)"#).isLocked)
    }
}
