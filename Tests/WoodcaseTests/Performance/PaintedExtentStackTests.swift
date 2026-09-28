//
//  PaintedExtentStackTests.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Foundation
    import Testing
    @testable import Woodcase

    /// How much stack ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)`` needs in a
    /// debug build.
    ///
    /// A node's painted extent folds in every unclipped descendant's, so it walks the whole
    /// subtree; a recursive walk would need kilobytes of debug frame per level inside a
    /// Swift task's 512 KiB (`project/2026-09-26-debug-stack-depth.md`). It runs from a
    /// work list, and this holds it to a quarter of a task's stack on the deepest tree a
    /// file can hold, as ``TreePipelineStackTests`` does for the read's stages.
    struct PaintedExtentStackTests {
        @Test("The painted extent of a deep frame tree fits in a quarter of a task's stack")
        func deepFrameTree() throws {
            var kept: [Any] = []
            let prepared = try StackHighWater.measure {
                Result { () throws -> (PenNode, PenRect, [String: PenRect]) in
                    let document = try PenParser.parse(Data(DeepDocuments.frameTree(depth: 200).utf8))
                    let rects = PenLayoutEngine.layout(document)
                    kept.append(document)
                    let root = try #require(document.children.first)
                    return try (root, #require(rects[root.id]), rects)
                }
            }.result.get()

            let measured = StackHighWater.measure {
                PenLayoutEngine.paintedExtent(of: prepared.0, rect: prepared.1, layoutRects: prepared.2)
            }

            #expect(measured.bytes < StackHighWater.taskStackSize / 4, "used \(measured.bytes) bytes of stack")
            #expect(measured.result == PenRect(x: 0, y: 0, width: 0, height: 0))
            kept.append(prepared)
            _ = StackHighWater.measure { kept = [] }
        }
    }
#endif
