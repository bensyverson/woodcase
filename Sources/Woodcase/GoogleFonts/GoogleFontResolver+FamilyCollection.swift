//
//  GoogleFontResolver+FamilyCollection.swift
//  Woodcase
//

import Foundation

/// Walking a document's node tree to find the font faces, and so the families, it draws.
public extension GoogleFontResolver {
    /// Collects all unique font family names referenced in a document.
    ///
    /// The families of ``collectFontFaces(from:)``.
    ///
    /// - Parameter document: The document to scan.
    /// - Returns: A set of unique font family names.
    static func collectFontFamilies(from document: PenDocument) -> Set<String> {
        Set(collectFontFaces(from: document).map(\.family))
    }

    /// Collects every face a document's text nodes set: each literal family at the weight
    /// and style the node gives it (400 upright when it gives none), and the face of each
    /// rich-text run the node draws (``PenNode/appliedRuns``), a key the run leaves unset
    /// taken from the node.
    ///
    /// A family, weight or style still written as a `$variable` has no value here; pass
    /// the document after variable resolution.
    ///
    /// - Parameter document: The document to scan.
    /// - Returns: The faces, each once.
    static func collectFontFaces(from document: PenDocument) -> Set<PenFontFace> {
        // A work list, not recursion, so a deep tree cannot overflow a Swift task's stack
        // in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        var faces: Set<PenFontFace> = []
        var pending = document.children
        while let node = pending.popLast() {
            switch node.kind {
            case let .text(data):
                let family = data.fontFamily?.literalValue
                let face = family.map {
                    PenFontFace(family: $0, fontWeight: data.fontWeight?.literalValue, fontStyle: data.fontStyle?.literalValue)
                }
                if let face { faces.insert(face) }
                for run in node.appliedRuns {
                    guard let runFamily = run.fontFamily ?? family else { continue }
                    faces.insert(PenFontFace(
                        family: runFamily,
                        weight: run.fontWeight.map { Int($0.rounded()) } ?? face?.weight ?? 400,
                        style: run.isItalic.map { $0 ? .italic : .normal } ?? face?.style ?? .normal
                    ))
                }
            case let .frame(data):
                pending.append(contentsOf: data.children ?? [])
            case let .group(data):
                pending.append(contentsOf: data.children ?? [])
            default:
                break
            }
        }
        return faces
    }
}
