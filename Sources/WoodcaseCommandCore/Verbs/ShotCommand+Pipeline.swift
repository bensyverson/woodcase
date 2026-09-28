//
//  ShotCommand+Pipeline.swift
//  WoodcaseCommandCore
//

import CoreGraphics
import Foundation
import Woodcase

extension Shot {
    /// Resolves the target and every `--outline` node, runs the render pipeline,
    /// annotates the image, and writes the PNG.
    ///
    /// - Parameters:
    ///   - request: What was asked for.
    ///   - url: The `.pen` file, already confirmed to exist.
    /// - Returns: What to print.
    /// - Throws: ``CommandFailure`` for anything a caller can fix, or whatever the
    ///   pipeline throws.
    static func render(_ request: Request, editing url: URL) async throws -> ShotOutput {
        let diagnostics = PenDiagnosticCollector()
        let selection = try await PenFileTransaction.read(at: url, diagnostics: diagnostics, fonts: .shared) { editable in
            editable.readContext.libraries.report(into: diagnostics)
            return try ShotTargets.select(
                node: request.node, outlining: request.outline, in: editable, editing: url
            )
        }.value

        let pins = try ThemePinParser.parse(request.theme)
        let document = PenVariableResolver.resolve(selection.document, theme: pins)
        await GoogleFontResolver.shared.prepareFonts(for: document, relativeTo: url, diagnostics: diagnostics)
        await RemoteImageResolver.shared.prepareImages(for: document, diagnostics: diagnostics)
        if let shaders = ShaderFills.diagnostic(in: document, node: selection.nodeID) {
            diagnostics.add(shaders)
        }
        report(diagnostics)

        let rects = PenLayoutEngine.layout(document)
        guard let rect = rects[selection.nodeID] else {
            throw ShotTargets.missingRectFailure(
                address: selection.nodeID, requested: request.node ?? selection.nodeID, editing: url
            )
        }
        guard let node = PenLayoutEngine.node(id: selection.nodeID, in: document.children) else {
            throw ShotTargets.missingRectFailure(
                address: selection.nodeID, requested: request.node ?? selection.nodeID, editing: url
            )
        }
        let framed = request.extent.region(of: node, rect: rect, layoutRects: rects)
        let cropped = try ShotTargets.drawnRegion(
            crop: request.crop, of: framed, named: selection.nodeID, editing: url
        )
        let scale = request.scale
            ?? effectiveScale(
                longestSide: max(cropped.width, cropped.height), maxPoints: Double(request.maxSize)
            )
        // Pen's PNG export of a painted extent keeps the extent's own — possibly
        // fractional — corner and rounds only the pixel *size* up
        // (`PenRect/grownToWholePixels(at:)`, `project/2026-09-28-geometry-model.md`).
        // A `--crop` is a caller-chosen sub-rectangle, not Pen's export box, so it is
        // left at whatever precision it was asked for.
        let region = request.crop == nil && request.extent == .painted
            ? cropped.grownToWholePixels(at: scale)
            : cropped
        let frame = PenLayoutEngine.absoluteRects(
            under: selection.nodeID, in: document, layoutRects: rects
        )
        let targets = try ShotTargets.overlayTargets(
            for: selection, in: frame, within: region, of: rect, editing: url
        )
        let imageProvider = PenRenderer.imageProvider(relativeTo: url.deletingLastPathComponent())

        guard let image = ShotRegionRenderer.image(
            of: document, node: selection.nodeID, region: region,
            layoutRects: rects, scale: scale, imageProvider: imageProvider
        ) else {
            throw Render.RenderError.renderFailed(selection.nodeID)
        }

        let annotated: ShotOverlay.Annotated
        do {
            annotated = try ShotOverlay.apply(
                to: image, outlining: targets, grid: request.grid,
                pixelsPerPoint: scale, origin: CGPoint(x: region.x, y: region.y)
            )
        } catch {
            throw CommandFailure(
                message: "Could not annotate the render of \(selection.nodeID): \(error)",
                exitCode: .environment
            )
        }

        let outputURL = URL(fileURLWithPath: request.out)
        try ImageExporter.writePNG(annotated.image, to: outputURL)

        return ShotOutput(
            node: selection.nodeID,
            scale: scale,
            rect: region,
            rects: ShotRect.list(for: selection, node: rect, outlines: targets),
            pixelWidth: annotated.image.width,
            pixelHeight: annotated.image.height,
            gutterLeft: annotated.leftGutter,
            gutterTop: annotated.topGutter,
            output: outputURL.path
        )
    }

    // MARK: - Diagnostics

    /// Writes whatever the font and image resolvers warned about to standard error, and the
    /// one warning for any shader fill under the shot node, which it draws without
    /// (``Woodcase/ShaderFills``).
    ///
    /// The resolvers already knew that a face was missing and a fallback was substituted
    /// — `shot` simply threw the collector away, so a picture drawn in a *different
    /// typeface from the one the file names* came back looking authoritative. A warning
    /// on stderr keeps stdout parseable and the exit code unchanged: the render did
    /// happen, it just did not happen in the face that was asked for.
    ///
    /// - Parameter diagnostics: The collector the resolvers wrote into.
    private static func report(_ diagnostics: PenDiagnosticCollector) {
        guard diagnostics.hasIssues else { return }
        for diagnostic in diagnostics.diagnostics {
            FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
        }
    }
}
