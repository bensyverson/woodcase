# Remote Image Fills

Download and cache the images that `http(s)` image fills point at.

## Overview

An image fill's `url` is usually a path beside the `.pen` file — `"./images/hero.png"`. It can also be an absolute `http(s)` URL, which is what the format's own editor writes when a photo comes from a stock library rather than the project folder:

```json
{ "type": "image", "url": "https://images.unsplash.com/photo-1522?w=1600", "mode": "fill" }
```

The renderer's ``PenRenderer/ImageProvider`` is synchronous — it is called from inside a `CGContext` draw — so it cannot download anything. Remote images are therefore resolved in two steps, the same shape as <doc:PenGoogleFonts>:

1. **Prepare** — ``RemoteImageResolver/prepareImages(for:)``, once, before layout and render. It walks the document, collects every remote image-fill URL, and downloads whatever the cache does not already hold. Downloads run concurrently.
2. **Serve** — ``RemoteImageResolver/cachedImage(for:)``, synchronously, from inside the provider.

## Usage

``PenRenderer/imageProvider(relativeTo:remote:)`` is the provider that covers both halves: the URL's scheme decides whether a fill is read from disk or from the remote cache.

```swift
let document = try PenParser.parse(contentsOf: url)
let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document), theme: [:])

await GoogleFontResolver.shared.prepareFonts(for: resolved)
await RemoteImageResolver.shared.prepareImages(for: resolved)

let rects = PenLayoutEngine.layout(resolved)
let image = PenRenderer.render(
    resolved, layoutRects: rects, size: size,
    imageProvider: PenRenderer.imageProvider(relativeTo: url.deletingLastPathComponent())
)
```

`render`, `shot` and `serve` all do this already. Skipping the prepare step is not an error: an image nobody downloaded is simply not drawn, exactly like a missing file on disk. ``PenRenderer/fileImageProvider(relativeTo:)`` remains available for a caller that deliberately wants only local fills.

## What Counts as Remote

Only the `http` and `https` schemes. Everything else — a bare relative path, a `./`-prefixed one — belongs to the file provider and keeps resolving against the `.pen` file's directory, unchanged.

Fills are collected from every node kind that has them: rectangle, ellipse, polygon, path, frame, icon and text, recursing through frame and group children. Stroke paints are *not* collected: they are typed as fills in the model, but the renderer only ever resolves a stroke to a solid color, so an image stroke fill can never reach a pixel.

## Caching

Downloaded images are cached at `$WOODCASE_HOME/images/`, which is `~/.woodcase/images/` unless that variable is set — the directory ``WoodcaseHome`` resolves, beside the font cache. The directory is flat and the filename is the identity — sixteen hex characters of an FNV-1a hash of the whole URL string, plus an inert `.img` extension:

```
~/.woodcase/images/6f1c0a94d3b27e15.img
```

Three consequences worth knowing:

- **The query string is part of the identity.** `photo.jpg` and `photo.jpg?w=400` are different images and get different files, because for most image CDNs they are.
- **The extension says nothing.** `CGImageSource` sniffs the container out of the bytes, so the cache never has to guess whether a URL served a PNG, a JPEG or a WebP — a URL ending in `.jpg` that serves a PNG is common enough that trusting the path would be a bug.
- **FNV-1a, not `Hasher`.** Swift's `Hasher` is seeded per process, so a cache keyed by it would miss every one of its own entries after a restart. This is not a security hash and nothing depends on it being one.

There is no expiry and no revalidation: a URL is fetched once per cache, and deleting the directory is safe — the image is re-downloaded on the next prepare. The cache used to live under `{cachesDirectory}/com.bensyverson.woodcase/images/`; nothing migrates one that is still there, it is simply no longer read.

Caching is best-effort. If the directory cannot be created or written — a read-only cache volume, a sandboxed process — the bytes are held in an in-process store instead, so the image still renders and is not re-downloaded for the life of the process. The first such failure prints one line to standard error naming the path, no matter how many images hit the same problem. `render`, `shot` and `serve` never fail because the cache could not be written.

## Failures

A download that fails is remembered for the life of the resolver, so a document with a dead URL is not re-fetched on every render. ``RemoteImageResolver/prepareImages(for:diagnostics:)`` reports each one as a warning at the ``PenDiagnostic/Stage/imageResolution`` stage; the fill draws nothing.

The warning says why, not just that: the server's status when it answered ("the server answered HTTP 404"), or the reason the request never got an answer at all — no route, a refused proxy, a certificate that could not be checked — from the fetcher's ``NetworkFailure``. A custom ``RemoteDataFetching`` that throws something other than ``RemoteFetchError`` still reads as unreachable rather than as a bare, reasonless miss. The phrasing is shared with <doc:PenGoogleFonts>'s own download-failure warning through `RemoteFetchError.reasonPhrase`, defined beside this resolver rather than in `RemoteFetchError` itself — the wording is a decision the two callers make together, not one the transport error should carry.

Bytes that arrive but are not an image — an error page served with a 200 — are cached and then fail to decode, which has the same visible result: nothing drawn.

## Custom Configuration

The default ``RemoteImageResolver/shared`` uses ``StandardDataFetcher/make(environment:)`` — ``URLSessionDataFetcher``, which honors `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY`, with a curl fallback on macOS for a sandbox that cannot reach the certificate-trust service, as <doc:PenGoogleFonts> describes — and `$WOODCASE_HOME/images`. For tests or custom networking, build a resolver with its own cache and ``RemoteDataFetching`` implementation, and hand it to the provider:

```swift
let resolver = RemoteImageResolver(
    cache: RemoteImageCache(rootDirectory: myCacheDir),
    fetcher: myFetcher
)
await resolver.prepareImages(for: document)
let provider = PenRenderer.imageProvider(relativeTo: baseDir, remote: resolver)
```

The viewer's `RenderCache` takes one the same way — `RenderCache(images:)`, defaulting to
the shared instance — so the served pipeline still downloads what a file points at while
the test suite renders through a resolver that cannot reach the network. See
<doc:PenGoogleFonts> for why the default is the wrong one for a test, and
`HermeticNetworkTests` for the scan that enforces it.

## Topics

### Resolution

- ``RemoteImageResolver``
- ``RemoteImageCache``
- ``PenRenderer/imageProvider(relativeTo:remote:)``
- ``PenRenderer/fileImageProvider(relativeTo:)``

### Networking

- ``RemoteDataFetching``
- ``StandardDataFetcher``
- ``URLSessionDataFetcher``
- ``TrustFallbackDataFetcher``
- ``CurlDataFetcher``
- ``RemoteFetchError``
