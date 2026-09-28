# Google Fonts Resolution

Automatically download and register Google Fonts referenced in .pen files.

## Overview

The `.pen` format uses [Google Fonts](https://fonts.google.com) for its text rendering. When Woodcase encounters a font family like "Manrope" or "Inter" that isn't installed on the system, it can automatically download the font from the [google/fonts](https://github.com/google/fonts) GitHub repository and register it with CoreText.

The unit of resolution is the **face** — family, weight and style, a ``PenFontFace`` —
not the family. A static family ships one file per face (`IBMPlexMono-BoldItalic.ttf`);
a variable one covers every weight in one file per style (`Lora[wght].ttf` and
`Lora-Italic[wght].ttf`). ``GoogleFontResolver/collectFontFaces(from:)`` collects every
face a document's text sets, and for each the resolution chain is:

0. **The document's declared fonts** — the files its root `fonts` array names (see
   *Declared fonts* below) are registered first, so a family the document ships never
   reaches the steps after it.
1. **Registered** — if Core Text already has a font of the family in that style whose
   weight is the face's (a variable font whose `wght` axis spans it, or a static font
   whose OS/2 weight class equals it), or the operating system ships the family, use it.
2. **On-disk cache** — register every file cached for the family.
3. **GitHub download** — fetch the file the family's `METADATA.pb` names for the face and
   cache it, with the `METADATA.pb` beside it.

## Faces

Which file serves a face is ``GoogleFontMetadata/entry(weight:style:)``, CSS font
matching over the METADATA's entries: style first (an italic face comes from the italic
files, and from the upright ones only when the family ships no italic), then weight — the
face's own weight when the family ships it, otherwise the nearest one CSS would pick
(heavier first above 500, lighter first below 400). So `render-font-faces.pen`'s IBM Plex
Mono at 700 italic fetches `IBMPlexMono-BoldItalic.ttf`, Spectral italic fetches
`Spectral-Italic.ttf`, and Lora and Inter in italic fetch their italic variable file — and
a variable family drawn only upright never fetches its italic.

Every file cached for a family is registered, not just the first one found. The resolver
used to register the first `.ttf` in directory order and stop, so a static family drew
every weight and style in one arbitrary file — upright Instrument Serif drew italic,
because `InstrumentSerif-Italic.ttf` listed first — and the bold and italic boards of
`render-font-faces.pen` scored MAE 7 to 16 against Pen's exports. They score 2.2 to 2.7
now, the same as the regular controls (`GoogleFontFacesSnapshotTests`). With every face's
file registered, Core Text picks the face by the text's weight and style as it would
among installed fonts.

The METADATA cached beside the files is what lets the next run answer from disk: a face
the family does not ship (a 900 where it stops at 700) maps to its nearest file, which is
already cached, so nothing is fetched again. A cache from before faces holds files but
no METADATA; the first render that needs a face it lacks fetches the METADATA and only the
missing files. Each face is attempted once per resolver.

## Usage

Add an `await` call to ``GoogleFontResolver/prepareFonts(for:)`` before the synchronous layout and render pipeline:

```swift
let document = try PenParser.parse(contentsOf: url)
let resolved = PenVariableResolver.resolve(document, theme: ["mode": "dark"])
let expanded = PenRefExpander.expand(resolved)

// Register the document's declared fonts, then download any missing Google Fonts faces
await GoogleFontResolver.shared.prepareFonts(for: expanded, relativeTo: url)

let rects = PenLayoutEngine.layout(expanded)
let image = PenRenderer.render(expanded, layoutRects: rects, size: size)
```

If `prepareFonts` is skipped or a download fails, fonts fall back to SF Pro — the same behavior as before.

## When a download fails

A failed download is reported once per family, and the warning says which of two facts it was. The two have different remedies:

- **Google Fonts has no such family.** Every license directory (`ofl/`, `apache/`, `ufl/`) answered 404. That is ``GoogleFontError/familyNotFound(_:)``, and the fix is the family name.
- **The download could not happen.** Any other failure means the repository never said "no": no DNS, a refused connection, a proxy that rejected its login, a server error, a certificate that could not be checked. That is ``GoogleFontError/networkUnavailable(family:failure:)``, carrying the ``RemoteFetchError``, and the warning quotes its ``NetworkFailure`` with the underlying error code.

