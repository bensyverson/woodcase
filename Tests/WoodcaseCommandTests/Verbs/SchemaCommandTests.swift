//
//  SchemaCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase schema` — the format's property vocabulary, printed from the decoders.
///
/// The point of the verb is that it cannot lie: everything it prints is read off the
/// same shapes a refusal is built from. So the tests here do not pin prose. They run
/// the binary twice — once for the table, once for the refusal a bogus property
/// raises — and assert the two agree, for **every** node type. A property added to a
/// decoder and left out of the table fails here without anyone editing a fixture.
@Suite("The schema the CLI prints")
struct SchemaCommandTests {
    // MARK: - Fixtures

    /// One node of every type, addressed by id.
    private static let nodeIDs: [PenNode.NodeType: String] = [
        .frame: "NFrme", .group: "NGrup", .rectangle: "NRect", .ellipse: "NElps",
        .path: "NPath", .polygon: "NPoly", .text: "NText", .note: "NNote",
        .prompt: "NPrmt", .context: "NCtxt", .icon: "NIcon", .script: "NScpt",
        .ref: "NRefr", .line: "NLine", .browser: "NBrws", .connection: "NConn",
    ]

    /// The property paths the binary says a node accepts, read off the refusal
    /// `set … kind.bogus=1` raises.
    ///
    /// - Parameters:
    ///   - fixture: The fixture holding the node.
    ///   - id: The node to ask.
    /// - Returns: Every backticked `common.*` or `kind.*` path in the refusal.
    private func acceptedPaths(_ fixture: CommandFixture, _ id: String) throws -> Set<String> {
        let run = try fixture.run("set", fixture.file.path, id, "kind.bogus=1", "--as", "t")
        #expect(run.status == 2, "set \(id) kind.bogus was not refused as a usage error")
        let matches = run.stderr.matches(of: /`((?:common|kind)\.[A-Za-z]+)`/)
        return Set(matches.map { String($0.1) })
    }

    // MARK: - The list of types

