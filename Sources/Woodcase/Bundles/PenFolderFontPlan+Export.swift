//
//  PenFolderFontPlan+Export.swift
//  Woodcase
//

import Foundation

public extension PenFolderFontPlan {
    /// The document a Pen Folder export writes for the families the person checked,
    /// before its files are gathered into the folder.
    ///
    /// - A checked ``Source/installed`` family gains one root `fonts` declaration per
    ///   file, under the file's real family name (``FontFile/familyName``) — Woodcase
    ///   draws a declared file only under that name, though Pen accepts any — with its
    ///   style and weight (a `[min, max]` range for a variable file) and the file's
    ///   absolute path as its url.
    /// - An unchecked ``Source/declared`` family loses its local declarations, so the
    ///   folder neither carries its files nor points at them; one declared at a web
    ///   address is kept as written.
    /// - Everything else is left as it is.
    ///
    /// ``PenBundle/export(_:to:identity:fontPlan:bundling:)`` then copies every local
    /// declared file into `fonts/` beside the exported .pen and rewrites its url
    /// relative to it, the way it moves images — Pen copies no font file and leaves a
    /// relative url as written, so a url that is not relative to the exported file
    /// breaks there.
    ///
    /// - Parameters:
    ///   - document: The document being exported, its own declarations included.
    ///   - families: The names of the checked families (``Family/name``); a name whose
    ///     row is not bundleable is ignored.
    /// - Returns: The document with its `fonts` array rewritten.
    func exportedDocument(_ document: PenDocument, bundling families: Set<String>) -> PenDocument {
        let dropped = Set(self.families.filter { $0.source == .declared && !families.contains($0.name) }.map(\.name))
        var declarations = (document.fonts ?? []).filter { declaration in
            guard dropped.contains(declaration.name) else { return true }
            if case .remote = GoogleFontResolver.location(of: declaration, relativeTo: nil) { return true }
            return false
        }
        for family in self.families where family.source == .installed && family.isBundleable && families.contains(family.name) {
            declarations += family.files.map { file in
                PenFontDeclaration(name: file.familyName, url: file.url.path, style: file.style, weight: file.weight)
            }
        }
        var exported = document
        exported.fonts = declarations.isEmpty ? nil : declarations
        return exported
    }
}
