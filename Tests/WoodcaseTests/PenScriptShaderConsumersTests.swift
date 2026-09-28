//
//  PenScriptShaderConsumersTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Covers every consumer the script node and shader fill must pass through
/// unbroken: variable resolution, the CRDT property codec, the editing-layer
/// diff, import-alias prefixing, the React emitter, and the renderer.
@MainActor
struct PenScriptShaderConsumersTests {
    private let peer = PeerID(rawValue: "aaa")

    private func makeCRDT() -> CRDTDocument {
        let node = PenNode(id: "s1", common: PenNodeCommon(), kind: .script(PenNode.ScriptData()))
        let doc = EditableDocument(from: PenDocument(children: [node]))
        return CRDTDocument(peerID: peer, document: doc)
    }

    // MARK: - PenVariableResolver

    @Test("A $ script input resolves to its literal from the variable table")
    func resolvesScriptInputVariable() {
        let document = PenDocument(
            version: "2.17",
            variables: ["rows": PenVariable(type: .number, value: .simple(.double(3)))],
            children: [
                PenNode(
                    id: "s1", common: PenNodeCommon(),
                    kind: .script(PenNode.ScriptData(inputs: ["rows": .variable("rows")]))
                ),
            ]
        )
        let resolved = PenVariableResolver.resolve(document)
        guard case let .script(data) = resolved.children[0].kind else {
            Issue.record("Expected .script")
            return
        }
        #expect(data.inputs?["rows"] == .number(3))
    }

    @Test("A $ script clip flag resolves to its literal")
    func resolvesScriptClipVariable() {
        let document = PenDocument(
            version: "2.17",
            variables: ["shouldClip": PenVariable(type: .boolean, value: .simple(.bool(true)))],
            children: [
                PenNode(
                    id: "s1", common: PenNodeCommon(),
                    kind: .script(PenNode.ScriptData(clip: .variable("shouldClip")))
                ),
            ]
        )
        let resolved = PenVariableResolver.resolve(document)
        guard case let .script(data) = resolved.children[0].kind else {
            Issue.record("Expected .script")
            return
        }
        #expect(data.clip == .literal(true))
    }

    @Test("A $ shader uniform resolves to its literal from the variable table")
    func resolvesShaderUniformVariable() {
        let document = PenDocument(
            version: "2.17",
            variables: ["glow": PenVariable(type: .color, value: .simple(.string("#FF0000")))],
            children: [
                PenNode(
                    id: "r1", common: PenNodeCommon(),
                    kind: .rectangle(PenNode.RectangleData(fills: .single(.shader(
                        PenFill.PenShaderFill(url: "effect.glsl", uniforms: ["glowColor": .variable("glow")])
                    ))))
                ),
            ]
        )
        let resolved = PenVariableResolver.resolve(document)
        guard case let .rectangle(data) = resolved.children[0].kind,
              case let .shader(fill) = data.fills?.all.first
        else {
            Issue.record("Expected a rectangle with a shader fill")
            return
        }
        #expect(fill.uniforms?["glowColor"] == .color("#FF0000"))
    }

    // MARK: - CRDT property codec

    @Test("scriptUri, inputs, and clip round-trip through the property codec")
    func propertyCodecRoundTripsScriptFields() {
        let crdt = makeCRDT()
        let node = PenNode(
            id: "s1", common: PenNodeCommon(),
            kind: .script(PenNode.ScriptData(
                scriptUri: "bars.js",
                inputs: ["rows": .number(3)],
                clip: .literal(true),
                width: .fixed(100),
                height: .fixed(40)
            ))
        )

        for field in ["scriptUri", "inputs", "clip", "width", "height"] {
            let property = "kind.\(field)"
            let extracted = crdt.extractKindValue(property: property, from: node.kind)
            let applied = crdt.applyKindProperty(property: property, value: extracted, to: .script(PenNode.ScriptData()))
            guard case let .script(data) = applied else {
                Issue.record("Expected .script")
                continue
            }
            let reExtracted = crdt.extractKindValue(property: property, from: .script(data))
            #expect(reExtracted == extracted, "Field \(field) did not round-trip")
        }
    }

    // MARK: - Editing-layer diff

