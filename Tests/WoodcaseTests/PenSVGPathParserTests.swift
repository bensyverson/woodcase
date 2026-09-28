import CoreGraphics
import Testing
@testable import Woodcase

struct PenSVGPathParserTests {
    // MARK: - Basic Commands

    @Test("Empty string returns nil")
    func emptyString() {
        #expect(PenSVGPathParser.parse("") == nil)
    }

    @Test("Whitespace-only string returns nil")
    func whitespaceOnly() {
        #expect(PenSVGPathParser.parse("   ") == nil)
    }

    @Test("Invalid input returns nil")
    func invalidInput() {
        #expect(PenSVGPathParser.parse("not a path") == nil)
    }

    @Test("MoveTo and LineTo absolute")
    func moveToLineTo() throws {
        let path = try #require(PenSVGPathParser.parse("M 10 20 L 100 200"))
        let box = path.boundingBox
        #expect(abs(box.minX - 10) < 0.01)
        #expect(abs(box.minY - 20) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - 200) < 0.01)
    }

    @Test("Relative moveTo and lineTo")
    func relativeMoveToLineTo() throws {
        // M 10 20 l 90 180 => line from (10,20) to (100,200)
        let path = try #require(PenSVGPathParser.parse("M 10 20 l 90 180"))
        let box = path.boundingBox
        #expect(abs(box.minX - 10) < 0.01)
        #expect(abs(box.minY - 20) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - 200) < 0.01)
    }

    // MARK: - Horizontal and Vertical Lines

