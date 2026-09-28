//
//  WoodcaseVersion.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `woodcase --version` answers with.
///
/// SwiftPM does not hand a package its own version at build time — a tag is a property
/// of the repository, not of the source — so the number lives here, as one constant,
/// and is bumped by hand in the commit that tags a release. That is the whole of the
/// maintenance rule: **a release commit changes this file**. Nothing derives it, so
/// nothing can derive it wrongly.
///
/// The line pairs the tool's own version with the .pen format it writes, because those
/// are the two numbers a caller acts on: the first says whether a verb or flag is
/// there, the second says what a file this tool touched will claim to be. The format
/// half is read from ``PenFormatVersion/current``, so it cannot drift from what the
/// writer actually emits.
enum WoodcaseVersion {
    /// The package's own version.
    ///
    /// Pre-1.0 and pre-launch: the minor moves when a verb, a flag or an output shape
    /// changes, which is most releases at this stage.
    static let current = "0.1.0"

    /// The line `--version` prints: the tool's version, then the .pen format it writes.
    ///
    /// ```text
    /// 0.1.0 (.pen 2.19)
    /// ```
    ///
    /// Whitespace-splittable, first field bare, so `woodcase --version | cut -d' ' -f1`
    /// is the version alone.
    static var line: String {
        "\(current) (.pen \(PenFormatVersion.current.description))"
    }
}
