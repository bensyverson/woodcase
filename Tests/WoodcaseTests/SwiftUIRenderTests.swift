//
//  SwiftUIRenderTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted SwiftUI with Xcode's toolchain and renders it.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Compiles every emitted fixture page, renders it with `ImageRenderer`, and measures it
    /// against Pen's own export beside the Core Graphics renderer's MAE on the same board.
    ///
    /// Two gates, per Ben's layout ruling (idiomatic stacks, intent over pixels): a board
    /// of fixed boxes must land within the CG renderer's MAE + 1.0, because there stacks
    /// and flexbox agree exactly; a board where stack negotiation differs from flexbox has
    /// its measured MAE recorded in ``baselines`` with the reason, and fails only when it
    /// regresses past that. The compile is one batch for the whole run
    /// (``SwiftUIRenderBatch``); a compile error fails these tests with the compiler's
    /// diagnostics rather than breaking the build.
    @Suite("SwiftUI render", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUIRenderTests {
        /// Boards not held to CG + 1.0 — where SwiftUI's stack negotiation differs from
        /// Pen's flexbox, where SwiftUI cannot draw what Pen does, or where another slice's
        /// property is still missing — keyed by ``SwiftUIRenderBoard/id``, with the MAE
        /// each measured when recorded and why.
        ///
        /// Recorded 2026-09-26, Xcode 27.0, macOS 27.0, with Inter from `Tests/WoodcaseTests/Fonts`.
        static let baselines: [String: (mae: Double, why: String)] = [
            // Background blur is a Material by design: SwiftUI has no backdrop blur of a set
            // radius, so these never reach Pen's Gaussian. The harness pins the light scheme,
            // which a Material's tint follows.
            "render-background-blur-flip": (29.32, "background blur is a Material"),
            "render-background-blur-r8": (25.62, "background blur is a Material"),
            "blur1": (7.95, "background blur is a Material"),
            "blur3": (10.38, "background blur is a Material"),
            "blur2": (8.35, "background blur is a Material"),
            // A turned fill_container child whose box only the layout knows — here a cross-axis
            // fill in a row that fits its content — keeps a flexible frame, which takes all the
            // height the board offers, and generating it warns (leaf ozlazY, 2026-09-28, same
            // toolchain); every other `render-turned-fill` board gates at CG + 1.0.
            "render-turned-fill-row-cross-fit-30": (23.04, "turned fill whose box only the layout knows: a flexible frame"),
        ]

        /// Boards held *below* CG + 1.0, keyed like ``baselines``, with the MAE each
        /// measured when recorded and why.
        ///
        /// The `render-text-line-height` boards are not here: since the CG renderer places
        /// explicit line heights as Pen does (leaf HVBKsf), they gate at CG + 1.0.
        static let ceilings: [String: (mae: Double, why: String)] = [
            // Lines at Pen's natural pitch (leaf 97Dngc): at SwiftUI's own pitch, render-text
            // measured 2.13 and the natural-line-height board 0.25. Recorded 2026-09-27, same toolchain.
            "render-text": (1.04, "tighter than CG + 1.0; CG scores 0.89 on it since HVBKsf"),
            "text-natural-line-height": (0.21, "tighter than CG + 1.0; CG scores 0.21 on it since HVBKsf"),
            // Material Symbols at the font's default optical size, as Pen draws it (leaf 6vLFNQ):
            // 0.84 while Core Text moved `opsz` to the point size. Recorded 2026-09-27, same toolchain.
            "parser-icon-font": (0.18, "tighter than CG + 1.0; CG scores 0.89 on it"),
            // Outer shadows cast by the stroke band as well as the shape (leaf vPZ0ia): before it,
            // sizeless-frames-paint measured 0.329, outer-and-inner 0.600, and each stroke-shadows
            // board with a band outside its shape 4.4–14.1. Recorded 2026-09-28, same toolchain.
            "render-sizeless-frames-paint": (0.01, "tighter than CG + 1.0; CG scores 0.008"),
            "render-shadows-outer-and-inner": (0.19, "tighter than CG + 1.0; CG scores 0.234"),
            "render-stroke-shadows-rect-outer": (0.09, "tighter than CG + 1.0; CG scores 0.109"),
            "render-stroke-shadows-rect-center": (0.08, "tighter than CG + 1.0; CG scores 0.099"),
            "render-stroke-shadows-rect-inner": (0.12, "tighter than CG + 1.0; CG scores 0.089"),
            "render-stroke-shadows-rect-round-outer": (0.11, "tighter than CG + 1.0; CG scores 0.134"),
            "render-stroke-shadows-rect-translucent-outer": (0.09, "tighter than CG + 1.0; CG scores 0.109"),
            "render-stroke-shadows-frame-perside-outer": (0.09, "tighter than CG + 1.0; CG scores 0.100"),
            "render-stroke-shadows-frame-perside-center": (0.09, "tighter than CG + 1.0; CG scores 0.094"),
            "render-stroke-shadows-frame-child-outer": (0.09, "tighter than CG + 1.0; CG scores 0.109"),
            "render-stroke-shadows-ellipse-outer": (0.16, "tighter than CG + 1.0; CG scores 0.179"),
            "render-stroke-shadows-polygon-outer": (0.12, "tighter than CG + 1.0; CG scores 0.140"),
            "render-stroke-shadows-path-outer": (0.10, "tighter than CG + 1.0; CG scores 0.099"),
            "render-stroke-shadows-inner-under-inner-stroke": (0.00, "tighter than CG + 1.0; CG scores 0.000"),
            // Pen, SwiftUI and CG all cast nothing from a line since leaf B7M4na fixed
            // PenShadowSilhouette (2026-09-28); kept as a ceiling, not folded into CG + 1.0,
            // so a line shadow regressing in either renderer is still caught on its own.
            "render-stroke-shadows-line-diagonal": (0.01, "Pen, SwiftUI and CG cast nothing from a line; CG scores 0.006"),
            "render-stroke-shadows-line-flat": (0.00, "Pen, SwiftUI and CG cast nothing from a line; CG scores 0.000"),
        ]

        /// How far a baselined or ceilinged board may drift before it fails.
        static let baselineTolerance = 0.5

        /// How far above the CG renderer's MAE a fixed-box board may land.
        static let fixedBoxMargin = 1.0

        @Test("The emitted code compiles at the default floor")
        func compilesAtTheDefaultFloor() async throws {
            let outcome = try await SwiftUIRenderBatch.shared.value
            print("SwiftUI render batch: \(String(format: "%.1f", outcome.seconds)) s")
            #expect(outcome.buildFailure == nil, "\(outcome.buildFailure ?? "")")
        }

        @Test("The emitted code compiles at iOS 18 / macOS 15")
        func compilesAtTheLowerFloor() async throws {
            let outcome = try await SwiftUIRenderBatch.shared.value
            #expect(outcome.lowerFloorFailure == nil, "\(outcome.lowerFloorFailure ?? "")")
        }

        @Test("Each board renders within its gate", arguments: SwiftUIRenderBoard.all)
        func boardMatchesPen(board: SwiftUIRenderBoard) async throws {
            // The CG side measures and draws Inter, and the layout-text-* boards' IBM Plex Sans.
            TestFontRegistration.registerTestFonts()
            let outcome = try await SwiftUIRenderBatch.shared.value
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

            let limit: Double = if let baseline = Self.baselines[board.id] {
                baseline.mae + Self.baselineTolerance
            } else if let ceiling = Self.ceilings[board.id] {
                min(ceiling.mae + Self.baselineTolerance, cgMAE + Self.fixedBoxMargin)
            } else {
                cgMAE + Self.fixedBoxMargin
            }
            #expect(mae <= limit, "\(board.id): SwiftUI MAE \(mae), CG \(cgMAE), limit \(limit); \(size)")
            await MAEReport.shared.record(id: "swiftui-\(board.id)", mae: mae, limit: limit)
        }
    }

    extension Tag {
        /// Tests that compile emitted SwiftUI with Xcode's toolchain and render it.
        @Tag static var swiftUIRegression: Self
    }

#endif
