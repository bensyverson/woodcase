//
//  SwiftUIThemeReads.swift
//  Woodcase
//

/// Counts the reads of `theme` one view struct's body makes, so the struct declares the
/// environment's theme only when its body reads it, and a context node knows whether its
/// subtree needs a `PenThemeReader`.
///
/// A shared reference, like ``SwiftUIShapeDeclarations``, because the node emitter is a
/// value copied into every call. A context node that wraps its subtree in a reader rolls
/// the count back to where the subtree began: those reads are the reader's, not the
/// struct's.
final class SwiftUIThemeReads {
    /// The reads the struct itself must answer.
    private(set) var count = 0

    /// Note one read of `theme`.
    func note() {
        count += 1
    }

    /// Forget the reads since `mark`, which a `PenThemeReader` now answers.
    func rollBack(to mark: Int) {
        count = min(count, mark)
    }
}
