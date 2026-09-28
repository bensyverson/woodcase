//
//  PenVariableResolverInheritanceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PenVariableResolverInheritanceTests {
    // MARK: - Helpers

    private func makeDocument(
        variables: [String: PenVariable] = [:],
        themes: [String: [String]]? = nil,
        children: [PenNode] = []
    ) -> PenDocument {
        PenDocument(
            version: "1",
            themes: themes,
            variables: variables.isEmpty ? nil : variables,
            children: children
        )
    }

    private func themedVar(
        _ type: PenVariableType,
        _ values: [(AnyCodable, [String: String]?)]
    ) -> PenVariable {
        PenVariable(
            type: type,
            value: .themed(values.map { PenThemedValue(value: $0.0, theme: $0.1) })
        )
    }

    // MARK: - Default Theme (First Option Per Axis)

    @Test("Node with no theme gets default (first option per axis)")
    func nodeWithNoThemeGetsDefault() {
        // A themed variable with mode: light -> "white", mode: dark -> "black"
        // Default should be "light" (first option)
        let doc = makeDocument(
            variables: [
                "bgColor": themedVar(.color, [
                    (.string("white"), ["mode": "light"]),
                    (.string("black"), ["mode": "dark"]),
                ]),
            ],
            themes: ["mode": ["light", "dark"]],
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(
                        fills: .single(.shorthand("$bgColor")),
                        children: []
                    ))
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)

        if case let .frame(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .shorthand(color) = fill
        {
            #expect(color == "white")
        } else {
            Issue.record("Expected resolved fill to be 'white'")
        }
    }

    // MARK: - Child Inherits Parent Theme

    @Test("Child inherits parent theme")
    func childInheritsParentTheme() {
        // Parent frame has theme: mode=dark
        // Child text node has no theme → should inherit dark
        let doc = makeDocument(
            variables: [
                "textColor": themedVar(.color, [
                    (.string("black"), ["mode": "light"]),
                    (.string("white"), ["mode": "dark"]),
                ]),
            ],
            themes: ["mode": ["light", "dark"]],
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(theme: ["mode": "dark"]),
                    kind: .frame(PenNode.FrameData(
                        children: [
                            PenNode(
                                id: "text1",
                                common: PenNodeCommon(),
                                kind: .text(PenNode.TextData(
                                    fills: .single(.shorthand("$textColor"))
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)

        // Navigate to the child text node
        if case let .frame(frameData) = resolved.children[0].kind,
           let children = frameData.children,
           case let .text(textData) = children[0].kind,
           case let .single(fill) = textData.fills,
           case let .shorthand(color) = fill
        {
            #expect(color == "white")
        } else {
            Issue.record("Expected child text fill to be 'white' (inherited dark theme)")
        }
    }

    // MARK: - Child Overrides One Axis

    @Test("Child overrides one axis, inherits others")
    func childOverridesOneAxis() {
        // Document has two axes: mode (light/dark) and density (normal/compact)
        // Parent: mode=dark, density=compact
        // Child: mode=light (overrides mode, inherits density=compact)
        let doc = makeDocument(
            variables: [
                "spacing": themedVar(.number, [
                    (.double(16.0), ["density": "normal"]),
                    (.double(8.0), ["density": "compact"]),
                ]),
                "bgColor": themedVar(.color, [
                    (.string("white"), ["mode": "light"]),
                    (.string("black"), ["mode": "dark"]),
                ]),
            ],
            themes: [
                "mode": ["light", "dark"],
                "density": ["normal", "compact"],
            ],
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(theme: ["mode": "dark", "density": "compact"]),
                    kind: .frame(PenNode.FrameData(
                        gap: .variable("spacing"),
                        children: [
                            PenNode(
                                id: "childFrame",
                                common: PenNodeCommon(theme: ["mode": "light"]),
                                kind: .frame(PenNode.FrameData(
                                    fills: .single(.shorthand("$bgColor")),
                                    gap: .variable("spacing"),
                                    children: []
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)

        // Parent frame: density=compact → spacing=8
        if case let .frame(parentData) = resolved.children[0].kind {
            #expect(parentData.gap == PenValue<Double>.literal(8.0))

            // Child frame: mode=light (overrides parent's dark), density=compact (inherited)
            if let children = parentData.children,
               case let .frame(childData) = children[0].kind
            {
                // spacing should still be 8.0 (density=compact inherited)
                #expect(childData.gap == PenValue<Double>.literal(8.0))
                // bgColor should be "white" (mode=light from child's own theme)
                if case let .single(fill) = childData.fills,
                   case let .shorthand(color) = fill
                {
                    #expect(color == "white")
                } else {
                    Issue.record("Expected child fill to be 'white'")
                }
            } else {
                Issue.record("Expected child frame data")
            }
        } else {
            Issue.record("Expected parent frame data")
        }
    }

    // MARK: - Multi-Axis Override

    @Test("Multi-axis override applies both axes")
    func multiAxisOverride() {
        let doc = makeDocument(
            variables: [
                "padding": themedVar(.number, [
                    (.double(16.0), ["mode": "light", "density": "normal"]),
                    (.double(8.0), ["mode": "dark", "density": "compact"]),
                    (.double(12.0), nil), // default fallback
                ]),
            ],
            themes: [
                "mode": ["light", "dark"],
                "density": ["normal", "compact"],
            ],
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(theme: ["mode": "dark", "density": "compact"]),
                    kind: .frame(PenNode.FrameData(
                        children: [
                            PenNode(
                                id: "rect1",
                                common: PenNodeCommon(x: .variable("padding")),
                                kind: .rectangle(PenNode.RectangleData())
                            ),
                        ]
                    ))
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)

        if case let .frame(frameData) = resolved.children[0].kind,
           let children = frameData.children
        {
            #expect(children[0].common.x == .literal(8.0))
        } else {
            Issue.record("Expected resolved x to be 8.0")
        }
    }

    // MARK: - Nested Overrides (Grandchild Overrides Child)

    @Test("Nested overrides: grandchild overrides child's override")
    func nestedOverrides() {
        let doc = makeDocument(
            variables: [
                "bgColor": themedVar(.color, [
                    (.string("white"), ["mode": "light"]),
                    (.string("black"), ["mode": "dark"]),
                ]),
            ],
            themes: ["mode": ["light", "dark"]],
            children: [
                PenNode(
                    id: "root",
                    common: PenNodeCommon(theme: ["mode": "dark"]),
                    kind: .frame(PenNode.FrameData(
                        fills: .single(.shorthand("$bgColor")),
                        children: [
                            PenNode(
                                id: "child",
                                common: PenNodeCommon(theme: ["mode": "light"]),
                                kind: .frame(PenNode.FrameData(
                                    fills: .single(.shorthand("$bgColor")),
                                    children: [
                                        PenNode(
                                            id: "grandchild",
                                            common: PenNodeCommon(theme: ["mode": "dark"]),
                                            kind: .frame(PenNode.FrameData(
                                                fills: .single(.shorthand("$bgColor")),
                                                children: []
                                            ))
                                        ),
                                    ]
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)

        // root: dark → "black"
        if case let .frame(rootData) = resolved.children[0].kind,
           case let .single(rootFill) = rootData.fills,
           case let .shorthand(rootColor) = rootFill
        {
            #expect(rootColor == "black")
        } else {
            Issue.record("Expected root fill 'black'")
        }

        // child: light → "white"
        if case let .frame(rootData) = resolved.children[0].kind,
           let rootChildren = rootData.children,
           case let .frame(childData) = rootChildren[0].kind,
           case let .single(childFill) = childData.fills,
           case let .shorthand(childColor) = childFill
        {
            #expect(childColor == "white")
        } else {
            Issue.record("Expected child fill 'white'")
        }

        // grandchild: dark again → "black"
        if case let .frame(rootData) = resolved.children[0].kind,
           let rootChildren = rootData.children,
           case let .frame(childData) = rootChildren[0].kind,
           let childChildren = childData.children,
           case let .frame(gcData) = childChildren[0].kind,
           case let .single(gcFill) = gcData.fills,
           case let .shorthand(gcColor) = gcFill
        {
            #expect(gcColor == "black")
        } else {
            Issue.record("Expected grandchild fill 'black'")
        }
    }

    // MARK: - Old API Compatibility

    @Test("Old resolve(_:theme:) convenience still works")
    func oldAPIStillWorks() {
        let doc = makeDocument(
            variables: [
                "bgColor": themedVar(.color, [
                    (.string("white"), ["mode": "light"]),
                    (.string("black"), ["mode": "dark"]),
                ]),
            ],
            themes: ["mode": ["light", "dark"]],
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(
                        fills: .single(.shorthand("$bgColor")),
                        children: []
                    ))
                ),
            ]
        )

        // Pinning theme to dark at root level via old API
        let resolved = PenVariableResolver.resolve(doc, theme: ["mode": "dark"])

        if case let .frame(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .shorthand(color) = fill
        {
            #expect(color == "black")
        } else {
            Issue.record("Expected resolved fill to be 'black' with theme pin")
        }
    }

    // MARK: - No Themes Document

    @Test("Document with no themes still resolves simple variables")
    func noThemesStillResolves() {
        let doc = makeDocument(
            variables: [
                "spacing": PenVariable(type: .number, value: .simple(.double(16.0))),
            ],
            children: [
                PenNode(
                    id: "rect1",
                    common: PenNodeCommon(x: .variable("spacing")),
                    kind: .rectangle(PenNode.RectangleData())
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.children[0].common.x == .literal(16.0))
    }

    // MARK: - Group Nodes Also Inherit

    @Test("Group children inherit theme from parent")
    func groupChildrenInheritTheme() {
        let doc = makeDocument(
            variables: [
                "textColor": themedVar(.color, [
                    (.string("black"), ["mode": "light"]),
                    (.string("white"), ["mode": "dark"]),
                ]),
            ],
            themes: ["mode": ["light", "dark"]],
            children: [
                PenNode(
                    id: "group1",
                    common: PenNodeCommon(theme: ["mode": "dark"]),
                    kind: .group(PenNode.GroupData(
                        children: [
                            PenNode(
                                id: "text1",
                                common: PenNodeCommon(),
                                kind: .text(PenNode.TextData(
                                    fills: .single(.shorthand("$textColor"))
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let resolved = PenVariableResolver.resolve(doc)

        if case let .group(groupData) = resolved.children[0].kind,
           let children = groupData.children,
           case let .text(textData) = children[0].kind,
           case let .single(fill) = textData.fills,
           case let .shorthand(color) = fill
        {
            #expect(color == "white")
        } else {
            Issue.record("Expected text fill 'white' inside dark-themed group")
        }
    }
}
