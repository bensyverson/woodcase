//
//  LintCheck.swift
//  Woodcase
//

import Foundation

/// One thing ``DocumentLinter`` looks for.
///
/// The raw value is the check's stable id — what a finding prints, what `--json`
/// carries, and what a caller filters on. It never changes for a given check.
///
/// A check's ``severity`` is the severity its findings normally carry: an *error* is
/// something that cannot render as authored, a *warning* is something that renders
/// but almost certainly not as intended. ``pipeline`` is the one exception — a
/// finding mapped from a ``PenDiagnostic`` keeps the diagnostic's own severity.
public enum LintCheck: String, Friendly, CaseIterable {
    /// A diagnostic the processing pipeline produced, mapped into a finding.
    case pipeline

    /// A `ref` whose component is not defined in this document.
    case brokenRef = "broken-ref"

    /// An `imports` entry whose library is not there to read: no file at the path, a
    /// library bundled with Pen (``PenLibraries/bundledScheme``), or a location that is not a file. Every
    /// instance through that alias draws nothing.
    case importNotFound = "import-not-found"

    /// An `imports` entry whose file is there but is not a .pen document this build
    /// reads. Every instance through that alias draws nothing.
    case importUnreadable = "import-unreadable"

    /// A library that itself imports another. Pen does not follow a library's own
    /// imports, so whatever in it reaches through that alias draws nothing.
    case importNotFollowed = "import-not-followed"

    /// A property that is still a `$variable` reference after variable resolution.
    case unresolvedVariable = "unresolved-variable"

    /// A text node that declares no fill, so it draws nothing, as Pen draws it.
    case textWithoutFill = "text-without-fill"

    /// A `fill_container` child of a `fit_content` parent on the same axis, which has
    /// nothing to fill.
    case fillContainerInFitParent = "fill-in-fit-parent"

    /// A `fit_content` container with no children, which has nothing to fit.
    case emptyFitContent = "empty-fit-content"

    /// A node whose settled rect falls outside its parent's.
    ///
    /// A clipping frame (`clip:true`) exempts overflow along the axis its
    /// `common.metadata._scroll` declares — a designed scroll, not a bug — and folds
    /// several children overflowing only its own stacking axis into one finding on
    /// the frame when nothing declares it. See <doc:WoodcaseLint>.
    case clipped

    /// An `icon` node whose `library` is not one this build knows.
    case unknownIconLibrary = "unknown-icon-library"

    /// An `icon` node whose `icon` name is not in its library's codepoint table.
    case unknownIcon = "unknown-icon"

    /// Two root nodes — artboards — whose settled rects sit on top of each other.
    case artboardOverlap = "artboard-overlap"

    /// Two children of one parent that share a name, so no name path tells them apart.
    case duplicateName = "duplicate-name"

    /// A text node whose box cannot grow and is shorter than its content needs, so
    /// the lines that fall outside it are not drawn at all.
    case textOverflow = "text-overflow"

    /// A text node whose settled width or height is zero while its content is
    /// non-empty, because its `textGrowth` holds that axis to `kind.width`/
    /// `kind.height` and the sizing has no fallback for the layout engine to use.
    case collapsedText = "collapsed-text"

    /// A `layout: "none"` frame with children whose width or height is `fit_content`
    /// with no fallback (or a fallback of 0). Pen settles an absolute frame's
    /// `fit_content` at its fallback, never around its children, so it is 0 on that
    /// axis: its fill is invisible, `clip` hides its children, and it takes no space in
    /// a flow.
    case collapsedAbsoluteFrame = "collapsed-absolute-frame"

    /// A ref's `descendants` entry carries a value the descendant it patches cannot
    /// decode, so expansion drops it and keeps the unpatched node.
    case overrideValueRejected = "override-value-rejected"

    /// A ref's `descendants` key names no descendant the component it instantiates
    /// defines, so the override never applies.
    case overrideTargetNotFound = "override-target-not-found"

    /// A ref's `descendants` entry carries a property keyed by a dotted path
    /// (`kind.content`) rather than the raw .pen name the merge reads, so it is
    /// silently absorbed and never applies.
    case overrideKeyUnread = "override-key-unread"

