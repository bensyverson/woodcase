import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// How the CG renderer draws a shadow's spread (`metadata.woodcase.shadowSpread`, leaf
/// zRp9CO): an outer shadow is cast by the silhouette grown by the spread, an inner one by
/// the shape shrunk by it — CSS's `box-shadow` spread. Every probe is a 60 × 40 white
/// rectangle at 40, 30 whose shadow is opaque black with no blur, so a pixel is either in
/// the shadow or not.
struct PenShadowSpreadRenderTests {
    /// The rectangle with one shadow, and `spread` stored for it — made for `madeFor`, which
    /// is the shadow itself unless a test says otherwise.
    private func grid(shadow: String, spread: Double?, madeFor: String? = nil) throws -> PixelGrid {
        let woodcase = spread.map { #""shadowSpread": [{"effect": 0, "spread": \#($0), "shadow": \#(madeFor ?? shadow)}]"# } ?? ""
        return try PenStrokeDashRendering.grid("""
        {"type": "rectangle", "id": "r", "x": 40, "y": 30, "width": 60, "height": 40, "fill": "#FFFFFF",
         "effect": \(shadow), "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        """)
    }

    private static let outer = ##"{"type": "shadow", "shadowType": "outer", "blur": 0, "color": "#000000"}"##
    private static let dropped = ##"{"type": "shadow", "shadowType": "outer", "offset": {"x": 0, "y": 20}, "blur": 0, "color": "#000000"}"##
    private static let inner = ##"{"type": "shadow", "shadowType": "inner", "blur": 0, "color": "#000000"}"##

    private func black(_ grid: PixelGrid, _ x: Int, _ y: Int) -> Bool {
        let pixel = grid.pixel(x, y)
        return pixel.a > 200 && pixel.r < 40
    }

    private func notBlack(_ grid: PixelGrid, _ x: Int, _ y: Int) -> Bool {
        !black(grid, x, y)
    }

    @Test("An outer shadow with no offset or blur casts nothing outside the shape without a spread")
    func noSpreadNoShadow() throws {
        let grid = try grid(shadow: Self.outer, spread: nil)
        #expect(notBlack(grid, 35, 50), "\(grid.pixel(35, 50))")
    }

    @Test("A positive spread grows an outer shadow past the shape on every side")
    func positiveSpreadGrowsOuterShadow() throws {
        let grid = try grid(shadow: Self.outer, spread: 10)
        #expect(black(grid, 35, 50), "left: \(grid.pixel(35, 50))")
        #expect(black(grid, 105, 50), "right: \(grid.pixel(105, 50))")
        #expect(black(grid, 70, 25), "top: \(grid.pixel(70, 25))")
        #expect(black(grid, 70, 75), "bottom: \(grid.pixel(70, 75))")
        #expect(notBlack(grid, 28, 50), "past the spread: \(grid.pixel(28, 50))")
        #expect(notBlack(grid, 70, 50), "the shadow never shows through the node: \(grid.pixel(70, 50))")
    }

    @Test("A negative spread shrinks an outer shadow")
    func negativeSpreadShrinksOuterShadow() throws {
        // Dropped 20 pt, the shadow's bottom edge is at 90 and its left at 40; shrunk by 10,
        // at 80 and 50.
        let plain = try grid(shadow: Self.dropped, spread: nil)
        #expect(black(plain, 45, 85), "unspread: \(plain.pixel(45, 85))")
        let shrunk = try grid(shadow: Self.dropped, spread: -10)
        #expect(notBlack(shrunk, 45, 85), "shrunk, below and beside: \(shrunk.pixel(45, 85))")
        #expect(black(shrunk, 70, 75), "shrunk, still under the middle: \(shrunk.pixel(70, 75))")
    }

    @Test("A positive spread casts an inner shadow in from every edge")
    func positiveSpreadGrowsInnerShadow() throws {
        let plain = try grid(shadow: Self.inner, spread: nil)
        #expect(notBlack(plain, 44, 50), "unspread: \(plain.pixel(44, 50))")
        let spread = try grid(shadow: Self.inner, spread: 8)
        #expect(black(spread, 44, 50), "left: \(spread.pixel(44, 50))")
        #expect(black(spread, 70, 34), "top: \(spread.pixel(70, 34))")
        #expect(notBlack(spread, 70, 50), "the middle stays clear: \(spread.pixel(70, 50))")
    }

    @Test("A stale spread — its shadow changed in Pen — is ignored")
    func staleSpreadIsIgnored() throws {
        let madeFor = Self.outer.replacingOccurrences(of: #""blur": 0"#, with: #""blur": 6"#)
        let grid = try grid(shadow: Self.outer, spread: 10, madeFor: madeFor)
        #expect(notBlack(grid, 35, 50), "\(grid.pixel(35, 50))")
    }
}