```text
warning: [fontResolution] font "Lobster" is not installed and could not be downloaded from Google Fonts: the host name could not be resolved [NSURLErrorDomain -1003]; text in it falls back to SF Pro.
warning: [fontResolution] font "Lobstre" is not installed, and Google Fonts has no family named "Lobstre"; text in it falls back to SF Pro.
```

The resolver used to swallow every fetch error and end in "not found", so a blocked network looked like a misspelt font.

## Proxies and sandboxes

``URLSessionDataFetcher`` honours the conventional proxy variables — `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY` and `NO_PROXY`, in either case — the way curl does; ``ProxyEnvironment`` documents the rules. With no proxy variables set it is plain `URLSession.shared`, and the system's proxy settings apply. Once one is set the environment is authoritative. A request goes through its scheme's proxy by an HTTP `CONNECT` tunnel, carrying the Basic credentials from the variable's `user:password@`, or goes direct when `NO_PROXY` excludes its host. A proxy host of `localhost` is dialled as `127.0.0.1`, because a sandbox without name resolution cannot look up even that.

This is what an agent sandbox needs: the Claude Code Bash sandbox's only egress is an authenticated proxy on localhost. It is not *all* it needs. That sandbox also denies the system certificate-trust service (`com.apple.trustd.agent`), so no Apple TLS client inside it can verify an HTTPS server. The fetcher detects this by re-evaluating the server's trust, and classifies the failure as ``NetworkFailure/Reason/certificateTrustUnavailable``.

On macOS the shared resolvers do not stop there. ``StandardDataFetcher`` composes ``URLSessionDataFetcher`` with a ``CurlDataFetcher`` in a ``TrustFallbackDataFetcher``: when, and only when, the first fails with that reason, the same URL is fetched again by `/usr/bin/curl`. curl verifies with LibreSSL against `/etc/ssl/cert.pem`, reads the proxy variables and their credentials itself, and resolves `localhost` without the system resolver, so the download succeeds inside the default sandbox. Every other outcome — data, a 404, any other transport failure, a certificate that was checked and rejected — comes from `URLSession` alone, so curl never runs on the normal path. When curl runs, its outcome is the fetch's: a 404 is still ``GoogleFontError/familyNotFound(_:)``, and a curl failure is a ``NetworkFailure`` in the `curl` domain with curl's exit code, such as `[curl 7]`.

The trust-service warning therefore reaches a reader only where there is no fallback — on iOS, or from a ``URLSessionDataFetcher`` used on its own — and it names the fix: `sandbox.enableWeakerNetworkIsolation: true` in Claude Code's settings, or running outside the sandbox. Linux needs no fallback: FoundationNetworking is libcurl already. The full diagnosis is in `project/2026-09-26-sandbox-font-downloads.md`, and `scripts/probe-proxy-egress` reproduces it against a local proxy; `--deny-trustd` shows the fallback carrying the download.

## Reads take the offline half

``GoogleFontResolver/prepareCachedFonts(for:diagnostics:)`` is the same chain with step 3 removed: system faces and every file the on-disk cache holds for the family, never a download. A face the cache lacks while its family is placed is not reported — the text draws in the family's nearest face until a render fetches the right one. It is synchronous, because nothing in it can block on a network, and ``SettledTree`` runs it before every layout — so `tree`, `lint` and the write verbs that print a settled tree measure text in the same faces `shot` and `render` draw with.

It has to run, rather than being an optimisation: registration happens *inside* the resolver, so a face sitting in the cache is invisible to CoreText until something asks for it. That is why `tree` used to report a Google font's width in SF Pro while `shot` reported the real one, and the two disagreed about every text box in a file.

Reads stay offline on purpose. A read that downloaded a font would be a read that hangs behind a captive portal, and `lint` promises in its own help that it never goes to the network. Instead, a family it cannot place is reported — one warning per family, to the ``PenDiagnosticCollector`` when a caller passes one and to standard error when it does not, never both:

