//
//  SwiftUIFaceMatchingTemplateTests.swift
//  WoodcaseTests
//

// macOS-only: it compiles the emitted support files with Xcode's toolchain.
#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// The emitted SwiftUI draws a static family's weight in the cut CSS picks, as the
    /// renderer does (``PenFaceMatchingTests``): its `PenFontFace` had its own trait
    /// table, one step light (leaf BpaSrF, `project/2026-09-28-pen-font-faces.md`).
    ///
    /// The support files are resources, not code this target links, so the test compiles
    /// them with a probe `main.swift` that registers "Woodcase Static Sans" and prints the
    /// PostScript name `PenFontFace.ctFont` resolves for each weight.
    @Suite("SwiftUI support: static face matching", .enabled(if: SwiftUIRenderBatch.toolchainAvailable))
    struct SwiftUIFaceMatchingTemplateTests {
        private static let fonts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts/StaticSans")

        private static let probe = """
        import CoreText
        import Foundation

        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasSuffix(".ttf") {
            CTFontManagerRegisterFontsForURL(directory.appendingPathComponent(name) as CFURL, .process, nil)
        }
        for weight in [450, 500, 550, 600, 700] as [CGFloat] {
            let face = PenFontFace(family: "Woodcase Static Sans", size: 14, weight: weight, italic: false)
            print("\\(Int(weight)) \\(CTFontCopyPostScriptName(face.ctFont) as String)")
        }

        """

        @Test("Each static weight resolves to the cut CSS picks")
        func staticWeights() async throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("face-matching-\(UUID().uuidString)", isDirectory: true)
            let bundle = root.appendingPathComponent("bundle", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            var sources: [URL] = []
            let files = SwiftUIEmitter.supportTemplates.merging([
                "BundleShim.swift": SwiftUIRenderBatch.bundleShim(at: bundle),
                "main.swift": Self.probe,
            ]) { $1 }
            for (name, content) in files {
                let url = root.appendingPathComponent(name)
                try content.write(to: url, atomically: true, encoding: .utf8)
                sources.append(url)
            }
            let binary = root.appendingPathComponent("probe")
            let build = try await SwiftUIRenderBatch.runAsync(
                SwiftUIRenderBatch.compile(floor: .iOS26) + ["-module-name", "Probe", "-o", binary.path] + sources.map(\.path),
                log: root.appendingPathComponent("build.log")
            )
            try #require(build.succeeded, "\(build.output)")
            let run = try await SwiftUIRenderBatch.runAsync(
                [binary.path, Self.fonts.path], log: root.appendingPathComponent("run.log")
            )
            try #require(run.succeeded, "\(run.output)")

            let picked = Dictionary(uniqueKeysWithValues: run.output.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: " ")
                return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
            })
            #expect(picked == [
                "450": "WoodcaseStaticSans-Medium",
                "500": "WoodcaseStaticSans-Medium",
                "550": "WoodcaseStaticSans-SemiBold",
                "600": "WoodcaseStaticSans-SemiBold",
                "700": "WoodcaseStaticSans-Bold",
            ])
        }
    }
#endif
