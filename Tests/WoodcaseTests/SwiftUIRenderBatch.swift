//
//  SwiftUIRenderBatch.swift
//  WoodcaseTests
//

// macOS-only: it shells out to Xcode's toolchain, and the harness links SwiftUI.
#if os(macOS)

    import Foundation
    @testable import Woodcase

    /// One compile and one render of every emitted board, shared by every case of
    /// ``SwiftUIRenderTests``.
    ///
    /// The compiler's fixed cost (about a second) dwarfs a board's render, so every
    /// fixture's page goes into one module with the harness `main.swift` (a test resource)
    /// and a generated `renderBoards()` list, built by **one** `xcrun swiftc -Onone` child
    /// at the default floor; the same sources are type-checked at the lower floor
    /// alongside it. Nothing here links SwiftUI into a test target: a bad emission is a
    /// compiler diagnostic in a failing test, never a broken build.
    enum SwiftUIRenderBatch {
        /// What the batch produced.
        struct Outcome {
            /// Where the harness wrote `<board id>.png`, when the default-floor build ran.
            var renders: URL?
            /// The default-floor build's or the harness run's failure output, if either failed.
            var buildFailure: String?
            /// The lower floor's type-check failure output, if it failed.
            var lowerFloorFailure: String?
            /// Wall time of the whole batch: emit, both compiles, and the render.
            var seconds: Double
        }

        /// The batch, built on first use and shared by every test in the process.
        static let shared: Task<Outcome, Error> = Task { try await run() }

        /// How long a child (`swiftc`, or the harness itself) may run before
        /// ``runAsync(_:log:deadline:)`` decides it is hung, not merely slow, and kills
        /// it.
        ///
        /// The default-floor build of every emitted board took up to 574 s alone on a
        /// loaded machine (measured 2026-09-27, `swift test --filter SwiftUIRenderTests
        /// -j 3`, load ~130 on an 8-core Mac) and crossed the previous 600 s budget
        /// entirely under the full suite's contention — the house convention (see
        /// `project/gotchas.md`, "wall-clock budgets") is to scale a *not hung* guard
        /// rather than pick a number that only covers today's quietest run. 30 minutes
        /// gives roughly 3x headroom over the worst compile measured so far, while
        /// staying well inside the run's own watchdog (`perl -e 'alarm …'`).
        static let defaultDeadline: Duration = .seconds(1800)

        /// Whether the toolchain the batch needs is installed.
        static let toolchainAvailable: Bool = (try? runSync(["/usr/bin/xcrun", "--find", "swiftc"])) == 0

        private static let arch: String = {
            #if arch(arm64)
                "arm64"
            #else
                "x86_64"
            #endif
        }()

        private static func run() async throws -> Outcome {
            let clock = ContinuousClock()
            let start = clock.now
            let root = TestOutputDirectory.url.appendingPathComponent("swiftui-render-\(UUID().uuidString.prefix(8))")
            let sources = root.appendingPathComponent("Sources")
            let renders = root.appendingPathComponent("renders")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)

            var entries: [String] = []
            var support: [GeneratedFile] = []
            let bundle = root.appendingPathComponent("PenHarness.bundle")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            for (index, board) in SwiftUIRenderBoard.all.enumerated() {
                // Boards from different fixtures may share a frame name, so each view is
                // renamed for its place in the batch.
                let type = "Board\(index)"
                let emitted = try board.emitPage(named: type)
                try emitted.page.content.write(to: sources.appendingPathComponent("\(type).swift"), atomically: true, encoding: .utf8)
                let scale = try board.referenceScale()
                // The harness pins light around every board; an inner scheme wins inside it.
                let view = board.colorScheme == .light ? "\(type)()" : "\(type)().environment(\\.colorScheme, .\(board.colorScheme.rawValue))"
                entries.append("        (\"\(board.id)\", \(scale), AnyView(\(view))),")
                if support.isEmpty {
                    support = emitted.support
                }
                for file in emitted.theme {
                    let target = sources.appendingPathComponent(URL(fileURLWithPath: file.path).lastPathComponent)
                    if let written = try? String(contentsOf: target, encoding: .utf8) {
                        // One module holds one `PenTheme`: two themed fixtures must agree on it.
                        guard written == file.content else { throw BatchError.conflictingTheme(board.fixture, file.path) }
                        continue
                    }
                    try file.content.write(to: target, atomically: true, encoding: .utf8)
                }
                // SwiftPM flattens processed resources into the module's bundle; so does this.
                let resources = emitted.images.map { SwiftUIFixtures.directory.appendingPathComponent($0) } + emitted.fonts
                for source in resources {
                    let target = bundle.appendingPathComponent(source.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.copyItem(at: source, to: target)
                    }
                }
            }
            for file in support {
                let name = URL(fileURLWithPath: file.path).lastPathComponent
                try file.content.write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            // What SwiftPM synthesizes for a target with resources, pointed at this batch's bundle.
            let boards = """
            import SwiftUI

            \(bundleShim(at: bundle))
            @MainActor func renderBoards() -> [(name: String, scale: CGFloat, view: AnyView)] {
                [
            \(entries.joined(separator: "\n"))
                ]
            }

            """
            try boards.write(to: sources.appendingPathComponent("Boards.swift"), atomically: true, encoding: .utf8)
            let harness = SwiftUIFixtures.directory.appendingPathComponent("swiftui-harness/main.swift")
            try FileManager.default.copyItem(at: harness, to: sources.appendingPathComponent("main.swift"))

            let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
                .filter { $0.hasSuffix(".swift") }.sorted()
                .map { sources.appendingPathComponent($0).path }
            let binary = root.appendingPathComponent("harness").path
            let defaultFloor = SwiftUIEmitter.Options().deploymentFloor
            let lowerFloor = SwiftUIEmitter.DeploymentFloor.iOS18
            async let build = runAsync(
                compile(floor: defaultFloor) + ["-Onone", "-module-name", "PenHarness", "-o", binary] + files,
                log: root.appendingPathComponent("build.log")
            )
            async let check = runAsync(
                compile(floor: lowerFloor) + ["-typecheck", "-module-name", "PenHarness"] + files,
                log: root.appendingPathComponent("typecheck.log")
            )
            let (built, checked) = try await (build, check)
            // A breakdown for whoever is chasing the batch's wall time under load: which
            // half — codegen or type-checking alone — is actually the long pole.
            print("SwiftUIRenderBatch: build \(built.elapsed), typecheck \(checked.elapsed)")

            var outcome = Outcome(seconds: 0)
            if !checked.succeeded {
                outcome.lowerFloorFailure = checked.output
            }
            if !built.succeeded {
                outcome.buildFailure = built.output
            } else {
                let rendered = try await runAsync(
                    [binary, renders.path, testFonts.path],
                    log: root.appendingPathComponent("render.log")
                )
                if !rendered.succeeded {
                    outcome.buildFailure = rendered.status.map { "the harness exited \($0):\n\(rendered.output)" } ?? rendered.output
                } else {
                    outcome.renders = renders
                }
            }
            let elapsed = clock.now - start
            outcome.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return outcome
        }

        /// The fonts the test process registers (``TestFontRegistration``): Inter, which
        /// most boards set, and IBM Plex Sans, which the `layout-text-*` boards set. The
        /// harness registers the same files, so both sides draw in the same faces and
        /// neither reads the user's `~/.woodcase` font cache.
        static let testFonts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts")

        /// What SwiftPM synthesizes for a target with resources — `Bundle.module` — pointed
        /// at `bundle`, a directory the batch copies the resources into. Every batch needs it:
        /// the support files register the package's fonts from `Bundle.module` (`PenFonts`).
        static func bundleShim(at bundle: URL) -> String {
            """
            import Foundation

            extension Foundation.Bundle {
                static let module = Bundle(path: \(SwiftUILiteral.string(bundle.path)))!
            }

            """
        }

        /// The compiler invocation for a floor: Swift 6 mode, whole-module, the floor's
        /// macOS target.
        ///
        /// `-wmo` makes one frontend compile every file. Without it `swiftc` starts a
        /// frontend per file and each one parses the whole module again, so the cost grows
        /// with files × module size: the 334-file render batch spent 731 s type-checking
        /// that way under load, and 12.6 s of CPU whole-module (measured 2026-09-28,
        /// `xcrun swiftc -typecheck` over the batch's own sources, load ~55). `-j 3` caps
        /// the driver's parallelism on this shared 8-core Mac, as `swift build` and
        /// `swift test` are capped (`project/gotchas.md`, "Ten cold Swift builds at once
        /// panic this Mac").
        static func compile(floor: SwiftUIEmitter.DeploymentFloor) -> [String] {
            [
                "/usr/bin/xcrun", "swiftc", "-wmo", "-j", "3", "-swift-version", "6",
                "-target", "\(arch)-apple-macos\(floor.macOSVersion)",
            ]
        }

        /// What a child process produced: it exited on its own, or the batch's own
        /// deadline killed it first because it had run longer than a healthy build
        /// should.
        ///
        /// A killed child has no exit status of its own (``status`` is `nil` for it),
        /// and its log may be empty — a `swiftc` that never got far enough to print a
        /// diagnostic — so ``output`` always opens with an explanation naming the
        /// command, the deadline and how long it actually ran, rather than surfacing
        /// silence as if it were a clean pass.
        enum ProcessOutcome {
            /// The process ran to completion in `elapsed`.
            case exited(status: Int32, output: String, elapsed: Duration)
            /// The process was killed after outrunning `deadline`, having actually run
            /// for `elapsed` — which can exceed `deadline` itself, since the watchdog's
            /// own timer is just as subject to a loaded machine's scheduling delay as
            /// the child it is timing.
            case timedOut(command: String, deadline: Duration, elapsed: Duration, output: String)

            /// The exit status, or `nil` when the process was killed for taking too long.
            var status: Int32? {
                if case let .exited(status, _, _) = self { status } else { nil }
            }

            /// Whether the process exited with status 0. Never true for a timeout.
            var succeeded: Bool {
                status == 0
            }

            /// How long the process ran, whichever case this is.
            var elapsed: Duration {
                switch self {
                case let .exited(_, _, elapsed): elapsed
                case let .timedOut(_, _, elapsed, _): elapsed
                }
            }

            /// Captured stdout/stderr; for ``timedOut``, prefixed with why there may be
            /// nothing else to show.
            var output: String {
                switch self {
                case let .exited(_, output, _):
                    return output
                case let .timedOut(command, deadline, elapsed, output):
                    let reason = "\(command) killed after \(Self.seconds(deadline)) s "
                        + "(ran \(Self.seconds(elapsed)) s): the machine may be loaded, or the "
                        + "batch is too big; re-run SwiftUIRenderTests alone"
                    return output.isEmpty ? reason : "\(reason)\n\n\(output)"
                }
            }

            private static func seconds(_ duration: Duration) -> String {
                let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                return String(format: "%.0f", value)
            }
        }

        /// Run a process to completion, its output (stdout and stderr) in `log`, killing
        /// it if it outruns `deadline`.
        ///
        /// The output goes to a file rather than a pipe so a chatty compiler can never
        /// fill a pipe buffer and stall; the wait itself is bounded by ``BoundedWait``,
        /// because an `await` on a callback we do not own needs a deadline we do — and,
        /// unlike ``BoundedWait``'s own abandon-and-move-on contract, a deadline that
        /// fires here also terminates the child: it is a real process eating CPU, not a
        /// suspended `await` that costs nothing left behind.
        static func runAsync(
            _ arguments: [String],
            log: URL,
            deadline: Duration = defaultDeadline
        ) async throws -> ProcessOutcome {
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = Array(arguments.dropFirst())
            process.standardOutput = handle
            process.standardError = handle

            let clock = ContinuousClock()
            let start = clock.now
            let command = commandSummary(arguments)
            do {
                let status = try await BoundedWait.value(command, within: deadline) {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                            do {
                                try process.run()
                            } catch {
                                process.terminationHandler = nil
                                continuation.resume(throwing: error)
                            }
                        }
                    } onCancel: {
                        if process.isRunning { process.terminate() }
                    }
                }
                let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                return .exited(status: status, output: output, elapsed: clock.now - start)
            } catch is BoundedWait.Expired {
                let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                return .timedOut(command: command, deadline: deadline, elapsed: clock.now - start, output: output)
            }
        }

        /// A short label for a child's argument vector — the executable and its first
        /// couple of arguments — so a timeout message names what was running without
        /// dumping (for `swiftc`) hundreds of source paths.
        private static func commandSummary(_ arguments: [String]) -> String {
            let head = arguments.prefix(3).map { URL(fileURLWithPath: $0).lastPathComponent }
            let summary = head.joined(separator: " ")
            return arguments.count > 3 ? "\(summary) …" : summary
        }

        /// A batch that cannot be put together.
        enum BatchError: Error {
            /// A fixture emitted a theme file that differs from one another fixture wrote:
            /// the fixture and the file.
            case conflictingTheme(String, String)
        }

        private static func runSync(_ arguments: [String]) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = Array(arguments.dropFirst())
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

#endif
