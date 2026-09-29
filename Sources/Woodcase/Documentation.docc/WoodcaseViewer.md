# The Viewer

A local, read-only web view of the .pen files you are working on — and the JSON, PNG and
event API any other dashboard can build on.

## Overview

`woodcase serve [--port N] [--open] [<file>…]` starts a small HTTP server on `127.0.0.1`
that watches the files you name — or every file the working directory's project log has
seen, when you name none — renders their artboards, and pushes an event the moment one
changes on disk.

```text
woodcase serve                       every .pen this project's log has seen
woodcase serve design.pen --open     one file, opened in the browser
woodcase serve --port 0 --json       an ephemeral port, reported as JSON
```

`woodcase preview` is the same server with nothing to serve: no files, no log, no
watcher. It answers only the `/preview` routes — the viewer's own components in every
state worth looking at — which `serve` also carries, so a person already looking at a
document need not start a second process. See *The preview pages* below.

### Which log it follows

The activity log belongs to a project — `.woodcase/activity.jsonl` at the nearest `.git`
above the .pen file (see <doc:WoodcaseActivityLog>) — so which one the viewer follows
depends on what it was asked to serve:

| Invocation | Logs followed |
|---|---|
| `woodcase serve` | The working directory's project log, and the files it has seen |
| `woodcase serve a.pen b.pen` | Each file's own project log |
| Files from two projects | Both logs, followed together |
| `$WOODCASE_HOME` set | That one log, whatever files were named |

Duplicates collapse: two files in one project are one log, followed once. Every read the
pages make — the feed, a file's last change, presence — merges the logs in time order,
so the dashboard shows one history rather than one per project.

A bare `woodcase serve` keeps adopting as it runs. The startup pass reads the log's
history; after that, a log line naming a .pen file the index does not know adds it —
indexed, watched, warmed, and announced as an ordinary `change`, so an open dashboard
grows a card without a reload. A `serve` given files on the command line adopts nothing:
that list is the whole list, on purpose.

The URL is the only thing on stdout, so `woodcase serve &` and a `head -1` find it;
everything else goes to stderr while the process runs. `--json` replaces that line with
`{"files": […], "port": N, "url": "…"}`. Without `--port`, the CLI searches upward from
7333 until one binds and reports the one it got, so the address usually survives a
restart but a second `serve` on the same machine finds 7334 rather than refusing;
`--port N` pins exactly `N` and fails if it is taken, and `--port 0` takes whatever the
system offers, which is what several viewers at once — or a test suite — want. `Ctrl-C`
stops it and leaves nothing behind.

`ViewerServer.start(files:port:)` itself only ever binds the one port it is given —
`0` for ephemeral, `N` to pin — with no retry of its own; the search is `woodcase
serve`'s policy, layered on top so a caller that already knows its port (a test, an
embedder) never pays for one.

It lives in its own target, `WoodcaseViewer`, so the `Woodcase` library never grows a web
server. Like the renderer, it is Apple-only: the server is Network.framework and the
render cache is CoreGraphics.

```swift
import WoodcaseViewer

let server = ViewerServer(pages: { _ in ViewerPages.routes() })
let port = try await server.start(files: [url], port: 0, logs: ActivityLogLocation.logs(for: [url]))
print("http://127.0.0.1:\(port)/")
// …
await server.stop()
```

Port `0` binds whatever is free and reports it, which is how several viewers — or a test
suite — run at once.

### Nothing waits on a socket forever

Network.framework answers in callbacks, and the server awaits three of them: the
listener's state on the way up, and a send's completion for each response and each event
written to an open stream. A callback that never arrives would suspend that task for the
life of the process — and a Swift task suspended at an `await` has no thread and no stack,
so the failure is invisible in a `sample`, which is precisely what made it expensive.

So every one of those awaits goes through `ResumeOnce`, which resumes exactly once from
whichever arrives first: the callback, a later callback, or a deadline. A listener that
says nothing throws `HTTPServer.StartupError.unresponsive` rather than hanging `serve`;
a client that stops reading is given up on, told about on stderr, and dropped. The budget
is a *not hung* guard at thirty seconds, nowhere near the milliseconds these operations
actually take.

Every listener state is classified by `HTTPServer.outcome(of:)` rather than by a `switch`
with a `default`, so no reachable state can silently resume nothing. `.waiting` — which
`NWListener` uses for a port it cannot have yet, and retries indefinitely — is reported as
a failure here: the viewer binds loopback, where there is no network path to wait for and
a port that is taken now will still be taken later.

## File ids

Every URL names a file by a short id, not by its path: twelve hex characters of FNV-1a
over the file's canonical path (the same spelling `ActivityEvent.canonicalPath(for:)`
records). So a link keeps working across a restart, `/tmp` and `/private/tmp` are one
file, and a path containing a slash never has to survive being a path segment.

`GET /files` is how you learn the ids.

## The endpoints

| Route | Answers |
| --- | --- |
| `GET /` | The dashboard page — or the empty page, when nothing is being served |
| `GET /files/{file}` | The map page — or the artboard page, for a single-artboard file |
| `GET /files/{file}/artboards/{artboard}` | The artboard page, showing that one |
| `GET /files/{file}/map` | The bird's-eye map, as a fragment |
| `GET /files/{file}/artboards` | The map page's outline — one row per artboard — as a fragment |
| `GET /files/{file}/activity` | The activity feed, as a fragment |
| `GET /files/{file}/variables` | The variables section, as a fragment |
| `GET /files/{file}/details` | The selected node's attributes, as a fragment |
| `GET /files/{file}/presence` | The presence stack, as a fragment |
| `GET /files/{file}/follow` | The Follow control, for the map page |
| `GET /files/{file}/artboards/{artboard}/outline` | The node outline, selecting into that artboard |
| `GET /files/{file}/artboards/{artboard}/follow` | The Follow control, for that page |
| `GET /files/{file}/artboards/{artboard}/render` | The render, its overlay and the selection footer |
| `GET /files/{file}/artboards/{artboard}/code` | The generated code beside the render, as a fragment |
| `GET /viewer.css`, `GET /viewer.js` | The page's stylesheet and script |
| `GET /files` | Every file being served, with artboards and last change |
| `GET /files/{file}/tree.json` | The settled tree, in `woodcase tree --json`'s form |
| `GET /files/{file}/artboards/{artboard}.png` | One artboard, rendered |
| `GET /files/{file}/artboards/{artboard}/export` | One artboard as a download — image, document or code |
| `GET /files/{file}/activity.json` | The file's recent activity-log events |
| `GET /events` | Server-Sent Events: `change` and `presence` |

Only `GET` and `HEAD` are answered; anything else is `405` with an `Allow` header. Every
failure is a JSON body naming what went wrong and the request that would work:

```json
{
  "error" : "File 'a1b2c3d4e5f6' has no artboard 'Nope'. It has: Cnv01, Brd01, Cmp01.",
  "remedy" : "GET /files/a1b2c3d4e5f6 lists this file's artboards and their ids.",
  "status" : 404
}
```

### Times, and reading them back

Times are the activity log's exact form — ISO-8601, UTC, milliseconds
(`2026-08-29T16:31:04.123Z`) — so a timestamp in an event and the same timestamp in
`activity.jsonl` are the same string. A stock `JSONDecoder` decodes dates as numbers and
will fail on them; the viewer ships the decoder that matches:

```swift
let report = try ViewerJSON.decoder.decode(FileListReport.self, from: data)
```

### `GET /files`

```json
{
  "files" : [
    {
      "artboards" : [
        {
          "height" : 300, "id" : "Cnv01", "isInstance" : false, "isReusable" : false,
          "isSlot" : false, "name" : "Canvas", "width" : 400, "x" : 0, "y" : 0
        }
      ],
      "id" : "a1b2c3d4e5f6",
      "lastChange" : {
        "identity" : "ana", "nodes" : ["Ttl01"], "op" : "set",
        "paths" : ["Canvas/Title"], "time" : "2026-08-29T16:31:04.123Z"
      },
      "name" : "batch",
      "path" : "/Users/ana/Designs/batch.pen",
      "revision" : "3f2a91c0d4e5b678"
    }
  ]
}
```

