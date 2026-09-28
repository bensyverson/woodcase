//
//  TurnedFillSizesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins the boxes ``TurnedFillSizes`` works out for turned `fill_container` children against
/// Pen's settled layout of `render-turned-fill.pen`: each box, turned, is Pen's rect for the
/// child, and a fill sharing a container with one takes Pen's share.
struct TurnedFillSizesTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every board's flex container, and Pen's settled rects.
    private static func fixture() throws -> (containers: [PenNode], pen: [String: PenRect]) {
        let document = try PenParser.parse(Data(contentsOf: fixturesDir.appendingPathComponent("render-turned-fill.pen")))
        let pen = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: fixturesDir.appendingPathComponent("render-turned-fill.layout.json"))
        )
        let containers = document.children.flatMap { board -> [PenNode] in
            guard case let .frame(data) = board.kind else { return [] }
            return data.children ?? []
        }
        return (containers, pen)
    }

    @Test("Each turned fill child's box, turned, is Pen's settled rect for it")
    func boxesMatchPen() throws {
        let (containers, pen) = try Self.fixture()
        var resolved = 0
        for container in containers {
            guard case let .frame(data) = container.kind else { continue }
            let sizes = TurnedFillSizes(container: data)
            for child in data.children ?? [] {
                guard let box = sizes.boxes[child.id], let want = pen[child.id] else { continue }
                let sized = sizes.sized(child)
                let width = try #require(PenLayoutEngine.widthSizing(of: sized).fixedValue, "\(child.id)")
                let height = try #require(PenLayoutEngine.heightSizing(of: sized).fixedValue, "\(child.id)")
                let turned = PenLayoutEngine.rotatedBoundingBox(
                    width: width, height: height, rotationDegrees: child.common.rotation?.literalValue ?? 0
                )
                #expect(abs(turned.width - want.width) < 0.01 && abs(turned.height - want.height) < 0.01,
                        "\(child.id): box \(box), turned \(turned), Pen \(want)")
                resolved += 1
            }
        }
        // Eleven turned children and the unturned fill sharing row-main-two-30's width.
        #expect(resolved == 12)
    }

    @Test("A cross-axis fill in a row that fits its content is left to the layout")
    func fitContentCrossIsUnresolved() throws {
        let (containers, _) = try Self.fixture()
        let container = try #require(containers.first { $0.id == "tf12p" })
        guard case let .frame(data) = container.kind else { throw TestFailure.notAFrame }
        let sizes = TurnedFillSizes(container: data)
        #expect(sizes.unresolved == ["tf12b": .crossSize])
        #expect(sizes.boxes.isEmpty)
    }

    @Test("A turned main-axis fill beside a sibling sized by its content is left to the layout")
    func contentSizedSiblingIsUnresolved() throws {
        let sizes = try Self.sizes(children: [
            ##"{"type": "text", "id": "t", "content": "Hi"}"##,
            ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40, "rotation": 30}"##,
        ])
        #expect(sizes.unresolved == ["b": .share])
        #expect(sizes.boxes.isEmpty)
    }

    @Test("A turned fill child with a variable turn, or a size it fits, is left to the layout", arguments: [
        ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40, "rotation": "$turn"}"##,
        ##"{"type": "frame", "id": "b", "width": "fill_container", "rotation": 30, "layout": "vertical", "children": [{"type": "rectangle", "id": "r", "width": 10, "height": 10}]}"##,
    ])
    func ownSizeIsUnresolved(child: String) throws {
        let sizes = try Self.sizes(children: [child])
        #expect(sizes.unresolved == ["b": .ownSize])
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A container with no turned fill child, or only a half-turned one, sizes nothing", arguments: [
        ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40}"##,
        ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40, "rotation": 180}"##,
        ##"{"type": "rectangle", "id": "b", "width": 60, "height": 40, "rotation": 30}"##,
    ])
    func nothingToSize(child: String) throws {
        let sizes = try Self.sizes(children: [child, ##"{"type": "rectangle", "id": "d", "width": "fill_container", "height": 40}"##])
        #expect(sizes.boxes.isEmpty && sizes.unresolved.isEmpty)
    }

    @Test("A squeezed turned fill takes Pen's 1 pt floor, as the layout engine gives it")
    func squeezedShareIsFloored() throws {
        let sizes = try Self.sizes(children: [
            ##"{"type": "rectangle", "id": "a", "width": 200, "height": 40}"##,
            ##"{"type": "rectangle", "id": "c", "width": 100, "height": 40}"##,
            ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40, "rotation": 30}"##,
        ])
        #expect(sizes.boxes["b"]?.width == PenLayoutEngine.FlexLayout.minimumFillMain)
    }

    /// The sizes of a 300 × 120 row, padding 10, gap 10, holding `children` (JSON).
    private static func sizes(children: [String]) throws -> TurnedFillSizes {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "p", "layout": "horizontal", "width": 300, "height": 120, "padding": 10, "gap": 10, "children": [\##(children.joined(separator: ","))]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        guard case let .frame(data) = try #require(document.children.first).kind else { throw TestFailure.notAFrame }
        return TurnedFillSizes(container: data)
    }

    private enum TestFailure: Error {
        case notAFrame
    }
}
