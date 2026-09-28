//
//  PreviewCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase
import WoodcaseViewer

/// Serves the viewer's own component previews, and nothing else.
///
/// `serve` with no files: the same ``WoodcaseViewer/ViewerServer``, an empty file index,
/// no activity log, no watcher, nothing on disk. What it answers is the catalog — an
/// index of every component that declares preview states, a canvas per component with
/// every state stacked, and a page per state whose URL is stable enough to paste into a
/// review.
///
/// ```text
/// woodcase preview                      the index, on the next free port from 7333
/// woodcase preview outline-panel        straight to one component's canvas
/// woodcase preview avatar/small         straight to one state
/// woodcase preview --list               every state and its path, on stdout
/// woodcase preview --list --json        the same for an agent
/// ```
///
/// `serve` answers `/preview` too — a person already looking at a document should not
/// have to start a second process to check a component. This verb exists for the other
/// direction: looking at the components when there is no document at all, which is
/// most of the time a component is being worked on.
///
/// ## Adapter only
///
/// The verb parses flags, validates the target against ``WoodcaseViewer/PreviewCatalog``,
/// starts the server, prints, waits and stops. The pages, the frames and the catalog
/// belong to the viewer target.
struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Serve the viewer's own component previews: every component, in every state worth looking at.",
        discussion: """
        A management verb, like `serve`, and the same server — with no files, no \
        activity log and no watcher. It reads nothing and writes nothing: no .pen file, \
        no .woodcase directory, nothing on disk at all.

        Three routes. /preview is the index of components; /preview/<component> stacks \
        every state that component declares, each with a note saying what to look at; \
        /preview/<component>/<state> is one state alone, which is the URL to shoot:

          woodcase preview &
          sleepy shot http://127.0.0.1:7333/preview/avatar/small --size 1280x800

        Name a component — or a component/state — to land there instead of on the \
        index. A name the catalog does not have is refused before the port is bound, \
        listing what it does have, so a typo never leaves a server running.

        --list prints every state's path without starting anything. Paths, not URLs: \
        --list binds no port, so it has none to name, and a listing written against a \
        port something else is holding is a page of dead links that look alive. The base \
        belongs to whichever server is running — it prints its own URL, and --json \
        reports it as `url` — and the two are joined at the point of use:

          woodcase preview --port 7333 &   # prints http://127.0.0.1:7333/preview
          woodcase preview --list          # prints /preview/avatar/small
          sleepy shot http://127.0.0.1:7333/preview/avatar/small

        Running, the URL is the only thing this verb puts on stdout, so it survives a \
        pipe. Ctrl-C stops it.
        """
    )

    @Argument(
        help: ArgumentHelp(
            "The component, or component/state, to open — `avatar` or `avatar/small`. "
                + "Omit for the index. Validated against the catalog before any port is bound."
        )
    )
    var target: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Pin exactly this port and fail if it's taken; 0 takes whatever the system offers. "
                + "Omit to search upward from 7333 until one is free. --list prints paths and "
                + "binds nothing, so it ignores this."
        )
    )
    var port: UInt16?

    /// Where the automatic search starts when `--port` is not given.
    ///
    /// Hidden, and for the same reason `serve` hides its own: a test must be able to
    /// force the search away from the real 7333, which another viewer — a person's, or
    /// another agent's — may already hold.
    @Option(name: .long, help: .hidden)
    var portBase: UInt16?

    @Flag(name: .long, help: "Open the URL in the default browser once the server is up.")
    var open: Bool = false

    @Flag(
        name: .long,
        help: "Print every component and state with its path, and exit. Starts no server."
    )
    var list: Bool = false

    @OptionGroup var output: OutputOptions

    /// What `--list --json` prints: the catalog's metadata, with a path on every row.
    ///
    /// A wire shape of its own rather than ``WoodcaseViewer/PreviewComponent/Metadata``
    /// straight out of the catalog, because the route is the reason an agent asks: a
    /// listing it has to reassemble paths from is a listing it will assemble wrong.
    ///
    /// The rows carry **paths**, not URLs. `--list` binds nothing, so it has no port to
    /// name and no business guessing one — a listing written against 7333 while a server
    /// sits on 7334 is a page of dead links that look alive. The running verb reports its
    /// real base (`--json`'s `url`); an agent joins the two.
    enum Listing {
        /// One state, and the route that serves it.
        struct State: Friendly {
            /// The state's slug within its component.
            let slug: String
            /// The heading a reader sees above it.
            let name: String
            /// What a reviewer should look at here.
            let note: String
            /// The production surface it is shown on.
            let frame: PreviewFrame
            /// The path that serves it alone, to be joined to a running base.
            let path: String
        }

        /// One component, its states, and the route that serves its canvas.
        struct Component: Friendly {
            /// The component's slug.
            let slug: String
            /// Its display name.
            let title: String
            /// One sentence saying what it is for.
            let blurb: String
            /// The repository-relative file that defines it.
            let source: String
            /// The path that serves its canvas, to be joined to a running base.
            let path: String
            /// Its states, in declaration order.
            let states: [State]
        }
    }

    /// What `--json` prints once the server is up.
    struct Started: Friendly {
        /// The address to open — the index, or the target that was named.
        let url: String
        /// The port that was bound.
        let port: UInt16
        /// How many components the catalog holds.
        let components: Int
        /// How many states they declare between them.
        let states: Int
    }

    /// Where a run lands: the index, one component's canvas, or one state.
    ///
    /// Resolved from the positional argument during validation, so a name the catalog
    /// does not have is a refusal rather than a running server on a 404.
    enum Target {
        /// `/preview` — the index.
        case index
        /// `/preview/{component}` — one canvas.
        case component(PreviewComponent)
        /// `/preview/{component}/{state}` — one state, alone.
        case state(PreviewComponent, PreviewState)

        /// The path this target is served at.
        var path: String {
            switch self {
            case .index: ViewerLink.previews
            case let .component(component): ViewerLink.previewComponent(component.slug)
            case let .state(component, state):
                ViewerLink.previewState(component: component.slug, state: state.slug)
            }
        }
    }

    func validate() throws {
        if list, target != nil {
            throw ValidationError(
                "--list prints the whole catalog and starts nothing, so it takes no component. "
                    + "Run `woodcase preview --list` for every state, or "
                    + "`woodcase preview \(target ?? "")` to serve that one."
            )
        }
        if list, open {
            throw ValidationError(
                "--list starts no server, so --open has nothing to open. "
                    + "Run `woodcase preview --list` to print the catalog, or "
                    + "`woodcase preview --open` to serve it and open the index."
            )
        }
        _ = try resolved()
    }

    /// Serves the catalog — or prints it — and waits to be interrupted.
    func run() async throws {
        let target = try resolved()
        guard !list else {
            return try printCatalog()
        }

        let server = ViewerServer(pages: { _ in ViewerPages.routes() })
        // No files and no logs: the preview handlers read the catalog and nothing else,
        // so there is nothing for a context to hold and nothing to create on disk.
        let bound = try await ViewerHosting.bind(
            server, files: [], logs: [], pinned: port, searchBase: portBase ?? ViewerHosting.defaultPort
        )
        defer { Task { await server.stop() } }

        let address = ViewerHosting.address(port: bound, path: target.path)
        try report(address: address, port: bound)

        if open {
            ViewerHosting.openInBrowser(address)
        }

        for await _ in ViewerHosting.interruptions() {
            break
        }
        StandardError.write("Stopping.")
        await server.stop()
    }

    // MARK: - The target

    /// The positional argument, resolved against the catalog.
    ///
    /// - Returns: What the run should land on.
    /// - Throws: `ValidationError` naming what the catalog does have — exit 2, and
    ///   before anything is bound.
    private func resolved() throws -> Target {
        guard let target, !target.isEmpty else { return .index }

        let parts = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let componentSlug = String(parts[0])
        guard let component = PreviewCatalog.component(slug: componentSlug) else {
            throw ValidationError(
                "The preview catalog has no component '\(componentSlug)'. It has: "
                    + "\(PreviewCatalog.all.map(\.slug).joined(separator: ", ")). "
                    + "`woodcase preview --list` prints them with their states."
            )
        }
        guard parts.count == 2 else { return .component(component) }

        let stateSlug = String(parts[1])
        guard let state = component.state(slug: stateSlug) else {
            throw ValidationError(
                "Component '\(component.slug)' has no state '\(stateSlug)'. It has: "
                    + "\(component.states.map(\.slug).joined(separator: ", ")). "
                    + "`woodcase preview \(component.slug)` serves them all."
            )
        }
        return .state(component, state)
    }

    // MARK: - Output

    /// Prints every component and every state with its path.
    ///
    /// - Throws: Whatever the JSON encoder throws.
    private func printCatalog() throws {
        let components = PreviewCatalog.all.map { component in
            Listing.Component(
                slug: component.slug,
                title: component.title,
                blurb: component.blurb,
                source: component.source,
                path: ViewerLink.previewComponent(component.slug),
                states: component.states.map { state in
                    Listing.State(
                        slug: state.slug,
                        name: state.name,
                        note: state.note,
                        frame: state.frame,
                        path: ViewerLink.previewState(component: component.slug, state: state.slug)
                    )
                }
            )
        }
        guard !output.json else {
            return try print(CanonicalJSON.text(components))
        }
        // One row per state, not per component: the state is what gets shot, reviewed
        // and reported, so it is what a row has to be greppable by.
        for component in components {
            for state in component.states {
                print("\(component.slug)/\(state.slug)  \(state.frame.rawValue)  \(state.path)")
            }
        }
    }

    /// Prints where the server is.
    ///
    /// - Parameters:
    ///   - address: The URL to open.
    ///   - port: The bound port.
    /// - Throws: Whatever the JSON encoder throws.
    private func report(address: String, port: UInt16) throws {
        // stdout is block-buffered when it is not a terminal, and this process does not
        // exit — so without an explicit flush `woodcase preview | head -1` waits forever
        // for a line sitting in a buffer.
        defer { fflush(stdout) }
        let states = PreviewCatalog.all.reduce(0) { $0 + $1.states.count }
        guard !output.json else {
            return try print(CanonicalJSON.text(Started(
                url: address, port: port, components: PreviewCatalog.all.count, states: states
            )))
        }
        print(address)
        StandardError.write(
            "\(PreviewCatalog.all.count) components, \(states) states. "
                + "Nothing is being watched and nothing was written."
        )
        StandardError.write("Ctrl-C to stop.")
    }
}
