//
//  PenLayoutEngine+LayoutFrame.swift
//  Woodcase
//

import Foundation

extension PenLayoutEngine {
    /// A container the layout walk is part-way through: the state a recursive call
    /// kept in its stack frame, kept in an array on the heap instead.
    ///
    /// Exactly one of ``absolute`` and ``flex`` is set. They are two optionals rather
    /// than an enum because a payload switched out of an enum is a copy, and mutating
    /// the copy would copy a flex container's measurements on every step.
    struct LayoutFrame {
        /// One node for the layout walk to size: what used to be one recursive call.
        struct Call {
            /// The node to size.
            let node: PenNode

            /// The width its parent offers it, or `nil` for unconstrained.
            let availableWidth: Double?

            /// The height its parent offers it, or `nil` for unconstrained.
            let availableHeight: Double?

            /// The rect map its descendants' rects are written to, as an index into the
            /// walk's stores: `0` is the caller's map, any other a flex container's scratch
            /// map for its measuring passes.
            let target: Int

            /// Whether the call reads and writes the measurement cache. A measuring pass
            /// never does, and nothing below it does either.
            let usesCache: Bool
        }

        /// What a container's layout asks of the walk next.
        enum Step {
            /// Size this child, then resume the container with its size.
            case call(Call)

            /// The container is sized; every rect below it is written.
            case done(width: Double, height: Double)
        }

        /// How starting a call turned out.
        enum Start {
            /// The call was answered at once: a leaf, or a measurement cache hit.
            case finished(width: Double, height: Double)

            /// The call is a container with children to size.
            case pending(LayoutFrame)
        }

        /// The call this frame answers.
        let call: Call

        /// The container's state when it lays its children out at their own x/y.
        var absolute: AbsoluteLayout?

        /// The container's state when it lays its children out in a flex flow.
        var flex: FlexLayout?

        /// The scratch store the frame owns, which the walk frees when it finishes.
        var scratch: Int? {
            flex?.scratch
        }

        /// Runs the container until it needs a child sized or is done.
        ///
        /// - Parameters:
        ///   - size: The size of the child the last step asked for, or `nil` on the
        ///     first step.
        ///   - stores: The walk's rect maps.
        /// - Returns: The next child to size, or the container's own size.
        mutating func advance(
            resuming size: (width: Double, height: Double)?,
            stores: inout [[String: PenRect]]
        ) -> Step {
            if flex != nil {
                return flex!.advance(resuming: size, stores: &stores)
            }
            return absolute!.advance(resuming: size, stores: &stores)
        }
    }
}
