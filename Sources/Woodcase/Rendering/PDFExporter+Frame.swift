//
//  PDFExporter+Frame.swift
//  Woodcase
//

import CoreGraphics
import Foundation

public extension PDFExporter.Page {
    /// A page holding one node of a document, at the node's own size, drawn at the
    /// page's origin.
    ///
    /// ``PenRenderer/render(_:layoutRects:into:rootNodeID:overrides:imageProvider:)``
    /// draws in canvas coordinates and leaves positioning to its caller, so a page that
    /// passes it a frame sitting anywhere but (0, 0) draws off the page and comes out
    /// blank. Every PDF of a frame goes through here so that translation lives in one
    /// place.
    ///
    /// - Parameters:
    ///   - nodeID: The node to draw, usually a top-level frame.
    ///   - document: The resolved, ref-expanded document.
    ///   - layoutRects: The document's layout, from ``PenLayoutEngine/layout(_:textMeasurer:)``.
    ///   - imageProvider: Loads the images that image fills name.
    /// - Returns: `nil` when the layout has no rect for `nodeID`.
    init?(
        frame nodeID: String,
        of document: PenDocument,
        layoutRects: [String: PenRect],
        imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil }
    ) {
        guard let rect = layoutRects[nodeID] else { return nil }
        self.init(width: CGFloat(rect.width), height: CGFloat(rect.height)) { context in
            context.translateBy(x: CGFloat(-rect.x), y: CGFloat(-rect.y))
            PenRenderer.render(
                document, layoutRects: layoutRects, into: context,
                rootNodeID: nodeID, imageProvider: imageProvider
            )
        }
    }
}