Artboards are the document's top-level frames **after ref expansion and variable
resolution**, with settled sizes, so a frame authored as `fill_container` reports the
width it actually has. A reusable component definition is one of them: expansion keeps
the definitions here (``PenRefExpander/Purpose/canvas``), so a component is an artboard
exactly as it is for `woodcase tree`, `woodcase shot` and `woodcase render`. A definition
is what a designer edits, and an agent has to be able to see the thing being edited — and
in a real Pen file the top-level frames are often *all* definitions, with the screens on
the canvas being refs to them (`banking.pen`, `woodcase-app.pen`), so stripping them
listed the ref-placed copies and gave no way to open what those copies are of. A file
that cannot be parsed is listed with an `error` and no artboards rather than being left
out.

`x` and `y` are where the frame sits **on the canvas**, in layout points — the one piece
of geometry no single artboard's own view needs, and what the bird's-eye map is drawn
from. Every box *inside* an artboard is measured from that artboard's corner instead; this
is the corner.

`isReusable` and `isInstance` say which of those two an artboard is — a definition, or a
placed instance (a top-level `ref`, whose expanded id contains a slash: `YGJ0d/nSNTs`) —
and `isSlot` says the frame itself is a slot. The artboard map draws the same
``KindMark`` badge from these flags that the outline draws from ``TreeRow``'s.

### `GET /files/{file}/tree.json`

The body is ``TreeFormatter/json(_:revision:)`` verbatim — a ``TreeReport``, byte for
byte what `woodcase tree --json` prints — so the page's overlay, the CLI and a script all
decode one shape.

| Query | Mirrors |
| --- | --- |
| `?node=` | `tree <node>` — an id, a name path, or an instance path |
| `?depth=` | `--depth` |
| `?expand` | `--expand`, walking into component instances |
| `?props=a,b` | `--props`, as a comma-separated list |
| `?theme=` | `--theme` |

A `?node=` that matches nothing is `404` naming the address — never an empty listing.

### `GET /files/{file}/artboards/{artboard}.png`

| Query | Meaning |
| --- | --- |
| `?theme=` | Theme axes to pin |
| `?max=` | Cap on the longer side, in pixels (default 1600) |

The render is scaled so the longer side fits `max`, never past 2×. What it settled on
comes back in the headers, because a viewer that draws boxes over the image needs to map
pixels back to layout points:

```text
X-Woodcase-Scale: 2.0        pixels per layout point
X-Woodcase-Width: 400.0      the artboard's settled size, in points
X-Woodcase-Height: 300.0
X-Woodcase-Revision: 3f2a91c0d4e5b678
```

An artboard id may contain a slash — a top-level component instance expands to
`YGJ0d/nSNTs` — so **percent-encode it into the path**:
`/files/a1/artboards/YGJ0d%2FnSNTs.png`. Path segments are decoded one at a time, so an
encoded slash stays inside the id.

### `?theme=`

Two spellings, both accepted, so neither is ever wrong:

```text
?theme=scheme:night,tint:sand     the viewer's form
?theme=scheme=night,tint=sand     the CLI's --theme form
```

Pins are laid over the document's default theme. A pin that is not `axis:value` is `400`
naming the pin.

### `GET /files/{file}/artboards/{artboard}/export`

One artboard as a file, in a format the CLI already writes and no other. There is no SVG
and no whole-package archive here, because there is no verb behind either.

| Query | Meaning |
| --- | --- |
| `?format=` | `png`, `pdf`, or one of `react`, `theme-css`, `states-css`, `manifest` |
| `?scale=` | Pixels per layout point for the PNG — 1, 2, 3, or any whole number |
| `?max=` | A cap on the longer side, in **points**; wins over `?scale=` |
| `?theme=` | Theme axes to pin, as everywhere else |

`png` and `pdf` are what `woodcase render --format` and `woodcase shot` write; the four
code formats are the files `woodcase generate react` writes, picked out of the emitted
set for this artboard. `react` is `components/{Name}.tsx` for a reusable definition and
`pages/{Name}.tsx` for a top-level frame; the other three belong to the document.

The response is `Content-Disposition: attachment` with a name built from the file, the
artboard and the scale — `batch-Canvas@2x.png` — which is what makes the Export panel a
plain `GET` form with no JavaScript behind it. Unlike the `.png` route the export is
**not** clamped to 2× and **not** cached: somebody asking for 3× means it, and a large
one-off image is not worth holding.

Two refusals are worth knowing. A `?format=` nothing writes is a `400` listing the ones
that do. A code format this document produces no file for — `states-css` when no
component declares a state, `react` for a top-level *instance*, which is a placement
rather than a definition — is a `404` saying which of those it is.

```text
GET /files/a1/artboards/Cnv01/export?format=png&scale=2
GET /files/a1/artboards/Cnv01/export?format=png&max=1200
GET /files/a1/artboards/Cnv01/export?format=react
```

### `GET /files/{file}/activity.json`

```json
{ "file" : "a1b2c3d4e5f6", "events" : [ … ] }
```

The events are ``ActivityEvent`` values — the log's own struct, so a tool that already
reads `activity.jsonl` needs no second decoder. `?limit=` caps how many come back
(default 50), most recent last.

## `GET /events`

A `text/event-stream`, chunked, with a `: heartbeat` comment every 15 seconds so an idle
stream is not mistaken for a dead one. A client is greeted with the current `presence`
the moment it connects, then receives events as they happen. Two event names, and the
page needs no others — everything else it shows it fetches after a `change`.

### `change`

```text
id: 12
event: change
data: {"artboards":["Cnv01","Brd01"],"changedArtboards":["Cnv01"],
data: "file":"a1b2c3d4e5f6","identity":"ana","name":"batch","nodes":["Cnv01"],
data: "op":"set","path":"/Users/ana/batch.pen","paths":["Canvas"],
data: "revision":"3f2a91c0d4e5b678","time":"2026-08-29T16:31:04.123Z"}
```

`artboards` is what to re-request; `revision` is the document's revision after the write.
`identity`, `op`, `nodes` and `paths` come from the activity log.

`changedArtboards` is a different question from `artboards`, and both are needed. The
first says **what to re-request** — every artboard the viewer re-rendered. The second says
**where the news is**: the artboards the edited nodes actually live in, read off the
settled tree by ``PreparedDocument/artboardIDs(containing:)``. A page following an
identity moves to the first of them, and an artboard nobody is looking at gets an unread
dot from them. It is a subset of `artboards`, and it is empty for a write nobody logged —
an unattributed change names no nodes, so it points at no artboard in particular.

A node reached through a component instance carries the id-path expansion gave it
(`Chi01/Lbl01`) while the log records the id as written (`Lbl01`), so both spellings
match. That is why editing one node inside a reusable definition names the definition
*and* every artboard that places it: all of those renders really did change.

**Attribution is best-effort, and that is deliberate.** The watcher sees the write; the
log explains it, and the log line is appended just after the file is renamed into place.
So a change waits briefly for the log and publishes with whatever has arrived. A file
saved or edited by anything that does not log arrives with `identity` null
and no nodes — which is the truth: nobody claimed it.

### `presence`

```text
event: presence
data: {"identities":[{"events":12,"files":["a1b2c3d4e5f6"],
data: "lastSeen":"2026-08-29T16:31:04.123Z","name":"ana"}]}
```

Derived entirely from the activity log — there is no registration and no heartbeat from
an agent. An identity is present because it wrote something, and its age is how long ago.
The order is **first appearance in the log**, and that is part of the contract: the page
colors identities by it, so an agent keeps its color.

## Watching, and why it re-arms

``PenFileTransaction`` commits by writing a temporary neighbor and renaming it over the
original — the only way to leave a reader either the whole old file or the whole new one.
The file descriptor a watcher holds therefore stops being the file at that path after the
first edit: it sees a rename and then goes quiet forever, watching an unlinked inode.
Any editor worth using writes the same way.

So `FileWatcher` re-opens the path and arms a new source on every event, and coalesces a
burst — one save is a write, an extend, an attribute change and a rename — into one
report after 100 ms.

## The warm cache

Per file and theme, the viewer keeps the expensive half of the pipeline:

```text
Parse → Expand → Resolve → Fonts → Layout → prepared → Render → PNG
```

Everything up to `prepared` depends only on the file and the theme, so clicking through
the artboards of one file pays it once. Renders are kept per artboard, theme and size
cap. A file changing drops both, and the artboards are re-rendered before the `change`
event goes out — so the PNG a page requests on hearing the news is already made.

