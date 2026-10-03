//
//  PenImageModeMigrationRule.swift
//  Woodcase
//

import Foundation

/// Brings a pre-2.20 document's image paints into format 2.20, the way Pen 1.2.15 does
/// when it opens one.
///
/// 2.20 renamed the image modes and changed what a missing mode means:
///
/// | Before 2.20 | 2.20 |
/// |---|---|
/// | `fill` | `cover` |
/// | `fit` | `contain` |
/// | `stretch` | `stretch` |
/// | no `mode` (drawn stretched) | `stretch`, written out — a missing mode now means `cover` |
///
/// Pen rewrites every image paint it can reach: a node's `fill` and its `stroke`, each a
/// single paint or an array, on every node type, in `children` and in `ref` `descendants`
/// override bags alike. An image paint is any object with `type: "image"`. A mode outside
/// the table is left as it is, as Pen leaves it.
///
/// Every rewrite keeps the file drawing exactly as it did, so the rule emits no
/// diagnostic.
///
/// ```json
/// {"type": "image", "url": "./a.png", "mode": "fit"}
/// ```
/// becomes
/// ```json
/// {"type": "image", "url": "./a.png", "mode": "contain"}
/// ```
///
/// It runs for every document older than 2.20 — see ``PenLegacyMigrator/rules(upgrading:)``.
public struct PenImageModeMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// Format 2.20, which renamed the image modes.
    public let target = PenFormatVersion(major: 2, minor: 20)

    /// The node keys a paint lives under, in the file's spelling.
    private static let paintKeys = ["fill", "stroke"]

    /// The image modes 2.20 renamed, by their pre-2.20 spelling.
    private static let renamedModes: [String: String] = ["fill": "cover", "fit": "contain"]

    /// The mode a pre-2.20 image paint without one was drawn with.
    private static let implicitMode = "stretch"

    /// Whether a document's bytes could hold an image paint.
    ///
    /// - Parameter data: The raw bytes of a .pen file.
    /// - Returns: `false` when the bytes never say `image`, so there is no image paint to rewrite.
    public func mayApply(to data: Data) -> Bool {
        data.range(of: Data("image".utf8)) != nil
    }

    /// Rewrites the image paints in one node's `fill` and `stroke`.
    ///
    /// Each key may hold one paint or an array of them; anything else is left alone.
    public func apply(toNode node: inout [String: AnyCodable], id _: String?, diagnostics _: PenDiagnosticCollector?) {
        for key in Self.paintKeys {
            switch node[key] {
            case let .dictionary(paint)?:
                node[key] = .dictionary(migrated(paint))
            case let .array(paints)?:
                node[key] = .array(paints.map { value in
                    guard case let .dictionary(paint) = value else { return value }
                    return .dictionary(migrated(paint))
                })
            default:
                break
            }
        }
    }

    /// One paint object, migrated if it is an image.
    private func migrated(_ paint: [String: AnyCodable]) -> [String: AnyCodable] {
        guard paint["type"] == .string("image") else { return paint }
        var result = paint
        switch paint["mode"] {
        case nil:
            result["mode"] = .string(Self.implicitMode)
        case let .string(mode)?:
            if let renamed = Self.renamedModes[mode] {
                result["mode"] = .string(renamed)
            }
        default:
            break
        }
        return result
    }
}