    @Test("A width/height change on a script node is categorized as layout")
    func changeCategorySizeIsLayout() {
        let old = PenNode.ScriptData(width: .fixed(100), height: .fixed(40))
        let new = PenNode.ScriptData(width: .fixed(200), height: .fixed(40))
        #expect(ChangeCategory.categorize(oldKind: .script(old), newKind: .script(new)) == .layout)
    }

    @Test("A scriptUri/inputs/clip-only change on a script node is render-only")
    func changeCategoryContentIsRenderOnly() {
        let old = PenNode.ScriptData(scriptUri: "a.js")
        let new = PenNode.ScriptData(scriptUri: "b.js")
        #expect(ChangeCategory.categorize(oldKind: .script(old), newKind: .script(new)) == .renderOnly)
    }

    @Test("PropertyDiff reports every changed script field")
    func propertyDiffReportsScriptFields() {
        let old = PenNode.ScriptData(scriptUri: "a.js", width: .fixed(100))
        let new = PenNode.ScriptData(scriptUri: "b.js", width: .fixed(200))
        let changed = PropertyDiff.diffKind(old: .script(old), new: .script(new))
        #expect(changed == Set(["kind.scriptUri", "kind.width"]))
    }

    // MARK: - Import-alias prefixing

    @Test("A $ script input reference is prefixed with the import alias")
    func prefixesScriptInputVariable() {
        let node = PenNode(
            id: "s1", common: PenNodeCommon(),
            kind: .script(PenNode.ScriptData(inputs: ["rows": .variable("rowCount")], clip: .variable("shouldClip")))
        )
        let prefixed = PenImportPrefixer.prefixNode(node, alias: "V")
        guard case let .script(data) = prefixed.kind else {
            Issue.record("Expected .script")
            return
        }
        #expect(data.inputs?["rows"] == .variable("V:rowCount"))
        #expect(data.clip == .variable("V:shouldClip"))
    }

    @Test("A $ shader uniform reference is prefixed with the import alias")
    func prefixesShaderUniformVariable() {
        let node = PenNode(
            id: "r1", common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shader(
                PenFill.PenShaderFill(url: "effect.glsl", uniforms: ["glowColor": .variable("glow")])
            ))))
        )
        let prefixed = PenImportPrefixer.prefixNode(node, alias: "V")
        guard case let .rectangle(data) = prefixed.kind,
              case let .shader(fill) = data.fills?.all.first
        else {
            Issue.record("Expected a rectangle with a shader fill")
            return
        }
        #expect(fill.uniforms?["glowColor"] == .variable("V:glow"))
    }

    // MARK: - React emitter

    @Test("The React emitter emits an empty, sized placeholder for a script node")
    func emitsScriptPlaceholder() {
        let node = PenNode(
            id: "s1", common: PenNodeCommon(),
            kind: .script(PenNode.ScriptData(scriptUri: "bars.js", width: .fixed(100), height: .fixed(40)))
        )
        guard case let .script(data) = node.kind else { return }
        let ctx = EmitContext()
        ReactEmitter.emitScript(node, data: data, indent: 0, ctx: ctx, isRoot: true)
        let output = ctx.lines.joined(separator: "\n")
        #expect(output.contains("bars.js"))
        #expect(output.contains("<div"))
        #expect(output.contains("100"))
        #expect(output.contains("40"))
    }

    // MARK: - Renderer

    @Test("The renderer draws nothing for a script node")
    func rendererDrawsNothingForScript() throws {
        let document = PenDocument(version: "2.17", children: [
            PenNode(
                id: "s1", common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .script(PenNode.ScriptData(scriptUri: "bars.js", width: .fixed(50), height: .fixed(50)))
            ),
        ])
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: 50, height: 50)
        ))

        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 50, height: 50,
            bitsPerComponent: 8, bytesPerRow: 200,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 50, height: 50))
        let data = try #require(context.data)
        let buffer = data.bindMemory(to: UInt8.self, capacity: 50 * 50 * 4)
        for i in 0 ..< 50 * 50 * 4 {
            #expect(buffer[i] == 0, "Expected a fully transparent image; found non-zero byte at offset \(i)")
        }
    }
}
