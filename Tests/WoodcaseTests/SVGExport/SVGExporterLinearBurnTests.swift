#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// How an SVG export writes a linear burn: `color-burn`, then `plus-darker` as a second
    /// declaration (Ben's ruling, 2026-10-21). WebKit draws `plus-darker` as an exact linear
    /// burn; a browser that does not know the value drops that declaration and keeps
    /// `color-burn`, the nearest blend CSS has.
    struct SVGExporterLinearBurnTests {
        private typealias Fixture = SVGExportFixture

        /// The fallback pair, as the `style` attribute writes it.
        private static let burnStyle = "mix-blend-mode:color-burn;mix-blend-mode:plus-darker"

        @Test("A node's linear burn writes color-burn, then plus-darker")
        func nodeBlend() throws {
            let fixture = try Fixture("""
            [{"type": "rectangle", "id": "r", "width": 100, "height": 60, "fill": "#FF0000",
              "metadata": {"type": "woodcase", "woodcase": {"blendMode": "linearBurn"}}}]
            """)
            let xml = try #require(try fixture.svg(["r"]))
            let groups = try Fixture.elements("g", in: xml)
            #expect(groups.contains { Fixture.attribute("style", of: $0) == Self.burnStyle })
        }

        @Test("A fill's linear burn writes color-burn, then plus-darker")
        func fillBlend() throws {
            let fixture = try Fixture("""
            [{"type": "rectangle", "id": "r", "width": 100, "height": 60,
              "fill": ["#E6994D", {"type": "color", "color": "#3366FF", "blendMode": "linearBurn"}]}]
            """)
            let xml = try #require(try fixture.svg(["r"]))
            let paths = try Fixture.elements("path", in: xml)
            #expect(paths.contains { Fixture.attribute("style", of: $0) == Self.burnStyle })
        }

        @Test("Every other mode writes one declaration")
        func otherModes() {
            #expect(PenBlendMode.colorBurn.svgStyle == "mix-blend-mode:color-burn")
            #expect(PenBlendMode.linearDodge.svgStyle == "mix-blend-mode:plus-lighter")
            #expect(PenBlendMode.normal.svgStyle == nil)
        }
    }

    /// Draws a linear burn's SVG export in WebKit, which must take the second declaration:
    /// `#3366FF` linear-burned over `#E6994D` is `#1A004D`, where `color-burn` gives a red
    /// near 229 (`PenRendererBlendTests`).
    @Suite("SVG export linear burn WebView", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct SVGExportLinearBurnWebViewTests {
        private nonisolated static let fixturesDir = WebViewRegressionFixture.fixturesDirectory

        private let harness = WebViewTestHarness()

        @Test("WebKit draws the exported linear burn exactly")
        func webKitDrawsPlusDarker() async throws {
            let url = try await Self.page()
            let image = try await harness.render(fileURL: url, viewportSize: CGSize(width: 40, height: 40), allowingReadAccessTo: Self.fixturesDir)
            let pixel = try #require(Self.rgba(of: image, atFraction: 0.5))
            // #1A004D, within a step either way.
            #expect(abs(Int(pixel.r) - 0x1A) <= 2 && abs(Int(pixel.g) - 0x00) <= 2 && abs(Int(pixel.b) - 0x4D) <= 2, "\(pixel)")
        }

        /// Exports a `#3366FF` square at linear burn over an `#E6994D` one and writes a page
        /// that inlines it.
        @concurrent
        private nonisolated static func page() async throws -> URL {
            let fixture = try SVGExportFixture("""
            [{"type": "frame", "id": "b", "width": 40, "height": 40, "fill": "#E6994D", "layout": "none", "children": [
              {"type": "rectangle", "id": "r", "width": 40, "height": 40, "fill": "#3366FF",
               "metadata": {"type": "woodcase", "woodcase": {"blendMode": "linearBurn"}}}]}]
            """)
            let svg = try #require(SVGExporter.string(
                fixture.document, layoutRects: fixture.rects, rootNodeIDs: ["b"], bounds: nil, imageProvider: { _ in nil }
            ))
            let html = """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <style>html, body { margin: 0; padding: 0; background: #FFFFFF; } svg { display: block; }</style>
            </head><body>\(svg)<script>window.__READY__ = true;</script></body></html>
            """
            let tmpDir = fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let url = tmpDir.appendingPathComponent("svg-linear-burn.html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        /// The sRGB pixel at the given fraction of `image`'s width and height.
        private nonisolated static func rgba(of image: CGImage, atFraction fraction: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            let x = Int(Double(width) * fraction), y = Int(Double(height) * fraction)
            let index = (y * width + x) * 4
            return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }
    }

#endif
