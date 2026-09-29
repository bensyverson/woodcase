//
//  VariablesPanel+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension VariablesPanel {
    /// The design tokens a file declares: every type, and none at all.
    static let previews = PreviewComponent(
        slug: "variables-panel",
        title: "Variables panel",
        blurb: "The file's variables under the outline: swatches for colors, a pill for booleans, and a variant table behind each disclosure.",
        source: "Sources/WoodcaseViewer/Components/VariablesPanel.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Every variable type",
                note: "Color, themed color, number, themed number, string and boolean. Only colors get a swatch; the two attributed rows carry a relative age, one recent and one two days old.",
                frame: .leftPane
            ) {
                VariablesPanel(
                    variables: [
                        ViewerVariable(
                            name: "accent", type: .color, value: "#2FBF6F", swatch: "#2FBF6F",
                            lastEditor: "claude-a", lastChange: PreviewFixtures.now.addingTimeInterval(-4)
                        ),
                        ViewerVariable(
                            name: "bg", type: .color, value: "#F6F5F1", swatch: "#F6F5F1",
                            variants: [
                                ViewerVariable.Variant(axis: "mode=light", value: "#F6F5F1", swatch: "#F6F5F1"),
                                ViewerVariable.Variant(axis: "mode=dark", value: "#161615", swatch: "#161615"),
                            ],
                            lastEditor: "ben", lastChange: PreviewFixtures.now.addingTimeInterval(-172_800)
                        ),
                        ViewerVariable(name: "spacing-md", type: .number, value: "16"),
                        ViewerVariable(
                            name: "card-radius", type: .number, value: "8",
                            variants: [
                                ViewerVariable.Variant(axis: "density=compact", value: "4"),
                                ViewerVariable.Variant(axis: "density=regular", value: "8"),
                            ]
                        ),
                        ViewerVariable(name: "font-primary", type: .string, value: "IBM Plex Sans"),
                        ViewerVariable(name: "dark-mode", type: .boolean, value: "true"),
                    ],
                    axes: ["mode": ["light", "dark"]],
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "empty",
                name: "A file that declares none",
                note: "The header, its collapse toggle and nothing else. The toggle stays: a panel that lost its control when empty looked broken rather than empty.",
                frame: .leftPane
            ) {
                VariablesPanel(variables: [], axes: [:], clock: PreviewFixtures.clock)
            },
        ]
    )
}
