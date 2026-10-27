//
//  DocumentSession+Objection.swift
//  Woodcase
//

import Foundation

extension DocumentSession {
    /// What stops undo or redo steps from running.
    struct Objection: Friendly {
        /// Other authors' writes the steps would overwrite, left in place.
        var kept: [KeptChange] = []

        /// The existence of nodes the steps need that are gone, or of ids they would
        /// take that are in use, when no other author is to credit for it.
        var unrestored: [ChangeKey] = []

        /// The objection with each report once, in first-seen order.
        var deduplicated: Objection {
            var seenKept = Set<KeptChange>()
            var seenKeys = Set<ChangeKey>()
            return Objection(
                kept: kept.filter { seenKept.insert($0).inserted },
                unrestored: unrestored.filter { seenKeys.insert($0).inserted }
            )
        }

        /// Several objections as one, each report once, in first-seen order.
        ///
        /// - Parameter objections: The objections.
        /// - Returns: Their reports, merged.
        static func merged(_ objections: [Objection]) -> Objection {
            Objection(
                kept: objections.flatMap(\.kept),
                unrestored: objections.flatMap(\.unrestored)
            ).deduplicated
        }
    }
}
