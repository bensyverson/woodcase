//
//  SwiftUIEmitterIsolationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// The SwiftUI emitter writes SwiftUI as *text*; it must never link it.
///
/// The emitter lives in the cross-platform `Woodcase` library, and its goldens are meant
/// to run on Linux. The library as a whole does not build on Linux yet (issue `cAUDcr`),
/// so this scan is the Linux guard for the emitter until it does: no file under
/// `CodeGen/SwiftUI/` may import an Apple UI or graphics framework.
struct SwiftUIEmitterIsolationTests {
    /// Frameworks the emitter must not import.
    private static let forbidden = ["SwiftUI", "SwiftUICore", "CoreGraphics", "CoreText", "AppKit", "UIKit"]

    @Test("Nothing under CodeGen/SwiftUI imports SwiftUI, CoreGraphics or AppKit")
    func emitterImportsOnlyFoundation() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Woodcase/CodeGen/SwiftUI")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty, "no emitter sources at \(directory.path)")
        for file in files {
            let source = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            for match in source.matches(of: /(?m)^\s*(?:@\w+\s+)*import\s+(?:\w+\s+)?(\w+)/) {
                let module = String(match.output.1)
                #expect(!Self.forbidden.contains(module), "\(file) imports \(module)")
            }
        }
    }
}
