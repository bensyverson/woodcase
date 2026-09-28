//
//  ShotCommand+Request.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

extension Shot {
    /// Everything one run was asked for.
    ///
    /// Gathered off the parsed command so the pipeline can run as a `static` function
    /// — the command's own storage is not `Sendable` across the transaction's
    /// isolation boundary, and a value type crosses it cleanly.
    struct Request {
        /// The `--node` argument as typed, or `nil`.
        let node: String?

        /// The raw `--theme` value.
        let theme: String?

        /// The `--max` value, in points.
        let maxSize: Int

        /// The `--scale` value, or `nil` if it was not given. Takes precedence over
        /// `maxSize` when present — see ``effectiveScale(longestSide:maxPoints:)``'s
        /// caller in ``render(_:editing:)``.
        let scale: Double?

        /// Whether `--grid` was given.
        let grid: Bool

        /// The `--outline` addresses, as typed, in the order given.
        let outline: [String]

        /// The `--crop` rectangle, or `nil` for the whole node. In the rendered node's
        /// own coordinate space — the space the printed `rect=` establishes.
        let crop: PenRect?

        /// The `--extent` value: which of the node's extents the run frames.
        let extent: ShotExtent

        /// The `--out` path.
        let out: String
    }
}
