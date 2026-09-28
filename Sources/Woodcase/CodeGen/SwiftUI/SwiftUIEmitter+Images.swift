//
//  SwiftUIEmitter+Images.swift
//  Woodcase
//

import Foundation

extension SwiftUIEmitter {
    /// The URLs of the local images `node` and its descendants fill or stroke with, as the .pen file
    /// writes them (`./images/photo.png`): what `woodcase generate swiftui` copies into
    /// `Sources/<Module>/Resources/`.
    ///
    /// Only the kinds this emitter paints are read, and only enabled nodes and fills; a
    /// remote or absolute URL is left out, as the views do not reference it.
    static func imageAssetURLs(in node: PenNode) -> Set<String> {
        guard node.common.enabled?.literalValue != false else { return [] }
        var paints: [PenFills?] = []
        var children: [PenNode] = []
        switch node.kind {
        case let .frame(data):
            paints = [data.fills, data.stroke]
            children = data.children ?? []
        case let .group(data): children = data.children ?? []
        case let .rectangle(data): paints = [data.fills, data.stroke]
        case let .ellipse(data): paints = [data.fills, data.stroke]
        case let .text(data): paints = [data.fills]
        case let .path(data): paints = [data.fills, data.stroke]
        case let .polygon(data): paints = [data.fills, data.stroke]
        case let .line(data): paints = [data.stroke]
        case let .icon(data): paints = [data.fills]
        default: break
        }
        var urls: Set<String> = []
        for fill in paints.flatMap({ $0?.all ?? [] }) where fill.isEnabled {
            if case let .image(image) = fill, let url = image.url, SwiftUINodeEmitter.resourceName(url) != nil {
                urls.insert(url)
            }
        }
        for child in children {
            urls.formUnion(imageAssetURLs(in: child))
        }
        return urls
    }

    /// A warning for each resource name two different image URLs share: `.process`
    /// flattens both into one bundle, where only one of them can live.
    static func warnCollidingImages(_ urls: Set<String>, diagnostics: PenDiagnosticCollector?) {
        let byName = Dictionary(grouping: urls.sorted()) { SwiftUINodeEmitter.resourceName($0) ?? $0 }
        for (name, clashing) in byName.sorted(by: { $0.key < $1.key }) where clashing.count > 1 {
            diagnostics?.warn(
                "Images \(clashing.joined(separator: ", ")) share the resource name \"\(name)\"; the package can bundle only one",
                stage: .codeGen, nodeID: nil
            )
        }
    }
}
