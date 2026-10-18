//
//  ReactEmitter+Images.swift
//  Woodcase
//

extension ReactEmitter {
    /// Scans generated file content for image asset URLs.
    ///
    /// Matches both inline-style references (`url('./images/...')`) and
    /// string-literal references (`"./images/..."`) in the generated code.
    static func collectImageURLs(from files: [GeneratedFile]) -> Set<String> {
        var urls: Set<String> = []
        // Match ./images/... paths in quotes (single or double)
        let pattern = /['"](\.\/(images\/[^'"]+))['"]/
        for file in files where file.path.hasSuffix(".tsx") {
            for match in file.content.matches(of: pattern) {
                urls.insert(String(match.output.1))
            }
        }
        return urls
    }

    /// Walks a node tree and collects image fill URLs.
    public static func collectImageURLs(from node: PenNode) -> Set<String> {
        var urls: Set<String> = []
        for descendant in PenNode.inDocumentOrder([node]) {
            collectImageURLs(of: descendant, into: &urls)
        }
        return urls
    }

    /// Collects the image fill URLs of one node, not its children.
    private static func collectImageURLs(of node: PenNode, into urls: inout Set<String>) {
        // Extract fills from any node kind that has them
        let fills: PenFills? = switch node.kind {
        case let .frame(data):
            data.fills
        case let .rectangle(data):
            data.fills
        case let .ellipse(data):
            data.fills
        case let .icon(data):
            data.fills
        case let .polygon(data):
            data.fills
        default:
            nil
        }

        // Check each fill for image URLs
        if let fills {
            for fill in fills.all {
                if case let .image(imageFill) = fill, let url = imageFill.url {
                    urls.insert(url)
                }
            }
        }
    }
}
