//
//  SwiftUIScreenRenderTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted SwiftUI with Xcode's toolchain and renders it.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Compiles every component `woodcase-app.pen` emits and the theme it reads its variables
    /// through, renders each screen in each theme Pen exported it in — light, dark, compact —
    /// with `ImageRenderer`, and measures it against Pen's export (``SwiftUIScreenBatch``).
    ///
    /// The screens are whole stacks of text, rows and instances, where SwiftUI's stack
    /// negotiation and text metrics differ from Pen's flexbox, so per the layout ruling
    /// (idiomatic stacks, intent over pixels) each records its measured MAE in ``baselines``
    /// with the reason, and fails only when it regresses past it.
    @Suite("SwiftUI screens", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUIScreenRenderTests {
        /// Each screen's MAE against Pen's export when recorded, and why it is above the
        /// Core Graphics renderer's (`PenWoodcaseAppTests`, 0.4–1.8 on the same references).
        ///
        /// The layout now matches Pen's: a `fill_container` stack carries a zero minimum, so
        /// content larger than its room overflows it as Pen's flex item does (it used to grow
        /// the frame, widening Home and pushing the Ratings tab bar down; 3.02–5.42 before),
        /// and a text with no line height is set at Pen's rounded natural pitch rather than
        /// SwiftUI's (see `project/2026-09-26-swiftui-components.md`). What is left is glyph
        /// rasterization, small horizontal text offsets, shadow antialiasing and, on Lab, a
        /// Material for background blur. The heavy weights that drew lighter than Pen's were
        /// the static IBM Plex Sans cuts, each resolved one weight light (leaf BpaSrF).
        ///
        /// Recorded 2026-09-27 through `PenTheme`, after the `fill_container` minimum and the natural
        /// line pitch (leaves `HjUFQT`, `97Dngc`); Xcode 27.0, macOS 27.0, with the committed test fonts
        /// (`swift test --filter SwiftUIScreenRenderTests`). Re-recorded 2026-09-28 the same way with
        /// IBM Plex Sans in Google's variable face (leaf BpaSrF, 1.22–2.40 before: the static cuts drew
        /// each Medium and SemiBold one weight light; `project/2026-09-28-pen-font-faces.md`).
        static let baselines: [String: (mae: Double, why: String)] = [
            "home-collection": (0.875, "text rasterization"),
            "home-collection-dark": (0.896, "text rasterization"),
            "usage-log": (0.692, "text and shadow antialiasing"),
            "usage-log-dark": (0.715, "text and shadow antialiasing"),
            "ratings": (1.048, "text and shadow antialiasing"),
            "ratings-dark": (0.950, "text and shadow antialiasing"),
            "wishlist": (1.822, "text offsets; text and shadow antialiasing"),
            "wishlist-dark": (1.668, "text offsets; text and shadow antialiasing"),
            "settings": (0.412, "text antialiasing; the text fields' inset"),
            "settings-dark": (0.443, "text antialiasing; the text fields' inset"),
            "settings-compact": (0.412, "text antialiasing; the text fields' inset"),
            "settings-compact-dark": (0.443, "text antialiasing; the text fields' inset"),
            "lab": (1.669, "text antialiasing; background blur is a Material"),
            "lab-dark": (2.103, "text antialiasing; background blur is a dark Material"),
        ]

        /// How far a screen may drift past its baseline before it fails.
        static let tolerance = 0.5

        @Test("The woodcase-app components compile at the default floor")
        func compiles() async throws {
            let outcome = try await SwiftUIScreenBatch.shared.value
            #expect(outcome.buildFailure == nil, "\(outcome.buildFailure ?? "")")
        }

        @Test("The woodcase-app components compile at iOS 18 / macOS 15")
        func compilesAtTheLowerFloor() async throws {
            let outcome = try await SwiftUIScreenBatch.shared.value
            #expect(outcome.lowerFloorFailure == nil, "\(outcome.lowerFloorFailure ?? "")")
        }

        @Test("Each screen renders in its theme within its baseline", arguments: SwiftUIScreenBatch.screens)
        func screenMatchesPen(screen: SwiftUIScreenBatch.Screen) async throws {
            let outcome = try await SwiftUIScreenBatch.shared.value
            let renders = try #require(outcome.renders, "the batch did not render: \(outcome.buildFailure ?? "")")
            let swiftUI = try #require(PenSnapshotTestHelpers.loadFixtureImage(named: screen.name, fixturesDir: renders))
            let reference = try #require(
                PenSnapshotTestHelpers.loadFixtureImage(named: screen.referenceName, fixturesDir: SwiftUIFixtures.directory)
            )
            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: swiftUI, and: reference)
            let size = "\(swiftUI.width)x\(swiftUI.height) vs \(reference.width)x\(reference.height)"
            print("SwiftUI woodcase-app-\(screen.name): MAE \(String(format: "%.3f", mae)) \(size)")

            let baseline = try #require(Self.baselines[screen.name], "no baseline for \(screen.name); measured \(mae)")
            let limit = baseline.mae + Self.tolerance
            #expect(mae <= limit, "\(screen.name): SwiftUI MAE \(mae), limit \(limit); \(size)")
            await MAEReport.shared.record(id: "swiftui-woodcase-app-\(screen.name)", mae: mae, limit: limit)
        }
    }

#endif