The `Fonts` step is where a served viewer reaches the network: it runs
``GoogleFontResolver/prepareFonts(for:)`` and ``RemoteImageResolver/prepareImages(for:)``,
which download a face or an image fill this machine does not have. That is right for a
rendering surface — a designer's file names faces the reader may not own, and the viewer
draws them the way `shot` does — and wrong for a test, which would then fail offline and
write the reader's `$WOODCASE_HOME`. So ``RenderCache/init(maximumScale:defaultLongestSide:fonts:images:)``
takes both resolvers, defaulting to the process-wide shared pair; the test target passes
a pair over a temporary cache and a fetcher that answers nothing, and
`HermeticNetworkTests` reads the suite's own sources to prove no test skips that.

Startup warms twice, in order: every artboard at full size, then every artboard at the
map's `?max=` cap. The order is the point — the artboard somebody opens first is what
they are waiting for — and so is the fact that only startup does the second pass. A
thumbnail is a second full render of every artboard, and running that on every write
would make each write slower for a map that is usually not open; a map opened after a
change fills in on demand, under the placeholder shimmer.

## The page

Three routes, each returning a complete page from a page component:

| Page | Route |
| --- | --- |
| `DashboardPage` | `/`, when at least one file is served |
| `EmptyPage` | `/`, when none is |
| `MapPage` | `/files/{file}`, when the file has more than one artboard |
| `FileEmptyPage` | `/files/{file}`, when the file has no artboards yet |
| `ArtboardPage` | `/files/{file}/artboards/{artboard}`, and `/files/{file}` otherwise |

The two empty states are one atom answering the same question a level apart, and both
replace themselves: each carries `data-empty-file` — a file id, or empty for *any file
at all* — and `viewer.js` reloads the page when a `change` says the wait is over. A
fragment swap could not do it, because the page that answers next is a different page.
So `woodcase new` turns an empty dashboard into a real one, and its first frame turns
`FileEmptyPage` into a map, with nobody pressing anything.

### The top bar

``TopBar`` is the same strip on every page, and what it can offer is decided by one typed
fact — ``TopBar/Subject`` — rather than by a flag per control: `files` (the dashboard) has
no file to follow and no artboard to present, `map` has a file but no one artboard, and
`artboard` has both.

The brand reads **woodcase** and links to the root, so the breadcrumb no longer starts
with a *Files* crumb saying the same thing: a trail is short and its last step, the one
that names what you are looking at, is the one worth the room. The file crumb still leads
up to the map, with a `▦` glyph and the file-wide unread dot.

At the other end: the theme pins, the presence stack, ``LiveBadge``, the presentation
button, and ``KeyboardHint``.

``LiveBadge`` renders **all three** of ``ConnectionState``'s labels and the stylesheet
shows the one `data-state` names — `connecting`, `live`, and `lost`, which reads
*disconnected*. The script writes only the attribute, from the same enum's raw values, so
the badge cannot do what it used to: go amber on a dropped stream while still reading
"live".

``KeyboardHint`` is the platform's own popover, opened by `popovertarget` from the `?`
button. It was a `title` tooltip, which needs a hover held for a second, never appears for
a touch or a keyboard, and so read as a badge that did nothing. The popover needs no
script — it closes on Escape and on a click outside like every other popover on the
machine — and a browser that has never heard of `popover` drops the `:popover-open` rule
and keeps the panel hidden rather than printing the table into the bar.

### The selection footer

``SelectionBar`` under the render is the page's product: the name path, the id, the settled
rect, the revision, a copy button, and ``ArtboardSteps`` at the far end. With nothing
selected it states the artboard's size and the density it was rendered at — and nothing
else; the line that told you to click a node was advice the outline, the render and the
footer had all already given.

The path is the one item in that row that shrinks, and it is truncated from its **front** —
`…/Fav Card 2/Cover Image`, never `Home — Collection (Light)/Con…` — because the end of a
path is the part that names the node. The stylesheet does it by laying the box out
right-to-left; the text inside is a `<bdi>`, and that isolate is load-bearing: an em dash,
a slash and a parenthesis are all *neutral* characters, so an RTL box without it reorders
and mirrors them and hands back `(Light` at the wrong end.

### The dashboard's file cards

``FileList`` is a card grid, not a list of rows: one ``FileCard`` per served file, most
recently changed first, in `auto-fill` columns so the count follows the window. The order
answers the question the page is opened with — *what just changed?* — and a file nobody
has touched sorts last rather than being hidden.

Each card leads with a **real render** of the file's cover artboard, requested as
`…/{artboard}.png?max=480` with `loading="lazy"`. That is the same PNG endpoint the map's
thumbnails and the artboard view read, so a card is one more entry in the render cache
rather than a second pipeline — fonts and remote images included, because the entry comes
out of ``RenderCache``'s one prepare step, and every request after the first is a hit.

`RenderCache.warm` deliberately does **not** pre-render the covers. Measured here, one
extra render per file per change holds the cache actor long enough to delay a page waiting
on it — enough to fail `selectionScrollsTheOutlineToItsRow` reproducibly, where the same
suite is green without it. A card is a lazy `<img>` over an already-prepared document, so
its cold path is the cheap half of the pipeline; paying that on demand beats making every
file change slower for a page that is usually not open.

Which artboard is the cover is ``Artboard/cover(of:)``: the first that is neither a
reusable definition nor a slot, falling back to the first of any. A file is represented by
a screen rather than by a part of one — a card showing the 60×24 "Button" component says
nothing about which file it is — and a *placed instance* counts as a screen, which is how
a component-only file like `banking.pen` covers with its themed instance rather than with
a definition. A file that could not be parsed keeps its card and says `unreadable` where
the render would be.

### Two canvas modes

The canvas pane shows **either** the bird's-eye map **or** one artboard, never both. The
map is the landing view, because the first question about a file you have not seen is
what is in it; drilling into a box gives the render the whole pane.

`/files/{file}` lands on the map, with two exceptions. A file with a single artboard goes
straight to it — a map of one box is a page you would only ever click through. And a
`?node=` that names a node opens the artboard that holds it, because a link to a node is a
link to wherever that node is, and `/files/{file}?node=Vr7Kd` is a URL an agent pastes.
`/files/{file}/artboards/{artboard}` is always the artboard.

Which mode a page is in is one element: `#v-stage` for an artboard, `#v-map` for the map.
Both carry `data-file`, and the script reads the mode off them rather than off the path.

Navigation between the two lives in what was already on the page:

| From | To | How |
| --- | --- | --- |
| map | artboard | Click a box, click its row in the outline, or ←/→/↑/↓ then `Enter` |
| artboard | map | The breadcrumb's file name (a `▦` glyph), or `Esc` |
| artboard | artboard | The footer's `‹ 2 of 5 ›`, or ← / → |

The breadcrumb's map crumb also carries the unread dot for the *rest of the file*: the
artboard page has no boxes to mark, and what you want to know there is whether something
changed somewhere else.

### One node, three walks, one id

A click on the render, a row in the outline and the Details pane are three different walks
over the same file, and a selection only works if all three spell a node the same way.
Inside a component instance they nearly do not.

``PenRefExpander`` replaces a `ref` with a clone of its component and prefixes every id in
the clone with the `ref`'s own — so the instance `Card1` of the component `CardC` is rooted
at `Card1/CardC`, and its descendants are `Card1/Ttl03`, `Card1/Btn02/Lbl02`, and so on.
The descendants are exactly the id-paths ``TreeView`` prints and
``EditableDocument/resolve(_:tags:)-(String,_)`` accepts. The **root** is not: the outline
names that row after the `ref` alone, and the resolver has no step onto a component root,
so a `?node=Card1/CardC` matched no row *and* answered "names no node in this file" —
which is what a click on an instance's own frame used to produce.

So `ArtboardLayout.address(of:under:)` reconciles them, in one place: a box whose
instance prefix is longer than its parent's is a clone root, and takes the prefix — the
`ref`'s id-path — as its id. Everything else keeps the id expansion gave it. The rule is
read off the expanded ids alone, so it needs no second walk of the authored tree and makes
no assumption about how deeply instances nest.

The other half of the agreement is that the outline **always expands instances** (see
`?expand` above): the render draws every node inside an instance, so the outline has to
carry a row for every node the render can be clicked on.

The outline is also scoped to the artboard on screen — `ArtboardPageBuilder.rows(of:artboard:state:)`
walks ``TreeView`` from that one root, not the whole flat store. A file carries every
artboard, every component definition and every instance in one place; a listing that
walked all of it would print every one of them at once, however few belong to what you
are looking at. The root it walks from is `ArtboardLayout.address(of:under:)` applied to
the artboard's id, not the id as-is: a ref-placed artboard's id is the expansion's own
compound id (`<ref>/<component root>`), the same string the paragraph above says the
resolver rejects — so the outline's root has to go through the same reconciliation a
node's row does, or the very first row would fail to resolve.