    /// A reusable node's `common.metadata._props` entry that `generate react` cannot
    /// turn into a prop: a value that is not a path, a path naming no descendant, or two
    /// entries reading the same field of one descendant.
    case codegenPropPath = "codegen-prop-path"

    /// A `common.metadata._role` value outside ``ComponentRole``, which
    /// `generate react` reads and drops.
    case codegenRole = "codegen-role"

    /// An instance whose descendant override no declared prop reads, on a definition
    /// that declares `_props` at all — the emitter inlines the component rather than
    /// writing a tag for it.
    case codegenUnmappedOverride = "codegen-unmapped-override"

    /// A `mesh_gradient` paint Pen paints nothing for: its `points` or `colors` do not
    /// number `columns × rows` (or one of the four is missing), the grid is under
    /// two vertices on an axis, or a point is malformed in a way Pen cannot place.
    case meshGradientDropped = "mesh-gradient-dropped"

    /// A `mesh_gradient` paint Pen paints, but not as authored: a colour Pen's mesh reads
    /// as nothing (any length but 3, 6 or 8 hex digits, `#RGBA` included) or as another
    /// colour (a digit that is not hex), a patch that folds over itself, or a malformed
    /// point Pen places its own way.
    case meshGradientDistorted = "mesh-gradient-distorted"

    /// A text node carrying a stroke, an underline or a strikethrough — keys Pen
    /// strips from text when it opens the file, and never draws.
    case textStyleStripped = "text-style-stripped"

    /// An enabled shader fill, in a node's fills or its stroke. Pen runs it; Woodcase
    /// draws nothing for it on any target, so a render, a shot or generated code leaves
    /// that paint out.
    case shaderNotDrawn = "shader-not-drawn"

    /// A per-side stroke width on a shape without box sides — an ellipse, a polygon, a
    /// path or a line. Pen strokes it at the top width alone, all round, and draws no
    /// stroke when the top is missing; the other sides are never drawn.
    case perSideStrokeOnShape = "per-side-stroke-on-shape"

    /// The severity findings of this check carry.
    ///
    /// ``pipeline`` findings override it with the diagnostic's own severity; every
    /// other check's findings use this. ``unknownIcon`` and ``unknownIconLibrary`` are
    /// errors rather than warnings for the same reason ``brokenRef`` is: the node
    /// draws nothing at all, exactly like an instance of a missing component — not a
    /// rendered result that merely looks wrong. ``duplicateName`` is a warning for the
    /// opposite reason: both nodes render exactly as authored, and only a later
    /// address lookup is at risk. ``textOverflow`` is a warning rather than an error
    /// because the node does draw — the lines that fit are painted, and only the ones
    /// past the fold are lost. ``overrideValueRejected``, ``overrideTargetNotFound``
    /// and ``overrideKeyUnread`` are errors for the same reason as the write-time
    /// refusal they mirror: the override is silently dropped, so the instance draws
    /// the component's unpatched default instead of what the file says it should.
    /// ``importNotFound`` and ``importUnreadable`` are errors on ``brokenRef``'s reading:
    /// every instance through the alias draws nothing. ``importNotFollowed`` is a
    /// warning, because it costs something only where the library reaches through its
    /// own import — which the library's author may never do.
    /// ``codegenPropPath`` and ``codegenRole`` are errors on that same reading — a
    /// declaration the file makes that `generate react` reads and discards — while
    /// ``codegenUnmappedOverride`` is a warning, because the emitter does produce the
    /// right pixels for it: it inlines the component rather than dropping anything.
    /// ``collapsedText`` and ``collapsedAbsoluteFrame`` are warnings for the same reason
    /// ``fillContainerInFitParent`` and ``emptyFitContent`` are: the node still draws, at
    /// whatever the collapsed axis leaves it, rather than being dropped outright.
    /// ``meshGradientDropped`` is an error because Pen paints nothing for the fill, and
    /// removes it outright on load when its counts are wrong; ``meshGradientDistorted`` and ``textStyleStripped``
    /// are warnings because Pen still draws the node, only not as the file says.
    /// ``shaderNotDrawn`` is a warning on the same reading from the other side: the file
    /// is well formed and Pen draws it as written; only Woodcase's render and code differ.
    /// ``perSideStrokeOnShape`` is a warning because the node draws, Pen and Woodcase alike,
    /// only not with the widths the file writes.
    public var severity: PenDiagnostic.Severity {
        switch self {
        case .pipeline, .textWithoutFill, .fillContainerInFitParent, .emptyFitContent, .clipped,
             .artboardOverlap, .duplicateName, .textOverflow, .codegenUnmappedOverride, .collapsedText,
             .collapsedAbsoluteFrame, .meshGradientDistorted, .textStyleStripped, .importNotFollowed,
             .shaderNotDrawn, .perSideStrokeOnShape:
            .warning
        case .brokenRef, .importNotFound, .importUnreadable, .unresolvedVariable, .unknownIcon, .unknownIconLibrary,
             .overrideValueRejected, .overrideTargetNotFound, .overrideKeyUnread,
             .codegenPropPath, .codegenRole, .meshGradientDropped:
            .error
        }
    }

