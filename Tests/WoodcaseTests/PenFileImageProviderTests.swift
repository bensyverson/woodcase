import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Woodcase

struct PenFileImageProviderTests {
    /// Creates a temporary directory with a test PNG image at the given relative path.
    /// Returns the base directory URL and a cleanup function.
    private func makeFixture(
        relativePath: String,
        width: Int = 20,
        height: Int = 10
    ) throws -> (baseDir: URL, cleanup: () -> Void) {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-img-test-\(UUID().uuidString)")

        let imageURL = baseDir.appendingPathComponent(relativePath)
        let imageDir = imageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: imageDir, withIntermediateDirectories: true
        )

        let image = makeTestImage(width: width, height: height)
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                imageURL as CFURL,
                UTType.png.identifier as CFString,
                1, nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        return (baseDir, { try? FileManager.default.removeItem(at: baseDir) })
    }

    /// Creates a simple solid-color test image.
    private func makeTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test("Loads an image from a relative path")
    func loadsRelativePath() throws {
        let (baseDir, cleanup) = try makeFixture(relativePath: "photo.png")
        defer { cleanup() }

        let provider = PenRenderer.fileImageProvider(relativeTo: baseDir)
        let image = try #require(provider("photo.png"))
        #expect(image.width == 20)
        #expect(image.height == 10)
    }

    @Test("Loads an image from a nested relative path")
    func loadsNestedPath() throws {
        let (baseDir, cleanup) = try makeFixture(
            relativePath: "images/nested/texture.png",
            width: 50, height: 30
        )
        defer { cleanup() }

        let provider = PenRenderer.fileImageProvider(relativeTo: baseDir)
        let image = try #require(provider("images/nested/texture.png"))
        #expect(image.width == 50)
        #expect(image.height == 30)
    }

    @Test("Loads an image from a dot-relative path like ./images/foo.png")
    func loadsDotRelativePath() throws {
        let (baseDir, cleanup) = try makeFixture(
            relativePath: "images/hero.png",
            width: 100, height: 60
        )
        defer { cleanup() }

        let provider = PenRenderer.fileImageProvider(relativeTo: baseDir)
        let image = try #require(provider("./images/hero.png"))
        #expect(image.width == 100)
        #expect(image.height == 60)
    }

    @Test("Returns nil for a nonexistent path")
    func returnsNilForMissing() {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-img-test-\(UUID().uuidString)")
        let provider = PenRenderer.fileImageProvider(relativeTo: baseDir)
        #expect(provider("nonexistent.png") == nil)
    }

    @Test("Returns nil for a file that is not a valid image")
    func returnsNilForInvalidImage() throws {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-img-test-\(UUID().uuidString)")
        let fileURL = baseDir.appendingPathComponent("not-an-image.png")
        try FileManager.default.createDirectory(
            at: baseDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: baseDir) }

        try Data("this is not an image".utf8).write(to: fileURL)

        let provider = PenRenderer.fileImageProvider(relativeTo: baseDir)
        #expect(provider("not-an-image.png") == nil)
    }
}
