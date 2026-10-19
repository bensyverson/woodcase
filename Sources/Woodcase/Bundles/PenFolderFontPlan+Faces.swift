//
//  PenFolderFontPlan+Faces.swift
//  Woodcase
//

import Foundation

extension PenFolderFontPlan {
    /// Every face an expanded document's text draws under any theme it can show.
    ///
    /// Each theme combination resolves the document's variables
    /// (``PenVariableResolver/resolve(_:theme:overrides:)``) and adds the faces of that
    /// resolution (``GoogleFontResolver/collectFontFaces(from:)``), so a family or weight
    /// variable contributes every value it takes. A node that pins its own theme still
    /// does, under every root theme. Past ``maximumCombinations`` the combinations are
    /// each option of each axis alone (``ThemeCoverage/eachOptionAlone(count:)``).
    ///
    /// - Parameter expanded: The document with every `ref` expanded.
    /// - Returns: The faces, and which themes they were collected under.
    static func drawnFaces(in expanded: PenDocument) -> (faces: Set<PenFontFace>, coverage: ThemeCoverage) {
        let (themes, coverage) = themeSelections(expanded.themes ?? [:])
        var faces: Set<PenFontFace> = []
        for theme in themes {
            faces.formUnion(GoogleFontResolver.collectFontFaces(from: PenVariableResolver.resolve(expanded, theme: theme)))
        }
        return (faces, coverage)
    }

    /// The root themes to resolve under: every combination of the axes' options, or each
    /// option alone when there are more than ``maximumCombinations``.
    ///
    /// - Parameter axes: The document's theme axes and their options, default first.
    /// - Returns: The themes, the default first, and which coverage they give.
    static func themeSelections(_ axes: [String: [String]]) -> (themes: [[String: String]], coverage: ThemeCoverage) {
        let sorted = axes.sorted { $0.key < $1.key }.filter { !$0.value.isEmpty }
        let combinations = sorted.reduce(1) { $0 * $1.value.count }
        guard combinations > maximumCombinations else {
            var themes: [[String: String]] = [[:]]
            for (axis, options) in sorted {
                themes = themes.flatMap { theme in options.map { theme.merging([axis: $0]) { $1 } } }
            }
            return (themes, .everyCombination(count: themes.count))
        }
        var themes: [[String: String]] = [[:]]
        for (axis, options) in sorted {
            themes += options.dropFirst().map { [axis: $0] }
        }
        return (themes, .eachOptionAlone(count: themes.count))
    }
}
