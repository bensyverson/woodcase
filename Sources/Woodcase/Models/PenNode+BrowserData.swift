//
//  PenNode+BrowserData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Browser

    /// Type-specific data for a `browser` node — a live web page Pen (format 2.19 and later) embeds in
    /// the design.
    ///
    /// Pen draws a snapshot of the page it loads. Woodcase never loads it: the layout
    /// engine sizes the node like a rectangle, the renderer draws a neutral placeholder
    /// labeled with ``url`` (see <doc:PenRendering>), and the React emitter writes an
    /// `<iframe>` pointing at ``pageURL``.
    ///
    /// The keys are exactly those of Pen's format since 2.19. A browser takes a stroke
    /// and effects but no fill and no blend mode, and ``zoom`` and the scroll offsets
    /// are plain numbers, never `$variable` references.
    struct BrowserData: Friendly, PenStrokable {
        /// Creates a browser payload; every key is optional, as in the file.
        public init(
            url: String? = nil,
            deviceId: String? = nil,
            zoom: Double? = nil,
            scrollX: Double? = nil,
            scrollY: Double? = nil,
            cornerRadius: PenCornerRadius? = nil,
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            stroke: PenFills? = nil,
            strokeWidth: PenStrokeWidth? = nil,
            strokeLinecap: PenStrokeCap? = nil,
            strokeLinejoin: PenStrokeJoin? = nil,
            strokeAlignment: PenStrokeAlign? = nil,
            effects: PenEffects? = nil
        ) {
            self.url = url
            self.deviceId = deviceId
            self.zoom = zoom
            self.scrollX = scrollX
            self.scrollY = scrollY
            self.cornerRadius = cornerRadius
            self.width = width
            self.height = height
            self.stroke = stroke
            self.strokeWidth = strokeWidth
            self.strokeLinecap = strokeLinecap
            self.strokeLinejoin = strokeLinejoin
            self.strokeAlignment = strokeAlignment
            self.effects = effects
        }

        /// The page's address as Pen stores it. Pen drops an `https://` scheme, so
        /// `https://example.com` is written `example.com`; ``pageURL`` puts it back.
        /// Empty means Pen shows its URL prompt.
        public var url: String?
        /// A device-emulation preset id; absent means a responsive viewport.
        public var deviceId: String?
        /// The page's zoom factor. Absent means 1.
        public var zoom: Double?
        /// The page's horizontal scroll offset.
        public var scrollX: Double?
        /// The page's vertical scroll offset.
        public var scrollY: Double?
        /// The radius the page's snapshot is clipped to — uniform, or one per corner.
        public var cornerRadius: PenCornerRadius?
        /// The node's width, laid out like a rectangle's.
        public var width: PenSizing?
        /// The node's height, laid out like a rectangle's.
        public var height: PenSizing?
        /// The stroke's paint.
        public var stroke: PenFills?
        /// The stroke's width — uniform, or one value per side.
        public var strokeWidth: PenStrokeWidth?
        /// How the stroke's line ends are capped.
        public var strokeLinecap: PenStrokeCap?
        /// How the stroke's corners are joined.
        public var strokeLinejoin: PenStrokeJoin?
        /// Where the stroke sits relative to the node's edge.
        public var strokeAlignment: PenStrokeAlign?
        /// The node's shadows and blurs.
        public var effects: PenEffects?

        /// The keys a `browser` node writes; `effects` is spelled `effect` in the file.
        public enum CodingKeys: String, CodingKey {
            case url, deviceId, zoom, scrollX, scrollY, cornerRadius
            case width, height
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
            case effects = "effect"
        }
    }
}

// MARK: - The page address

public extension PenNode.BrowserData {
    /// The full address of the page, with the `https://` scheme Pen strips restored,
    /// or `nil` when ``url`` is absent or blank.
    ///
    /// An address that already names a scheme (`http://…`, `https://…`) is kept as
    /// written, as are the scheme-only forms a browser loads without a host
    /// (`about:`, `data:`, `blob:`). A protocol-relative `//host/…` gains `https:`,
    /// and anything else — `example.com`, `localhost:3000` — gains `https://`.
    ///
    /// ```swift
    /// PenNode.BrowserData(url: "example.com").pageURL   // "https://example.com"
    /// ```
    var pageURL: String? {
        let address = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        if address.hasPrefix("//") { return "https:" + address }
        if address.prefixMatch(of: #/[A-Za-z][A-Za-z0-9+.\-]*:\/\//#) != nil { return address }
        if address.prefixMatch(of: #/(?i:about|data|blob):/#) != nil { return address }
        return "https://" + address
    }
}
