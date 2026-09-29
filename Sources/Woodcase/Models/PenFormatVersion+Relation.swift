//
//  PenFormatVersion+Relation.swift
//  Woodcase
//

import Foundation

public extension PenFormatVersion {
    /// Where a declared format version stands against the version Woodcase models.
    ///
    /// The one fact every version decision follows from: the gate's diagnostic, which
    /// version a write stamps, and whether a write is allowed at all. Naming the fact
    /// rather than any one of its consequences keeps them from drifting apart.
    ///
    /// | Relation | Read | Written back as |
    /// | --- | --- | --- |
    /// | ``older`` | migrated or decoded, as the gate routes it | the model's version |
    /// | ``current`` | decoded | the model's version |
    /// | ``newerMinor`` | decoded with the model, with one notice | the declared version, unchanged |
    /// | ``differentMajor`` | decoded after a structural probe, with a warning | never: writes are refused |
    enum Relation: String, Friendly, CaseIterable {
        /// The same major, an older minor.
        case older

        /// Exactly the modeled version.
        case current

        /// The same major, a newer minor: a newer Pen wrote it, and the model is a
        /// subset of what it may hold.
        case newerMinor

        /// Another major version altogether.
        case differentMajor

        /// Whether a document in this relation may be read but never written.
        ///
        /// Only a different major is: writing it would stamp a 2.x model over a file
        /// whose schema this build does not know (ruling 3 in
        /// `project/2026-09-26-pen-1.2.14-compatibility.md`).
        public var isReadOnly: Bool {
            self == .differentMajor
        }
    }

    /// This version's relation to a modeled version.
    ///
    /// - Parameter model: The version Woodcase models. Defaults to ``current``.
    /// - Returns: Where this version stands against it.
    func relation(to model: PenFormatVersion = .current) -> Relation {
        guard major == model.major else { return .differentMajor }
        if minor < model.minor { return .older }
        if minor > model.minor { return .newerMinor }
        return .current
    }
}
