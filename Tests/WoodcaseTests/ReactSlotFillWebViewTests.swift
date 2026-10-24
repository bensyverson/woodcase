//
//  ReactSlotFillWebViewTests.swift
//  WoodcaseTests
//

// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// `slots-screen.pen`'s `Board` page as React writes it, compiled by the harness's Babel
    /// and rendered in WebKit: each `Screen` instance shows what its slot fill says — the
    /// default content's `Item A` rows, the fill's `Item B` rows, and nothing for the emptied
    /// list (Penumbra spec §13.5 rule 13; ``CodeGenSlotFillTests`` reads the markup).
    @Suite("React slot fills", .tags(.webViewRegression), .serialized, .hangGuard)
    @MainActor
    struct ReactSlotFillWebViewTests {
        private static let fixturesDir = SwiftUIFixtures.directory
        private static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private let harness = WebViewTestHarness()

        /// `Item A`'s and `Item B`'s fills.
        private static let itemA: (UInt8, UInt8, UInt8) = (0xEE, 0xF2, 0xFF)
        private static let itemB: (UInt8, UInt8, UInt8) = (0xFE, 0xF3, 0xC7)

        @Test("Each instance draws its own slot content: the default, the fill, or nothing")
        func fillsRender() async throws {
            let document = try SwiftUIFixtures.document("slots-screen")
            let page = try #require(PageAnalyzer.analyze(document).first { $0.name == "Board" })
            let files = ReactEmitter.emit(
                document: document,
                components: ComponentAnalyzer.analyze(document),
                pages: [page],
                theme: ThemeAnalyzer.analyze(document)
            ).files
            let html = ReactHarnessBuilder.buildHTML(
                from: files, componentName: "Board", viewportWidth: 940, viewportHeight: 360, jsRelativePath: "../js"
            )
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let url = tmpDir.appendingPathComponent("slot-fills-Board.html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            let capture = try await harness.render(
                fileURL: url, viewportSize: CGSize(width: 940, height: 360), allowingReadAccessTo: Self.projectRoot
            )

            // Where Pen lays out each instance's first row, from the board's top-left.
            let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
            let layout = PenLayoutEngine.layout(resolved)
            let rects = PenLayoutEngine.absoluteRects(under: "board", in: resolved, layoutRects: layout)
            let board = try #require(rects["board"])
            let defaultRow = try #require(rects["screenDefault/listRow1/itemA"])
            let filledRow = try #require(rects["screenFilled/fillB1/itemB"])
            let scale = Double(capture.width) / 940
            let pixels = try #require(Pixels(capture))
            func sample(_ rect: PenRect, dx: Double = 0) -> (UInt8, UInt8, UInt8) {
                pixels.rgb(
                    x: Int((rect.x + rect.width - 10 + dx - board.x) * scale),
                    y: Int((rect.y + rect.height / 2 - board.y) * scale)
                )
            }

            #expect(Self.matches(sample(defaultRow), Self.itemA), "Default: \(sample(defaultRow))")
            #expect(Self.matches(sample(filledRow), Self.itemB), "Filled: \(sample(filledRow))")
            // Emptied sits 310 points right of Filled; where Filled draws its first row it
            // draws neither item.
            let emptied = sample(filledRow, dx: 310)
            #expect(!Self.matches(emptied, Self.itemA) && !Self.matches(emptied, Self.itemB), "Emptied: \(emptied)")
        }

        /// Whether two colors agree within a few levels a channel.
        private static func matches(_ color: (UInt8, UInt8, UInt8), _ expected: (UInt8, UInt8, UInt8)) -> Bool {
            abs(Int(color.0) - Int(expected.0)) <= 6 && abs(Int(color.1) - Int(expected.1)) <= 6
                && abs(Int(color.2) - Int(expected.2)) <= 6
        }

        /// A capture's pixels, redrawn as 8-bit RGBA.
        private struct Pixels {
            let width: Int
            let height: Int
            let bytes: [UInt8]

            init?(_ image: CGImage) {
                width = image.width
                height = image.height
                var buffer = [UInt8](repeating: 0, count: width * height * 4)
                let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
                    guard let context = CGContext(
                        data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    return true
                }
                guard drawn else { return nil }
                bytes = buffer
            }

            /// The color at a pixel, from the top-left.
            func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
                let x = min(max(x, 0), width - 1)
                let y = min(max(y, 0), height - 1)
                let offset = (y * width + x) * 4
                return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
            }
        }
    }

#endif
