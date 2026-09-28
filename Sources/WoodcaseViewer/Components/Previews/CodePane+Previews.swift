//
//  CodePane+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension CodePane {
    /// The generated file: with one to show, and with none.
    static let previews = PreviewComponent(
        slug: "code-pane",
        title: "Code pane",
        blurb: "The right pane's Code tab: a language picker and the file this artboard generates.",
        source: "Sources/WoodcaseViewer/Components/CodePane.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A generated React page",
                note: "The picker sits above the file and the path is named. The code block must scroll inside the pane rather than widening it.",
                frame: .rightPane
            ) {
                CodePane(
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    code: ArtboardCode(
                        target: .react,
                        path: "pages/Canvas.tsx",
                        text: "export function Canvas() {\n  return <div />;\n}\n"
                    ),
                    targets: ViewerCodeTarget.allCases,
                    state: ViewState(tab: .code)
                )
            },
            PreviewState(
                slug: "empty",
                name: "An artboard that generates no file",
                note: "An instance artboard, which the emitter writes nothing of its own for. The picker stays so the reader can try another language.",
                frame: .rightPane
            ) {
                CodePane(
                    file: "a1b2c3d4e5f6",
                    artboard: "YGJ0d/nSNTs",
                    code: nil,
                    targets: ViewerCodeTarget.allCases,
                    state: ViewState(tab: .code)
                )
            },
        ]
    )
}