### View state lives in the query

There is no client-side state. Everything you are looking at that is not the file itself
is in the URL, so a link describes a view, back and forward work, and a URL an agent
pastes reopens exactly what was on screen.

| Parameter | Means |
| --- | --- |
| `?node=` | The selected node — an id or a name path |
| `?theme=` | Theme axes pinned for the render and the variables |
| `?depth=N` | List N levels, as `tree --depth` does |
| `?follow=` | Whose writes move the page — `anyone`, an identity's name, or `paused:<who>` |

``Follow`` is the `?follow=` vocabulary as a type. It is three states rather than a target
plus a flag, because a paused follow is its own fact: any manual navigation drops follow
to nobody, and the control has to keep offering the name it would resume. Absent means
nobody; `follow=anyone` follows every attributed write; `follow=ana` follows one identity;
`follow=paused:ana` is switched off and remembers. An identity literally named `anyone`
reads back as *anyone* — the one collision in the vocabulary, accepted because the
alternative is a second parameter and the log's identities are agent names.
| `?tab=` | Which of the right pane's panels is showing: `activity`, `details`, `export`, `code` |
| `?lang=` | Which generated file the Code tab shows: `react`, `theme-css`, `states-css`, `manifest` |

There is no `?expand=`. The outline **always** walks into component instances, because the
render always draws them: every node inside an instance is on screen and can be clicked, and
an outline that stopped at the `ref` would have no row to select for what a person just
clicked. `tree --expand` keeps the flag — a text listing has a reason to be short — and so
does `/files/{file}/tree.json`, which mirrors the verb.

`?tab=` has a default rather than a fixed value: a state with `?node=` set opens on
**Details**, one without opens on **Activity**. That is the whole reason the tab exists —
you selected something in order to look at it — and it lives in one function,
`ViewState.tab(forSelection:)`, so a link the page wrote, a URL a person typed and the
script's own reading of the query cannot disagree. An explicit `?tab=` always wins, until
the next selection moves it again; that is the simple rule, and the tab bar is one click
away.

Because the default depends on the selection, every link a *selected* view writes names
its tab, Activity included. Leaving it out would make the Activity tab's own href
`?node=…` with no tab — which parses straight back to Details, so the tab would be
unclickable.

A `?tab=`, `?lang=` or `?format=` value the enumeration does not have is a `400` naming
it and listing what it could have been; nothing is silently ignored.

`ViewState` is the type; `ViewState.of(_:)` reads one off a request and `ViewerLink`
writes every URL from one. A malformed parameter is a `400` naming it, never a silently
dropped one.

### Correct with the script off

Every page is served whole: the outline rows, the variables, the activity, the presence,
and the selected node **already outlined over the render**, with its name path and id in
the footer. Outline rows are `<a href="?node=…">`; the theme picker is a `GET` form with
a real submit button, which CSS hides only once the script has marked the document
scripted. Nothing on the page needs JavaScript to be usable.

### Fragments

Each fragment response *is* the element it replaces, id and all, so a swap is an
`outerHTML` replacement of server-rendered markup. Every fragment takes the same query
the page does and renders the same components with the same props.

| Fragment | Element |
| --- | --- |
| `/files/{file}/activity` | `#v-activity` |
| `/files/{file}/variables` | `#v-variables` |
| `/files/{file}/details` | `#v-details` |
| `/files/{file}/presence` | `#v-presence` |
| `/files/{file}/map` | `#v-map` — the bird's-eye map |
| `/files/{file}/artboards` | `#v-outline` — the map page's artboard listing |
| `/files/{file}/follow` | `#v-follow`, for the map page |
| `/files/{file}/artboards/{artboard}/outline` | `#v-outline` — the node outline |
| `/files/{file}/artboards/{artboard}/follow` | `#v-follow` |
| `/files/{file}/artboards/{artboard}/render` | `#v-render-region` |
| `/files/{file}/artboards/{artboard}/code` | `#v-code` |

`render` is the image, the boxes drawn over it and the selection footer — everything that
moves when the file changes or the selection does. It is a fragment rather than
client-side drawing because an edit marker needs an identity's hashed color and a box
needs an absolute layout rect, and re-deriving either in JavaScript would be a second
implementation of a component.

`map` is a fragment for a reason worth naming: the *list* of artboards changes when the
file does. An agent adding a top-level frame is a new box on a page nobody reloaded, and
it arrives at the canvas position the write gave it. It is whole-file, because nothing on
the map is current.

`follow` is a fragment for the mirror-image reason: it changes when the *file does not*.
Clicking an outline row drops follow to nobody, and the dropdown that says so — with the
link that offers to resume — is server-rendered like every other control on the page
rather than assembled a second time in JavaScript. Its path names an artboard when there
is one, because the control's form submits back to the page you are on; the map has none,
and follows the same identities to the same effect, since a matching write drills into the
artboard it touched.

Two fragments answer with `#v-outline`, and they are the two modes' two outlines: the map
page lists artboards, the artboard page lists nodes — scoped to the one artboard on
screen, not the whole file. The node outline names an artboard in its own `outline`
fragment path (`GET /files/{file}/artboards/{artboard}/outline`) for two reasons at once:
that is which tree it walks, and it is also *where* a row's `href` has to select the node
— `/files/{file}?node=…` is the map, so a row that wrote it would navigate out of the
artboard it was clicked in.

### The bird's-eye map

``ArtboardMap`` is the whole document zoomed out and fills the map page's canvas: every
artboard a **real low-res render** at the canvas `x`/`y` `GET /files` reports for it, its
name and its kind badge underneath, and each box an ordinary `<a>` — so clicking one
drills in, with the script off as well as on. The arrangement on the canvas is how the
person who drew the file thinks about it, so that is what you navigate by. Every box
carries `data-artboard="<id>"`, which is the hook anything hanging per-artboard state off
a box uses: the unread dot, the keyboard's focus ring, the follow-drop handler.

Each thumbnail is `…/{artboard}.png?max=320` — the PNG endpoint's own size cap, so a
thumbnail is one more entry in the render cache rather than a second pipeline, and every
box on the map shares one small render per artboard and theme. It is laid out at the
artboard's own point size, which is the box's size scaled, so the two rectangles always
agree and nothing is letterboxed.

An artboard something was written to recently is outlined in its editor's color, the way
a touched outline row grows a bar. Node-level edit markers are too fine for a box 24
pixels across, so the map marks the artboard instead: same log, same recency window, same
color, one level up.

Beside it, the outline lists the same artboards as rows — the same ``KindMark``, settled
rect and click-to-copy id chip a node row has, and the same link a box carries. A map
answers *where*, a list answers *what there is*, and a file you have not seen wants both.
One focus ring is drawn on both, so the two views never disagree about where you are.

Boxes are placed in **layout points** — `--v-board-x`, `--v-board-y`, `--v-board-w`,
`--v-board-h` — and the stylesheet multiplies each by one zoom, `--v-map-scale`, exactly
as the render overlay multiplies its boxes by `--v-scale`. Positions are measured from the
map's own corner (the union of the artboards' rects), so a file whose artboards all start
at `x: 500` draws against the left edge rather than after 500 points of nothing.

| | |
| --- | --- |
| `ArtboardMap.minimumScale` | 0.06 — below this the map **scrolls** instead of shrinking |
| `ArtboardMap.maximumScale` | 0.5 — a map is a map; two small artboards are not blown up |
| Label threshold | a box under 24px wide drops its label and keeps its name in `title` |

The minimum is what makes a 40 000-point canvas usable: fitting it into a 760-point pane
would need a zoom of 0.019 and draw every artboard as a hairline, so the map holds 0.06 —
the zoom at which a 400-point artboard is still 24 pixels across — and scrolls sideways.
Labels are not multiplied by the zoom: a name is 11px at every zoom, and a box too small to
hold one drops it through a CSS container query rather than through JavaScript. Because
artboards do not overlap by ruling (a root added without coordinates is placed clear of
every other root), there is no packing fallback: an overlapping file draws overlapping,
which is the truth, and `lint`'s `artboard-overlap` finding is what says so.

The server writes a first zoom for an assumed 760×560 pane so the page is right before the
script runs; `viewer.js` measures the real pane and overwrites the one property. The canvas
pane itself is sized by the pane and never by the plane inside it — `.v-canvas` declares
one explicit grid track each way for exactly that reason, because an implicit `auto` track
would size to a 40 000-point plane and stretch the whole page instead of scrolling.

