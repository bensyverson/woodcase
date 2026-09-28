//
//  SwiftUIThemedNumbersRenderTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted SwiftUI with Xcode's toolchain and renders it.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders `render-themed-numbers`'s light and dark boards — a themed shadow blur,
    /// rotation, gradient stop and per-side stroke width — and measures each against Pen's
    /// export beside the Core Graphics renderer's MAE on the same board, gated at CG + 1.0
    /// like ``SwiftUIRenderTests``. A fixed-box board with no baseline, so every kind reading
    /// its variable is proven directly: dropping any one of the four back to a warning draws
    /// visibly different from Pen's export and fails the gate.
    @Suite("SwiftUI themed numbers", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUIThemedNumbersRenderTests {
        /// How far above the CG renderer's MAE a board may land.
        static let fixedBoxMargin = 1.0

        @Test("Each themed board renders within CG + 1.0", arguments: SwiftUIThemedNumbersBatch.boards)
        func boardMatchesPen(board: SwiftUIRenderBoard) async throws {
            TestFontRegistration.registerTestFonts()
            let outcome = try await SwiftUIThemedNumbersBatch.shared.value
            let renders = try #require(outcome.renders, "the batch did not render: \(outcome.buildFailure ?? "")")
            let swiftUI = try #require(PenSnapshotTestHelpers.loadFixtureImage(named: board.id, fixturesDir: renders))
            let reference = try #require(
                PenSnapshotTestHelpers.loadFixtureImage(named: board.referenceName ?? board.id, fixturesDir: SwiftUIFixtures.directory)
            )
            let cgRender = try board.renderCG(scale: CGFloat(board.referenceScale()))
            let cg = try #require(cgRender)

            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: swiftUI, and: reference)
            let cgMAE = PenSnapshotTestHelpers.meanAbsoluteError(between: cg, and: reference)
            let size = "\(swiftUI.width)x\(swiftUI.height) vs \(reference.width)x\(reference.height)"
            print("SwiftUI \(board.id): MAE \(String(format: "%.3f", mae)) (CG \(String(format: "%.3f", cgMAE))) \(size)")

            let limit = cgMAE + Self.fixedBoxMargin
            #expect(mae <= limit, "\(board.id): SwiftUI MAE \(mae), CG \(cgMAE), limit \(limit); \(size)")
            await MAEReport.shared.record(id: "swiftui-\(board.id)", mae: mae, limit: limit)
        }
    }

#endif
