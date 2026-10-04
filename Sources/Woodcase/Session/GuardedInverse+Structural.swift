//
//  GuardedInverse+Structural.swift
//  Woodcase
//

import Foundation

extension GuardedInverse {
    /// Whether the step adds, removes, moves or rebuilds nodes, rather than writing
    /// properties, overrides or document members.
    ///
    /// An undo weighs a structural step against everything inside the subtree it
    /// touches, and runs the steps that take back one structural operation together
    /// or not at all (``UndoEntry/Reversal``).
    var isStructural: Bool {
        switch operation {
        case .insertNode, .deleteNode, .moveNode, .replaceSubtree, .detachRef:
            true
        case .updateCommon, .updateKind, .setProperties, .overrideDescendant, .overrideRoot,
             .addVariable, .updateVariable, .removeVariable, .addImport, .updateImport, .removeImport,
             .addThemeAxis, .updateThemeAxis, .removeThemeAxis, .setDocumentProperties:
            false
        }
    }
}