### `viewer.js`

The page's only script, and its contract is eleven things:

1. **Listen.** One `EventSource` on `/events`. A `change` naming the file on screen
   re-requests whichever canvas is showing — the render fragment on an artboard, the map
   on the map page — together with the outline that goes with it and the three whole-file
   panels; a `presence` re-requests the presence stack. The dashboard has no fragments of
   its own, so it re-reads its own page and takes `#v-files`, `#v-activity` and
   `#v-presence` from it.
2. **Intercept.** An outline row click becomes a `pushState` plus two fragment swaps; a
   click on the render hit-tests the inline layout JSON and selects the smallest node
   under the pointer; a click on the canvas *around* the artboard clears the selection,
   because empty space means nothing and there is no link to hang that on; a theme
   dropdown submits its form. Anything it does not handle falls through to the browser
   navigating, which is always correct.
3. **Time the overlay.** An edit marker fades seven seconds after it arrives — the
   ruling's five-to-ten window — unless its tag is clicked, which pins it. This is the
   one piece of behavior that cannot be server-rendered, and the reason the file exists.
4. **Keep the selection in sight.** After any swap, and once on load, the selected
   outline row is scrolled into view with `block: "nearest"` — but a swap first restores
   the scroll position of the panel it replaced, so a click on a row already in view
   moves nothing. Without that, every selection threw the outline back to row one and
   `block: "nearest"` then parked the row against the bottom edge, which is what made
   clicking down a long tree feel like the panel was fighting you. Selection is view
   state and the server owns which row is selected; where the panel happens to be
   scrolled is a
   property of this screen, so it is the client's to fix.
5. **Copy, and remember.** Clicking an ``IdChip`` copies its id and never falls through
   to whatever it sits inside — a capture-phase listener on `.v-id-chip` calls
   `stopPropagation` before the outline row's own click handler ever runs, so copying an
   id never also selects the row or navigates. The variables panel's collapse is the
   other piece of state that lives only in the browser: a click on `.v-variables-toggle`
   toggles `.is-collapsed` and remembers it in `localStorage`, keyed per file, restored on
   load and re-applied after every fragment swap (a `MutationObserver` on the page body,
   since a swap replaces the panel with a freshly server-rendered — and so always
   expanded — one). Both are wrapped in `try`/`catch`: a private window or blocked site
   data leaves the chip un-clickable-but-harmless and the panel expanded, never a thrown
   error.
6. **Fit the map, and hold the ring.** The bird's-eye map ships zoomed for an assumed
   pane, which is the only pane the server can know about; the script measures the real
   one and writes `--v-map-scale`, and every box follows because every box is placed in
   points and multiplied by it. It re-fits on a resize and after a swap. It also owns the
   focus ring: which box the keyboard is on, mirrored onto the artboard listing beside it,
   scrolled into the pane with the map's own `scrollLeft`/`scrollTop` — at the minimum zoom
   the map is wider than the pane — and put back on the same artboard after a swap
   replaces the map with markup that carries no ring.
7. **Keyboard and presentation.** See the table below. The dispatcher and every row
   it reads from are one data structure, `KEY_TABLE`, exposed as `window.__woodcaseKeys`
   so a browser test reads the exact rows the script reacts to rather than a second
   copy of the spec. An outline row's collapsed state is itself client-only — an
   `is-row-collapsed` class and the `hidden` attribute recomputed from it — so a fragment
   swap always arrives fully expanded; the disclosure triangle beside it is a server-
   rendered ``DisclosureGlyph``, not something the client draws. Presentation is entered
   from the top bar's `⛶` button as well as from `f`, and entering it flashes the exit
   hint: the *words* are ``PresentationHint``'s, server-rendered, and all the script owns
   is how long they stay — the same division the edit markers are under.

8. **Follow, and move.** A `change` whose `identity` matches ``Follow`` — any identity
   for `follow=anyone` — navigates to the first artboard in its `changedArtboards` that
   is not already on screen. It is a plain navigation, not a `pushState` with swaps, and
   that is deliberate: the listener that refreshes the fragments captured their URLs
   *synchronously* when the event arrived, for the artboard that was then on screen, so
   its requests are already in flight for the old one. Swapping the new one in beside
   them is a race. Nothing is lost by replacing the document — every piece of view state
   is in the URL, which is also why the theme pins survive a followed write untouched: a
   write carries no theme, so following one must never re-render under different pins.
   Any manual navigation — an outline row, the render, an artboard — rewrites `follow=`
   to `paused:<who>` in the capture phase, before the handlers above read `location` and
   before the browser reads an anchor's `href`, and re-requests the control so it stops
   claiming otherwise. Clicking an id chip is not navigating and never drops follow.
9. **Remember what is unread.** A `change` marks every artboard in `changedArtboards`
   other than the one on screen, in `localStorage` keyed by file id and artboard id; the
   artboard being viewed is cleared. The marks are re-applied after every swap, from a
   `MutationObserver`, because the map and the artboard listing are fragments that arrive
   knowing nothing about what this browser has read. They hang on `data-artboard="<id>"` —
   an attribute, not a class — so any other view of the artboards inherits the dots by
   carrying the same attribute: a map box, a listing row, a footer step. The breadcrumb's
   map crumb gets one too, for the whole file rather than for one artboard, read back out
   of storage so it counts artboards the page is not currently showing. Unread starts at
   *this page load*, not at the file's history: a fresh browser shows no dots, which is
   the truth, since nobody has told it what you have already seen. Every storage touch is
   wrapped in `try`/`catch`; a private window shows a dotless page rather than a broken
   one.
10. **Move the tabs, and remember the furniture.** A click on a `.v-tab` becomes a
   `pushState` plus setting `data-tab` on `#v-right` — every panel is already on the
   page, so switching is an attribute write, not a fetch. The URL it pushes is built
   from `location`, never from the link's own `href`: the server wrote that href before
   anything was selected, and following it would navigate away from the selection. The
   same write moves the `is-current` pill and rewrites every tab's `href`, so the bar
   never disagrees with the panel under it. A *selection* — from a click **or** from the
   keyboard, because it happens inside `select()` — also writes `tab=` into the URL with
   `replaceState` and re-requests `#v-details`, applying the same rule
   `ViewState.tab(forSelection:)` keeps on the server. Two preferences here
   belong to the browser rather than to the view, and so are not in the URL: the pane
   sizes, written as custom properties (`--v-col-left`, `--v-row-lower`) on the grid
   containers when a `.v-grip` is dragged, and the code pane's language. Both live in
   `localStorage` under `woodcase.panes` and `woodcase.code.lang`, both are restored on
   load, and both are wrapped in `try`/`catch` — a private window gets the default widths
   and the default language, never a thrown error.
11. **Step between artboards in place.** The footer's `‹`/`›`, and the ← / → that click
   them, are a `pushState` plus a swap rather than a page load. Replacing the document
   threw away everything not in the URL — the event stream, the pane widths, where the
   outline was scrolled, a row's collapsed state, and presentation mode, which is a class
   on `<body>` — so holding an arrow key walked the file by reloading it once per press.
   An artboard is most of the page, and the swap covers the five pieces that name it:
   `#v-render-region` (the image, the layout JSON, `#v-stage`'s own `data-artboard`, the
   selection footer and its steps), `#v-outline` (whose rows must select *into* the new
   artboard), `#v-right` (the tab hrefs, Export and Code), `#v-follow` (the form posts
   back to the page you are on) and `.v-crumbs`, plus the tab title. The last two have no
   fragment endpoint, so all five come out of **one fetch of the destination page** —
   the same move the dashboard makes with `swapFromPage`, and the same render the reload
   would have cost the server, minus the document. Nothing else is touched, which is what
   keeps presentation mode, the pane widths and the stream alive across a step. Moving
   between the map and an artboard stays a real navigation: those are two different pages
   with two different canvases. A `popstate` for a *different* artboard runs the same
   whole-page swap, and item 1's own `popstate` handler stands aside for it so the two
   never both answer. A fragment fetch names its artboard when it is issued, so every
   swap carries the token of the artboard it was issued for and a response that lands
   after the page has moved is dropped — the race item 8 avoids by replacing the document
   instead.

Items 1 and 6 meet through a `MutationObserver`: a `change` refreshes the render region
but knows nothing about the right pane, so the arrival of a fresh `#v-render-region` is
the signal that the details and the code beside it are stale.

