//
//  PenImportResolverTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-24.
//

import Foundation
import Testing
import Woodcase

struct PenImportResolverTests {
    // MARK: - Helpers

    /// Makes a minimal reusable component frame node.
    private func makeReusableComponent(
        id: String,
        fill: String? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        var fills: PenFills?
        if let fill {
            fills = .single(.shorthand(fill))
        }
        return PenNode(
            id: id,
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(
                width: .fixed(100),
                height: .fixed(50),
                fills: fills,
                children: children
            ))
        )
    }

    /// Makes a document with optional imports, variables, themes, and children.
    private func makeDocument(
        themes: [String: [String]]? = nil,
        imports: [String: String]? = nil,
        variables: [String: PenVariable]? = nil,
        children: [PenNode] = []
    ) -> PenDocument {
        PenDocument(
            themes: themes,
            imports: imports,
            variables: variables,
            children: children
        )
    }

    // MARK: - Step 1: Basic skeleton tests

    @Test("No-imports document returns unchanged")
    func noImportsPassthrough() {
        let doc = makeDocument(children: [
            PenNode(id: "frame1", common: PenNodeCommon(), kind: .frame(PenNode.FrameData())),
        ])

        let resolved = PenImportResolver.resolve(doc, libraries: [:])

        #expect(resolved.children.count == 1)
        #expect(resolved.children[0].id == "frame1")
        #expect(resolved.imports == nil)
    }

    @Test("Single import merges library's reusable component with alias-prefixed ID")
    func singleImportMergesComponent() {
        let library = makeDocument(children: [
            makeReusableComponent(id: "btnBase", fill: "#FF0000"),
        ])

        let host = makeDocument(
            imports: ["V": "pencil:my-lib.pen"],
            children: [
                PenNode(id: "page1", common: PenNodeCommon(), kind: .frame(PenNode.FrameData())),
            ]
        )

        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:my-lib.pen": library])

        // Host child should still be there
        #expect(resolved.children.contains { $0.id == "page1" })
        // Library component should be merged with prefixed ID
        #expect(resolved.children.contains { $0.id == "V:btnBase" })
        // Imports field should be cleared
        #expect(resolved.imports == nil)
    }

    @Test("Library component's internal ref target is alias-prefixed")
    func refTargetIsPrefixed() {
        // Library has a reusable component that contains a ref to another reusable
        let innerComponent = makeReusableComponent(id: "icon1")
        let outerComponent = PenNode(
            id: "card1",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fixed(100),
                children: [
                    PenNode(
                        id: "ref1",
                        common: PenNodeCommon(),
                        kind: .ref(PenNode.RefData(ref: "icon1"))
                    ),
                ]
            ))
        )

        let library = makeDocument(children: [innerComponent, outerComponent])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])

        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        // Find the outer component
        let card = resolved.children.first { $0.id == "V:card1" }
        #expect(card != nil)

        // The ref inside it should point to V:icon1
        if case let .frame(frameData) = card?.kind,
           let children = frameData.children,
           let refChild = children.first,
           case let .ref(refData) = refChild.kind
        {
            #expect(refData.ref == "V:icon1")
        } else {
            Issue.record("Expected frame with ref child")
        }
    }

    // MARK: - Step 3: Variable and theme merging tests

    @Test("Library variable is merged with alias prefix")
    func libraryVariableMergedWithPrefix() {
        let library = makeDocument(
            variables: [
                "--background": PenVariable(type: .color, value: .simple(.string("#FFFFFF"))),
            ]
        )

        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        #expect(resolved.variables?["V:--background"] != nil)
        if case let .simple(value) = resolved.variables?["V:--background"]?.value {
            #expect(value == .string("#FFFFFF"))
        } else {
            Issue.record("Expected simple variable value")
        }
    }

    @Test("Library themed value conditions are prefixed with alias")
    func themedValueConditionsPrefixed() {
        let library = makeDocument(
            variables: [
                "--bg": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: .string("#FFF"), theme: nil),
                    PenThemedValue(value: .string("#000"), theme: ["Mode": "Dark"]),
                ])),
            ]
        )

        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        let variable = resolved.variables?["V:--bg"]
        #expect(variable != nil)
        if case let .themed(themedValues) = variable?.value {
            // Default (nil theme) should remain nil
            #expect(themedValues[0].theme == nil)
            // "Mode" → "V:Mode"
            #expect(themedValues[1].theme == ["V:Mode": "Dark"])
        } else {
            Issue.record("Expected themed variable value")
        }
    }

    @Test("Library theme axis is merged with alias prefix")
    func themeAxisMergedWithPrefix() {
        let library = makeDocument(
            themes: ["Mode": ["Light", "Dark"]],
            variables: [
                "--bg": PenVariable(type: .color, value: .simple(.string("#FFF"))),
            ]
        )

        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        #expect(resolved.themes?["V:Mode"] == ["Light", "Dark"])
    }

    @Test("Host variables and themes take precedence on conflict")
    func hostWinsOnConflict() {
        let library = makeDocument(
            themes: ["Shared": ["A", "B"]],
            variables: [
                "--shared": PenVariable(type: .color, value: .simple(.string("#LIB"))),
            ]
        )

        let host = makeDocument(
            themes: ["V:Shared": ["X", "Y"]],
            imports: ["V": "pencil:lib.pen"],
            variables: [
                "V:--shared": PenVariable(type: .color, value: .simple(.string("#HOST"))),
            ]
        )

        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        // Host values should win
        if case let .simple(value) = resolved.variables?["V:--shared"]?.value {
            #expect(value == .string("#HOST"))
        } else {
            Issue.record("Expected host variable to win")
        }
        #expect(resolved.themes?["V:Shared"] == ["X", "Y"])
    }

    // MARK: - Step 5: Variable reference prefixing tests

    @Test("PenValue.variable references within library components are prefixed")
    func penValueVariableRefPrefixed() {
        // Library component uses a variable reference for its fill color
        let component = PenNode(
            id: "card1",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fixed(100),
                fills: .single(.color(PenFill.PenColorFill(
                    color: .variable("--background")
                )))
            ))
        )

        let library = makeDocument(children: [component])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        let card = resolved.children.first { $0.id == "V:card1" }
        if case let .frame(data) = card?.kind,
           case let .single(fill) = data.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .variable("V:--background"))
        } else {
            Issue.record("Expected color fill with prefixed variable")
        }
    }

    @Test("Fill shorthand $-variable references within library components are prefixed")
    func fillShorthandVarRefPrefixed() {
        let component = PenNode(
            id: "box1",
            common: PenNodeCommon(reusable: true),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(50),
                height: .fixed(50),
                fills: .single(.shorthand("$--accent"))
            ))
        )

        let library = makeDocument(children: [component])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        let box = resolved.children.first { $0.id == "V:box1" }
        if case let .rectangle(data) = box?.kind,
           case let .single(fill) = data.fills,
           case let .shorthand(str) = fill
        {
            #expect(str == "$V:--accent")
        } else {
            Issue.record("Expected shorthand fill with prefixed variable")
        }
    }

    @Test("Stroke fill variable references within library components are prefixed")
    func strokeFillVarRefPrefixed() {
        let component = PenNode(
            id: "line1",
            common: PenNodeCommon(reusable: true),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100),
                height: .fixed(2),
                stroke: .single(.shorthand("$--border"))
            ))
        )

        let library = makeDocument(children: [component])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        let line = resolved.children.first { $0.id == "V:line1" }
        if case let .rectangle(data) = line?.kind,
           case let .single(fill) = data.stroke,
           case let .shorthand(str) = fill
        {
            #expect(str == "$V:--border")
        } else {
            Issue.record("Expected stroke fill with prefixed variable")
        }
    }

    // MARK: - Step 7: Descendant override key prefixing tests

    @Test("Descendant override keys are prefixed per segment")
    func descendantKeysPrefixed() {
        let component = PenNode(
            id: "card1",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fixed(100),
                children: [
                    PenNode(
                        id: "ref1",
                        common: PenNodeCommon(),
                        kind: .ref(PenNode.RefData(
                            ref: "inner1",
                            descendants: [
                                "KssvD": PenDescendantOverride(properties: ["name": .string("override1")]),
                                "KssvD/jqIIk": PenDescendantOverride(properties: ["name": .string("override2")]),
                            ]
                        ))
                    ),
                ]
            ))
        )

        let library = makeDocument(children: [component])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        let card = resolved.children.first { $0.id == "V:card1" }
        if case let .frame(data) = card?.kind,
           let children = data.children,
           let refChild = children.first,
           case let .ref(refData) = refChild.kind,
           let descendants = refData.descendants
        {
            // Single segment: "KssvD" → "V:KssvD"
            #expect(descendants["V:KssvD"] != nil)
            // Multi-segment: "KssvD/jqIIk" → "V:KssvD/V:jqIIk"
            #expect(descendants["V:KssvD/V:jqIIk"] != nil)
        } else {
            Issue.record("Expected ref with prefixed descendant keys")
        }
    }

    // MARK: - Step 9: Multiple imports and transitive resolution tests

    @Test("Two imports with different aliases are both resolved")
    func twoImportsResolved() {
        let lib1 = makeDocument(children: [makeReusableComponent(id: "btn1")])
        let lib2 = makeDocument(children: [makeReusableComponent(id: "card1")])

        let host = makeDocument(
            imports: ["A": "pencil:lib1.pen", "B": "pencil:lib2.pen"]
        )

        let resolved = PenImportResolver.resolve(host, libraries: [
            "pencil:lib1.pen": lib1,
            "pencil:lib2.pen": lib2,
        ])

        #expect(resolved.children.contains { $0.id == "A:btn1" })
        #expect(resolved.children.contains { $0.id == "B:card1" })
    }

    @Test("A library's own imports are not followed, as in Pen")
    func transitiveImportsNotFollowed() {
        // innerLib has a component
        let innerLib = makeDocument(children: [makeReusableComponent(id: "icon1")])

        // outerLib imports innerLib
        let outerLib = makeDocument(
            imports: ["I": "pencil:inner.pen"],
            children: [
                PenNode(
                    id: "card1",
                    common: PenNodeCommon(reusable: true),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(200),
                        height: .fixed(100),
                        children: [
                            PenNode(
                                id: "ref1",
                                common: PenNodeCommon(),
                                kind: .ref(PenNode.RefData(ref: "I:icon1"))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let host = makeDocument(imports: ["V": "pencil:outer.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: [
            "pencil:outer.pen": outerLib,
            "pencil:inner.pen": innerLib,
        ])

        // outerLib's card1 should be V:card1
        #expect(resolved.children.contains { $0.id == "V:card1" })
        // Pen reads one level of imports: outerLib's own `I` is never loaded, so its
        // ref to I:icon1 — prefixed V:I:icon1 — names no component in either tool.
        #expect(!resolved.children.contains { $0.id == "V:I:icon1" })
    }

    @Test("Circular imports terminate, because a library's imports are not followed")
    func circularImportsDetected() {
        // lib1 imports lib2, lib2 imports lib1
        let lib1 = makeDocument(
            imports: ["B": "pencil:lib2.pen"],
            children: [makeReusableComponent(id: "from1")]
        )
        let lib2 = makeDocument(
            imports: ["A": "pencil:lib1.pen"],
            children: [makeReusableComponent(id: "from2")]
        )

        let host = makeDocument(imports: ["X": "pencil:lib1.pen"])
        // Should not infinite loop — cycle detection stops it
        let resolved = PenImportResolver.resolve(host, libraries: [
            "pencil:lib1.pen": lib1,
            "pencil:lib2.pen": lib2,
        ])

        // The direct import's component arrives...
        #expect(resolved.children.contains { $0.id == "X:from1" })
        // ...and lib1's own import of lib2 is not followed, as in Pen.
        #expect(!resolved.children.contains { $0.id == "X:B:from2" })
    }

    // MARK: - Definitions without a merge

    @Test("definitions(for:libraries:) prefixes a library's reusables without touching the host tree")
    func definitionsArePrefixedAndSeparate() {
        let library = makeDocument(
            themes: ["mode": ["light", "dark"]],
            variables: ["ink": PenVariable(type: .color, value: .simple(.string("#111111")))],
            children: [makeReusableComponent(id: "btn1", fill: "$ink")]
        )
        let host = makeDocument(
            imports: ["V": "lib.pen"],
            children: [PenNode(id: "page1", common: PenNodeCommon(), kind: .frame(PenNode.FrameData()))]
        )

        let definitions = PenImportResolver.definitions(for: host.imports, libraries: ["lib.pen": library])

        #expect(Array(definitions.components.keys) == ["V:btn1"])
        #expect(definitions.variables.keys.sorted() == ["V:ink"])
        #expect(definitions.themes == ["V:mode": ["light", "dark"]])
        // Merged into a document, they bring variables and axes and never a root.
        let merged = definitions.merged(into: host)
        #expect(merged.children.map(\.id) == ["page1"])
        #expect(merged.variables?["V:ink"] != nil)
        #expect(merged.themes?["V:mode"] == ["light", "dark"])
        #expect(merged.imports == host.imports)
    }

    // MARK: - Resolver closure API

    @Test("Resolver closure API works for lazy loading")
    func resolverClosureAPI() throws {
        let library = makeDocument(children: [
            makeReusableComponent(id: "lazy1"),
        ])

        let host = makeDocument(imports: ["L": "pencil:lazy.pen"])
        let resolved = try PenImportResolver.resolve(host) { path in
            if path == "pencil:lazy.pen" {
                return library
            }
            throw ResolverError.notFound
        }

        #expect(resolved.children.contains { $0.id == "L:lazy1" })
    }

    // MARK: - Regression: nested reusable extraction

    @Test("Nested reusable components are not extracted separately from their parent")
    func nestedReusablesNotDuplicated() {
        let innerComponent = makeReusableComponent(id: "icon1")
        let outerComponent = PenNode(
            id: "card1",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fixed(100),
                children: [innerComponent]
            ))
        )

        let library = makeDocument(children: [outerComponent])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        let rootIDs = resolved.children.map(\.id)
        let vIcon1Count = rootIDs.count(where: { $0 == "V:icon1" })
        #expect(vIcon1Count == 0, "Nested reusable V:icon1 should NOT appear as a root-level entry; it is already inside V:card1")

        let vCard1Count = rootIDs.count(where: { $0 == "V:card1" })
        #expect(vCard1Count == 1, "Top-level reusable V:card1 should appear exactly once")
    }

    @Test("Sibling reusable components at the same level are all extracted")
    func siblingReusablesAllExtracted() {
        let comp1 = makeReusableComponent(id: "btn1")
        let comp2 = makeReusableComponent(id: "btn2")
        let container = PenNode(
            id: "page1",
            common: PenNodeCommon(reusable: false),
            kind: .frame(PenNode.FrameData(
                width: .fixed(400),
                height: .fixed(300),
                children: [comp1, comp2]
            ))
        )

        let library = makeDocument(children: [container])
        let host = makeDocument(imports: ["V": "pencil:lib.pen"])
        let resolved = PenImportResolver.resolve(host, libraries: ["pencil:lib.pen": library])

        #expect(resolved.children.contains { $0.id == "V:btn1" })
        #expect(resolved.children.contains { $0.id == "V:btn2" })
    }

    // MARK: - Step 11: Integration test with real fixtures

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    @Test("Banking fixture with the kit library resolves through full pipeline")
    func bankingIntegration() throws {
        let banking = try PenParser.parse(contentsOf: fixtureURL("banking.pen"))
        let kit = try PenParser.parse(contentsOf: fixtureURL("kit.lib.pen"))

        // Verify banking has imports
        #expect(banking.imports?["V"] == "kit.lib.pen")

        // Step 1: Resolve imports
        let resolved = PenImportResolver.resolve(
            banking,
            libraries: ["kit.lib.pen": kit]
        )

        // Imports should be cleared
        #expect(resolved.imports == nil)

        // Library components should be merged with V: prefix
        let prefixedComponents = resolved.children.filter { $0.id.hasPrefix("V:") }
        #expect(prefixedComponents.count > 0, "Expected library components with V: prefix")

        // Library variables should be merged with V: prefix
        let prefixedVars = resolved.variables?.keys.filter { $0.hasPrefix("V:") } ?? []
        #expect(prefixedVars.count > 0, "Expected library variables with V: prefix")

        // Step 2: Expand refs (should now find V:-prefixed components)
        let expanded = PenRefExpander.expand(resolved)

        // Step 3: Resolve variables
        let varResolved = PenVariableResolver.resolve(expanded)

        // Verify the pipeline completed — children should exist
        #expect(varResolved.children.count > 0)
    }
}

private enum ResolverError: Error {
    case notFound
}
