//
//  FigmaImport.swift
//  Woodcase
//

/// A Figma selection as Pen: the clip a paste takes, and every loss on the way.
public struct FigmaImport: Friendly {
    /// The selection as a clip: its roots are the selected layers at their canvas positions,
    /// then any component an instance needs that was not selected. Hand it to
    /// ``PenClip/plan(into:at:)`` to paste it.
    public var clip: PenClip
    /// What the mapping could not carry, in document order.
    public var losses: [FigmaImportLoss]

    /// An import of `clip` with `losses`.
    public init(clip: PenClip, losses: [FigmaImportLoss]) {
        self.clip = clip
        self.losses = losses
    }
}
