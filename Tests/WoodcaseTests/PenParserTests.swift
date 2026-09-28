//
//  PenParserTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-22.
//

import Foundation
import Testing
import Woodcase

struct PenParserTests {
    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        let nameWithoutExtension = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: nameWithoutExtension, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func loadFixture(_ name: String) throws -> PenDocument {
        let url = try fixtureURL(name)
        return try PenParser.parse(contentsOf: url)
    }

    // MARK: - Empty Document

    @Test("Parses minimal empty document")
    func emptyDocument() throws {
        let doc = try loadFixture("parser-empty-document.pen")
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.children.isEmpty)
        #expect(doc.variables == nil)
        #expect(doc.themes == nil)
        #expect(doc.imports == nil)
    }

    // MARK: - All Node Types

    @Test("Parses all supported node types")
    func allNodeTypes() throws {
        let doc = try loadFixture("parser-all-node-types.pen")
        #expect(doc.children.count == 12)

        // Frame
        let frame = doc.children[0]
        #expect(frame.id == "frame1")
        #expect(frame.common.name == "Container")
        if case let .frame(data) = frame.kind {
            #expect(data.children?.isEmpty == true)
        } else {
            Issue.record("Expected frame kind")
        }

        // Rectangle
        let rect = doc.children[1]
        #expect(rect.id == "rect1")
        if case .rectangle = rect.kind {} else {
            Issue.record("Expected rectangle kind")
        }

        // Ellipse
        let ellipse = doc.children[2]
        #expect(ellipse.id == "ellipse1")
        if case .ellipse = ellipse.kind {} else {
            Issue.record("Expected ellipse kind")
        }

        // Text
        let text = doc.children[3]
        #expect(text.id == "text1")
        if case let .text(data) = text.kind {
            if let value = data.content {
                #expect(value == .literal("Hello World"))
            } else {
                Issue.record("Expected plain text content")
            }
            #expect(data.fontSize == .literal(24))
            #expect(data.fontFamily == .literal("Helvetica"))
        } else {
            Issue.record("Expected text kind")
        }

        // Path
        let path = doc.children[4]
        #expect(path.id == "path1")
        if case let .path(data) = path.kind {
            #expect(data.geometry == "M 0 0 L 100 0 L 50 100 Z")
        } else {
            Issue.record("Expected path kind")
        }

        // Group
        let group = doc.children[5]
        #expect(group.id == "group1")
        #expect(group.common.name == "My Group")
        if case let .group(data) = group.kind {
            #expect(data.children?.isEmpty == true)
        } else {
            Issue.record("Expected group kind")
        }

        // Line
        let line = doc.children[6]
        #expect(line.id == "line1")
        if case .line = line.kind {} else {
            Issue.record("Expected line kind")
        }

        // Polygon
        let polygon = doc.children[7]
        #expect(polygon.id == "polygon1")
        if case let .polygon(data) = polygon.kind {
            #expect(data.polygonCount == .literal(6))
        } else {
            Issue.record("Expected polygon kind")
        }

        // Ref
        let ref = doc.children[8]
        #expect(ref.id == "ref1")
        if case let .ref(data) = ref.kind {
            #expect(data.ref == "frame1")
        } else {
            Issue.record("Expected ref kind")
        }

        // Note
        let note = doc.children[9]
        #expect(note.id == "note1")
        if case let .note(data) = note.kind {
            if let value = data.content {
                #expect(value == .literal("Design note: this is a test layout"))
            } else {
                Issue.record("Expected plain text content in note")
            }
        } else {
            Issue.record("Expected note kind")
        }

        // Prompt
        let prompt = doc.children[10]
        #expect(prompt.id == "prompt1")
        if case let .prompt(data) = prompt.kind {
            #expect(data.model == "claude-3")
        } else {
            Issue.record("Expected prompt kind")
        }

        // Context
        let context = doc.children[11]
        #expect(context.id == "context1")
        if case let .context(data) = context.kind {
            if let value = data.content {
                #expect(value == .literal("This section displays the speaker name"))
            } else {
                Issue.record("Expected plain text content in context")
            }
        } else {
            Issue.record("Expected context kind")
        }
    }

    // MARK: - Nested Children

    @Test("Parses nested frame hierarchy")
    func nestedChildren() throws {
        let doc = try loadFixture("parser-nested-children.pen")
        #expect(doc.children.count == 1)

        guard case let .frame(outerData) = doc.children[0].kind else {
            Issue.record("Expected frame root")
            return
        }
        #expect(outerData.layout == .vertical)
        #expect(outerData.children?.count == 2)

        // Header frame
        guard case let .frame(headerData) = outerData.children?[0].kind else {
            Issue.record("Expected frame header")
            return
        }
        #expect(headerData.layout == .horizontal)
        #expect(headerData.children?.count == 2)

        // Logo rect inside header
        let logo = headerData.children?[0]
        #expect(logo?.id == "logo")
        if case .rectangle = logo?.kind {} else {
            Issue.record("Expected rectangle logo")
        }

        // Body frame
        guard case let .frame(bodyData) = outerData.children?[1].kind else {
            Issue.record("Expected frame body")
            return
        }
        #expect(bodyData.children?.count == 1)
    }

    // MARK: - Fill Types

    @Test("Parses all fill types")
    func fillTypes() throws {
        let doc = try loadFixture("parser-fill-types.pen")
        #expect(doc.children.count == 5)

        // Solid color fill
        guard case let .rectangle(solidData) = doc.children[0].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(fill) = solidData.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .literal("#FF6600"))
        } else {
            Issue.record("Expected single color fill")
        }

        // Linear gradient
        guard case let .rectangle(linearData) = doc.children[1].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(fill) = linearData.fills,
           case let .gradient(gradFill) = fill
        {
            #expect(gradFill.gradientType == .linear)
            #expect(gradFill.rotation == .literal(90))
            #expect(gradFill.colors?.count == 3)
        } else {
            Issue.record("Expected single gradient fill")
        }

        // Radial gradient
        guard case let .rectangle(radialData) = doc.children[2].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(fill) = radialData.fills,
           case let .gradient(gradFill) = fill
        {
            #expect(gradFill.gradientType == .radial)
            #expect(gradFill.colors?.count == 2)
        } else {
            Issue.record("Expected single gradient fill")
        }

        // Angular gradient
        guard case let .rectangle(angularData) = doc.children[3].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(fill) = angularData.fills,
           case let .gradient(gradFill) = fill
        {
            #expect(gradFill.gradientType == .angular)
            #expect(gradFill.colors?.count == 4)
        } else {
            Issue.record("Expected single gradient fill")
        }

        // Image fill
        guard case let .rectangle(imageData) = doc.children[4].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(fill) = imageData.fills,
           case let .image(imgFill) = fill
        {
            #expect(imgFill.url == "https://example.com/texture.png")
            #expect(imgFill.mode == .fill)
        } else {
            Issue.record("Expected single image fill")
        }
    }

    // MARK: - Multiple Fills

    @Test("Parses array of fills on one node")
    func multipleFills() throws {
        let doc = try loadFixture("parser-multiple-fills.pen")
        guard case let .rectangle(data) = doc.children[0].kind else {
            Issue.record("Expected rectangle")
            return
        }

        guard case let .multiple(fills) = data.fills else {
            Issue.record("Expected multiple fills")
            return
        }
        #expect(fills.count == 3)

        // First: color fill
        if case .color = fills[0] {} else {
            Issue.record("Expected color fill at index 0")
        }

        // Second: gradient fill
        if case .gradient = fills[1] {} else {
            Issue.record("Expected gradient fill at index 1")
        }

        // Third: shorthand
        if case let .shorthand(str) = fills[2] {
            #expect(str == "#00FF0080")
        } else {
            Issue.record("Expected shorthand fill at index 2")
        }
    }

    // MARK: - Stroke Variants

    @Test("Parses uniform and per-side strokes, and drops a legacy dash pattern")
    func strokeVariants() throws {
        let doc = try loadFixture("parser-stroke-variants.pen")
        #expect(doc.children.count == 3)

        // Uniform stroke — the legacy `join: "miter"` is the default and is dropped
        guard case let .rectangle(uniformData) = doc.children[0].kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(uniformData.stroke == .single(.shorthand("#000000")))
        #expect(uniformData.strokeAlignment == .inner)
        #expect(uniformData.strokeLinejoin == nil)
        #expect(uniformData.strokeLinecap == .round)
        #expect(uniformData.strokeWidth == .uniform(.literal(2)))

        // Per-side stroke — the legacy `align: "center"` is the default and is dropped
        guard case let .rectangle(perSideData) = doc.children[1].kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(perSideData.stroke == .single(.shorthand("#0000FF")))
        #expect(perSideData.strokeAlignment == nil)
        #expect(perSideData.strokeLinejoin == .bevel)
        if case let .perSide(sides) = perSideData.strokeWidth {
            #expect(sides.top == .literal(1))
            #expect(sides.right == .literal(2))
            #expect(sides.bottom == .literal(3))
            #expect(sides.left == .literal(4))
        } else {
            Issue.record("Expected per-side stroke width")
        }

        // Formerly dashed stroke — 2.17 has no dash pattern, so only the rest survives
        guard case let .rectangle(dashedData) = doc.children[2].kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(dashedData.stroke == .single(.shorthand("#FF0000")))
        #expect(dashedData.strokeAlignment == .outer)
        #expect(dashedData.strokeLinecap == .square)
    }

    // MARK: - Effect Variants

    @Test("Parses shadow, blur, and multiple effects")
    func effectVariants() throws {
        let doc = try loadFixture("parser-effect-variants.pen")
        #expect(doc.children.count == 4)

        // Outer shadow
        guard case let .rectangle(outerShadowData) = doc.children[0].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(effect) = outerShadowData.effects,
           case let .shadow(shadow) = effect
        {
            #expect(shadow.shadowType == .outer)
            #expect(shadow.offset?.x == .literal(4))
            #expect(shadow.offset?.y == .literal(4))
            // The fixture's `spread: 2` is gone: it is a 2.17 file, and format 2.19 has
            // no spread (PenShadowMigrationRule).
            #expect(shadow.extras.isEmpty)
            #expect(shadow.blur == .literal(8))
        } else {
            Issue.record("Expected single outer shadow effect")
        }

        // Inner shadow
        guard case let .rectangle(innerShadowData) = doc.children[1].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(effect) = innerShadowData.effects,
           case let .shadow(shadow) = effect
        {
            // A 2.17 inner shadow reads as outer, as Pen 1.2.14 migrates it: every earlier
            // Pen drew it outside the shape (PenShadowMigrationRule).
            #expect(shadow.shadowType == .outer)
        } else {
            Issue.record("Expected single shadow effect")
        }

        // Blur
        guard case let .rectangle(blurData) = doc.children[2].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .single(effect) = blurData.effects,
           case let .blur(blur) = effect
        {
            #expect(blur.radius == .literal(10))
        } else {
            Issue.record("Expected single blur effect")
        }

        // Multiple effects
        guard case let .rectangle(multiData) = doc.children[3].kind else {
            Issue.record("Expected rectangle")
            return
        }
        if case let .multiple(effects) = multiData.effects {
            #expect(effects.count == 2)
            if case .shadow = effects[0] {} else {
                Issue.record("Expected shadow at index 0")
            }
            if case .blur = effects[1] {} else {
                Issue.record("Expected blur at index 1")
            }
        } else {
            Issue.record("Expected multiple effects")
        }
    }

    // MARK: - Text Content

    @Test("Parses plain text, flattened legacy runs, variable text, and textGrowth modes")
    func textContent() throws {
        let doc = try loadFixture("parser-text-content.pen")
        #expect(doc.children.count == 5)

        // Plain text
        guard case let .text(plainData) = doc.children[0].kind else {
            Issue.record("Expected text kind")
            return
        }
        if let value = plainData.content {
            #expect(value == .literal("Hello World"))
        } else {
            Issue.record("Expected plain content")
        }
        #expect(plainData.textGrowth == .auto)
        #expect(plainData.textAlign == .center)
        #expect(plainData.textAlignVertical == .middle)

        // The fixture's three styled runs, flattened by the version gate into one string
        guard case let .text(richData) = doc.children[1].kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(richData.content == .literal("Bold Italic Colored"))

        // Fixed-width text
        guard case let .text(fixedWidthData) = doc.children[2].kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(fixedWidthData.textGrowth == .fixedWidth)

        // Fixed-width-height text
        guard case let .text(fixedBothData) = doc.children[3].kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(fixedBothData.textGrowth == .fixedWidthHeight)

        // Variable text
        guard case let .text(varData) = doc.children[4].kind else {
            Issue.record("Expected text kind")
            return
        }
        if let value = varData.content {
            #expect(value == .variable("headline"))
        } else {
            Issue.record("Expected plain variable content")
        }
    }

    // MARK: - Variables

    @Test("Parses all four variable types")
    func variables() throws {
        let doc = try loadFixture("parser-variables.pen")
        let vars = try #require(doc.variables)
        #expect(vars.count == 4)

        let boolVar = try #require(vars["showSubtitle"])
        #expect(boolVar.type == .boolean)
        if case let .simple(val) = boolVar.value {
            #expect(val == .bool(true))
        } else {
            Issue.record("Expected simple boolean value")
        }

        let colorVar = try #require(vars["primaryColor"])
        #expect(colorVar.type == .color)
        if case let .simple(val) = colorVar.value {
            #expect(val == .string("#FF6600"))
        } else {
            Issue.record("Expected simple color value")
        }

        let numVar = try #require(vars["spacing"])
        #expect(numVar.type == .number)
        if case let .simple(val) = numVar.value {
            #expect(val == .int(16))
        } else {
            Issue.record("Expected simple number value")
        }

        let strVar = try #require(vars["headline"])
        #expect(strVar.type == .string)
        if case let .simple(val) = strVar.value {
            #expect(val == .string("Breaking News"))
        } else {
            Issue.record("Expected simple string value")
        }
    }

    // MARK: - Themed Variables

    @Test("Parses theme-conditional variable values")
    func themedVariables() throws {
        let doc = try loadFixture("parser-themed-variables.pen")

        // Themes
        let themes = try #require(doc.themes)
        #expect(themes["mode"] == ["light", "dark"])
        #expect(themes["density"] == ["compact", "regular"])

        // Theme-aware color variable
        let bgColor = try #require(doc.variables?["bgColor"])
        #expect(bgColor.type == .color)
        if case let .themed(values) = bgColor.value {
            #expect(values.count == 3)
            #expect(values[0].theme == ["mode": "light"])
            #expect(values[0].value == .string("#FFFFFF"))
            #expect(values[1].theme == ["mode": "dark"])
            #expect(values[1].value == .string("#1A1A1A"))
            #expect(values[2].theme == nil)
            #expect(values[2].value == .string("#F0F0F0"))
        } else {
            Issue.record("Expected themed value")
        }

        // Theme-aware number variable
        let textSize = try #require(doc.variables?["textSize"])
        #expect(textSize.type == .number)
        if case let .themed(values) = textSize.value {
            #expect(values.count == 3)
            #expect(values[0].theme == ["density": "compact"])
        } else {
            Issue.record("Expected themed value")
        }
    }

    // MARK: - Reusable + Ref

    @Test("Parses reusable component and ref with descendant overrides")
    func reusableRef() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        #expect(doc.children.count == 3)

        // Reusable component
        let component = doc.children[0]
        #expect(component.id == "card-component")
        #expect(component.common.reusable == true)

        // Ref with descendant overrides
        let ref1 = doc.children[1]
        #expect(ref1.id == "card-instance1")
        guard case let .ref(refData1) = ref1.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData1.ref == "card-component")
        let descendants1 = try #require(refData1.descendants)
        #expect(descendants1.count == 2)
        #expect(descendants1["card-title"]?.properties["content"] == .string("Custom Title"))

        // Ref with enabled=false override
        let ref2 = doc.children[2]
        guard case let .ref(refData2) = ref2.kind else {
            Issue.record("Expected ref kind")
            return
        }
        let descendants2 = try #require(refData2.descendants)
        #expect(descendants2["card-title"]?.properties["enabled"] == .bool(false))
    }

    // MARK: - Imports

    @Test("Parses import declarations")
    func imports() throws {
        let doc = try loadFixture("parser-imports.pen")
        let imports = try #require(doc.imports)
        #expect(imports.count == 2)
        #expect(imports["designSystem"] == "./design-system.pen")
        #expect(imports["icons"] == "../shared/icons.pen")
    }

    // MARK: - Unknown Properties / Forward Compat

    @Test("Preserves unknown node types and metadata through round-trip")
    func unknownProperties() throws {
        let doc = try loadFixture("parser-unknown-properties.pen")
        #expect(doc.children.count == 2)

        // Known node with metadata
        let knownNode = doc.children[0]
        #expect(knownNode.id == "known-with-extras")
        let metadata = try #require(knownNode.common.metadata)
        #expect(metadata["customKey"] == .string("customValue"))
        #expect(metadata["version"] == .int(2))

        // Unknown node type
        let unknownNode = doc.children[1]
        #expect(unknownNode.id == "future-node")
        #expect(unknownNode.common.name == "My Video")
        #expect(unknownNode.common.opacity == .literal(0.8))
        guard case let .unknown(typeName, properties) = unknownNode.kind else {
            Issue.record("Expected unknown kind")
            return
        }
        #expect(typeName == "video_clip")
        #expect(properties["videoUrl"] == .string("https://example.com/video.mp4"))
        #expect(properties["startTime"] == .int(0))
        #expect(properties["duration"] == .double(10.5))
        #expect(properties["loop"] == .bool(true))
    }

    // MARK: - Context in Hierarchy

    @Test("Parses context nodes alongside visual nodes")
    func contextHierarchy() throws {
        let doc = try loadFixture("parser-context-hierarchy.pen")
        guard case let .frame(rootData) = doc.children[0].kind else {
            Issue.record("Expected frame root")
            return
        }
        let children = try #require(rootData.children)
        #expect(children.count == 4)

        // Context nodes interspersed with visual nodes
        if case let .context(ctxData) = children[0].kind {
            if let value = ctxData.content {
                #expect(value == .literal("Left section: speaker name and title"))
            }
        } else {
            Issue.record("Expected context at index 0")
        }

        if case .frame = children[1].kind {} else {
            Issue.record("Expected frame at index 1")
        }

        if case .context = children[2].kind {} else {
            Issue.record("Expected context at index 2")
        }

        if case .frame = children[3].kind {} else {
            Issue.record("Expected frame at index 3")
        }
    }

    // MARK: - Realistic Lower Third

    @Test("Parses realistic lower-third design with variables and context")
    func realisticLowerThird() throws {
        let doc = try loadFixture("parser-realistic-lower-third.pen")

        // Themes
        #expect(doc.themes?["mode"] == ["light", "dark"])

        // Variables
        let vars = try #require(doc.variables)
        #expect(vars.count == 5)
        #expect(vars["speakerName"]?.type == .string)
        #expect(vars["accentColor"]?.type == .color)

        // Root frame
        guard case let .frame(rootData) = doc.children[0].kind else {
            Issue.record("Expected frame root")
            return
        }
        #expect(rootData.layout == .horizontal)
        #expect(rootData.clip == .literal(true))

        // Corner radius
        if case let .uniform(val) = rootData.cornerRadius {
            #expect(val == .literal(8))
        } else {
            Issue.record("Expected uniform corner radius")
        }

        // Children: context, accent bar, context, text area
        let children = try #require(rootData.children)
        #expect(children.count == 4)

        // Accent bar
        if case .rectangle = children[1].kind {
            #expect(children[1].id == "accent-bar")
        } else {
            Issue.record("Expected rectangle accent bar")
        }

        // Text area frame
        guard case let .frame(textAreaData) = children[3].kind else {
            Issue.record("Expected frame text area")
            return
        }
        #expect(textAreaData.justifyContent == .center)
        #expect(textAreaData.children?.count == 2)

        // Name text uses variable
        if case let .text(nameData) = textAreaData.children?[0].kind {
            if let value = nameData.content {
                #expect(value == .variable("speakerName"))
            }
            #expect(nameData.fontWeight == .literal("700"))
        } else {
            Issue.record("Expected text node for name")
        }
    }

    // MARK: - Round-Trip

    @Test("Round-trip: parse → encode → parse produces equal document",
          arguments: [
              "parser-empty-document.pen",
              "parser-all-node-types.pen",
              "parser-nested-children.pen",
              "parser-fill-types.pen",
              "parser-multiple-fills.pen",
              "parser-stroke-variants.pen",
              "parser-effect-variants.pen",
              "parser-text-content.pen",
              "parser-variables.pen",
              "parser-themed-variables.pen",
              "parser-reusable-ref.pen",
              "parser-imports.pen",
              "parser-unknown-properties.pen",
              "parser-context-hierarchy.pen",
              "parser-realistic-lower-third.pen",
          ])
    func roundTrip(fixture: String) throws {
        let original = try loadFixture(fixture)
        let encoded = try PenParser.encode(original)
        let decoded = try PenParser.parse(encoded)
        #expect(decoded == original, "Round-trip failed for \(fixture)")
    }

    // MARK: - String Parsing

    @Test("Parses document from JSON string")
    func parseString() throws {
        let json = """
        {"version":"2.17","children":[{"id":"r","type":"rectangle","width":50,"height":50}]}
        """
        let doc = try PenParser.parse(json)
        // An older minor is read into the model and reports the model's version.
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.children.count == 1)
        #expect(doc.children[0].id == "r")
    }

    // MARK: - Error Cases

    @Test("Invalid JSON throws decodingFailed")
    func invalidJSON() {
        let data = Data("not valid json".utf8)
        #expect(throws: PenParserError.self) {
            try PenParser.parse(data)
        }
    }

    @Test("Empty data throws decodingFailed")
    func emptyData() {
        let data = Data()
        #expect(throws: PenParserError.self) {
            try PenParser.parse(data)
        }
    }

    @Test("Missing version field is read as a legacy document")
    func missingVersion() throws {
        let json = Data("""
        {"children":[]}
        """.utf8)
        let doc = try PenParser.parse(json)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.children.isEmpty)
    }

    @Test("Missing children field throws decodingFailed")
    func missingChildren() {
        let json = Data("""
        {"version":"2.17"}
        """.utf8)
        #expect(throws: PenParserError.self) {
            try PenParser.parse(json)
        }
    }

    @Test("Non-existent file throws fileReadFailed")
    func nonExistentFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).pen")
        #expect(throws: PenParserError.self) {
            try PenParser.parse(contentsOf: url)
        }
    }

    // MARK: - Errors name their file

    @Test("A file that will not decode names itself, and says why")
    func decodingFailureNamesItsFile() throws {
        let url = try Self.writeTemporary("not json at all")
        defer { try? FileManager.default.removeItem(at: url) }

        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(contentsOf: url)
        }
        guard case let .decodingFailed(errorURL, _)? = thrown else {
            Issue.record("Expected decodingFailed, got \(String(describing: thrown))")
            return
        }
        #expect(errorURL == url)
        #expect(thrown?.url == url)
        #expect(thrown?.description == "Cannot read \(url.path): not a .pen document — The given data was not valid JSON")
    }

    @Test("A key of the wrong type is named by its path, not by Foundation's shrug")
    func decodingFailureNamesTheKey() throws {
        let url = try Self.writeTemporary(#"{"version": "2.17", "children": [{"id": 5}]}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(contentsOf: url)
        }
        #expect(thrown?.description.contains("children[0].id should be a string") == true)
        #expect(thrown?.description.contains("isn’t in the correct format") == false)
    }

    @Test("Bytes with no file behind them name no file")
    func decodingBytesNamesNoFile() {
        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(Data("not json at all".utf8))
        }
        #expect(thrown?.url == nil)
        #expect(thrown?.description.hasPrefix("Cannot read the .pen input:") == true)
    }

    /// Writes `contents` to a uniquely named temporary .pen file.
    private static func writeTemporary(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenParserTests-\(UUID().uuidString).pen")
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Encode to String

    @Test("Encodes document to JSON string")
    func encodeToString() throws {
        let doc = PenDocument(version: "1", children: [])
        let json = try PenParser.encodeToString(doc)
        #expect(json.contains("\"version\""))
        #expect(json.contains("\"children\""))
    }
}
