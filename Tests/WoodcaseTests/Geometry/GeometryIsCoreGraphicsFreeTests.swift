import Foundation
import Testing

/// Guards the geometry layer's one promise: it compiles without CoreGraphics, so the
/// code emitters that read it build on Linux.
///
/// macOS always has CoreGraphics, so no build here can prove that; this test reads the
/// sources instead and fails on any import of CoreGraphics or any `CG` type.
struct GeometryIsCoreGraphicsFreeTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Geometry
        .deletingLastPathComponent() // WoodcaseTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()

    /// The folders promised to build without CoreGraphics: the shape geometry, and the
    /// mesh core the React emitter already rasterizes with.
    static let coreGraphicsFreeFolders = ["Sources/Woodcase/Geometry", "Sources/Woodcase/Rendering/Mesh"]

    @Test("No file in a CoreGraphics-free folder uses CoreGraphics", arguments: coreGraphicsFreeFolders)
    func noCoreGraphics(folder: String) throws {
        let directory = Self.packageRoot.appendingPathComponent(folder)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("import CoreGraphics"), "\(file.lastPathComponent) imports CoreGraphics")
            #expect(!source.contains(/\bCG[A-Z]/), "\(file.lastPathComponent) names a CoreGraphics type")
        }
    }
}