The layout the overlay positions from rides in the page as `#v-layout`, a JSON
`ArtboardLayout`: every node of the artboard in **artboard coordinates**, with the
scale the image was rendered at. The engine's own rects are parent-local, so the boxes
come from ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)``, which accumulates
origins the way the renderer's transform stack does — the same walk `woodcase shot
--outline` places its boxes with. That walk answers in the **root's** frame, and a
top-level frame's own rect is in canvas coordinates, so `ArtboardLayout` subtracts the
artboard's origin exactly as `shot --outline` does: an artboard at `x: 500` would
otherwise put every box past the right edge of its own image, where no click can reach
one. It then walks the tree itself only for
what a rect map cannot carry: document order, the name path, and the clip test, which is
parent-*local* by definition.

### Keyboard and presentation

| Context | Key | Effect |
| --- | --- | --- |
| the map | ← / ↑ | move the ring to the previous artboard box, in document order |
| the map | → / ↓ | move it to the next one |
| the map | `Enter` | open the artboard on the ring, exactly as clicking its box would |
| an artboard, nothing selected | ← / → | previous / next artboard, as clicking the footer's step would |
| an artboard, a node selected | ↑ / ↓ | previous / next outline row, as clicking that row would |
| an artboard, a node selected | ← / → | collapse / expand the row's children; a leaf does nothing |
| any | `f` | toggle presentation: chrome hidden, no overlays, selection kept |
| any | `Esc` | leave presentation, else select the parent node, else go up to the map |
| focus in a form control | any | untouched — the control keeps the key |

The three contexts in the first column are mutually exclusive and cover every keypress.
"The map" is `#v-map` being on the page at all. On an artboard, "nothing selected" and "a
node selected" read `?node=` off the URL, the same fact ``ViewState`` carries everywhere
else in the page: with nothing selected, ← / → only ever step artboards; with a node
selected, they only ever collapse or expand, never falling back to stepping artboards.

`Esc` climbs the hierarchy one node at a time — the selection's parent, then that node's
parent, up to the artboard's root — and the level above the root is the map, so from a
root (or with nothing selected) it goes up. On a single-artboard file, which has no map
to go up to, a root selection clears instead. Nothing is skipped and nothing selected is
merely dropped, which is the ladder people keep asking design tools for.

On the map the ring starts nowhere: the first → or ↓ takes the first box and the first ←
or ↑ takes the last, the same rule the outline's own arrow stepping uses. Both ends clamp
rather than wrapping.

A form control — `input`, `select`, `textarea`, `button`, or anything
`isContentEditable` — keeps every key; the dispatcher checks the event's own `target`,
never focus indirectly, so a probe field appended anywhere on the page is enough to prove
it.

Presentation mode is one class, `body.is-presenting`, and the stylesheet does the rest:
the top bar, both side panels, the pane grips, the selection footer and `#v-overlay` are
hidden, and the canvas **leaves the grid** — `position: fixed; inset: 0` — so what is left
is the artboard on its own background and nothing else. It is entered with `f` or with the
`⛶` button in the top bar, and left with `f` or `Esc`; ``PresentationHint`` flashes *Press
f or Escape to exit* on entry and fades, because the mode has just hidden every control
that would have said so.

Leaving the grid is the fix for a real bug, not tidiness. Hiding the chrome used to leave
`.v-main` sizing itself from its contents, and every pane below it sizes its row with
`minmax(0, 1fr)` — a track whose *minimum* is zero, so with no definite height coming down
it resolves to nothing. The render then measured itself against a pane 0 px tall,
`fitStage()` clamped at its `0.05` floor, and a 400-point artboard was drawn **20 px
wide**. Fixed to the viewport, the pane is the screen by construction.

`fitStage()` re-runs on entry, on exit, on a resize and after every swap. Presenting, it
is allowed to scale the artboard **up** — normally it never exceeds 1:1 — as far as the
density its PNG was rendered at (`data-density`, up to ``RenderCache/maximumScale``), which
is one image pixel per point of enlargement and so as far as it can go without turning
size into blur. Arrow keys still step artboards, in place and without leaving the mode, and
each new artboard is refit to the same screen. The selection itself is untouched —
`?node=` stays on the URL — so leaving presentation shows the same node outlined, exactly
as it was before `f` was pressed.

The outline has no server-rendered *collapse* of its own: it always ships flat and fully
expanded, one `<a>` per row with its depth on `--v-depth`. The disclosure triangle beside
each row, though, **is** server-rendered — a shared ``DisclosureGlyph`` (an inline SVG,
not the bare `▾` it replaced) when ``TreeRow/childCount`` is greater than zero, a blank
`.v-disclose` spacer otherwise, so every row's name still lines up in one column whether
or not that row has one. Collapsing a row hides every following row whose depth is
greater until one at or above its own depth ends the run — the same "no such row follows"
test that makes a leaf a no-op for both ← and →. The *state* is nothing but an
`is-row-collapsed` class and the `hidden` attribute recomputed from it in one forward
pass, so a fragment swap — which replaces the rows outright — always lands fully expanded
again; the script's own `markOutlineDisclosure()` skips a row whose first child already
carries `.v-disclose`, which every server-rendered row's now does.

The whole table is one JavaScript array the dispatcher reads from, exposed as
`window.__woodcaseKeys` (each row's `key`, `context` and `label` — its `run` function is
dropped by `JSON.stringify`, so a page inspecting the table sees only what a person
reading this one does). A browser test dispatches a synthesized `KeyboardEvent` for every
row and asserts what it did; there is no `sleepy` operation for a key press, so this is
the same "honest about mechanism" choice `sleepy click` makes for a synthesized pointer
event.
### Follow, and unread dots

One control in the top bar, *Follow*, with three kinds of option: **nobody** (the
default), **anyone**, and one entry per identity the activity log has seen — server-
rendered from the same list the presence stack draws, in the log's order of first
appearance, so an agent keeps its place in both. A `?follow=` naming someone the log has
not seen yet is offered too, appended: a control whose selected value is not among its
options silently reads as *nobody*, which would say you are following no one while the
page follows someone.

It is view state, so it lives in the query and a reload keeps it. Following moves the page
to the artboard a matching write touched, and **never** to a different theme — a write
carries no theme. An unattributed write matches nothing, `anyone` included: the page moves
because somebody wrote, and nobody claimed that one.

Any manual navigation drops follow to nobody. It does not forget, though: `follow=ana`
becomes `follow=paused:ana`, and the control grows a *resume following ana* link that is
the same view state with the follow switched back on — so resuming carries the theme pins
and the selection forward untouched. That is why ``Follow`` has three states rather than a
target and a flag.

Following from the *map* is a drill-in: nothing is on screen for a write to land beside,
so a matching write opens the artboard it touched.

Beside it, each artboard carries a dot when a change touched it since this browser last
viewed it — per viewer, in `localStorage`, never on the server — on its box on the map, on
its row in the listing, and on a footer step that leads to it. The breadcrumb's map crumb
carries one for the file as a whole, which is the useful question on an artboard page: is
the news somewhere else? It all starts at page load rather than at the file's history,
because the file's history is not a record of what *you* have seen.

### Identity color

`ActorColor` is the Jobs dashboard's hash, ported so an agent is the same color in
both tools: FNV-1a 32-bit, `hue = h(name + "u") % 360`, `saturation = h(name +
"zzzzzzzz") % 50 + 50`, lightness 48%. It appears in exactly two places — the avatar disc
and the edit markers — because a hashed hue collides with the accent green often enough
that colored text would read as a link.

The **ink** on that hue is Woodcase's own, not the dashboard's: `ActorColor.ink` is
black when the disc's WCAG relative luminance exceeds `0.179` and white below it. That
number is where the two inks cross — solving `(L + 0.05) / 0.05 = 1.05 / (L + 0.05)`
gives `√1.05 − 0.05` — so both land on 4.58:1 there and the better one is better still
either side. Every hue on the wheel therefore clears AA with the hash left exactly as it
is, which is the whole reason the ink is a second property rather than a different
lightness: the dashboard's white-on-everything reads at 1.72:1 on `claude-a`'s green.

It ships as `--v-actor-ink` beside `--v-actor`, written by whatever knows the identity —
``AvatarView`` on the disc, ``ArtboardOverlay/MarkerBox`` on the edit box, so the tag's
words and the avatars inside it pivot with the box they sit on. The stylesheet reads
`color: var(--v-actor-ink, #FFFFFF)`; the fallback is for a disc drawn with no identity
behind it. `DESIGN.md` § *Colors* carries the before-and-after ratios for this and for
the rest of the palette's AA pass.

