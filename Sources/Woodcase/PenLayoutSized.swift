//
//  PenLayoutSized.swift
//  Woodcase
//

import Foundation

/// A node payload with a width and a height sizing.
protocol PenLayoutSized {
    /// The declared width sizing.
    var width: PenSizing? { get set }

    /// The declared height sizing.
    var height: PenSizing? { get set }
}

extension PenNode.FrameData: PenLayoutSized {}
extension PenNode.TextData: PenLayoutSized {}
extension PenNode.RectangleData: PenLayoutSized {}
extension PenNode.EllipseData: PenLayoutSized {}
extension PenNode.PathData: PenLayoutSized {}
extension PenNode.LineData: PenLayoutSized {}
extension PenNode.PolygonData: PenLayoutSized {}
extension PenNode.NoteData: PenLayoutSized {}
extension PenNode.PromptData: PenLayoutSized {}
extension PenNode.ContextData: PenLayoutSized {}
extension PenNode.IconData: PenLayoutSized {}
extension PenNode.ScriptData: PenLayoutSized {}
extension PenNode.BrowserData: PenLayoutSized {}
