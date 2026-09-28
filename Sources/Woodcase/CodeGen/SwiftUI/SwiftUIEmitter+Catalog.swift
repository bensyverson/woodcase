//
//  SwiftUIEmitter+Catalog.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// The catalog of `components` and `pages` (each page with its view struct's name):
    /// every component in its states, every page, and the theme's tokens and the text
    /// styles `drawn` — the trees with every instance expanded — sets.
    static func catalog(
        components: [SwiftUIComponent],
        pages: [(page: PageDefinition, type: String)],
        drawn: [PenNode],
        theme: SwiftUITheme?
    ) -> SwiftUICatalog {
        SwiftUICatalog(
            components: components.map {
                SwiftUICatalog.Entry(title: $0.definition.name, specimens: specimens(of: $0))
            },
            pages: pages.map {
                SwiftUICatalog.Entry(title: $0.page.name, specimens: [Specimen(name: nil, call: ["\($0.type)()"])])
            },
            theme: theme,
            textStyles: SwiftUICatalogTextStyle.styles(in: drawn, theme: theme)
        )
    }
}
