//
//  RemoteImageResolver+Collection.swift
//  Woodcase
//

import Foundation

public extension RemoteImageResolver {
    /// Collects every distinct `http(s)` image-fill URL in a document.
    ///
    /// Relative paths are left out: those are files beside the .pen document, and
    /// ``PenRenderer/fileImageProvider(relativeTo:)`` already resolves them.
    ///
    /// - Parameter document: The document to scan.
    /// - Returns: The set of remote image URLs, exactly as the file spells them.
    static func collectRemoteImageURLs(from document: PenDocument) -> Set<String> {
        var urls: Set<String> = []
        for node in document.children {
            collectRemoteImageURLs(from: node, into: &urls)
        }
        return urls
    }

    /// Whether a URL string names something the network must fetch.
    ///
    /// True only for `http` and `https`. Everything else — a bare relative path, a
    /// `./`-prefixed one, a `file:` URL — belongs to the file provider.
    ///
    /// - Parameter urlString: The image fill's URL.
    /// - Returns: `true` if the URL is remote.
    static func isRemote(_ urlString: String) -> Bool {
        guard let scheme = URL(string: urlString)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private extension RemoteImageResolver {
    static func collectRemoteImageURLs(from node: PenNode, into urls: inout Set<String>) {
        for fill in fills(of: node)?.all ?? [] {
            guard case let .image(imageFill) = fill,
                  let url = imageFill.url,
                  isRemote(url)
            else { continue }
            urls.insert(url)
        }
        for child in children(of: node) {
            collectRemoteImageURLs(from: child, into: &urls)
        }
    }

    /// A node's fills, for every kind that has them.
    ///
    /// Strokes are deliberately not walked. They are typed `PenFills` in the model, but
    /// ``PenStrokeRenderer`` only ever resolves a stroke to a solid color — an image
    /// stroke fill is never drawn — so downloading for one would be work with no
    /// possible effect on the output.
    static func fills(of node: PenNode) -> PenFills? {
        switch node.kind {
        case let .rectangle(data): data.fills
        case let .ellipse(data): data.fills
        case let .polygon(data): data.fills
        case let .path(data): data.fills
        case let .frame(data): data.fills
        case let .icon(data): data.fills
        case let .text(data): data.fills
        default: nil
        }
    }

    /// A node's inline children. Only frames and groups have any — every other kind in
    /// ``PenNode/Kind`` is a leaf, and `ref` nodes have been expanded into frames by
    /// the time anything renders.
    static func children(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }
}
