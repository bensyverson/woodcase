//
//  CodeGeneration.swift
//  Woodcase
//

/// Code for some of a document's nodes: each definition's own file, by its id.
///
/// Where `woodcase generate` writes a whole package — every component, every page, the
/// theme and the support files — this writes only what was asked for, one
/// ``DefinitionCode`` per definition:
///
/// - A **component** (a reusable node, at the root or nested) is the file the whole emit
///   writes for it, character for character.
/// - Any other **root** of the document — a board, a frame, a text, a shape, an icon, a
///   group, an instance — is a **view** drawn from it as a page is drawn, named by the rule
///   ``PageAnalyzer`` names a page: `Toggle:off` is `ToggleOff`, a name a component has
///   takes `Page`, two of one name are numbered in the order asked.
///
/// The components a definition uses are referenced by name, not included. A caller that
/// wants them asks for them too: a ``PenClip``'s roots other than its copied ones and its
/// carried connectors (``PenClip/connectorIDs``) are exactly the components the copy needs.
///
/// ```swift
/// let clip = try PenClip.extract(nodeIDs: selection, from: document)
/// let source = try CodeGeneration.code(for: clip, language: .swiftUI)
///     .map(\.file.content)
///     .joined(separator: "\n")
/// ```
///
/// A layer inside another is not a root: copy it into a ``PenClip`` first, which places it
/// as one and carries the components and variables it needs. Every emitter option is its
/// default.
public enum CodeGeneration {
    /// The code for `nodeIDs` in `document`, one file per definition, in the order asked.
    ///
    /// - Parameters:
    ///   - nodeIDs: The definitions: ids of components anywhere in the document, or of its
    ///     roots. A repeat is dropped.
    ///   - document: The document as code generation reads it, refs and variables
    ///     unresolved, with no imports left (a ``PenClip``'s document, or a file with its
    ///     imports merged in).
    ///   - language: The language to write.
    ///   - diagnostics: Receives the emitter's warnings.
    /// - Returns: Each definition's code, in the order of `nodeIDs`.
    /// - Throws: ``CodeGenerationError/nodeNotFound(id:)`` for an id no node has,
    ///   ``CodeGenerationError/notADefinition(id:)`` for a layer that is neither a root nor a
    ///   component, and ``WoodcaseResources/Missing`` when SwiftUI's support templates
    ///   cannot be read.
    public static func code(
        for nodeIDs: [String],
        in document: PenDocument,
        language: CodeLanguage,
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> [DefinitionCode] {
        let selection = try selection(nodeIDs, in: document)
        let theme = ThemeAnalyzer.analyze(document)
        return switch language {
        case .react:
            ReactEmitter.code(for: selection, theme: theme, diagnostics: diagnostics)
        case .swiftUI:
            try SwiftUIEmitter.code(for: selection, in: document, theme: theme, diagnostics: diagnostics)
        }
    }

    /// The code for a clip's copied roots, in the clip's order: ``code(for:in:language:diagnostics:)``
    /// over its ``PenClip/contentIDs`` in its ``PenClip/document``.
    ///
    /// - Parameters:
    ///   - clip: The copied nodes.
    ///   - language: The language to write.
    ///   - diagnostics: Receives the emitter's warnings.
    /// - Returns: Each copied root's code.
    /// - Throws: ``WoodcaseResources/Missing`` when SwiftUI's support templates cannot be
    ///   read.
    public static func code(
        for clip: PenClip,
        language: CodeLanguage,
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> [DefinitionCode] {
        try code(for: clip.contentIDs, in: clip.document, language: language, diagnostics: diagnostics)
    }

    /// `nodeIDs` resolved against `document`: a component wherever one has the id, else a
    /// view of the root that has it, each view named by ``PageAnalyzer`` in the order asked.
    private static func selection(_ nodeIDs: [String], in document: PenDocument) throws -> DefinitionSelection {
        let components = ComponentAnalyzer.analyze(document)
        let componentsByID = Dictionary(components.map { ($0.id, $0) }) { first, _ in first }
        let roots = Dictionary(document.children.map { ($0.id, $0) }) { first, _ in first }
        var seen: Set<String> = []
        var asked: [String] = []
        var viewRoots: [PenNode] = []
        for id in nodeIDs where seen.insert(id).inserted {
            if componentsByID[id] == nil {
                guard let root = roots[id] else {
                    throw contains(id, in: document) ? CodeGenerationError.notADefinition(id: id) : .nodeNotFound(id: id)
                }
                viewRoots.append(root)
            }
            asked.append(id)
        }
        let views = PageAnalyzer.pages(drawnFrom: viewRoots, componentNames: Set(components.map(\.name)))
        let viewsByID = Dictionary(views.map { ($0.id, $0) }) { first, _ in first }
        let entries: [DefinitionSelection.Entry] = asked.compactMap { id in
            if let component = componentsByID[id] { return .component(component) }
            return viewsByID[id].map { .view($0) }
        }
        return DefinitionSelection(components: components, entries: entries)
    }

    /// Whether any node of `document`, at any depth, has `id`. Walks a work list, so a
    /// deep tree costs no stack.
    private static func contains(_ id: String, in document: PenDocument) -> Bool {
        var pending = document.children
        while let node = pending.popLast() {
            if node.id == id { return true }
            pending += node.kind.inlineChildren
        }
        return false
    }
}
