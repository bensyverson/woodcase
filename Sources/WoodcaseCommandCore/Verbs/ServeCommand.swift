//
//  ServeCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase
import WoodcaseViewer

/// Starts the local web viewer over the .pen files you are working on.
///
/// A management verb, and the only one in this tool that does not end: it binds a port
/// on `127.0.0.1`, watches the files, and stays up until it is interrupted. Everything
/// it serves — the page, the JSON, the PNGs, the event stream — is documented in
/// <doc:WoodcaseViewer>.
///
/// ```text
/// woodcase serve                       every .pen this project's log has seen
/// woodcase serve design.pen            just this one
/// woodcase serve --port 7333 --open    a pinned port, opened in the browser
/// ```
///
/// With no files it reads the working directory's activity log; with files, each file's
/// own — one project, one log, and two files from two projects are followed together.
///
/// ## What it prints
///
/// The URL, alone, on stdout — so `woodcase serve &` and a `head -1` are enough to
/// find it. Everything else goes to stderr, which keeps stdout parseable while the
/// process is still running. `--json` replaces the URL line with one object:
///
/// ```json
/// { "files" : ["/Users/ana/Designs/banking.pen"], "port" : 7333, "url" : "http://127.0.0.1:7333/" }
/// ```
///
/// ## Adapter only
///
/// The verb parses flags, starts ``ViewerServer``, prints, waits and stops. Every
/// decision — what to watch, what to render, what to push — belongs to the viewer
/// target, so the same server runs from a test, from an editor, or from here.
struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Serve a local web view of the .pen files you are working on.",
        discussion: """
        A management verb: it binds a port on 127.0.0.1, watches the files you name, \
        re-renders an artboard the moment it changes on disk, and pushes the change to \
        every open page. It writes nothing and holds no lock; other verbs edit the same \
        files while it is running, which is the point.

        Name no files and it serves every .pen this project's activity log has seen — \
        the cross-file dashboard of whatever this session has been editing. Name files \
        and it follows each one's own project log.

        The URL is the only thing on stdout, so it survives a pipe:

          woodcase serve design.pen --port 7333 --open

        Stop it with Ctrl-C. Nothing is left behind.
        """
    )

    @Argument(help: "The .pen files to serve. Omit to serve every file this project's log has seen.")
    var files: [PenFilePath] = []

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Pin exactly this port and fail if it's taken; 0 takes whatever the system offers. "
                + "Omit to search upward from 7333 until one is free."
        )
    )
    var port: UInt16?

    /// Where the automatic search starts when `--port` is not given.
    ///
    /// Hidden: it exists only so a test can force the search away from the real 7333,
    /// which may already be bound by another `woodcase serve` — a person's, or another
    /// agent's, on the same machine — and asserting "the next port after 7333" would
    /// be flaky whenever that happens to already be true, for reasons unrelated to the
    /// code under test.
    @Option(name: .long, help: .hidden)
    var portBase: UInt16?

    @Flag(name: .long, help: "Open the URL in the default browser once the server is up.")
    var open: Bool = false

    @OptionGroup var output: OutputOptions

    /// Where the automatic port search starts — ``ViewerHosting/defaultPort``, shared
    /// with `preview` so both viewer verbs look in the same place.
    static let defaultPort = ViewerHosting.defaultPort

    /// How many ports past ``defaultPort`` the automatic search tries —
    /// ``ViewerHosting/autoIncrementSpan``.
    static let autoIncrementSpan = ViewerHosting.autoIncrementSpan

    /// What `--json` prints once the server is up.
    struct Started: Friendly {
        /// The address to open.
        let url: String
        /// The port that was bound. Differs from `--port` whenever it named `0` (the
        /// system chose) or was omitted (the search settled somewhere past 7333).
        let port: UInt16
        /// The absolute paths being served, in the order they are listed.
        let files: [String]
    }

    /// Starts the server, prints where it is, and waits to be interrupted.
    func run() async throws {
        let urls = try files.map { try $0.existingFile() }
        let server = ViewerServer(pages: { _ in ViewerPages.routes() })

        // One log per project the named files belong to; with no files, the working
        // directory's — which is the dashboard of whatever this project has been editing.
        let logs = ActivityLogLocation.logs(for: urls)

        let bound = try await ViewerHosting.bind(
            server, files: urls, logs: logs, pinned: port, searchBase: portBase ?? Self.defaultPort
        )
        defer { Task { await server.stop() } }

        let served = await served(by: server)
        let address = ViewerHosting.address(port: bound)
        try report(address: address, port: bound, files: served)

        if open {
            ViewerHosting.openInBrowser(address)
        }

        for await _ in ViewerHosting.interruptions() {
            break
        }
        StandardError.write("Stopping.")
        await server.stop()
    }

    /// The paths the server settled on watching.
    ///
    /// Asked of the running server rather than assumed from the arguments, because a
    /// bare `woodcase serve` adopts whatever the activity log names and the answer is
    /// the only interesting part of the output.
    private func served(by server: ViewerServer) async -> [String] {
        guard let context = await server.context else { return [] }
        return await context.files.files.map(\.path)
    }

    /// Prints where the server is.
    ///
    /// - Parameters:
    ///   - address: The URL to open.
    ///   - port: The bound port.
    ///   - files: The paths being served.
    /// - Throws: Whatever the JSON encoder throws.
    private func report(address: String, port: UInt16, files: [String]) throws {
        // stdout is block-buffered when it is not a terminal, and this process does not
        // exit — so without an explicit flush `woodcase serve | head -1` waits forever
        // for a line that is sitting in a buffer. Every other verb gets away with never
        // flushing because every other verb ends.
        defer { fflush(stdout) }
        guard !output.json else {
            try print(CanonicalJSON.text(Started(url: address, port: port, files: files)))
            return
        }
        print(address)
        StandardError.write(
            files.isEmpty
                ? "Watching nothing yet — edit a .pen file, or name one on the command line."
                : "Watching \(files.count) \(files.count == 1 ? "file" : "files"): "
                + files.joined(separator: ", ")
        )
        StandardError.write("Ctrl-C to stop.")
    }
}
