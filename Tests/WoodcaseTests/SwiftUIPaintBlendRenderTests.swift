//
//  SwiftUIPaintBlendRenderTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted SwiftUI with Xcode's toolchain and renders it.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders the SwiftUI emitted for the paint-blend boards and measures each against the
    /// CG renderer — the SwiftUI codegen gate for paint blend modes, beside React's
    /// `ReactPaintBlendWebViewTests` on the same `paint-blend-stacks` boards.
    ///
    /// A paint blends only within its node's paints, fills then strokes, as one isolated
    /// group, and only the node's own blend reaches the backdrop (Ben's reading-1 ruling,
    /// 2026-10-20). Each board is a 120 × 120 white artboard with a colored backdrop and a
    /// blended node over it; `paint-blend-frames` adds a frame with children whose own paints
    /// blend (a child's node blend must still reach past it), a frame's blended outer stroke,
    /// and an ellipse's blended outer stroke over a translucent fill.
    @Suite("SwiftUI paint blend", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUIPaintBlendRenderTests {
        /// The largest MAE each board may score against the CG render, by board id. Limits
        /// follow the margin rule (`project/2026-09-26-mae-margin-rule.md`),
        /// `max(measured × 1.5, measured + 0.25)`, measured 2026-10-22 with
        /// `swift test --filter SwiftUIPaintBlendRenderTests`.
        static let limits: [String: Double] = [
            "paint-blend-stacks-gradient-screen": 0.34, // measured 0.084
            "paint-blend-stacks-softlight-stack": 0.44, // measured 0.188
            // `.plusLighter` is a Porter–Duff plus, as CSS's `plus-lighter` is: over a 40% fill
            // it sums the alphas, and from a 50% source it adds αs·Cs where the renderer mixes
            // the add by αs. React measures the same on these boards.
            "paint-blend-stacks-linear-dodge-translucent": 0.94, // measured 0.625
            "paint-blend-stacks-linear-dodge-half": 4.79, // measured 3.188
            "paint-blend-frames-frame-children": 0.42, // measured 0.167
            "paint-blend-frames-translucent-stroke": 0.42, // measured 0.162
        ]

        /// The limit for a board the table does not name, each measured 0.000–0.001.
        static let defaultLimit = 0.25

        @Test("Each paint-blend board matches the CG render", arguments: SwiftUIPaintBlendBatch.boards)
        func boardMatchesCG(board: SwiftUIRenderBoard) async throws {
            let (swiftUI, cg) = try await Self.images(board)
            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: swiftUI, and: cg)
            print("SwiftUI paint blend \(board.id): MAE \(String(format: "%.3f", mae)) (vs CG)")
            let limit = Self.limits[board.id] ?? Self.defaultLimit
            #expect(mae <= limit, "\(board.id): SwiftUI MAE \(mae) against CG, limit \(limit)")
            await MAEReport.shared.record(id: "swiftui-\(board.id)", mae: mae, limit: limit)
        }

        /// The ruling's plainest case: a blue multiply fill alone on its node blends with
        /// nothing, so it draws blue over the red backdrop, not the multiply's black.
        @Test("A lone multiply fill over red draws blue")
        func loneMultiplyDrawsBlue() async throws {
            let board = try #require(SwiftUIPaintBlendBatch.boards.first { $0.id == "paint-blend-stacks-lone-multiply" })
            let (swiftUI, _) = try await Self.images(board)
            let pixel = try #require(Self.rgba(of: swiftUI, atFraction: 0.5))
            #expect(pixel.r <= 2 && pixel.g <= 2 && pixel.b >= 253, "\(pixel)")
        }

        /// The board's SwiftUI render and the CG renderer's picture of it.
        private static func images(_ board: SwiftUIRenderBoard) async throws -> (swiftUI: CGImage, cg: CGImage) {
            let outcome = try await SwiftUIPaintBlendBatch.shared.value
            let renders = try #require(outcome.renders, "the batch did not render: \(outcome.buildFailure ?? "")")
            let swiftUI = try #require(PenSnapshotTestHelpers.loadFixtureImage(named: board.id, fixturesDir: renders))
            let cgRender = try board.renderCG(scale: CGFloat(SwiftUIPaintBlendBatch.scale))
            return try (swiftUI, #require(cgRender))
        }

        /// The sRGB pixel at the given fraction of `image`'s width and height.
        private static func rgba(of image: CGImage, atFraction fraction: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            let x = Int(Double(width) * fraction), y = Int(Double(height) * fraction)
            let index = (y * width + x) * 4
            return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }
    }

#endif