    @Test("Horizontal line absolute")
    func horizontalLine() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 50 H 100"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.minY - 50) < 0.01)
        #expect(abs(box.maxY - 50) < 0.01)
    }

    @Test("Vertical line absolute")
    func verticalLine() throws {
        let path = try #require(PenSVGPathParser.parse("M 50 0 V 100"))
        let box = path.boundingBox
        #expect(abs(box.minX - 50) < 0.01)
        #expect(abs(box.maxX - 50) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxY - 100) < 0.01)
    }

    @Test("Relative horizontal and vertical lines")
    func relativeHV() throws {
        // M 10 10 h 50 v 50 => goes to (60,10) then (60,60)
        let path = try #require(PenSVGPathParser.parse("M 10 10 h 50 v 50"))
        let box = path.boundingBox
        #expect(abs(box.minX - 10) < 0.01)
        #expect(abs(box.minY - 10) < 0.01)
        #expect(abs(box.maxX - 60) < 0.01)
        #expect(abs(box.maxY - 60) < 0.01)
    }

    // MARK: - Close Path

    @Test("Close path creates a closed triangle")
    func closePath() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 L 100 0 L 50 100 Z"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - 100) < 0.01)
    }

    // MARK: - Cubic Bézier

    @Test("Cubic bezier absolute")
    func cubicBezier() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 C 25 50 75 50 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        // Control points at y=50 will make the curve extend downward
        #expect(box.maxY > 0)
    }

    @Test("Relative cubic bezier")
    func relativeCubicBezier() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 c 25 50 75 50 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
    }

    @Test("Smooth cubic bezier")
    func smoothCubicBezier() throws {
        // S uses reflection of previous cubic's last control point
        let path = try #require(PenSVGPathParser.parse("M 0 0 C 25 50 75 50 100 0 S 175 -50 200 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 200) < 0.01)
    }

    @Test("Relative smooth cubic bezier")
    func relativeSmoothCubicBezier() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 C 25 50 75 50 100 0 s 75 -50 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 200) < 0.01)
    }

    // MARK: - Quadratic Bézier

    @Test("Quadratic bezier absolute")
    func quadraticBezier() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 Q 50 100 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(box.maxY > 0)
    }

    @Test("Relative quadratic bezier")
    func relativeQuadraticBezier() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 q 50 100 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
    }

    @Test("Smooth quadratic bezier")
    func smoothQuadraticBezier() throws {
        // T reflects previous quadratic control point
        let path = try #require(PenSVGPathParser.parse("M 0 0 Q 50 100 100 0 T 200 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 200) < 0.01)
    }

    @Test("Relative smooth quadratic bezier")
    func relativeSmoothQuadraticBezier() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 Q 50 100 100 0 t 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 200) < 0.01)
    }

    // MARK: - Arc

    @Test("Arc absolute")
    func arcAbsolute() throws {
        // Half circle arc from (0,0) to (100,0), radius 50, sweep=1
        // Sweeps from θ=π to θ=2π (going through negative y)
        let path = try #require(PenSVGPathParser.parse("M 0 0 A 50 50 0 0 1 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 1)
        #expect(abs(box.maxX - 100) < 1)
        // The arc extends into negative y (above in screen coords)
        #expect(box.minY < 0)
    }

    @Test("Relative arc")
    func relativeArc() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 a 50 50 0 0 1 100 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 1)
        #expect(abs(box.maxX - 100) < 1)
    }

    @Test("Arc with large arc flag and sweep flag")
    func arcFlags() throws {
        // Large arc flag = 1 means the longer arc
        let path = try #require(PenSVGPathParser.parse("M 0 0 A 50 50 0 1 1 100 0"))
        let box = path.boundingBox
        // With large arc flag, the arc goes the long way around
        #expect(box.minY < 0)
    }

    // MARK: - Compact Notation

    @Test("Compact notation without spaces")
    func compactNotation() throws {
        let path = try #require(PenSVGPathParser.parse("M0,0L100,100"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - 100) < 0.01)
    }

    @Test("Negative numbers as separators")
    func negativeNumberSeparators() throws {
        // In SVG, negative sign can act as separator: M10-20 means M 10 -20
        let path = try #require(PenSVGPathParser.parse("M10-20L100-200"))
        let box = path.boundingBox
        #expect(abs(box.minX - 10) < 0.01)
        #expect(abs(box.minY - -200) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - -20) < 0.01)
    }

    // MARK: - Multiple Subpaths

    @Test("Multiple subpaths")
    func multipleSubpaths() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 L 50 50 Z M 100 100 L 150 150 Z"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxX - 150) < 0.01)
        #expect(abs(box.maxY - 150) < 0.01)
    }

    // MARK: - Implicit LineTo After MoveTo

    @Test("Implicit lineTo after moveTo")
    func implicitLineToAfterMoveTo() throws {
        // Per SVG spec, extra coordinates after M are treated as implicit L
        let path = try #require(PenSVGPathParser.parse("M 0 0 100 100 200 0"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 200) < 0.01)
    }

    // MARK: - Repeated Command Coordinates

    @Test("Multiple coordinate pairs for same command")
    func repeatedCoordinates() throws {
        // L followed by multiple coordinate pairs means multiple line segments
        let path = try #require(PenSVGPathParser.parse("M 0 0 L 50 0 100 50 100 100"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - 100) < 0.01)
    }

    // MARK: - Decimal Values

    @Test("Decimal coordinate values")
    func decimalValues() throws {
        let path = try #require(PenSVGPathParser.parse("M 0.5 1.5 L 99.5 199.5"))
        let box = path.boundingBox
        #expect(abs(box.minX - 0.5) < 0.01)
        #expect(abs(box.minY - 1.5) < 0.01)
        #expect(abs(box.maxX - 99.5) < 0.01)
        #expect(abs(box.maxY - 199.5) < 0.01)
    }

    // MARK: - Fill Rule

    @Test("Parse with even-odd fill rule")
    func fillRuleEvenOdd() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 L 100 0 L 100 100 L 0 100 Z", fillRule: .evenodd))
        // Path should be valid
        let box = path.boundingBox
        #expect(abs(box.maxX - 100) < 0.01)
    }

    @Test("Parse with nonzero fill rule (default)")
    func fillRuleNonzero() throws {
        let path = try #require(PenSVGPathParser.parse("M 0 0 L 100 0 L 100 100 L 0 100 Z"))
        let box = path.boundingBox
        #expect(abs(box.maxX - 100) < 0.01)
    }

    // MARK: - Real-World Path Data

    @Test("Complex real-world SVG path (star shape)")
    func realWorldStarPath() throws {
        // 5-pointed star
        let star = "M 50 0 L 61 35 L 98 35 L 68 57 L 79 91 L 50 70 L 21 91 L 32 57 L 2 35 L 39 35 Z"
        let path = try #require(PenSVGPathParser.parse(star))
        let box = path.boundingBox
        #expect(abs(box.minX - 2) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxX - 98) < 0.01)
        #expect(abs(box.maxY - 91) < 0.01)
    }

    @Test("Rounded rectangle path with curves")
    func roundedRectanglePath() throws {
        // A simple rounded rect using cubic curves for corners
        let rr = "M 10 0 L 90 0 C 95 0 100 5 100 10 L 100 90 C 100 95 95 100 90 100 L 10 100 C 5 100 0 95 0 90 L 0 10 C 0 5 5 0 10 0 Z"
        let path = try #require(PenSVGPathParser.parse(rr))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxX - 100) < 0.01)
        #expect(abs(box.maxY - 100) < 0.01)
    }

    // MARK: - Pencil Fixture Paths

    @Test("Pencil fixture: star path (compact relative notation)")
    func pencilStarPath() throws {
        // Pencil normalizes to compact relative commands
        let geometry = "M60 0l14 42 46 0-38 26 14 42-36-25-36 25 14-42-38-26 46 0z"
        let path = try #require(PenSVGPathParser.parse(geometry))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.5)
        #expect(abs(box.minY - 0) < 0.5)
        #expect(abs(box.maxX - 120) < 0.5)
        #expect(abs(box.maxY - 110) < 0.5)
    }

    @Test("Pencil fixture: wave path (relative cubic beziers)")
    func pencilWavePath() throws {
        let geometry = "M0 40c20-40 40-40 60 0 20 40 40 40 60 0"
        let path = try #require(PenSVGPathParser.parse(geometry))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.5)
        #expect(abs(box.maxX - 120) < 0.5)
        // Wave goes from y=40 up to y≈0 and down to y≈80
        #expect(box.minY < 5)
        #expect(box.maxY > 35)
    }

    @Test("Pencil fixture: heart path (relative cubics with close)")
    func pencilHeartPath() throws {
        let geometry = "M60 100c0 0-50-30-50-65 0-20 15-30 30-30 10 0 17 5 20 13 3-8 10-13 20-13 15 0 30 10 30 30 0 35-50 65-50 65z"
        let path = try #require(PenSVGPathParser.parse(geometry))
        let box = path.boundingBox
        #expect(abs(box.minX - 10) < 1)
        #expect(abs(box.minY - 5) < 1)
        #expect(abs(box.maxX - 110) < 1)
        #expect(abs(box.maxY - 100) < 1)
    }

    // MARK: - Pen 2.17 Compact Relative Output

    // Pen.app rewrites path geometry compact-relative on save: the sign of a
    // negative coordinate is the only separator between numbers.

    @Test("Compact relative geometry parses to the same path as the spaced form")
    func compactRelativeMatchesSpacedForm() throws {
        let compact = try #require(PenSVGPathParser.parse("M0 0l100 0-50 100z"))
        let spaced = try #require(PenSVGPathParser.parse("M 0 0 L 100 0 L 50 100 Z"))
        #expect(compact == spaced)
    }

    @Test("Compact relative geometry with a non-zero origin matches the spaced form")
    func compactRelativeOffsetMatchesSpacedForm() throws {
        let compact = try #require(PenSVGPathParser.parse("M10 10l80 0-40 80z"))
        let spaced = try #require(PenSVGPathParser.parse("M 10 10 L 90 10 L 50 90 Z"))
        #expect(compact == spaced)
    }
}
