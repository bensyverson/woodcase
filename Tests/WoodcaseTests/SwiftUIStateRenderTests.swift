//
//  SwiftUIStateRenderTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted SwiftUI with Xcode's toolchain and renders it.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Compiles `codegen-states.pen`'s components, renders each in the states Pen draws a
    /// `:state` sibling frame for, and measures each render against Pen's export of that
    /// frame (``SwiftUIStateBatch``): a pressed button against `StatesButton:pressed`, a
    /// disabled one against `StatesButton:disabled`, an off switch against `Switch:off`.
    @Suite("SwiftUI states", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUIStateRenderTests {
        /// Each board's MAE against Pen's export when recorded, and what the error is.
        ///
        /// The error is the text, not the state. Every text's box is its size rounded up to
        /// whole points, as Pen measures it (`PenLineBox`); before, the `fit_content` chip and
        /// link rendered a pixel narrower at 2x and a `fit_content` label centred in a fixed
        /// button sat half a point off (the chip 3.13, selected 4.68, the link 5.96, the
        /// button 2.38–2.64). What is left on the chip and the link is Core Text's glyphs
        /// themselves: they cover more than Pen's — on the link's transparent board the mean
        /// alpha is 41.7 against Pen's 34.7 — and the Core Graphics renderer scores the same
        /// three boards 2.57, 4.09 and 4.98 (`woodcase shot … --scale 2`, then `scripts/png-mae`).
        ///
        /// Recorded 2026-09-27, Xcode 27.0, macOS 27.0, with Inter from `~/.woodcase/fonts`
        /// (`swift test --filter SwiftUIStateRenderTests`).
        static let baselines: [String: (mae: Double, why: String)] = [
            "StatesButton": (0.958, "text antialiasing"),
            "StatesButton-pressed": (1.052, "text antialiasing"),
            "StatesButton-disabled": (0.667, "text antialiasing"),
            "StatesButton-hover": (0.815, "text antialiasing"),
            "Switch": (0.894, "the knob's edge antialiasing"),
            "Switch-off": (0.882, "the knob's edge antialiasing"),
            "SortSelect": (0.888, "text antialiasing"),
            "SortSelect-open": (0.585, "text antialiasing"),
            "MoreLink": (5.008, "Core Text's glyphs cover more than Pen's; CG scores 4.98"),
            "Chip": (2.698, "Core Text's glyphs cover more than Pen's; CG scores 2.57"),
            "Chip-selected": (4.152, "Core Text's glyphs cover more than Pen's; CG scores 4.09"),
        ]

        /// How far a board may drift past its baseline before it fails.
        static let tolerance = 0.5

        @Test("The state components compile at the default floor")
        func compiles() async throws {
            let outcome = try await SwiftUIStateBatch.shared.value
            #expect(outcome.buildFailure == nil, "\(outcome.buildFailure ?? "")")
        }

        @Test("The state components compile at iOS 18 / macOS 15")
        func compilesAtTheLowerFloor() async throws {
            let outcome = try await SwiftUIStateBatch.shared.value
            #expect(outcome.lowerFloorFailure == nil, "\(outcome.lowerFloorFailure ?? "")")
        }

        @Test("Each state renders as Pen draws its sibling frame", arguments: SwiftUIStateBatch.boards)
        func stateMatchesPen(board: SwiftUIStateBatch.Board) async throws {
            let outcome = try await SwiftUIStateBatch.shared.value
            let renders = try #require(outcome.renders, "the batch did not render: \(outcome.buildFailure ?? "")")
            let swiftUI = try #require(PenSnapshotTestHelpers.loadFixtureImage(named: board.name, fixturesDir: renders))
            let reference = try #require(
                PenSnapshotTestHelpers.loadFixtureImage(named: board.referenceName, fixturesDir: SwiftUIFixtures.directory)
            )
            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: swiftUI, and: reference)
            let size = "\(swiftUI.width)x\(swiftUI.height) vs \(reference.width)x\(reference.height)"
            print("SwiftUI \(board.referenceName): MAE \(String(format: "%.3f", mae)) \(size)")
            // Pen sizes a `fit_content` frame around its text's width rounded up to a point.
            #expect(swiftUI.width == reference.width && swiftUI.height == reference.height, "\(board.name): \(size)")

            let baseline = try #require(Self.baselines[board.name], "no baseline for \(board.name); measured \(mae)")
            let limit = baseline.mae + Self.tolerance
            #expect(mae <= limit, "\(board.name): SwiftUI MAE \(mae), limit \(limit); \(size)")
            await MAEReport.shared.record(id: "swiftui-\(board.referenceName)", mae: mae, limit: limit)
        }
    }

#endif
