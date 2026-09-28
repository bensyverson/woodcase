//
//  ArtboardCode.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One file `woodcase generate react` would write, picked out of the emitted set for
/// one artboard.
///
/// The viewer does not generate anything of its own: it runs the same three analyzers
/// and the same ``ReactEmitter`` the verb runs, over the same document — parsed, with
/// its imported components merged in by ``Woodcase/EditableDocument/materializeForGeneration()``
/// — and takes
/// one file out of the result. So the code beside the render is the code on disk after
/// `generate react --output`, character for character, and a pane that showed something
/// else would be a lie about what the CLI does.
///
/// Which file belongs to an artboard follows the emitter's own naming: a reusable
/// definition is `components/{Name}.tsx`, a top-level frame is `pages/{Name}.tsx`, and
/// the three document-wide files are named by ``ViewerCodeTarget``. An artboard the
/// emitter writes no file for — a top-level component *instance*, which is a placement
/// rather than a definition — has no ``ArtboardCode``, and the pane says so instead of
/// showing an empty box.
public struct ArtboardCode: Friendly {
    /// Creates a piece of generated code.
    ///
    /// - Parameters:
    ///   - target: Which of the emitted files this is.
    ///   - path: Its path inside the generated output, as `generate` writes it.
    ///   - text: Its contents.
    public init(target: ViewerCodeTarget, path: String, text: String) {
        self.target = target
        self.path = path
        self.text = text
    }

    /// Which of the emitted files this is.
    public let target: ViewerCodeTarget

    /// Its path inside the generated output — `pages/Dashboard.tsx`.
    public let path: String

    /// Its contents.
    public let text: String

    /// The file's own name, without the directory — what a download is called.
    public var filename: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Picks one emitted file out of a generated set.
    ///
    /// - Parameters:
    ///   - artboard: The artboard's node id, which decides *which* `.tsx` is meant.
    ///   - emission: The whole emitted set, as ``ReactEmitter/emit(document:components:pages:theme:options:diagnostics:)``
    ///     returned it.
    ///   - target: Which file to take.
    /// - Returns: The file, or `nil` when the emitter wrote none — an artboard that is
    ///   only a placement, or a `states.css` for a document with no interactive states.
    public static func of(
        artboard: String,
        in emission: ArtboardEmission,
        target: ViewerCodeTarget
    ) -> ArtboardCode? {
        guard let wanted = path(for: artboard, in: emission, target: target),
              let file = emission.result.files.first(where: { $0.path == wanted })
        else { return nil }
        return ArtboardCode(target: target, path: file.path, text: file.content)
    }

    /// The emitted path a target names for one artboard.
    private static func path(
        for artboard: String,
        in emission: ArtboardEmission,
        target: ViewerCodeTarget
    ) -> String? {
        switch target {
        case .react:
            if let component = emission.components.first(where: { $0.id == artboard }) {
                return "components/\(component.name).tsx"
            }
            if let page = emission.pages.first(where: { $0.id == artboard }) {
                return "pages/\(page.name).tsx"
            }
            return nil
        case .themeCSS:
            return "theme.css"
        case .statesCSS:
            return "states.css"
        case .manifest:
            return "manifest.json"
        }
    }
}
