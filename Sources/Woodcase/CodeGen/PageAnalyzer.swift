//
//  PageAnalyzer.swift
//  Woodcase
//

/// Analyzes a .pen document to find pages (top-level non-reusable frames).
///
/// Pages are distinct from components: they are top-level frames that represent
/// screens/routes in the application. They import and instantiate child components
/// but do not themselves accept props.
public enum PageAnalyzer {
    /// Find all pages in the document.
    ///
    /// A page is a top-level frame (direct child of the document) that is not
    /// marked as `reusable: true`, and not a top-level component's state variant — a
    /// `{Name}:{state}` sibling, or a frame its `_states` metadata names.
    ///
    /// A page is named by the rule a component is (``ComponentAnalyzer``), a leading
    /// `Screen/` or `Component/Screen/` folder dropped as well as `Component/`, and each name
    /// is one every emitter can write as a type and a file beside the others: a page
    /// named like a component is suffixed `Page`, so the page's file can import the
    /// component, as is one named for a JavaScript or web global, a React export or the
    /// package's own (``CodeGenName/reservedNames``: `string` is `StringPage`), and a page whose name another page already has — ignoring case, since
    /// their files share a folder on a case-insensitive disk — is numbered from 2, in
    /// document order.
    public static func analyze(_ document: PenDocument) -> [PageDefinition] {
        // Collect reusable component base names to exclude state variant siblings
        let reusable = document.children.filter { $0.common.reusable == true }
        let reusableNames: Set<String> = Set(reusable.compactMap(\.common.name))
        let variantIDs: Set<String> = Set(reusable.flatMap { node -> [String] in
            guard case let .dictionary(states)? = node.common.metadata?["_states"] else { return [] }
            return states.values.compactMap { if case let .string(id) = $0 { id } else { nil } }
        })

        let found = document.children.compactMap { node -> PageDefinition? in
            guard case .frame = node.kind,
                  node.common.reusable != true,
                  !variantIDs.contains(node.id)
            else { return nil }

            // Exclude state variant siblings (e.g. "Toggle:off" when "Toggle" is reusable)
            if let nodeName = node.common.name,
               let colonIndex = nodeName.lastIndex(of: ":")
            {
                let prefix = String(nodeName[nodeName.startIndex ..< colonIndex])
                if reusableNames.contains(prefix) {
                    return nil
                }
            }

            let name = CodeGenName.typeName(node.common.name ?? node.id, droppingPrefixes: CodeGenName.pagePrefixes)
            return PageDefinition(id: node.id, name: name, sourceNode: node)
        }
        return disambiguated(found, componentNames: Set(ComponentAnalyzer.analyze(document).map(\.name)))
            .sorted { $0.name < $1.name }
    }

    /// Collect the IDs of all components referenced by ref nodes within a page's tree.
    public static func referencedComponentIDs(in node: PenNode) -> Set<String> {
        var ids: Set<String> = []
        collectRefIDs(from: node, into: &ids)
        return ids
    }

    // MARK: - Private

    private static func collectRefIDs(from node: PenNode, into ids: inout Set<String>) {
        switch node.kind {
        case let .ref(data):
            ids.insert(data.ref)
        case let .frame(data):
            for child in data.children ?? [] {
                collectRefIDs(from: child, into: &ids)
            }
        case let .group(data):
            for child in data.children ?? [] {
                collectRefIDs(from: child, into: &ids)
            }
        default:
            break
        }
    }

    /// `pages` renamed where a name would clash: with a component's or a reserved name
    /// (``CodeGenName/reservedNames``), by a `Page` suffix; with an earlier page's, compared
    /// without case, by a number from 2.
    private static func disambiguated(_ pages: [PageDefinition], componentNames: Set<String>) -> [PageDefinition] {
        var taken: Set<String> = []
        return pages.map { page in
            var renamed = page
            let clashes = componentNames.contains(page.name) || CodeGenName.reservedNames.contains(page.name)
            let base = clashes ? page.name + CodeGenName.reservedPageSuffix : page.name
            let name = CodeGenName.numbered(base) { taken.contains($0.lowercased()) || componentNames.contains($0) }
            taken.insert(name.lowercased())
            renamed.name = name
            return renamed
        }
    }
}