```text
woodcase: font "Manrope" is not installed and not in the font cache at /Users/ana/.woodcase/fonts; text in it is measured in SF Pro. Run `woodcase render` or `woodcase shot` once to download it there.
```

A cache directory that exists and cannot be read is a different fact with a different remedy, and gets its own sentence — running `shot` would only write into the same unreadable directory:

```text
woodcase: font "Manrope" is not installed, and the font cache at /Users/ana/.woodcase/fonts exists but cannot be read, so the fonts in it are not used; text in it is measured in SF Pro.
```

The return value carries the same list either way, so a caller that wants to label its own output does not have to capture the warning. Running `shot` or `render` once fills the cache for every read that follows.

## Declared fonts

A document may ship its own fonts in a root `fonts` array — ``PenDocument/fonts``, one
``PenFontDeclaration`` per file: a family `name`, a `url`, and the `style` and `weight`
(or `[min, max]` range) it covers. They register **ahead of** Google Fonts, and a text
node whose `fontFamily` is a declaration's name is measured and drawn in the declared
file. Core Text does the rest of the matching: once every file of a family is
registered, a node's weight and style pick the face as they would among installed fonts.

Where the file is decides which path may reach it:

- **A local file** — a path relative to the .pen file (resolved against its directory,
  as an image fill's path is), or an absolute one — is registered straight from its
  URL on every read. ``SettledTree`` does it through
  ``GoogleFontResolver/registerDeclaredFonts(of:relativeTo:diagnostics:)`` before the
  Google offline chain, with the file from ``PenReadContext/sourceURL``; a document read
  with no resolver still registers its local files
  (``GoogleFontResolver/registerLocalDeclaredFonts(of:relativeTo:)``), because they are
  the document's own data rather than this machine's cache.
- **A remote file** (`https://…`) is downloaded only on the render path —
  ``GoogleFontResolver/prepareFonts(for:relativeTo:diagnostics:)``, which `shot`,
  `render` and the viewer call — through the same fetcher as Google Fonts, and kept in
  the font cache under `declared/`, named by a hash of its url
  (``GoogleFontResolver/cachedDeclaredFontURL(for:)``). Every read after that registers
  it from the cache, offline.

A declaration that cannot be registered — its file is missing, it is remote and not
cached yet, it is not a font Core Text registers under the declared name, or its path
is relative and the document has no file — is reported once, naming the family and
where its file was looked for, and its text falls back as any unresolved family does.
Google Fonts is then consulted for the name, on the render path, like any other family.

Registration is always from a file URL, never from bytes: Core Text silently refuses
descriptors made from in-memory data.

## Variable Fonts

Most Google Fonts are now distributed as [variable fonts](https://fonts.google.com/knowledge/introducing_type/introducing_variable_fonts), where a single TTF file covers a range of weights. When Woodcase registers a variable font, it uses CoreText's `kCTFontVariationAttribute` to set the `wght` axis to the exact weight requested in the .pen file — including fractional values that traditional static fonts can't express.

Core Text would also move a variable font's optical-size axis (`opsz`) to the point size on its own. Pen does not: it draws every size at the font's default optical size, so Woodcase turns automatic optical sizing off (`kCTFontOpticalSizeAttribute: "none"`) in the renderer, the layout engine's measurer and the SwiftUI support file alike, and the emitted React writes `fontOpticalSizing: "none"` on every text (a browser's `font-optical-sizing: auto` does what Core Text does). Left on, Inter above 14 pt came out in its narrower display cut — a 56 pt word 9 pt narrower than Pen's — and wrapped and scored against Pen's exports accordingly (`PenTextOpticalSizeTests`).

## Caching

Downloaded fonts are cached at `$WOODCASE_HOME/fonts/<family>/` (the family name lowercased with its spaces removed, as google/fonts names its directories), each family's `METADATA.pb` beside its files, which is `~/.woodcase/fonts/` unless that variable is set — the same directory the activity log's override names, resolved by ``WoodcaseHome``. Deleting it is safe: fonts are re-downloaded on the next render.

They used to live under `{cachesDirectory}/com.bensyverson.woodcase/fonts/`, which is purgeable by the OS and, more to the point, inside the part of `~/Library` an agent harness walls off with the rest of the home directory — so a sandboxed read measured every downloaded face in SF Pro. Nothing migrates an old cache: it is simply no longer read, and the first render fills the new directory.

A caller that wants a different root injects one — ``GoogleFontCache/init(rootDirectory:)`` — which is what an editor with a platform cache directory of its own does.

Caching is best-effort. If that directory cannot be created or written — a read-only cache volume, a sandboxed process — resolution falls back to an in-process store instead: the font is still registered and rendered, just not persisted, so it is re-downloaded the next time the process starts. Registration always happens from a file URL — CoreText refuses descriptors created from in-memory data — so the fallback writes the bytes to a temporary file before registering them. The first such failure prints one line to standard error naming the path, no matter how many fonts hit the same problem. `shot`, `render` and `serve` never fail because the cache could not be written.

## Custom Configuration

The default ``GoogleFontResolver/shared`` instance uses ``StandardDataFetcher/make(environment:)`` — ``URLSessionDataFetcher``, which honours the proxy environment, with the curl fallback on macOS; see above — and `$WOODCASE_HOME/fonts`. For testing or custom networking, create a resolver with a custom ``RemoteDataFetching`` implementation:

```swift
let resolver = GoogleFontResolver(
    cache: GoogleFontCache(rootDirectory: myCustomDir),
    fetcher: myCustomFetcher
)
await resolver.prepareFonts(for: document)
```

Anything that resolves fonts on someone else's behalf takes the resolver from its caller
rather than reaching for ``GoogleFontResolver/shared``. The read verbs' offline half
takes it from the document: ``PenFileTransaction`` is handed one as `fonts:` and puts it
on the document's ``PenReadContext``, and every settled read of that document — `tree`,
`lint`, a write's preview, a script's `doc.tree()` — registers fonts through it. The
library never defaults it: a document built in memory, or read without `fonts:`, carries
none and measures in the faces the process already has. The command line and the viewer
name theirs at every transaction (`fonts: .shared`, and the render cache's resolver), and
`ProductionFontWiringTests` reads their sources to hold them to it. The viewer's
`RenderCache` takes its resolvers as parameters that do default to the shared instance,
so a `RenderCache()` still downloads what a designer's file names.

A shared default is exactly what a test must not take. A suite over the shared resolver
fetches from GitHub into the reader's `$WOODCASE_HOME`, fails behind a captive portal,
and waits on `URLSession`'s seven-day resource timeout rather than on a deadline of ours
— and a settled read through it measures in whatever that directory holds, so a test can
pass on a machine with Inter cached and fail on a clean checkout. So every test builds
its resolvers over a temporary cache and a fetcher that cannot reach the network, and
`HermeticNetworkTests` scans the sources to prove it: the tests under `Tests/` (including
the `RenderCache(…)` calls, where the leak is a default argument and therefore invisible
at the call site), and the library under `Sources/Woodcase` and `Sources/WoodcaseScripting`,
which must never default a resolver to the shared one. Its allowlist carries one sentence
per exempt file.

## Font Licensing

All fonts on Google Fonts are open source, primarily under the [SIL Open Font License](https://openfontlicense.org). Downloading and using them in software is explicitly permitted. Woodcase downloads fonts directly from Google's official [GitHub repository](https://github.com/google/fonts), which Google publishes for exactly this purpose.

## Topics

### Resolution

- ``GoogleFontResolver``
- ``PenFontFace``
- ``PenFontDeclaration``
- ``GoogleFontCache``
- ``GoogleFontMetadata``
- ``GoogleFontError``

### Networking

The same fetching seam serves remote image fills — see <doc:PenRemoteImages>.

- ``RemoteDataFetching``
- ``StandardDataFetcher``
- ``URLSessionDataFetcher``
- ``TrustFallbackDataFetcher``
- ``CurlDataFetcher``
- ``RemoteFetchError``
- ``NetworkFailure``
- ``ProxyEnvironment``
- ``ProxyEndpoint``
- ``ProxyExclusion``
