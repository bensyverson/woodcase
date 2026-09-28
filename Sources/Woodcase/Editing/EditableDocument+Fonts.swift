//
//  EditableDocument+Fonts.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Registers the faces a settled read of this document measures in — the one place
    /// ``SettledTree`` asks.
    ///
    /// The document's declared fonts first, then the offline half of the Google Fonts
    /// chain, through the resolver on ``readContext``: system faces and the on-disk
    /// cache, never a download. With no resolver only the declared local files register,
    /// and everything else measures in whatever the process already has.
    ///
    /// ## Declared fonts
    ///
    /// A document that declares its own fonts — the root `fonts` array,
    /// ``PenDocument/fonts`` — registers them here, **ahead of** Google Fonts, with each
    /// url resolved against ``PenReadContext/sourceURL`` the way an import path is. So
    /// every settled read — `tree`, `lint`, a write's preview, a script — measures in
    /// the declared face, and the Google chain that follows skips a family the
    /// declaration placed. With a resolver, a remote declaration comes from the font
    /// cache and a failure is reported
    /// (``GoogleFontResolver/registerDeclaredFonts(of:relativeTo:diagnostics:)``); with
    /// none, local files still register
    /// (``GoogleFontResolver/registerLocalDeclaredFonts(of:relativeTo:)``), because
    /// they are the document's own data rather than this machine's cache.
    ///
    /// - Parameter resolved: The expanded, variable-resolved document about to be laid out.
    func registerFonts(forSettling resolved: PenDocument) {
        guard let fonts = readContext.fonts else {
            GoogleFontResolver.registerLocalDeclaredFonts(of: resolved, relativeTo: readContext.sourceURL)
            return
        }
        fonts.registerDeclaredFonts(of: resolved, relativeTo: readContext.sourceURL)
        fonts.prepareCachedFonts(for: resolved)
    }
}
