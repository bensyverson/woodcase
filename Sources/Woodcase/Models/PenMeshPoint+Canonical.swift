//
//  PenMeshPoint+Canonical.swift
//  Woodcase
//

import Foundation

/// Pen's serialized form of a mesh vertex.
///
/// Measured, not assumed: `mesh-point-elision.pen` and Pen's re-save of it
/// (`scripts/pen-oracle`, `pen` CLI 0.3.9) pin every rule below, and
/// `PenMeshGradientFixtureTests` holds this code to that file.
public extension PenMeshPoint {
    /// How far a handle may sit from its default and still be written as the default.
    ///
    /// Judged on the value as written, *before* rounding: Pen keeps a `0.12514` handle
    /// on a `0.125` default and writes it as `0.1251`.
    static let defaultHandleTolerance = 1e-4

    /// The decimal places Pen writes a position or handle to.
    static let serializedDecimalPlaces = 4

    /// The point as Pen's serializer writes it.
    ///
    /// Each handle within ``defaultHandleTolerance`` of its default is dropped; a point
    /// left with no handles and no ``Object/extras`` becomes ``bare(_:)``. Every remaining number is rounded to
    /// ``serializedDecimalPlaces`` places. A ``malformed(_:)`` point is returned as
    /// written: Pen's serializer rewrites one, but Woodcase preserves what it cannot model.
    ///
    /// - Parameter defaults: The mesh's default handles, from
    ///   ``Handles/defaults(columns:rows:)``.
    /// - Returns: The canonical point.
    func canonicalized(defaults: Handles) -> PenMeshPoint {
        let object: Object
        switch self {
        case let .bare(position): return .bare(position.rounded())
        case let .object(written): object = written
        case .malformed: return self
        }
        let kept = Object(
            position: object.position.rounded(),
            leftHandle: Self.nonDefault(object.leftHandle, defaults.left)?.rounded(),
            rightHandle: Self.nonDefault(object.rightHandle, defaults.right)?.rounded(),
            topHandle: Self.nonDefault(object.topHandle, defaults.top)?.rounded(),
            bottomHandle: Self.nonDefault(object.bottomHandle, defaults.bottom)?.rounded(),
            extras: object.extras
        )
        let hasHandles = [kept.leftHandle, kept.rightHandle, kept.topHandle, kept.bottomHandle]
            .contains { $0 != nil }
        // A vertex carrying extras stays an object: the bare form has nowhere to keep them.
        return hasHandles || !kept.extras.isEmpty ? .object(kept) : .bare(kept.position)
    }

    /// The handle, or `nil` when it is absent or within tolerance of its default.
    private static func nonDefault(_ handle: Vector?, _ fallback: Vector) -> Vector? {
        guard let handle else { return nil }
        let isDefault = abs(handle.x - fallback.x) < defaultHandleTolerance
            && abs(handle.y - fallback.y) < defaultHandleTolerance
        return isDefault ? nil : handle
    }
}

extension PenMeshPoint.Vector {
    /// The vector rounded to Pen's serialized precision, with `-0` written as `0`.
    func rounded() -> PenMeshPoint.Vector {
        let scale = pow(10, Double(PenMeshPoint.serializedDecimalPlaces))
        /// Rounds one component; the `+ 0` turns the `-0` a tiny negative rounds to into
        /// `+0`, which encodes as `0`.
        func round(_ value: Double) -> Double {
            (value * scale).rounded() / scale + 0
        }
        return PenMeshPoint.Vector(round(x), round(y))
    }
}
