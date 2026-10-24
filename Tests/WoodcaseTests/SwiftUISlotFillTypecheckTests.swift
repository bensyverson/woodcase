//
//  SwiftUISlotFillTypecheckTests.swift
//  WoodcaseTests
//

// macOS-only: it type-checks the emitted SwiftUI with Xcode's toolchain.
#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// `slots-screen.pen`'s emitted SwiftUI type-checks: its `Board` page calls `Screen`
    /// with the default content, a trailing closure of three `ItemB()` rows, and an empty
    /// closure for the emptied list (Penumbra spec §13.5 rule 13; ``CodeGenSlotFillTests``
    /// reads the calls).
    @Suite("SwiftUI slot fills", .tags(.swiftUIRegression), .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUISlotFillTypecheckTests {
        @Test("The slots-screen fixture type-checks at the default floor")
        func typechecks() async throws {
            let root = TestOutputDirectory.url.appendingPathComponent("swiftui-slot-fills-\(UUID().uuidString.prefix(8))")
            let sources = root.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            let result = try SwiftUIFixtures.emit("slots-screen")
            // The library's files only: the catalog executable has a main of its own.
            for file in result.files where file.path.hasSuffix(".swift") && file.path.hasPrefix("Sources/PenUI/") {
                let name = URL(fileURLWithPath: file.path).lastPathComponent
                try file.content.write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let shim = SwiftUIRenderBatch.bundleShim(at: root.appendingPathComponent("PenHarness.bundle"))
            try shim.write(to: sources.appendingPathComponent("BundleShim.swift"), atomically: true, encoding: .utf8)
            let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
                .filter { $0.hasSuffix(".swift") }.sorted()
                .map { sources.appendingPathComponent($0).path }

            let checked = try await SwiftUIRenderBatch.runAsync(
                SwiftUIRenderBatch.compile(floor: SwiftUIEmitter.Options().deploymentFloor)
                    + ["-typecheck", "-module-name", "PenUI"] + files,
                log: root.appendingPathComponent("typecheck.log")
            )
            #expect(checked.succeeded, "\(checked.output)")
        }
    }

#endif
