//
//  FigmaImportSession.swift
//  Woodcase
//

/// One run of ``FigmaImporter``: the message's tree and blobs, the components the clip
/// carries, and the losses reported so far.
struct FigmaImportSession {
    /// The node types the importer maps. Anything else on a page refuses the selection.
    static let supportedTypes: Set<String> = [
        "FRAME", "SECTION", "SYMBOL", "INSTANCE", "ROUNDED_RECTANGLE", "ELLIPSE", "VECTOR",
        "BOOLEAN_OPERATION", "TEXT", "RECTANGLE", "LINE", "REGULAR_POLYGON", "STAR",
    ]

    /// The caller's choices.
    let options: FigmaImportOptions
    /// The message's nodes.
    let tree: FigmaNodeTree
    /// The message's geometry blobs.
    let blobs: FigmaBlobTable
    /// The components the clip carries, which an instance may reference.
    let components: Set<FigmaGUID>
    /// What has been lost so far, one entry per node and feature.
    private(set) var losses: [FigmaImportLoss] = []

    /// A session over `tree` and `blobs` whose clip carries `components`.
    init(options: FigmaImportOptions, tree: FigmaNodeTree, blobs: FigmaBlobTable, components: Set<FigmaGUID>) {
        self.options = options
        self.tree = tree
        self.blobs = blobs
        self.components = components
    }

    /// Reports that `feature` of the node `record` was lost.
    ///
    /// A second report of the same feature on the same node adds its detail to the first,
    /// so a node loses each feature once however many fields it spans.
    mutating func report(
        _ feature: FigmaImportLoss.Feature, _ treatment: FigmaImportLoss.Treatment, on record: KiwiRecord, detail: String? = nil
    ) {
        let nodeID = FigmaGUID(record["guid"])?.penID ?? ""
        if let index = losses.firstIndex(where: { $0.nodeID == nodeID && $0.feature == feature }) {
            guard let detail else { return }
            let details = losses[index].detail.map { $0.components(separatedBy: ", ") } ?? []
            if !details.contains(detail) {
                losses[index].detail = (details + [detail]).joined(separator: ", ")
            }
            return
        }
        losses.append(FigmaImportLoss(
            nodeID: nodeID, figmaName: record["name"]?.stringValue, feature: feature, treatment: treatment, detail: detail
        ))
    }

    /// The Pen node made of the Figma node `guid` and everything under it.
    ///
    /// - Throws: ``FigmaImportError`` when a geometry blob cannot be read.
    mutating func node(_ guid: FigmaGUID) throws(FigmaImportError) -> PenNode {
        guard let record = tree.records[guid] else { throw .malformedMessage("node \(guid.penID) is missing") }
        reportUnreadFields(of: record)
        var common = commonProperties(of: record)
        let kind: PenNode.Kind
        switch tree.type(of: guid) {
        case "FRAME" where record["resizeToFit"]?.boolValue == true:
            kind = try group(record, guid: guid, common: &common)
        case "FRAME":
            kind = try frame(record, guid: guid, common: &common)
        case "SECTION":
            report(.section, .approximated, on: record)
            kind = try frame(record, guid: guid, common: &common)
        case "SYMBOL":
            common.reusable = true
            kind = try frame(record, guid: guid, common: &common)
        case "INSTANCE":
            kind = instance(record, common: &common)
        case "ROUNDED_RECTANGLE", "RECTANGLE":
            kind = rectangle(record, common: &common)
        case "ELLIPSE":
            kind = ellipse(record, common: &common)
        case "VECTOR":
            kind = try vector(record, common: &common)
        case "LINE":
            kind = line(record, common: &common)
        case "REGULAR_POLYGON":
            kind = polygon(record, common: &common)
        case "STAR":
            kind = try star(record, common: &common)
        case "BOOLEAN_OPERATION":
            kind = try boolean(record, guid: guid, common: &common)
        case "TEXT":
            kind = text(record, common: &common)
        case let type:
            throw .unsupportedNodes([FigmaImportError.UnsupportedNode(type: type, name: record["name"]?.stringValue, nodeID: guid.penID)])
        }
        reportSharedFeatures(of: record)
        var node = PenNode(id: guid.penID, common: common, kind: kind)
        if let mode = blendMode(of: record) { node.blendMode = mode }
        if record["locked"]?.boolValue == true {
            var metadata = node.common.metadata ?? PenMetadata(type: nil)
            metadata[woodcase: .locked] = .bool(true)
            node.common.metadata = metadata
        }
        return node
    }

    /// The children of `guid`, mapped, bottom layer first.
    mutating func children(of guid: FigmaGUID) throws(FigmaImportError) -> [PenNode] {
        var result: [PenNode] = []
        for child in tree.children[guid] ?? [] {
            try result.append(node(child))
        }
        return result
    }

    /// The properties every Pen node has: name, placement, opacity and visibility.
    private mutating func commonProperties(of record: KiwiRecord) -> PenNodeCommon {
        var common = PenNodeCommon(name: record["name"]?.stringValue)
        let placement = (FigmaTransform(record["transform"]) ?? .identity).placement
        common.x = .literal(placement.x)
        common.y = .literal(placement.y)
        if placement.rotation != 0 { common.rotation = .literal(placement.rotation) }
        if placement.flipX { common.flipX = .literal(true) }
        if placement.flipY { common.flipY = .literal(true) }
        if placement.isSkewed { report(.transformSkew, .dropped, on: record) }
        if let opacity = record["opacity"]?.doubleValue, opacity != 1 { common.opacity = .literal(opacity) }
        if record["visible"]?.boolValue == false { common.enabled = .literal(false) }
        if record["mask"]?.boolValue == true {
            common.enabled = .literal(false)
            report(.mask, .dropped, on: record)
        }
        return common
    }

    /// The node's own blend mode, `nil` for normal and pass-through.
    mutating func blendMode(of record: KiwiRecord) -> PenBlendMode? {
        guard let name = record["blendMode"]?.enumName else { return nil }
        return blendMode(named: name, on: record)
    }

    /// The Pen blend mode Figma's `BlendMode` case `name` is, `nil` for normal and
    /// pass-through; an unknown mode is reported and drawn normal.
    mutating func blendMode(named name: String, on record: KiwiRecord) -> PenBlendMode? {
        switch name {
        case "NORMAL", "PASS_THROUGH": return nil
        case "DARKEN": return .darken
        case "MULTIPLY": return .multiply
        case "LINEAR_BURN": return .linearBurn
        case "COLOR_BURN": return .colorBurn
        case "LIGHTEN": return .light
        case "SCREEN": return .screen
        case "LINEAR_DODGE": return .linearDodge
        case "COLOR_DODGE": return .colorDodge
        case "OVERLAY": return .overlay
        case "SOFT_LIGHT": return .softLight
        case "HARD_LIGHT": return .hardLight
        case "DIFFERENCE": return .difference
        case "EXCLUSION": return .exclusion
        case "HUE": return .hue
        case "SATURATION": return .saturation
        case "COLOR": return .color
        case "LUMINOSITY": return .luminosity
        default:
            report(.blendMode, .approximated, on: record, detail: name)
            return nil
        }
    }
}
