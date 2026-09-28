//
//  SwiftUISlotRenderTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted SwiftUI with Xcode's toolchain and renders it.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Compiles `codegen-slots.pen`'s components and pages — the pages' instances calls whose
    /// trailing closures fill the components' slots — renders each top-level frame, and
    /// measures it against Pen's export of that frame (``SwiftUISlotBatch``).
    @Suite("SwiftUI slots", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUISlotRenderTests {
        /// Each board's MAE against Pen's export as measured
        /// (`swift test --filter SwiftUISlotRenderTests -j 3`, Xcode 27.0, macOS 27.0, 2026-09-27), the
        /// limit the margin rule sets from it — `max(measured × 1.5, measured + 0.25)`, rounded up to
        /// a hundredth (`project/2026-09-26-mae-margin-rule.md`) — and what the error is.
        static let limits: [String: (measured: Double, limit: Double, why: String)] = [
            "Card": (0.982, 1.48, "SwiftUI's 1× Inter lines run taller than Pen's, which drifts the slot's text down"),
            "Panel": (0.222, 0.48, "glyph rasterization of the default footer"),
            "SlotButton": (1.617, 2.43, "the hugging button measures 179 points wide to Pen's 180, shifting its right edge"),
            "FilledCard": (1.084, 1.63, "line heights, as in Card, over three lines of text"),
            "ProfileCard": (0.390, 0.64, "glyph rasterization"),
            "DefaultCard": (0.443, 0.70, "line heights, as in Card"),
            "FilledPanel": (0.385, 0.64, "glyph rasterization"),
            "HeaderPanel": (0.401, 0.66, "glyph rasterization"),
            "UploadButton": (0.474, 0.73, "glyph rasterization of the label"),
        ]

        @Test("The slot fixture compiles at the default floor")
        func compiles() async throws {
            let outcome = try await SwiftUISlotBatch.shared.value
            #expect(outcome.buildFailure == nil, "\(outcome.buildFailure ?? "")")
        }

        @Test("The slot fixture compiles at iOS 18 / macOS 15")
        func compilesAtTheLowerFloor() async throws {
            let outcome = try await SwiftUISlotBatch.shared.value
            #expect(outcome.lowerFloorFailure == nil, "\(outcome.lowerFloorFailure ?? "")")
        }

        @Test("Each frame renders as Pen draws it", arguments: SwiftUISlotBatch.boards)
        func frameMatchesPen(board: SwiftUISlotBatch.Board) async throws {
            let outcome = try await SwiftUISlotBatch.shared.value
            let renders = try #require(outcome.renders, "the batch did not render: \(outcome.buildFailure ?? "")")
            let swiftUI = try #require(PenSnapshotTestHelpers.loadFixtureImage(named: board.name, fixturesDir: renders))
            let reference = try #require(
                PenSnapshotTestHelpers.loadFixtureImage(named: board.referenceName, fixturesDir: SwiftUIFixtures.directory)
            )
            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: swiftUI, and: reference)
            let size = "\(swiftUI.width)x\(swiftUI.height) vs \(reference.width)x\(reference.height)"
            print("SwiftUI \(board.referenceName): MAE \(String(format: "%.3f", mae)) \(size)")

            let limit = try #require(Self.limits[board.name], "no limit for \(board.name); measured \(mae)").limit
            #expect(mae <= limit, "\(board.name): SwiftUI MAE \(mae), limit \(limit); \(size)")
            await MAEReport.shared.record(id: "swiftui-\(board.referenceName)", mae: mae, limit: limit)
        }
    }

#endif
