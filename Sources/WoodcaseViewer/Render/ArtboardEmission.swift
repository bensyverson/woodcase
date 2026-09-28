//
//  ArtboardEmission.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One document run through the code-generation pipeline, kept whole.
///
/// ```text
/// Parse → Analyze (components, pages, theme) → Emit
/// ```
///
/// The analysis is kept beside the emitted files rather than thrown away, because
/// mapping an artboard to its generated file needs it: a definition's `.tsx` is named
/// after ``ComponentDefinition/name``, not after the frame, and the sanitizer that turns
/// `Component/Screen/Home` into `Home` lives in the analyzer.
///
/// This is the *whole* set for the document, not one artboard's slice, because that is
/// what the emitter produces — it resolves refs between components as it goes, so there
/// is no cheaper way to ask for one file. ``RenderCache`` keeps it warm per file, and
/// drops it when the file changes, exactly as it does for a prepared document.
public struct ArtboardEmission: Sendable {
    /// Creates an emission.
    ///
    /// - Parameters:
    ///   - components: The reusable definitions the document declares.
    ///   - pages: The top-level frames that are not definitions.
    ///   - result: Every file `generate react` would write.
    public init(components: [ComponentDefinition], pages: [PageDefinition], result: EmitResult) {
        self.components = components
        self.pages = pages
        self.result = result
    }

    /// The reusable definitions the document declares.
    public let components: [ComponentDefinition]

    /// The top-level frames that are not definitions.
    public let pages: [PageDefinition]

    /// Every file `generate react` would write.
    public let result: EmitResult

    /// Runs the pipeline over a parsed document.
    ///
    /// Codegen takes the document **as written**: refs stay refs and become component
    /// instantiations, and variables stay `$name` and become CSS custom properties. So
    /// this is handed the parsed document, never the expanded and resolved one the
    /// renderer works on — with its imports resolved, as
    /// ``Woodcase/EditableDocument/materializeForGeneration()`` makes it, so an imported
    /// component is generated beside the file's own exactly as `generate` does.
    ///
    /// - Parameter document: The document as code generation reads it.
    /// - Returns: The analysis and the emitted files.
    public static func of(_ document: PenDocument) -> ArtboardEmission {
        let components = ComponentAnalyzer.analyze(document)
        let pages = PageAnalyzer.analyze(document)
        return ArtboardEmission(
            components: components,
            pages: pages,
            result: ReactEmitter.emit(
                document: document,
                components: components,
                pages: pages,
                theme: ThemeAnalyzer.analyze(document)
            )
        )
    }
}