    @Test("`woodcase schema` lists every node type with a description")
    func listsEveryType() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema")
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        for type in PenNode.NodeType.allCases {
            let row = run.stdoutLines.first { $0.hasPrefix("  \(type.rawValue) ") }
            #expect(row != nil, "`woodcase schema` does not list \(type.rawValue)")
            #expect(row?.contains(type.summary) == true, "\(type.rawValue) is listed with no description")
        }
    }

    @Test("`woodcase schema` prints the common.* table, paths beside raw keys")
    func listsCommonProperties() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema")
        for row in PenSchema.common.properties {
            let line = run.stdoutLines.first { $0.contains(row.path) }
            #expect(line != nil, "the common table omits \(row.path)")
            #expect(line?.contains(row.key.column) == true, "\(row.path) is printed without its .pen key \(row.key.column)")
            #expect(line?.contains(row.value) == true, "\(row.path) is printed without its value shape")
        }
    }

    // MARK: - One type's table

    @Test("Every type's table lists every path `set` accepts", arguments: PenNode.NodeType.allCases)
    func tableMatchesWhatSetAccepts(type: PenNode.NodeType) throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let id = try #require(Self.nodeIDs[type])
        let accepted = try acceptedPaths(fixture, id)
        let run = try fixture.run("schema", type.rawValue)
        #expect(run.status == 0)

        let printed = Set(PenSchema.table(for: type).properties.map(\.path))
            .union(PenSchema.common.properties.map(\.path))
        #expect(printed == accepted, "the \(type.rawValue) table and its refusal disagree")

        for path in accepted where path.hasPrefix("kind.") {
            #expect(run.stdout.contains(path), "`woodcase schema \(type.rawValue)` omits \(path)")
        }
    }

    @Test("Every enum-valued property prints its spellings", arguments: PenNode.NodeType.allCases)
    func enumPropertiesPrintTheirValues(type: PenNode.NodeType) throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", type.rawValue)
        for property in PenSchema.table(for: type).properties {
            for spelling in property.spellings {
                #expect(
                    run.stdout.contains("\"\(spelling)\""),
                    "\(property.path) never prints its spelling \(spelling)"
                )
            }
        }
    }

    @Test("A text node's growth, alignment and sizing spell their values out")
    func textTableSpellsItsEnumsOut() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "text")
        #expect(run.stdout.contains(##""auto" | "fixed-width" | "fixed-width-height""##))
        #expect(run.stdout.contains(##""fit_content""##))
        #expect(run.stdout.contains(##""fill_container""##))
        // The raw key beside the codec path, for the two that differ.
        let fills = try #require(run.stdoutLines.first { $0.contains("kind.fills") })
        #expect(fills.contains(" fill "), "kind.fills is printed without its .pen key `fill`")
    }

    @Test("A property that takes a $variable says which type of variable")
    func variableTypesAreNamed() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "text")
        let fontSize = try #require(run.stdoutLines.first { $0.contains("kind.fontSize") })
        #expect(fontSize.contains("$number"))
        let content = try #require(run.stdoutLines.first { $0.contains("kind.content") })
        #expect(content.contains("$string"))
        let underline = try #require(run.stdoutLines.first { $0.contains("kind.underline") })
        #expect(underline.contains("$boolean"))
        let fills = try #require(run.stdoutLines.first { $0.contains("kind.fills") })
        #expect(fills.contains("$color"))
    }

    // MARK: - Nesting

    @Test("Nested shapes are recursed, never printed as an opaque object")
    func nestedShapesAreRecursed() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "frame")

        // A fill's variants, with the keys each one carries.
        for spelling in PenFill.fillTypeNames {
            #expect(run.stdout.contains(##""type": "\##(spelling)""##), "the fill table omits \(spelling)")
        }
        #expect(run.stdout.contains("gradientType"), "the gradient fill's keys are not listed")
        #expect(run.stdout.contains("colors"), "a gradient's stops are not listed")

        // A mesh gradient's points: both wire forms, and the object form's keys.
        let points = try #require(run.stdoutLines.first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("points ")
        })
        #expect(points.contains("[[x, y] | mesh point, …]"), "a mesh's points are not spelled out: \(points)")
        #expect(run.stdout.contains("mesh point —"), "the mesh point shape has no table of its own")
        for handle in ["leftHandle", "rightHandle", "topHandle", "bottomHandle"] {
            #expect(run.stdout.contains(handle), "the mesh point table omits \(handle)")
        }

        // An effect's variants.
        for spelling in PenEffect.effectTypeNames {
            #expect(run.stdout.contains(##""type": "\##(spelling)""##), "the effect table omits \(spelling)")
        }

        // strokeWidth's per-side object, spelled out rather than called an object.
        let stroke = try #require(run.stdoutLines.first { $0.contains("kind.strokeWidth") })
        #expect(!stroke.contains("object"), "kind.strokeWidth is printed as an opaque object")
        for side in ["top", "right", "bottom", "left"] {
            #expect(run.stdout.contains(side), "the per-side stroke width omits \(side)")
        }

        // The array-and-scalar unions that are not objects at all.
        let padding = try #require(run.stdoutLines.first { $0.contains("kind.padding") })
        #expect(padding.contains("[vertical, horizontal]"))
        #expect(padding.contains("[top, right, bottom, left]"))
        let radius = try #require(run.stdoutLines.first { $0.contains("kind.cornerRadius") })
        #expect(radius.contains("[topLeft, topRight, bottomRight, bottomLeft]"))
    }

    // MARK: - Shape of the verb

    @Test("`woodcase schema` needs no .pen file")
    func schemaNeedsNoFile() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "text")
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
    }

    @Test("An unknown type is a usage error listing the types")
    func unknownTypeIsUsage() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "textbox")
        #expect(run.status == 2)
        #expect(run.stderr.contains("textbox"))
        #expect(run.stderr.contains("text"))
        #expect(run.stderr.contains("woodcase schema"))
    }

    @Test("--json prints the same tables as a structured object")
    func jsonCarriesTheSameRows() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "text", "--json")
        #expect(run.status == 0)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        #expect(object["type"] as? String == "text")
        let properties = try #require(object["properties"] as? [[String: Any]])
        let paths = Set(properties.compactMap { $0["path"] as? String })
        #expect(paths == Set(PenSchema.table(for: .text).properties.map(\.path)))
        let content = try #require(properties.first { $0["path"] as? String == "kind.content" })
        #expect(content["key"] as? String == "content")
        #expect(content["variable"] as? String == "string")
        #expect(object["nested"] != nil)
    }

    @Test("`woodcase schema --json` with no type carries the types and the common table")
    func jsonOverviewCarriesTypesAndCommon() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "--json")
        #expect(run.status == 0)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        let types = try #require(object["types"] as? [[String: Any]])
        #expect(Set(types.compactMap { $0["type"] as? String }) == Set(PenNode.NodeType.allCases.map(\.rawValue)))
        #expect(object["common"] != nil)
    }

    // MARK: - Format 2.19

    @Test("`help schema` lists browser, fonts and connection, and spread nowhere")
    func helpSchemaSpeaks219() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let overview = try fixture.run("help", "schema")
        #expect(overview.status == 0)
        #expect(overview.stdoutLines.contains { $0.hasPrefix("  browser ") })
        #expect(overview.stdoutLines.contains { $0.hasPrefix("  connection ") })
        #expect(overview.stdoutLines.contains { $0.hasPrefix("  fonts ") }, "no fonts table:\n\(overview.stdout)")
        for key in ["name*", "url*", "style", "weight"] {
            #expect(overview.stdout.contains(key), "the fonts table omits \(key)")
        }
        for type in PenNode.NodeType.allCases {
            let table = try fixture.run("help", "schema", type.rawValue)
            #expect(!table.stdout.contains("spread"), "`help schema \(type.rawValue)` still offers spread")
        }
        #expect(!overview.stdout.contains("spread"))
    }

    @Test("A connection's table names its endpoints and the anchors they take")
    func connectionTableNamesAnchors() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "connection")
        #expect(run.status == 0)
        for word in ["kind.source", "kind.target", "path*", "anchor*", #""center""#, #""right""#] {
            #expect(run.stdout.contains(word), "`schema connection` omits \(word):\n\(run.stdout)")
        }
    }

    @Test("`schema --json` carries the root fonts table")
    func jsonOverviewCarriesFonts() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "--json")
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        let root = try #require(object["root"] as? [[String: Any]])
        #expect(root.contains { $0["name"] as? String == "fonts" })
    }

    // MARK: - Reachable through help

    @Test("`woodcase help schema` prints the same overview the verb does")
    func helpSchemaIsTheVerb() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let viaHelp = try fixture.run("help", "schema")
        let viaVerb = try fixture.run("schema")
        #expect(viaHelp.status == 0)
        #expect(viaHelp.stdout == viaVerb.stdout)
    }

    @Test("`woodcase help schema text` prints the same table the verb does")
    func helpSchemaTypeIsTheVerb() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let viaHelp = try fixture.run("help", "schema", "text")
        let viaVerb = try fixture.run("schema", "text")
        #expect(viaHelp.status == 0)
        #expect(viaHelp.stdout == viaVerb.stdout)
    }

    @Test("The primer routes to help schema beside help design")
    func primerNamesSchema() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run([])
        #expect(run.stdout.contains("woodcase help schema"))
        #expect(run.stdout.contains("woodcase help design"))
        #expect(run.stdout.contains("  read"))
        let read = try #require(run.stdoutLines.first { $0.hasPrefix("  read") })
        #expect(read.contains("schema"), "the primer does not group schema with the read verbs")
    }

    @Test("`woodcase help` lists schema among the topics")
    func helpListsSchemaTopic() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("help")
        #expect(run.status == 0)
        #expect(run.stdout.contains("schema"))
    }
}
