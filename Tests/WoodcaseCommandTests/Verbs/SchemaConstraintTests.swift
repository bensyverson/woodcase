//
//  SchemaConstraintTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase schema` prints the constraint each property's values keep to on write.
@Suite("The schema prints value constraints")
struct SchemaConstraintTests {
    @Test("The overview lists the common properties' constraints")
    func commonConstraints() throws {
        let text = try SchemaHelp.text(for: nil)

        #expect(text.contains("CONSTRAINTS"))
        let row = text.split(separator: "\n").first { $0.contains("common.opacity") && $0.contains("0 to 1") }
        #expect(row != nil, "the overview does not print common.opacity's range")
    }

    @Test("A type's table lists its own properties' constraints, every one of them")
    func typeConstraints() throws {
        for type in PenNode.NodeType.allCases {
            let text = try SchemaHelp.text(for: type.rawValue)
            for property in PenSchema.table(for: type).properties {
                guard let constraint = property.constraint else { continue }
                let row = text.split(separator: "\n").first {
                    $0.hasPrefix("  \(property.path) ") && $0.hasSuffix(constraint.summary)
                }
                #expect(row != nil, "schema \(type.rawValue) does not print \(property.path)'s constraint")
            }
        }
    }

    @Test("The JSON carries each row's constraint")
    func jsonConstraint() throws {
        let json = try SchemaHelp.json(for: "text")

        #expect(json.contains(#""constraint" : "> 0, in points""#))
    }
}