Presence order is the log's order of first appearance, and an outline row keeps its
editor's color for thirty seconds after the edit.

## Adding pages

The server knows nothing about pages. It is handed a route table and calls whatever
comes back, so a page is added without touching the server:

```swift
let server = ViewerServer(pages: { _ in ViewerPages.routes() })
```

A handler receives a `ViewerRequest`: the parsed request, the parameters its pattern
captured, and a `ViewerContext` holding the file index, the render cache, the activity
log and the event hub. Patterns are literal segments, `{name}` for a whole segment, and
`{name}.png` for a parameter with a literal suffix.

Precedence is specificity, then registration order. The most specific route that matches
answers, compared segment by segment from the left, and the first segment that differs
decides:

| Segment | Example | Beats |
| --- | --- | --- |
| a literal | `artboards` | both of the below |
| a capture with a suffix | `{artboard}.png` | a bare capture |
| a bare capture | `{artboard}` | — |

So `/files/{file}/artboards/{artboard}.png` answers `…/Cnv01.png` even though the page
route `/files/{file}/artboards/{artboard}` was registered first: a bare capture takes
the whole segment, extension and all, and now loses to the pattern that names the
extension. Registration order only breaks a
tie between two patterns of the same shape — and page routes are registered *before* the
built-ins, which is what lets a page own `/` and `/files/{file}`.

## The right pane: Activity, Details, Export, Code

Four panels behind a tab bar, and **every one of them is server-rendered on every page**.
The tab only decides which one the stylesheet shows. That is what makes the tabs work with
the script off — they are real links to `?tab=` — what lets a fragment land in a panel
nobody is looking at, and what makes switching instant rather than a round trip. Four
panels of a local file are cheap; a tab that has to fetch before it can be read is not.

The map page shows Activity alone: Details describes a selected node, and Export and Code
both answer about one artboard, so a page looking at all of them and none in particular
has none of the three.

The tab bar is also where the pane's own state is written back. A selection made without a
reload moves the pane to Details, and ``ViewerScript`` moves the lit pill and rewrites
every tab's `href` from `location` at the same time — the hrefs the server wrote describe
the view *at page load*, and a Details tab still carrying no `?node=` would drop the
selection on the way to its own tab.

### Details