    /// One line saying what the check looks for, for a help listing.
    public var summary: String {
        switch self {
        case .pipeline:
            "A diagnostic from the parse, migration, font or render pipeline."
        case .brokenRef:
            "A component instance whose component this document does not define."
        case .importNotFound:
            "An import whose library is not there to read, so its instances draw nothing."
        case .importUnreadable:
            "An import whose file is not a readable .pen document, so its instances draw nothing."
        case .importNotFollowed:
            "A library that imports another, which Pen does not follow."
        case .unresolvedVariable:
            "A property still holding a $variable reference after resolution."
        case .textWithoutFill:
            "A text node with no fill, which draws nothing, as Pen draws it."
        case .fillContainerInFitParent:
            "A fill_container node inside a fit_content parent on the same axis."
        case .emptyFitContent:
            "A fit_content container with no children to size itself from."
        case .clipped:
            "A node's settled rect falls outside its parent's, along an axis no scroll annotation declares."
        case .unknownIconLibrary:
            "An icon node whose library this build does not bundle or know about."
        case .unknownIcon:
            "An icon node whose name is not in its library's codepoint table."
        case .artboardOverlap:
            "Two root nodes whose settled rects sit on top of each other."
        case .duplicateName:
            "Two children of one parent share a name, so no name path tells them apart."
        case .textOverflow:
            "A text node's box cannot grow and is too short for its content, so lines are not drawn."
        case .collapsedText:
            "A text node's settled width or height is zero while its content is non-empty."
        case .collapsedAbsoluteFrame:
            "A layout:none frame with children and no width or height, which settles at 0 on that axis, as Pen settles it."
        case .overrideValueRejected:
            "A ref's stored override carries a value the descendant it patches cannot decode."
        case .overrideTargetNotFound:
            "A ref's stored override key names no descendant Pen lets it reach, so Pen drops it."
        case .overrideKeyUnread:
            "A ref's stored override carries a property path instead of the raw .pen key the merge reads."
        case .codegenPropPath:
            "A component's _props entry is not a path, names no descendant, or reads a field another entry already reads."
        case .codegenRole:
            "A component's _role is not one generate react knows, so the role is read and dropped."
        case .codegenUnmappedOverride:
            "An instance overrides a descendant no declared prop reads, so codegen inlines the component."
        case .meshGradientDropped:
            "A mesh gradient whose points or colours do not fill its grid, whose grid is under 2×2, or with a point Pen cannot read: Pen paints nothing."
        case .meshGradientDistorted:
            "A mesh gradient with a colour Pen misreads (such as #RGBA), a patch that folds over itself, or a malformed point Pen repairs: Pen paints it wrong."
        case .textStyleStripped:
            "A text node with a stroke, underline or strikethrough, which Pen strips on load and never draws."
        case .shaderNotDrawn:
            "A shader fill, which Pen runs and Woodcase does not draw on any target."
        case .perSideStrokeOnShape:
            "A per-side stroke width on an ellipse, polygon, path or line, which Pen draws at the top width alone."
        }
    }
}
