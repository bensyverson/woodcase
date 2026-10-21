//
//  FigmaImportLoss.swift
//  Woodcase
//

/// Something of a Figma node that the Pen document it became does not carry as Figma had
/// it: dropped, drawn another way, resolved to a value, or flattened.
///
/// ``FigmaImporter`` reports one for every Figma field it cannot map, so nothing is lost
/// silently; a caller shows them after a paste. One loss covers one feature of one node,
/// however many of its fields the feature spans. <doc:FigmaImport> lists every feature.
public struct FigmaImportLoss: Friendly, CustomStringConvertible {
    /// What part of Figma's model was lost. Each case is one row of the mapping table in
    /// <doc:FigmaImport>.
    public enum Feature: String, Friendly, CaseIterable {
        /// A boolean operation, flattened to the one path it draws.
        case booleanOperation
        /// A boolean operand the importer cannot outline, such as text, left out of the result.
        case booleanOperand
        /// A mask: the mask shape is hidden and the content it masked draws unmasked.
        case mask
        /// A horizontal or vertical constraint other than left or top.
        case constraints
        /// Auto layout: the children keep the positions Figma gave them, and nothing reflows.
        case autoLayout
        /// A layout grid.
        case layoutGrid
        /// A section, imported as a frame.
        case section
        /// A transform with a skew or a scale, which Pen's position, turn and flips cannot hold.
        case transformSkew
        /// A component's properties, which Pen components do not have.
        case componentProperties
        /// A variant set's properties; its variants are imported as components.
        case variants
        /// An instance swapped for another component inside an instance.
        case instanceSwap
        /// An instance override Pen has no property for.
        case instanceOverride
        /// An instance whose component the clipboard does not carry.
        case missingComponent
        /// A shared style, resolved to the values it applies.
        case styleReference
        /// A variable binding, resolved to the value Figma drew.
        case variableBinding
        /// A frame's pinned variable mode, resolved into its descendants' values.
        case variableMode
        /// A diamond gradient, drawn as a radial one.
        case diamondGradient
        /// A gradient transform with a skew, drawn without it.
        case gradientSkew
        /// An image paint whose bytes the caller did not supply: the clipboard carries only
        /// the image's hash.
        case imageNotEmbedded
        /// A tiled image paint, drawn to cover the box.
        case imageTile
        /// A paint type Pen has no fill for, such as video, noise or a pattern.
        case unsupportedPaint
        /// An effect type Pen has no effect for, such as noise, texture or glass.
        case unsupportedEffect
        /// A progressive blur.
        case progressiveBlur
        /// A drop shadow Figma shows through a translucent fill, which Pen knocks out.
        case shadowBehindNode
        /// A stroke cap Pen cannot draw (arrows, markers), drawn butt.
        case strokeCap
        /// A dash pattern on a stroke Pen cannot dash, such as one with per-side widths.
        case strokeDash
        /// Per-vertex or per-segment stroke caps, joins or corner radii in a vector network.
        case vectorStyleOverride
        /// Filled regions of one vector with different winding rules; one rule applies.
        case windingRules
        /// Stroked segments of a filled vector that border no filled region.
        case openStrokeSegments
        /// Corner smoothing (squircle corners), drawn as plain arcs.
        case cornerSmoothing
        /// A polygon whose Pen box is larger than Figma's, so its corners land where Figma
        /// drew them: a gradient or image laid over the box spreads over the larger one.
        case polygonBox
        /// A corner radius on a star, which is drawn with sharp points.
        case shapeCornerRadius
        /// Text truncation with an ellipsis.
        case textTruncation
        /// Bulleted or numbered list markers.
        case textList
        /// A text case transform (upper, lower, title, small caps).
        case textCase
        /// Paragraph spacing or indent.
        case paragraph
        /// A hyperlink on text.
        case hyperlink
        /// A blend mode Pen does not know.
        case blendMode
        /// A field the importer neither maps nor knows to be safe to ignore.
        case unreadField
    }

    /// What became of the lost feature.
    public enum Treatment: String, Friendly, CaseIterable {
        /// Left out of the Pen node.
        case dropped
        /// Drawn another way, as close as Pen allows.
        case approximated
        /// Replaced by the value Figma resolved it to, so the link to its source is gone.
        case resolved
        /// Baked into geometry or positions that no longer respond to it.
        case flattened
    }

    /// The id of the Pen node the loss is on.
    public var nodeID: String
    /// The Figma layer's name, if it had one.
    public var figmaName: String?
    /// What was lost.
    public var feature: Feature
    /// What became of it.
    public var treatment: Treatment
    /// The particulars — a field, paint or effect name, an image hash — if there are any.
    public var detail: String?

    /// A loss of `feature` on node `nodeID`.
    public init(nodeID: String, figmaName: String?, feature: Feature, treatment: Treatment, detail: String? = nil) {
        self.nodeID = nodeID
        self.figmaName = figmaName
        self.feature = feature
        self.treatment = treatment
        self.detail = detail
    }

    /// One line for a person: the layer, the feature, what became of it and the particulars.
    public var description: String {
        let layer = figmaName.map { "\"\($0)\"" } ?? nodeID
        let particulars = detail.map { " (\($0))" } ?? ""
        return "\(layer): \(feature.rawValue) \(treatment.rawValue)\(particulars)"
    }
}
