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
        var urls: Set<String> = []
        for node in PenNode.enabledInDocumentOrder([node]) {
            let paints: [PenFills?] = switch node.kind {
            case let .frame(data): [data.fills, data.stroke]
            case let .rectangle(data): [data.fills, data.stroke]
            case let .ellipse(data): [data.fills, data.stroke]
            case let .text(data): [data.fills]
            case let .path(data): [data.fills, data.stroke]
            case let .polygon(data): [data.fills, data.stroke]
            case let .line(data): [data.stroke]
            case let .icon(data): [data.fills]
            default: []
            }
            for fill in paints.flatMap({ $0?.all ?? [] }) where fill.isEnabled {
                if case let .image(image) = fill, let url = image.url, SwiftUINodeEmitter.resourceName(url) != nil {
                    urls.insert(url)
                }
            }
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
