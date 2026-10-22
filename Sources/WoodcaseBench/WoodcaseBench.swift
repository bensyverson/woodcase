//
//  WoodcaseBench.swift
//  WoodcaseBench
//

import Foundation

/// Runs Woodcase's performance benches on an optimized build, without compiling the
/// test target.
///
/// ```sh
/// swift run -c release WoodcaseBench list
/// swift run -c release WoodcaseBench property-read-cost
/// ```
///
/// Each bench prints `PROBE` lines; a figure means something only beside `uptime`. Never
/// time code with `swift test -c release`: that optimizes every file of `WoodcaseTests`
/// to run one probe (`project/2026-10-21-build-test-loop-baseline.md`).
@main
enum WoodcaseBench {
    /// Every bench, in the order `list` prints them.
    static var benches: [Bench] {
        var all = [
            BoardScalePatchBench.bench,
            PropertyReadCostBench.bench,
            PropertyWriteCostBench.bench,
            PaintedExtentBench.board,
            PaintedExtentBench.walk,
            ComponentLoopEditCostBench.bench,
            RemoteApplyCostBench.bench,
            CodeGenCorpusDump.bench,
        ]
        #if canImport(Darwin)
            all.insert(NodeTreeCostBench.bench, at: 3)
        #endif
        return all
    }

    /// Parses the command line and runs the bench it names.
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let name = arguments.first, name != "help", name != "--help" else {
            printUsage()
            exit(arguments.isEmpty ? 2 : 0)
        }
        if name == "list" {
            for bench in benches {
                print("\(bench.name) \(bench.arguments)".trimmingCharacters(in: .whitespaces))
                print("    \(bench.summary)")
            }
            return
        }
        guard let bench = benches.first(where: { $0.name == name }) else {
            FileHandle.standardError.write(Data("WoodcaseBench: no bench named '\(name)'; `WoodcaseBench list` names them\n".utf8))
            exit(2)
        }
        do {
            try bench.run(Array(arguments.dropFirst()))
        } catch let error as Bench.UsageError {
            FileHandle.standardError.write(Data("\(error.description)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("WoodcaseBench \(name) failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// The usage line, on standard output.
    private static func printUsage() {
        print("usage: WoodcaseBench list | <bench> [arguments]")
        print("  swift run -c release WoodcaseBench list")
    }
}
