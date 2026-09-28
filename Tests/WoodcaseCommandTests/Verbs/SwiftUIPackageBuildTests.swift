//
//  SwiftUIPackageBuildTests.swift
//  WoodcaseCommandTests
//

// macOS-only: it builds the generated package with SwiftPM and runs its catalog.
#if os(macOS)

    import Foundation
    import Testing

    /// A package `woodcase generate swiftui` writes builds with `swift build`, as it is, and
    /// its fonts register at run time.
    ///
    /// The render suites (`SwiftUIRenderTests` and its batches) compile the emitted views
    /// with one `swiftc` call and a stand-in `Bundle.module`, which proves the views but not
    /// the package: the manifest, the resource bundle SwiftPM makes, the catalog executable
    /// and the fonts copied beside the images. This builds one real package — `woodcase-app`,
    /// which draws images and icons and sets its text in IBM Plex Sans through a variable —
    /// from the CLI, then asks its catalog which fonts registered (`--fonts`). One package,
    /// because a cold SwiftPM build of it takes about a minute.
    @Suite("A generated SwiftUI package builds")
    struct SwiftUIPackageBuildTests {
        /// The IBM Plex Sans file the fixture's font cache holds: Google's variable face,
        /// which draws every weight the screens set.
        private static let plex = ["IBMPlexSans[wdth,wght].ttf"]

        /// Whether Xcode's toolchain is installed.
        private static let toolchainAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")

        @Test(
            "woodcase-app's package swift-builds, and its catalog registers the bundled fonts",
            .enabled(if: toolchainAvailable),
            .timeLimit(.minutes(15))
        )
        func packageBuildsAndRegistersFonts() async throws {
            let fixture = try CommandFixture(fixture: "woodcase-app.pen")
            try fixture.seedFontCache(family: "IBM Plex Sans", files: Self.plex)
            try copyImages(of: fixture)
            let package = fixture.root.appendingPathComponent("package", isDirectory: true)
            let generated = try fixture.run(
                "generate", "swiftui", fixture.file.path, "--output", package.path, "--name", "WoodcaseApp"
            )
            try #require(generated.status == 0, "\(generated.stderr)")
            try #require(generated.stdout.contains("+ 1 text font(s)"), "\(generated.stdout)")

            let build = try await Self.run(
                ["/usr/bin/xcrun", "swift", "build", "-j", "3", "--package-path", package.path],
                log: fixture.root.appendingPathComponent("build.log")
            )
            try #require(build.status == 0, "swift build failed:\n\(build.output.suffix(6000))")
            let binPath = try await Self.run(
                ["/usr/bin/xcrun", "swift", "build", "--show-bin-path", "--package-path", package.path],
                log: fixture.root.appendingPathComponent("bin-path.log")
            )
            let bin = try #require(
                binPath.output.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) }
            )

            let fonts = try await Self.run(
                ["\(bin)/WoodcaseAppCatalog", "--fonts"],
                log: fixture.root.appendingPathComponent("fonts.log")
            )
            #expect(fonts.status == 0, "\(fonts.output)")
            for file in Self.plex {
                #expect(
                    fonts.output.contains("registered\tIBM Plex Sans\t\(file)"),
                    "\(file) did not register:\n\(fonts.output)"
                )
            }
            #expect(fonts.output.contains("\tlucide.ttf"), "the icon font is not among the package's fonts:\n\(fonts.output)")
            #expect(!fonts.output.contains("failed"), "\(fonts.output)")
        }

        /// Copies the images `woodcase-app.pen` fills with into the fixture, beside the
        /// file, where `generate swiftui` looks for them.
        private func copyImages(of fixture: CommandFixture) throws {
            let source = CommandFixture.packageRoot.appendingPathComponent("Tests/WoodcaseTests/Fixtures/images")
            let target = fixture.root.appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for name in try FileManager.default.contentsOfDirectory(atPath: source.path) where name.hasPrefix("generated-") {
                try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: target.appendingPathComponent(name))
            }
        }

        /// Runs a process to completion, its stdout and stderr in `log`; bounded, because a
        /// wait on a callback we do not own needs a deadline we do.
        private static func run(_ arguments: [String], log: URL) async throws -> (status: Int32, output: String) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = Array(arguments.dropFirst())
            process.standardOutput = handle
            process.standardError = handle
            let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
                    if process.isRunning { process.terminate() }
                }
            }
            return (status, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
        }
    }

#endif
