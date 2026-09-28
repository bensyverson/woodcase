//
//  PreviewCatalog.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Every component of the viewer that has previews, and every state of it.
///
/// One catalog, two readers. `PreviewCatalogTests` renders each state and compares it
/// with `Tests/WoodcaseViewerTests/Fixtures/golden/<component>/<state>.html`, and the
/// served `/preview` pages render the same states for a person to look at — so the
/// picture that gets signed off and the fixture the suite checks are the same
/// declaration by construction.
///
/// ```swift
/// PreviewCatalog.state(component: "avatar", slug: "small")?.render()
/// ```
///
/// The registry below is the only place a component is listed. Its states live beside
/// it, in `Components/Previews/<Component>+Previews.swift`, so adding a state needs no
/// edit here.
public enum PreviewCatalog {
    /// Every component with previews, in reading order: the atoms, the chrome, the rows
    /// and the panels they sit in, the canvases, then the whole pages.
    ///
    /// A component belongs beside the ones it is read with, not at the end — the index
    /// is a table of contents, and a reader looking for the id chip looks among the
    /// atoms.
    public static let all: [PreviewComponent] = [
        AvatarView.previews,
        IdChip.previews,
        KindMark.previews,
        DisclosureGlyph.previews,
        LiveBadge.previews,
        PaneGrip.previews,
        PresenceStack.previews,
        TopBar.previews,
        ThemePicker.previews,
        FollowPicker.previews,
        KeyboardHint.previews,
        OutlineRow.previews,
        OutlinePanel.previews,
        ArtboardRow.previews,
        ArtboardOutline.previews,
        VariablesPanel.previews,
        ActivityRow.previews,
        ActivityFeed.previews,
        DetailsPanel.previews,
        ExportPanel.previews,
        CodePane.previews,
        RightPane.previews,
        ArtboardOverlay.previews,
        RenderRegion.previews,
        SelectionBar.previews,
        ArtboardSteps.previews,
        PresentationHint.previews,
        ArtboardMap.previews,
        FileCard.previews,
        FileList.previews,
        DashboardPage.previews,
        MapPage.previews,
        ArtboardPage.previews,
        EmptyPage.previews,
        FileEmptyPage.previews,
        // The preview pages themselves
        PreviewIndex.previews,
        PreviewCanvas.previews,
        PreviewStatePage.previews,
        // Added by the second review round (2026-09-26)
        IdentityHandle.previews,
    ]

    /// Finds a component by slug.
    ///
    /// - Parameter slug: The component's slug.
    /// - Returns: The component, or `nil` if the catalog has none by that name.
    public static func component(slug: String) -> PreviewComponent? {
        all.first { $0.slug == slug }
    }

    /// Finds one state of one component.
    ///
    /// - Parameters:
    ///   - component: The component's slug.
    ///   - slug: The state's slug within that component.
    /// - Returns: The state, or `nil` if either name is unknown.
    public static func state(component: String, slug: String) -> PreviewState? {
        self.component(slug: component)?.state(slug: slug)
    }
}
