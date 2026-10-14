#if os(macOS)

    import CoreGraphics
    import Foundation
    @testable import Woodcase

    /// A small document laid out, and an SVG export of it parsed back as XML, for the
    /// structural ``SVGExporter`` tests.
    struct SVGExportFixture {
        /// The expanded, resolved document.
        let document: PenDocument
        /// Its settled rects.
        let rects: [String: PenRect]

        /// Parses `children` — the JSON of the document's top-level nodes — and lays it out.
        ///
        /// - Parameter children: A JSON array of nodes, as a `.pen` file writes them.
        init(_ children: String) throws {
            let json = #"{"version": "2.19", "children": "# + children + "}"
            let parsed = try PenParser.parse(Data(json.utf8))
            document = PenVariableResolver.resolve(PenRefExpander.expand(parsed))
            rects = PenLayoutEngine.layout(document)
        }

        /// The SVG of `roots` at their canvas positions, parsed.
        ///
        /// - Parameters:
        ///   - roots: The root node ids.
        ///   - bounds: The region to frame, or `nil` for the roots' painted extent.
        ///   - imageProvider: Resolves image fills.
        /// - Returns: The parsed document, or `nil` when the exporter returned nothing.
        func svg(
            _ roots: [String],
            bounds: PenRect? = nil,
            imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil }
        ) throws -> XMLDocument? {
            guard let data = SVGExporter.data(
                document, layoutRects: rects, rootNodeIDs: roots, bounds: bounds, imageProvider: imageProvider
            ) else { return nil }
            return try XMLDocument(data: data)
        }

        /// Every element named `name`, anywhere in `xml`.
        static func elements(_ name: String, in xml: XMLDocument) throws -> [XMLElement] {
            try xml.nodes(forXPath: "//*[local-name()='\(name)']").compactMap { $0 as? XMLElement }
        }

        /// The value of `attribute` on `element`, or `nil`.
        static func attribute(_ attribute: String, of element: XMLElement) -> String? {
            element.attribute(forName: attribute)?.stringValue
        }

        /// A 2×2 opaque red image, for image fills.
        static let redImage: CGImage = {
            let context = CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            return context.makeImage()!
        }()
    }

#endif