``DetailsPanel`` lists the selected node's attributes: its name, its type, and one row
per property it *actually carries*. Unset is not a value — ``NodePropertyCodec/paths(for:)``
lists the whole vocabulary of a node's kind, and a text node that sets two of twenty-odd
properties reads as two rows, not as eighteen em-dashes. A row is named by its **codec
path** (`kind.content`, with the file's own key beside it in the hover), which is what
`woodcase get` prints and `woodcase set` takes, so a row is a property you can go and
change spelled the way the command wants it.

Each row is marked with where its value came from:

| Mark | Means |
| --- | --- |
| `literal` | Written on the node, as it stands |
| `$name` | Written as a variable; the value shown is what the current theme resolves it to |
| `override` | Written on the component instance this node sits inside, over the definition's value |

Getting those three apart takes **three documents**, and ``NodeDetails`` reads all three:
the editable store (which node an address means, and what the definition says), the
expanded document with variables still written as `$name` (what was *authored* here), and
the expanded-and-resolved one (what it is worth under the theme on screen). Reading only
the resolved document would report every `$accent` as the hex it happens to be today;
reading only the authored one would report a variable and never say what it means.
``RenderCache`` already made all three on its way to a render and used to throw two of
them away, so ``PreparedDocument`` now keeps them.

An override names the instance it came from — ``ResolvedNodeAddress/targetID``, the
*outermost* `ref`, because that is where the format stores the override even when the
node lives inside a nested instance two levels down — and what the definition says
underneath it. The definition itself is found by the shape of the expanded id: expansion
prefixes every id in a clone with the instance's own at every level, so the last segment
of `Nav01/Bdg01/Cnt01` is `Cnt01`, and that node is still in the flat store.

A `?node=` that resolves to nothing does *not* fail the page — a link pasted after a
rename should still open the artboard — and the pane says the address went nowhere rather
than looking like an empty selection.

### Export

``ExportPanel`` is a plain `GET` form aimed at
`/files/{file}/artboards/{artboard}/export`, so choosing a format and a size and pressing
the button *is* the download: no script, no assembled URL, and the address bar shows
exactly the request an agent can repeat with `curl`. It offers PNG and PDF always, and
the generated files **this document actually writes for this artboard** — asked of the
emitter rather than assumed, so a `states.css` appears only when some component declares
a state and a `.tsx` only when the artboard is a definition or a page.

### Code

``CodePane`` is the fourth tab: the file `woodcase generate` writes for the artboard on
screen. It does not generate anything of its own — it runs the same analyzers and the same
``ReactEmitter`` the verb runs, over the same parsed document, and takes one file out of
the result, cached per file by ``RenderCache`` and dropped when the file changes.

It spent a while as the right-hand half of a **split canvas**, opened by a switch at the
end of the tab bar. The split charged the render a third of its width on every page
whether or not the code was being read, and the question it answers — *what does this
artboard generate* — has exactly the shape of the ones Details and Export answer. So it is
a pill in the same bar, and the canvas is one pane again.

The language picker lives in the pane's own header, where the file it names is. It is a
`GET` form aimed at the page, so with the script off it is a navigation to
`?tab=code&lang=…` — its tab is written unconditionally, because submitting the Code
pane's own picker has to land back on the code. With the script on it is a
change-to-apply dropdown that also remembers the choice in `localStorage` — the one piece
of state here that is a property of *this browser* rather than of the view, because a URL
you paste to a colleague should open the artboard, not impose your taste in output files
on them.

### Resizable panes

Every pane is a grid track whose size is a custom property on its container —
`--v-col-left`, `--v-col-right`, `--v-row-lower` — so dragging a
``PaneGrip`` is one property write and the browser lays the rest out. Nothing is measured,
positioned or resized by hand, and the `var()` fallbacks are the sizes the page had before
it was resizable, which is what a browser with no stored sizes, or no script, still gets.
A grip is a real element rather than the grid's `gap` because a one-pixel line is not a
target. Sizes are kept per grip and **not** per file: how wide you like the outline is a
fact about your screen, not about the document.

## Kind marks, id chips and the variables pane

A real file's top-level frames are often *all* reusable definitions, with the screens on
the canvas being refs to them (`banking.pen`, `woodcase-app.pen`) — so the outline and
the artboard map both mark a node's role, not only its structural type. ``KindMark``
draws a small labeled badge — glyph, a `title` for a hover, and a short visible word —
for a reusable component definition (`component`), a placed instance (`instance`), or a
slot frame (`slot`, a frame whose `slot` property is non-`nil`). At most one applies, in
that order of precedence, and its glyph *replaces* the row's plain type glyph rather than
sitting beside it — a bare "◇" repeated next to a labeled "◇ instance" badge said the
same thing twice.

Every id the page shows — an outline row's, the selection footer's, an activity row's
expanded node list — is an ``IdChip``: a small monospace pill, styled like the Jobs
dashboard's id pills, that copies its id to the clipboard when clicked. Because a chip
usually sits inside something else that also handles clicks (an outline row is itself a
link), the click is caught in the capture phase before that other handler ever runs — see
`viewer.js`'s fourth contract item, above.

``VariablesPanel`` renders every ``PenVariableType`` distinctly: a color keeps its
swatch and reads as text, a number gets a right-aligned numeric class, a string is plain
text, and a boolean is a labeled pill rather than the bare word "true" or "false". Its
header wraps the toggle and the title `Variables` in one flush-left group
(`.v-panel-head-title`) so the title sits directly beside the disclosure control instead
of floating away from it — `.v-panel-head`'s own `space-between` would otherwise spread
every adjacent pair of its direct children, toggle-title included.

A variable's own row expands, behind a ``DisclosureGlyph``, to a small table of axis
rows rather than a bullet list: one row per themed variant, its `axis=option` pins in one
column and its value in the other, oldest variant first — a `card-radius` themed by
`density` reads as two rows, `density=compact` next to `4` and `density=regular` next to
`8`. A color variant's value carries its own swatch, drawn the same way the summary
row's does. A variable with no themed variants still expands to one row, its axis reading
`*`, so every variable's detail is a table rather than sometimes a table and sometimes
bare text. The panel's row list has a bounded `max-height` and scrolls on its own rather
than pushing the outline off screen, and the whole panel collapses behind the same glyph
its header uses.

``DisclosureGlyph`` (`Components/DisclosureGlyph.swift`) is the small inline-SVG triangle
behind both the panel's own toggle and each row's `<summary>` — a shared, panel-agnostic
component, styled only by the `.v-disclosure-glyph` rule, so the same shape and weight
are available to any other disclosure control the viewer grows later. It draws in a box
sized well past the triangle itself, for a comfortable click target. The shape always
points down, its *open* orientation; a caller that starts expanded leaves it unrotated,
and one that starts collapsed (a variable row) rotates it -90° by default and back to 0°
on its own `[open]` state, entirely in CSS — no script involved.

## Components and their previews

The page is built from components — Swift structs with a `body`, in
`Sources/WoodcaseViewer/Components/` — and pages are compositions with no markup of their
own. Each component renders from typed inputs that already exist (`TreeRow`,
`ActivityEvent`, `FileListReport.Summary`), so the rows `woodcase tree` prints and the
rows the browser shows are one model with two formatters.

### The catalog

A component's states are part of what the component *is*, so they live beside it rather
than in the tests. `Components/Previews/<Component>+Previews.swift` — and
`Pages/Previews/` for the pages — declares a `static let previews: PreviewComponent`: a
slug, a title, a blurb, the source file a reader opens when something looks wrong, and
one `PreviewState` per state worth looking at. `PreviewCatalog.all` is the whole
registry, one line per component, so a new *state* needs no edit outside the component's
own file.

A state carries a slug (its URL segment), a name, a **note** saying what a reviewer
should look at or what went wrong there once — a state with no note is a picture with no
caption — the `PreviewFrame` it belongs on, and a closure that builds the component. The
props are the **production** types, assembled by `PreviewFixtures` against a clock pinned
to one moment in UTC so a relative age renders the same every run. A preview-shaped twin
of a `TreeRow` would drift: it renders states production cannot reach and misses ones it
does, and then looks like coverage. Write the closure so it captures nothing — build
everything inside it — and the state stays sendable however the component's own types
are declared.

The states are **representative, not exhaustive**: empty, ordinary, crowded, wrong,
mid-flight. There is deliberately no matrix generator, and a state that renders nothing
is not a preview — that is a markup fact, and a behavior test holds it.

The same test, twice over: a state that renders the *same picture* as its neighbor is
not a preview either. `id-chip/outline` (a chip wearing a caller's extra class) and
`pane-grip/rows` (the horizontal seam) were dropped on 2026-09-02 for that reason —
each varied only an attribute, and a reviewer looking at two identical pictures learns
nothing they can grade. Where the difference is in the markup, the instrument is a
markup test.

A state only the browser can reach — a copied id chip, a dropped stream, an unread
artboard — is declared by **setting the attribute the script would set**, never by
mocking one up: the component grows a parameter whose default is what the server already
renders (`IdChip(id:copied:)` writes the same `is-copied` class and `copied` text
``ViewerScript`` writes; `TopBar.Crumb(unread:)` and `ArtboardRow(unread:)` write the
same `data-unread="1"`), so production markup is unchanged and the preview is the real
thing rather than a picture of it.

`PreviewFrame` names production surfaces rather than widths — `strip`, `leftPane`,
`rightPane`, `canvas`, `body`, `topBar`, `page` — because a component alone on a blank
page is the wrong picture: an outline panel is a fixed column and a right pane sits
against the window's edge. `canvas` is the render column *between* the two panes;
`body` is the dashboard's centered column, which is where the file cards live and is a
different width. The catalog declares the frames and `/preview` serves them.

### The preview pages

Three routes, registered in `ViewerPages` so **both** verbs carry them:

| Route | What it serves |
| --- | --- |
| `GET /preview` | The index: every component, its blurb, its state count, its source |
| `GET /preview/{component}` | The canvas: every state stacked, each under its name and note, each with an anchor and its own link |
| `GET /preview/{component}/{state}` | One state alone, whole page — the URL a review shot opens |

The three handlers are pure functions of `PreviewCatalog.all`: no file, no log, no
render cache. That is what lets `woodcase preview` answer them over an empty context
and `woodcase serve` answer them with the identical bytes beside a live document — and
it is asserted, by rendering one canvas from each kind of server and comparing.

An unknown component or state is a 404 whose body lists what does exist
(``ViewerError/unknownPreviewComponent(slug:available:)`` and
``ViewerError/unknownPreviewState(component:slug:available:)``), so a mistyped slug
answers with the catalog rather than with nothing.

`PreviewIndex`, `PreviewCanvas` and `PreviewStatePage` are components like any other —
they render inside `ViewerDocument` under a `Layout.preview`, so the stylesheet and the
script are the production ones, and they declare previews of their own against
`PreviewPageSamples` (a two-component fixture, not the live catalog: an index whose
golden changed every time anybody added a state anywhere would stop being read).

A state is drawn inside a `.v-preview-frame[data-frame="…"]` element, which the
stylesheet gives its surface's geometry from the *same* custom properties the artboard
grid uses — `--v-col-left`, `--v-col-right`, `--v-grip` — so there is one number and not
two. The one number of its own is `--v-preview-window`, the reference window the render
column is measured against. A `page` state has no frame: a document cannot nest a
document, so the canvas links to it and the single-state route serves it whole. The
rules live in `ViewerStylesheet+Previews.swift` and their design rationale in
`DESIGN.md` under *Previews*.

Three more things keep a shot of a state equal to what the state declared:

- **The pages are pictures, not windows.** The catalog's own top bar is
  `TopBar(subject: .previews)` — the trail and nothing else, so a live badge,
  presence stack or keyboard hint a state draws is the only one on its page and the
  script drives *it*. And `viewer.js` opens no `/events` stream on a `/preview` URL
  (it writes `data-stream="off"` on the root to say so), so presence, the badge and
  the unread dots stay as the state set them. The unread block also only ever removes
  a dot it put there itself; a server-written `data-unread="1"` is a declared state.
- **Renders are the catalog's.** Every fixture file id a state names is listed in
  `PreviewFixtures.fileIDs`, and `ViewerPages` answers
  `/files/<fixture>/artboards/{artboard}.png` with `PreviewFixtures.render` — the
  fixture layout drawn as boxes, served as a PNG — the type production answers
  at the same `.png` address. A literal file segment outranks the
  real image route's `{file}` capture, so `serve` shows the same picture;
  `PreviewImagesTests` fails a state whose `<img>` points anywhere unanswered.
- **Captions are prose.** A state's note and a component's blurb are written in the
  doc-comment dialect and rendered through `PreviewProse`: code spans and DocC symbol
  links become `<code>`, `*emphasis*` becomes `<em>`.

### The review loop

The point of the URLs is that a picture can be shot, sent and named:

```bash
base=http://127.0.0.1:7333
woodcase preview --port 7333 &                # prints $base/preview on stdout
woodcase preview --list                       # every state's path, e.g. /preview/avatar/small
sleepy shot "$base/preview/outline-panel/crowded" \
    --size 1280x800 --out local/viewer-shots/
```

`--list` prints **paths**, not URLs: it binds no port, so it has none to name, and a
listing written against 7333 while the server took 7334 is a page of dead links that
look alive. The base belongs to the running verb — it prints its own URL, and
`--json` reports it as `url` — so an agent walking the catalog reads the base once and
joins `"$base$path"` per state:

```bash
woodcase preview --list --json | jq -r '.[].states[].path' \
    | while read -r path; do sleepy shot "$base$path" --out local/viewer-shots/; done
```

A defect found is filed with the state's **path plus whatever base it was shot on**,
which is the whole reason a state has a stable path — "the third one down" is not a bug
report. There is deliberately no screenshot comparison: the goldens are the regression
test and they test markup.

### The goldens

Each state has a golden-HTML fixture at
`Tests/WoodcaseViewerTests/Fixtures/golden/<component>/<state>.html`, and
`PreviewCatalogTests` walks the whole catalog against them in one parameterized test.
That fixture is the component's preview and its regression test at once — one
declaration, so the picture a person signs off on and the fixture the suite checks
cannot drift apart. Re-bless with `UPDATE_GOLDEN=1 swift test --filter
WoodcaseViewerTests`, and read the diff — a golden nobody looked at only proves the code
has not changed. The fixtures are the *formatted* render; the server sends the compact
one, and the two differ only in whitespace.

To add a state: write one `PreviewState` in the component's `+Previews.swift` file, run
the suite (it fails, naming the fixture that is missing), re-bless, and read the new
file.

## See Also

- <doc:WoodcaseActivityLog>
- <doc:PenRendering>
- <doc:EditingDocuments>
