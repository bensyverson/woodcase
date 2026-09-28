//
//  SwiftUIEmitterPaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a node's fills become in emitted SwiftUI: gradients, images, stacks, blend modes,
/// opacity, and paints on text. ``SwiftUIRenderTests`` measures the same output against
/// Pen's renders; these pin each decision.
struct SwiftUIEmitterPaintTests {
    private static let redBlue = ##"[{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]"##
    private static let stops = "Gradient(stops: [.init(color: Color(hex: 0xFF0000), location: 0), "
        + ".init(color: Color(hex: 0x0000FF), location: 1)]).colorSpace(.device)"

    // MARK: - Linear

    @Test("A default linear gradient runs bottom to top, in device colour space")
    func linearDefault() throws {
        let code = try body(child: rect(fill: gradient("linear")))
        #expect(code.contains(".fill(.linearGradient(\(Self.stops), startPoint: .bottom, endPoint: .top))"))
    }

    @Test("A turned linear gradient on a fixed box keeps Pen's stop lines, not the unit box's")
    func linearTurnedOnFixedBox() throws {
        let code = try body(child: rect(fill: gradient("linear", extra: ##""rotation": 45"##), width: 240, height: 72))
        #expect(code.contains(".fill(.linearGradient(\(Self.stops), startPoint: UnitPoint(x: "))
        #expect(!code.contains("PenGradient("))
    }

    @Test("A turned linear gradient on a box of unknown proportions is drawn through PenGradient")
    func linearTurnedOnUnknownBox() throws {
        let child = ##"{"type": "rectangle", "id": "r", "width": "fill_container", "height": 72, "fill": \##(gradient("linear", extra: ##""rotation": 45"##))}"##
        let code = try body(child: child, frame: ##""layout": "vertical", "width": 300, "##)
        #expect(code.contains("PenGradient(.linear, \(Self.stops), rotation: 45)"))
    }

    @Test("The corrected end point puts stop 1 on Pen's line and the ramp square to it, in points")
    func linearPointsGeometry() {
        let fill = PenFill.PenGradientFill(
            gradientType: .linear, center: PenFill.PenFillPosition(x: 0.3, y: 0.4),
            size: PenFill.PenFillSize(width: .literal(1), height: .literal(0.6)), rotation: .literal(315)
        )
        let geometry = GradientGeometry(fill)
        let (width, height) = (240.0, 72.0)
        let points = SwiftUIGradient.linearPoints(geometry, width: width, height: height)
        #expect(points.start == geometry.linearStart)
        // Pen's stop lines run along the gradient's own x axis.
        let a = geometry.point(NormalizedPoint(x: 0, y: 0.5))
        let b = geometry.point(NormalizedPoint(x: 1, y: 0.5))
        let line = ((b.x - a.x) * width, (b.y - a.y) * height)
        let ramp = ((points.end.x - points.start.x) * width, (points.end.y - points.start.y) * height)
        #expect(abs(line.0 * ramp.0 + line.1 * ramp.1) < 1e-9)
        let offEnd = ((points.end.x - geometry.linearEnd.x) * width, (points.end.y - geometry.linearEnd.y) * height)
        #expect(abs(offEnd.0 * line.1 - offEnd.1 * line.0) < 1e-9)
    }

    // MARK: - Radial and angular

    @Test("A radial gradient of even size is an elliptical gradient reaching half its size")
    func radialEven() throws {
        let code = try body(child: rect(fill: gradient("radial", extra: ##""size": {"width": 0.8, "height": 0.8}, "center": {"x": 0.25, "y": 0.5}"##)))
        #expect(code.contains(".fill(.ellipticalGradient(\(Self.stops), center: UnitPoint(x: 0.25, y: 0.5), endRadiusFraction: 0.4))"))
    }

    @Test("A radial gradient of uneven size is drawn through PenGradient")
    func radialUneven() throws {
        let code = try body(child: rect(fill: gradient("radial", extra: ##""size": {"width": 0.5, "height": 1}, "rotation": 45"##)))
        #expect(code.contains("PenGradient(.radial, \(Self.stops), width: 0.5, rotation: 45)"))
    }

    @Test("An angular gradient on a square box is a conic gradient starting straight up, turned counter-clockwise")
    func angularSquare() throws {
        let code = try body(child: rect(fill: gradient("angular", extra: ##""rotation": 45"##)))
        #expect(code.contains(".fill(.conicGradient(\(Self.stops), center: .center, angle: .degrees(-135)))"))
    }

    @Test("An angular gradient on a wide box is stretched with it, through PenGradient")
    func angularWide() throws {
        let code = try body(child: rect(fill: gradient("angular"), width: 240, height: 72))
        #expect(code.contains("PenGradient(.angular, \(Self.stops))"))
    }

    // MARK: - Images

    @Test("An image fill is the bundled image, placed by its mode, and the result lists the asset")
    func imageFill() throws {
        let fill = ##"{"type": "image", "url": "./images/text-fills-uv.png", "mode": "fill"}"##
        let result = try emit(child: rect(fill: fill))
        let code = try page(result)
        #expect(code.contains(##"Image(penResource: "text-fills-uv.png", bundle: .module)"##))
        #expect(code.contains(".resizable()"))
        #expect(code.contains(".scaledToFill()"))
        #expect(result.imageAssetURLs == ["./images/text-fills-uv.png"])
        let manifest = try #require(result.files.first { $0.path == "Package.swift" })
        #expect(manifest.content.contains(##".target(name: "PenUI", resources: [.process("Resources")])"##))
    }

    @Test("A fit image is scaled to fit; a stretched one only made resizable")
    func imageModes() throws {
        let fit = try body(child: rect(fill: ##"{"type": "image", "url": "./images/a.png", "mode": "fit"}"##))
        #expect(fit.contains(".scaledToFit()"))
        let stretch = try body(child: rect(fill: ##"{"type": "image", "url": "./images/a.png"}"##))
        #expect(stretch.contains(".resizable()"))
        #expect(!stretch.contains(".scaledTo"))
    }

    @Test("A remote image fill is AsyncImage, fetched at draw time, with no warning")
    func remoteImage() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(child: rect(fill: ##"{"type": "image", "url": "https://example.com/a.png", "mode": "fill"}"##), diagnostics: diagnostics)
        #expect(code.contains(##"AsyncImage(url: URL(string: "https://example.com/a.png"))"##))
        #expect(code.contains("{ image in"))
        #expect(code.contains(".resizable()"))
        #expect(code.contains(".scaledToFill()"))
        #expect(code.contains("} placeholder: {"))
        #expect(code.contains("Color.clear"))
        #expect(!code.contains("Image(penResource:"))
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("A remote image is scaled by its mode inside AsyncImage's content closure; a stretched one only made resizable")
    func remoteImageModes() throws {
        let fit = try body(child: rect(fill: ##"{"type": "image", "url": "https://example.com/a.png", "mode": "fit"}"##))
        #expect(fit.contains(".scaledToFit()"))
        let stretch = try body(child: rect(fill: ##"{"type": "image", "url": "https://example.com/a.png"}"##))
        #expect(stretch.contains(".resizable()"))
        #expect(!stretch.contains(".scaledTo"))
        // stretch is not centred in a Color.clear overlay — no second Color.clear beyond AsyncImage's placeholder.
        #expect(stretch.components(separatedBy: "Color.clear").count == 2)
    }

    @Test("A remote image never lists an asset to bundle, and an absolute local path is still a warning")
    func remoteAndAbsoluteImagesAreNotBundled() throws {
        let remote = try emit(child: rect(fill: ##"{"type": "image", "url": "https://example.com/a.png"}"##))
        #expect(remote.imageAssetURLs.isEmpty)

        let diagnostics = PenDiagnosticCollector()
        let code = try body(child: rect(fill: ##"{"type": "image", "url": "/Users/ben/a.png"}"##), diagnostics: diagnostics)
        #expect(!code.contains("Image("))
        #expect(!code.contains("AsyncImage("))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("/Users/ben/a.png") })
    }

    // MARK: - Stacks, blend modes and opacity

    @Test("Stacked fills paint bottom to top: the top one fills the shape, each lower one a background in it")
    func stackedFills() throws {
        let top = gradient("linear", extra: ##""opacity": 0.5"##)
        let code = try body(child: rect(fill: ##"["#00FF00", \##(top)]"##, radius: 8))
        let shape = ".rect(cornerRadius: 8, style: .circular)"
        #expect(code.contains(".fill(.linearGradient(\(Self.stops), startPoint: .bottom, endPoint: .top).opacity(0.5))"))
        #expect(code.contains(".background(Color(hex: 0x00FF00), in: \(shape))"))
    }

    @Test("A fill's blend mode is the style's; linear burn is plusDarker, which is the same formula")
    func fillBlendModes() throws {
        let code = try body(child: rect(fill: ##"["#FF0000", {"type": "color", "color": "#0000FF", "blendMode": "linearBurn"}, {"type": "color", "color": "#FFFFFF", "blendMode": "multiply"}]"##))
        #expect(code.contains(".fill(Color(hex: 0xFFFFFF).blendMode(.multiply))"))
        #expect(code.contains(".background(Color(hex: 0x0000FF).blendMode(.plusDarker), in: .rect)"))
    }

    @Test("An image in a stack makes every layer a view: a ZStack clipped to the shape")
    func imageInStack() throws {
        let image = ##"{"type": "image", "url": "./images/a.png", "mode": "fill", "opacity": 0.5, "blendMode": "screen"}"##
        let code = try body(child: rect(fill: ##"["#00FF00", \##(image)]"##, radius: 8))
        #expect(code.contains("ZStack {"))
        #expect(code.contains("Rectangle()\n") && code.contains(".fill(Color(hex: 0x00FF00))"))
        #expect(code.contains(".opacity(0.5)"))
        #expect(code.contains(".blendMode(.screen)"))
        #expect(code.contains(".clipShape(.rect(cornerRadius: 8, style: .circular))"))
    }

    @Test("A frame with children paints its gradient as a background")
    func frameGradientBackground() throws {
        let code = try body(child: rect(fill: ##""#FF0000""##), frame: ##""fill": \##(gradient("linear")), "##)
        #expect(code.contains(".background(.linearGradient(\(Self.stops), startPoint: .bottom, endPoint: .top))"))
    }

    @Test("Gradients, images and blend modes are no longer reported; a shader and a stop variable still are")
    func diagnostics() throws {
        let diagnostics = PenDiagnosticCollector()
        let fills = ##"[\##(gradient("angular")), {"type": "color", "color": "#FF0000", "blendMode": "multiply"}]"##
        _ = try body(child: rect(fill: fills), diagnostics: diagnostics)
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "r" })

        let shader = PenDiagnosticCollector()
        _ = try body(child: rect(fill: ##"{"type": "shader", "url": "s.glsl"}"##), diagnostics: shader)
        #expect(shader.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("shader fills") })

        let variable = PenDiagnosticCollector()
        let themed = ##"{"type": "gradient", "colors": [{"color": "$brand", "position": 0}, {"color": "#FFFFFF", "position": 1}]}"##
        _ = try body(child: rect(fill: themed), diagnostics: variable)
        #expect(variable.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("$brand") })
    }

    /// A stop's position variable is read through `PenTheme` now (SwiftUIEmitterThemeReadTests);
    /// only one the document does not define is left out, and it is named.
    @Test("A gradient stop naming a position variable the document lacks is reported, and the gradient is not drawn")
    func gradientStopPositionVariableUndefined() throws {
        let diagnostics = PenDiagnosticCollector()
        let themed = ##"{"type": "gradient", "colors": [{"color": "#FF0000", "position": "$missingStop"}, {"color": "#FFFFFF", "position": 1}]}"##
        let code = try body(child: rect(fill: themed), diagnostics: diagnostics)
        #expect(!code.contains(".linearGradient"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $missingStop") })
    }

    // MARK: - Text

    @Test("Painted text shows its layers through its glyphs, over the node's box")
    func paintedText() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "textGrowth": "fixed-width-height", "width": 400, "height": 120, "fill": \##(gradient("linear", extra: ##""rotation": 270"##))}"##
        let code = try body(child: text)
        #expect(code.contains(".penTextFill {"))
        #expect(code.contains("Rectangle()\n") && code.contains(".fill(.linearGradient(\(Self.stops), startPoint: .leading, endPoint: .trailing))"))
        #expect(!code.contains(".foregroundStyle("))
    }

    // MARK: - Support

    @Test("The paint support file draws Pen's gradient map and masks text paints")
    func supportTemplate() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+Paint.swift"])
        #expect(support.contains("struct PenGradient: View"))
        #expect(support.contains("func penTextFill"))
        #expect(support.contains("var gradient: AnyGradient"))
    }

    // MARK: - Helpers

    private func gradient(_ type: String, extra: String = "") -> String {
        let tail = extra.isEmpty ? "" : ", \(extra)"
        return ##"{"type": "gradient", "gradientType": "\##(type)", "colors": \##(Self.redBlue)\##(tail)}"##
    }

    private func rect(fill: String, width: Double = 120, height: Double = 120, radius: Double = 0) -> String {
        let corner = radius > 0 ? ##", "cornerRadius": \##(SwiftUILiteral.number(radius))"## : ""
        return ##"{"type": "rectangle", "id": "r", "width": \##(SwiftUILiteral.number(width)), "height": \##(SwiftUILiteral.number(height))\##(corner), "fill": \##(fill)}"##
    }

    private func emit(child: String, frame keys: String = "", diagnostics: PenDiagnosticCollector? = nil) throws -> EmitResult {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "root", "name": "Board", \##(keys)"children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        return try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
    }

    private func page(_ result: EmitResult) throws -> String {
        try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }

    private func body(child: String, frame keys: String = "", diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        try page(emit(child: child, frame: keys, diagnostics: diagnostics))
    }
}
