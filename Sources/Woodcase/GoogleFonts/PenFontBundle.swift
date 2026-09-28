//
//  PenFontBundle.swift
//  Woodcase
//

import Foundation

/// The font files a generated package carries so it draws a document's text families
/// in the faces `woodcase render` draws them in, and what it leaves out.
///
/// ``GoogleFontResolver/fontBundle(for:declaredIn:relativeTo:)`` builds one; the caller
/// copies ``files`` into the package's resources.
public struct PenFontBundle: Friendly {
    /// A family the bundle has no file for, and why.
    public struct Missing: Friendly {
        /// The family, as a text node's `fontFamily` writes it.
        public var family: String

        /// Why no file was found, as a sentence without a leading `woodcase: `.
        public var reason: String

        /// A missing `family`, and why.
        public init(family: String, reason: String) {
            self.family = family
            self.reason = reason
        }
    }

    /// The font files to bundle, sorted by file name, each once.
    public var files: [URL]

    /// The families the operating system ships, which every Apple platform draws without
    /// a bundled file, sorted.
    public var systemFamilies: [String]

    /// The families no file was found for, sorted by family: the package draws them in
    /// whatever the system has.
    public var missing: [Missing]

    /// A bundle of `files`, leaving `systemFamilies` to the system and reporting `missing`.
    public init(files: [URL] = [], systemFamilies: [String] = [], missing: [Missing] = []) {
        self.files = files
        self.systemFamilies = systemFamilies
        self.missing = missing
    }
}
