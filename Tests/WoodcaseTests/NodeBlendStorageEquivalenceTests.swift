//
//  NodeBlendStorageEquivalenceTests.swift
//  WoodcaseTests
//

#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Every renderer and emitter draws a node blend stored in `metadata.woodcase.blendMode`
    /// exactly as it drew the top-level `blendMode` it replaces (leaf TesTbK).
    ///
    /// `group-blend.pen` still writes its seven node blends the old way, top-level, as
    /// RapidPro's copy does; this suite moves each into `metadata.woodcase` and requires the
    /// CG render, the SVG export and the React and SwiftUI emits of both spellings to match.
    struct NodeBlendStorageEquivalenceTests {
        private static let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/group-blend.pen")

        /// The fixture as written, and with every node blend moved into metadata.
        private static func spellings() throws -> (topLevel: PenDocument, stored: PenDocument) {
            let data = try Data(contentsOf: fixture)
            let object = try JSONDecoder().decode(AnyCodable.self, from: data)
            let stored = try JSONEncoder().encode(storingNodeBlends(in: object))
            return try (PenParser.parse(data), PenParser.parse(stored))
        }

        /// `value` with each node's top-level `blendMode` moved into `metadata.woodcase`.
        ///
        /// A node object is one with a `type` and an `id`; a paint or a shadow has a `type`
        /// but no `id`, so its own `blendMode` stays where it is.
        private static func storingNodeBlends(in value: AnyCodable) -> AnyCodable {
            switch value {
            case let .array(elements):
                return .array(elements.map(storingNodeBlends))
            case var .dictionary(object):
                for (key, child) in object {
                    object[key] = storingNodeBlends(in: child)
                }
                guard object["id"] != nil, object["type"] != nil, let blend = object.removeValue(forKey: "blendMode") else {
                    return .dictionary(object)
                }
                var metadata: [String: AnyCodable] = if case let .dictionary(existing)? = object["metadata"] { existing } else { [:] }
                var keys: [String: AnyCodable] = if case let .dictionary(existing)? = metadata["woodcase"] { existing } else { [:] }
                keys["blendMode"] = blend
                metadata["woodcase"] = .dictionary(keys)
                metadata["type"] = metadata["type"] ?? .string("woodcase")
                object["metadata"] = .dictionary(metadata)
                return .dictionary(object)
            default:
                return value
            }
        }

        /// How many top-level `blendMode` keys sit on node objects in `value`.
        private static func topLevelNodeBlends(in value: AnyCodable) -> Int {
            switch value {
            case let .array(elements):
                return elements.map(topLevelNodeBlends).reduce(0, +)
            case let .dictionary(object):
                let own = object["id"] != nil && object["blendMode"] != nil ? 1 : 0
                return own + object.values.map(topLevelNodeBlends).reduce(0, +)
            default:
                return 0
            }
        }

        private static func resolved(_ document: PenDocument) -> (PenDocument, [String: PenRect]) {
            let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
            return (resolved, PenLayoutEngine.layout(resolved))
        }

        @Test("The fixture still spells its node blends top-level, and the rewrite moves all seven")
        func fixtureIsTopLevel() throws {
            let object = try JSONDecoder().decode(AnyCodable.self, from: Data(contentsOf: Self.fixture))
            #expect(Self.topLevelNodeBlends(in: object) == 7)
            #expect(Self.topLevelNodeBlends(in: Self.storingNodeBlends(in: object)) == 0)
        }

        @Test("The CG renderer draws both spellings pixel for pixel alike")
        func cgRendersAlike() throws {
            let (topLevel, stored) = try Self.spellings()
            let (oldDocument, oldRects) = Self.resolved(topLevel)
            let (newDocument, newRects) = Self.resolved(stored)
            for root in oldDocument.children {
                let rect = try #require(oldRects[root.id])
                let size = CGSize(width: rect.width, height: rect.height)
                let old = try #require(PenRenderer.render(
                    oldDocument, layoutRects: oldRects, size: size, scale: 2, rootNodeID: root.id
                ))
                let new = try #require(PenRenderer.render(
                    newDocument, layoutRects: newRects, size: size, scale: 2, rootNodeID: root.id
                ))
                let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: old, and: new)
                #expect(mae == 0, "\(root.common.name ?? root.id): MAE \(mae)")
            }
        }

        @Test("The SVG export writes both spellings alike")
        func svgExportsAlike() throws {
            let (topLevel, stored) = try Self.spellings()
            let (oldDocument, oldRects) = Self.resolved(topLevel)
            let (newDocument, newRects) = Self.resolved(stored)
            for root in oldDocument.children {
                let old = SVGExporter.data(oldDocument, layoutRects: oldRects, rootNodeIDs: [root.id], bounds: nil) { _ in nil }
                let new = SVGExporter.data(newDocument, layoutRects: newRects, rootNodeIDs: [root.id], bounds: nil) { _ in nil }
                #expect(old != nil)
                #expect(old == new, "\(root.common.name ?? root.id)")
            }
        }

        @Test("The React and SwiftUI emitters write both spellings alike")
        func emittersWriteAlike() throws {
            let (topLevel, stored) = try Self.spellings()
            func emits(_ document: PenDocument) throws -> [String: String] {
                let components = ComponentAnalyzer.analyze(document)
                let pages = PageAnalyzer.analyze(document)
                let theme = ThemeAnalyzer.analyze(document)
                let react = ReactEmitter.emit(document: document, components: components, pages: pages, theme: theme)
                let swiftUI = try SwiftUIEmitter.emit(document: document, components: components, pages: pages, theme: theme)
                return Dictionary((react.files + swiftUI.files).map { ($0.path, $0.content) }) { first, _ in first }
            }
            let old = try emits(topLevel)
            let new = try emits(stored)
            #expect(old.values.contains { $0.contains("mix-blend-mode") || $0.contains("mixBlendMode") })
            #expect(old.values.contains { $0.contains(".blendMode(.multiply)") })
            #expect(old.keys.sorted() == new.keys.sorted())
            for path in old.keys.sorted() {
                #expect(old[path] == new[path], "\(path)")
            }
        }
    }

#endif
