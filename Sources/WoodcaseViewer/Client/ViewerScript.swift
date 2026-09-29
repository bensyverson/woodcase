//
//  ViewerScript.swift
//  WoodcaseViewer
//

import Foundation

/// The viewer's only script, served at `/viewer.js`.
///
/// ## What it is allowed to do
///
/// Five things, and nothing else:
///
/// 1. **Listen.** One `EventSource` on `/events`. A `change` for the file on screen
///    re-requests the fragments; a `presence` re-requests the presence stack. Not on a
///    `/preview` page: a preview is a declared state, and the stream would repaint it.
/// 2. **Swap.** Every update is a fragment the *server* rendered, replacing the element
///    with the same id. There is no template, no state and no component here — an edit
///    marker's color is a hash and a box's position is a layout rect, and re-deriving
///    either on the client would be a second implementation of something Swift already
///    owns.
/// 3. **Intercept.** An outline row, a click on the render and the footer's `‹`/`›` steps
///    are all links; the script turns them into a `pushState` plus a swap, and anything
///    it cannot do falls through to the browser navigating, which is always correct.
///    Stepping to another artboard swaps most of the page — the render region, the
///    outline, the right pane, the Follow control and the breadcrumb — out of one fetch
///    of the page it is moving to, because those are the pieces that name the artboard
///    and two of them have no fragment of their own. Moving between the map and an
///    artboard stays a real navigation: those are two different pages.
/// 4. **Fit.** The artboard ships at full size, because that is the only size the server
///    can know is right; fitting it to the pane needs the pane's width. The script writes
///    one custom property, `--v-scale`, and every box follows — each is placed in layout
///    points and multiplied by it — so nothing is repositioned by hand. Beside the panels
///    it never exceeds 1:1; presenting, it may grow as far as the density the PNG was
///    rendered at, which is the point past which size becomes blur. The bird's-eye
///    ``ArtboardMap`` on the map page works the same way, with `--v-map-scale` and its own
///    bounds: below ``ArtboardMap/minimumScale`` it scrolls rather than shrinking.
/// 5. **Reveal.** After a swap, and once on load, the selected outline row is scrolled
///    into view — but a swap first puts back the scroll position the panel it replaced
///    had, so a click on a row already in view moves nothing. The server owns *which*
///    row is selected; where the panel is scrolled is a fact about this screen, and only
///    the browser has it.
///
/// ## Which mode the page is in
///
/// Exactly one of `#v-stage` and `#v-map` exists, and which one is the whole of "what am
/// I looking at": a stage is one artboard, a map is all of them. Both carry `data-file`,
/// so nothing here parses the path. The mode decides which canvas fragment a `change`
/// re-requests, which outline fragment goes with it, and which rows of the key table a
/// keypress can match.
///
/// Eleven pieces of genuine client behavior ride alongside the five above: the overlay's
/// *timing* (an edit marker fades seven seconds after it appears, and clicking its tag
/// pins it), where the outline is *scrolled to* (a property of the panel's box on this
/// screen, not of the document), an id chip's *copy* (clicking one copies its id and —
/// via a capture-phase listener — never also selects or navigates whatever it sits
/// inside), the variables panel's *collapse* (remembered in `localStorage`, restored
/// after a reload and after every fragment swap), the *keyboard model* — arrow keys walk
/// the map's boxes, step artboards, or move and collapse outline rows depending on the
/// mode, `f`, the top bar's `⛶` button and `Esc` toggle a presentation mode that hides
/// everything but the render and flashes ``PresentationHint``'s server-rendered way out,
/// and a row's collapsed state is client-only since a swap arrives fully expanded — the
/// map's *focus ring* (which box the keyboard is on, mirrored onto the artboard listing
/// beside it), *following* an identity (a `change` whose identity matches moves the page
/// to the artboard it touched, which from the map is a drill-in, and any manual
/// navigation drops follow to nobody while remembering who to resume), the *unread dots*
/// (an artboard a change touched carries one until it is viewed, per viewer and per
/// browser, in `localStorage`, and the breadcrumb's way back up carries one for the whole
/// file), the *pane sizes* a drag writes as custom properties, *which generated file*
/// the code pane is showing, and *clicking away* — a click on the canvas around the
/// artboard clears the selection, because empty space means nothing and there is no link
/// to hang that on. None can be server-rendered, which is the reason this file exists at
/// all.
///
/// With the script switched off, every page is still correct: rows are links, the theme
/// picker is a form with a submit button (hidden by CSS only once the script has marked
/// the document as scripted), and the selection is already outlined server-side.
public enum ViewerScript {
    /// How long an edit marker stays before it fades, in milliseconds.
    ///
    /// Seven seconds is the middle of the ruling's five-to-ten window: long enough to
    /// look up from the terminal, short enough that a busy file does not accumulate a
    /// permanent lattice of boxes.
    public static let markerLifetime = 7000

    /// How long the presentation exit hint stays before it fades, in milliseconds.
    ///
    /// Long enough to read six words, short enough that it is gone before anyone is
    /// looking at the design rather than at the message about the design.
    public static let presentationHintLifetime = 1800

    /// The script's text.
    public static let javaScript = #"""
    // woodcase serve — the viewer's only script. See ViewerScript.swift for its contract.
    (() => {
      "use strict";

      const MARKER_LIFETIME = \#(markerLifetime);
      const PRESENTATION_HINT_LIFETIME = \#(presentationHintLifetime);
      // The whole-file fragments, which need nothing but the file id. The outline is not
      // among them: it is `/artboards/{id}/outline` on the artboard page and
      // `/artboards` on the map, so it goes through `outlineURL()` instead.
      const FRAGMENTS = ["activity", "variables", "presence"];

      const root = document.documentElement;
      root.dataset.js = "on";

      const stage = () => document.getElementById("v-stage");
      // The map page's canvas. Exactly one of the two exists, and which one is the
      // whole of "what mode am I in": a stage means one artboard, a map means all of
      // them. Both carry `data-file`, so everything below asks the page rather than
      // parsing the path.
      const mapCanvas = () => document.getElementById("v-map");
      const isMapMode = () => !!mapCanvas();
      const fileID = () => (stage() ?? mapCanvas())?.dataset.file ?? null;
      const artboardID = () => stage()?.dataset.artboard ?? null;
      const live = (state) => {
        const badge = document.getElementById("v-live");
        if (badge) badge.dataset.state = state;
      };

      // ---- swapping -------------------------------------------------------

      // Which artboard the page is showing, counted up every time that changes without
      // the document being replaced. A fragment fetch names its artboard when it is
      // *issued* — the `change` listener builds its URLs synchronously, for whatever was
      // on screen when the event arrived — so a response that lands after the page has
      // moved is an answer about the artboard that just left. Comparing the token it was
      // issued under is what drops it instead of swapping it in.
      let voyage = 0;

      // Says the page has moved to another artboard, and hands back the token that
      // belongs to where it now is.
      function departed() {
        voyage += 1;
        return voyage;
      }

      // Puts one server-rendered element in place of another, keeping where this screen
      // has the old one scrolled to.
      //
      // A panel that scrolls (`#v-outline` above all) is replaced by a freshly rendered
      // one that starts at the top, and the server has no idea where it was — so without
      // this, every swap throws the outline back to row one and `revealSelection` then
      // parks the selected row against the bottom edge. Where a panel is scrolled is a
      // fact about this screen, which is exactly the class of fact this file exists for.
      function replaceKeepingScroll(target, replacement) {
        const top = target.scrollTop;
        const left = target.scrollLeft;
        target.replaceWith(replacement);
        replacement.scrollTop = top;
        replacement.scrollLeft = left;
      }

      // Every fragment response IS the element it replaces, so the swap is an
      // outerHTML replacement: an element that carries state in its own attributes
      // (the stage's scale, a panel's id) must be replaced, never filled.
      async function swap(url, targetID) {
        const target = document.getElementById(targetID);
        if (!target) return false;
        const sailed = voyage;
        let html;
        try {
          const response = await fetch(url, { headers: { Accept: "text/html" } });
          if (!response.ok) return false;
          html = await response.text();
        } catch (error) {
          return false;
        }
        if (voyage !== sailed) return false;
        const holder = document.createElement("div");
        holder.innerHTML = html;
        const replacement = holder.firstElementChild;
        if (!replacement) return false;
        replaceKeepingScroll(target, replacement);
        armMarkers(replacement);
        fitStage();
        revealSelection();
        return true;
      }

      // The dashboard has no fragment endpoints of its own — its regions are the whole
      // page — so it re-reads the page it is already on and takes the pieces it needs.
      async function swapFromPage(ids) {
        let html;
        try {
          const response = await fetch(location.pathname + location.search, {
            headers: { Accept: "text/html" },
          });
          if (!response.ok) return;
          html = await response.text();
        } catch (error) {
          return;
        }
        const parsed = new DOMParser().parseFromString(html, "text/html");
        for (const id of ids) {
          const next = parsed.getElementById(id);
          const current = document.getElementById(id);
          if (next && current) {
            current.replaceWith(next);
            armMarkers(next);
          }
        }
      }

      const fragmentURL = (name) => `/files/${fileID()}/${name}${location.search}`;
      const artboardFragmentURL = (name) =>
        `/files/${fileID()}/artboards/${encodeURIComponent(artboardID())}/${name}${location.search}`;
      const renderURL = () => artboardFragmentURL("render");
      // The outline names the artboard on screen, because every row's href selects
      // *into* it — `/files/{id}?node=…` is the map now.
      const outlineURL = () =>
        isMapMode() ? fragmentURL("artboards") : artboardFragmentURL("outline");

      // Which artboard the *address bar* names, which is not always the one on screen:
      // between a `pushState` and the swap that follows it, the two disagree, and that
      // disagreement is precisely "the page has been asked to move". `null` for a URL
      // that names no artboard — `/files/{id}` on a single-artboard file resolves to one
      // server-side, and the page it answers with is the authority on which.
      function artboardFromLocation() {
        const parts = location.pathname.split("/artboards/");
        if (parts.length < 2) return null;
        const segment = parts[1].split("/")[0];
        if (!segment) return null;
        try {
          return decodeURIComponent(segment);
        } catch (error) {
          return segment;
        }
      }

      // A change to the file can be a change to the *list* of artboards, so whichever of
      // the two canvases is on screen is refreshed with everything else: an artboard
      // added while this page is open must not need a reload to be reachable.
      async function refreshArtboard() {
        const canvas = isMapMode()
          ? swap(fragmentURL("map"), "v-map")
          : swap(renderURL(), "v-render-region");
        await Promise.all([
          canvas,
          swap(outlineURL(), "v-outline"),
          ...FRAGMENTS.map((name) => swap(fragmentURL(name), `v-${name}`)),
        ]);
      }

      // The outline is re-rendered whole, so the selected row arrives wherever the
      // server put it — which, on a long tree, is out of sight. `nearest` scrolls the
      // least that makes it visible and does nothing when it already is.
      function revealSelection() {
        const row = document.querySelector("#v-outline .v-outline-row.is-selected");
        if (row) row.scrollIntoView({ block: "nearest" });
      }

      // ---- the overlay ----------------------------------------------------

      // The artboard ships at full size — `--v-scale: 1`, one CSS pixel per layout
      // point — because that is the only size the server can know is right. Fitting it
      // to the pane needs the pane's width, so it happens here, and it happens by
      // writing one custom property: every box is placed in points and multiplied by
      // that property, so they all follow without being touched.
      function fitStage() {
        const element = stage();
        if (!element) return;
        const pane = element.parentElement;
        if (!pane) return;
        const width = parseFloat(element.style.getPropertyValue("--v-art-w"));
        const height = parseFloat(element.style.getPropertyValue("--v-art-h"));
        if (!(width > 0) || !(height > 0)) return;
        const margin = 24;
        // How far the artboard may be enlarged. Beside the panels, not at all: a design
        // is read at the size it was drawn. Presenting, the screen *is* the point, so it
        // may grow as far as the density its PNG was rendered at — one image pixel per
        // point of enlargement, past which it would be blur rather than size.
        const ceiling = document.body.classList.contains("is-presenting")
          ? Math.max(1, parseFloat(element.dataset.density) || 1)
          : 1;
        const fit = Math.min(
          ceiling,
          (pane.clientWidth - margin) / width,
          (pane.clientHeight - margin) / height
        );
        element.style.setProperty("--v-scale", String(Math.max(0.05, fit)));
      }

      window.addEventListener("resize", fitStage);

      // The boxes arrive server-rendered, with the right colors and the right rects.
      // All the client owns is when they go: fade after MARKER_LIFETIME, unless pinned.
      function armMarkers(scope) {
        for (const box of scope.querySelectorAll(".v-box.is-edit")) {
          const timer = setTimeout(() => {
            if (box.classList.contains("is-pinned")) return;
            box.classList.add("is-fading");
            box.addEventListener("transitionend", () => box.remove(), { once: true });
          }, MARKER_LIFETIME);
          box.dataset.timer = String(timer);
        }
      }

      function layout() {
        const element = document.getElementById("v-layout");
        if (!element) return null;
        try {
          return JSON.parse(element.textContent);
        } catch (error) {
          return null;
        }
      }

      // The smallest node whose box contains the point — the one a person means when
      // they click inside three nested frames.
      function nodeAt(pointX, pointY) {
        const map = layout();
        if (!map) return null;
        let best = null;
        for (const node of map.nodes) {
          if (pointX < node.x || pointY < node.y) continue;
          if (pointX > node.x + node.width || pointY > node.y + node.height) continue;
          const area = node.width * node.height;
          if (!best || area < best.width * best.height) best = node;
        }
        return best;
      }

      // ---- navigation -----------------------------------------------------

      async function go(href) {
        history.pushState({}, "", href);
        await Promise.all([
          swap(renderURL(), "v-render-region"),
          swap(outlineURL(), "v-outline"),
        ]);
      }

      function select(nodeID) {
        const url = new URL(location.href);
        if (nodeID && url.searchParams.get("node") !== nodeID) {
          url.searchParams.set("node", nodeID);
        } else {
          url.searchParams.delete("node");
        }
        const navigated = go(url.pathname + url.search);
        // Here rather than on the click, so the keyboard's own selections —
        // the arrows, and Escape climbing to the parent — move the tab too.
        // `go` has already pushed the URL this reads.
        syncSelectionTab();
        return navigated;
      }

      document.addEventListener("click", (event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;

        const copy = event.target.closest(".v-copy");
        if (copy) {
          event.preventDefault();
          copyText(copy.dataset.copy ?? "").then((ok) => {
            if (ok) flashCopied(copy);
          });
          return;
        }

        const tag = event.target.closest(".v-box-tag");
        if (tag) {
          event.preventDefault();
          const box = tag.closest(".v-box");
          box.classList.toggle("is-pinned");
          clearTimeout(Number(box.dataset.timer));
          box.classList.remove("is-fading");
          return;
        }

        const row = event.target.closest(".v-outline-row");
        if (row && stage()) {
          event.preventDefault();
          select(row.dataset.node);
          return;
        }

        const image = event.target.closest(".v-render");
        if (image) {
          const map = layout();
          if (!map) return;
          const box = image.getBoundingClientRect();
          const scale = box.width / map.width;
          const hit = nodeAt(
            (event.clientX - box.left) / scale,
            (event.clientY - box.top) / scale
          );
          if (hit) select(hit.id);
        }
      });

      // A dropdown that applies on change; the submit button behind it is what works
      // when this listener never runs.
      document.addEventListener("change", (event) => {
        const select = event.target.closest(".v-theme-select");
        if (select) select.form.requestSubmit();
      });

      window.addEventListener("popstate", () => {
        if (!stage()) return;
        // A history entry for a *different* artboard is a whole-page move, and the
        // block below owns it. Re-requesting this artboard's fragments here would race
        // it, for markup that is about to be replaced anyway.
        const wanted = artboardFromLocation();
        if (wanted && wanted !== artboardID()) return;
        swap(renderURL(), "v-render-region");
        swap(outlineURL(), "v-outline");
      });

      // ---- the stream -----------------------------------------------------

      // A page under the preview catalog is a picture of a declared state, not a window
      // onto a document: its presence, its badge and its dots are fixtures the state set,
      // and the stream would repaint them from whatever the server is really watching —
      // nothing, under `woodcase preview` — so two shots of one state disagreed by which
      // won the race (`GqUQys`). So it does not listen. Everything else below still runs:
      // a copy chip still copies and a popover still opens. The fact is written on the
      // document so a test can read it rather than wait for a stream that never comes.
      const PREVIEWS = "\#(ViewerLink.previews)";
      const isPicture = location.pathname === PREVIEWS || location.pathname.startsWith(PREVIEWS + "/");
      root.dataset.stream = isPicture ? "off" : "on";
      const source = isPicture ? new EventTarget() : new EventSource("/events");
      // The two state names are `ConnectionState`'s own raw values, interpolated rather
      // than typed here: the badge's three labels and the stylesheet's three rules are
      // written from the same enum, so a state can never exist that the badge cannot say.
      source.addEventListener("open", () => live("\#(ConnectionState.live.rawValue)"));
      source.addEventListener("error", () => live("\#(ConnectionState.lost.rawValue)"));

      source.addEventListener("presence", () => {
        if (fileID()) {
          swap(fragmentURL("presence"), "v-presence");
        } else {
          swapFromPage(["v-presence"]);
        }
      });

      source.addEventListener("change", (event) => {
        let payload;
        try {
          payload = JSON.parse(event.data);
        } catch (error) {
          return;
        }
        // The two empty states — no files at all, and a file with no artboards yet —
        // have no fragment to swap: the page that answers next is a *different* page,
        // with a different body layout and a different trail. So they reload, which is
        // what turns `woodcase new` into a dashboard, and the first frame into a map,
        // with nobody pressing anything. The dashboard's marker names no file, because
        // any file at all replaces it; a file's names its own and waits for a frame,
        // which is also what keeps a run of edits from reloading it over and over.
        const empty = document.querySelector("[data-empty-file]");
        if (empty) {
          const waiting = empty.dataset.emptyFile;
          const arrived = waiting
            ? payload.file === waiting && (payload.artboards || []).length > 0
            : true;
          if (arrived) location.reload();
          return;
        }
        if (!fileID()) {
          swapFromPage(["v-files", "v-activity", "v-presence"]);
          return;
        }
        if (payload.file !== fileID()) return;
        refreshArtboard();
      });

      armMarkers(document);
      fitStage();
      revealSelection();

      // ==== BEGIN copy-chip + collapsible variables (z54mg) ================
      //
      // Self-contained on purpose: an id chip's click has to run *before* the
      // outline-row click handler above ever sees it (a chip usually sits inside a
      // row that is itself a link), and a capture-phase listener guarantees that
      // regardless of registration order, rather than relying on this block being
      // read before the one above it.

      // Copies text to the clipboard, falling back to a hidden textarea and
      // execCommand when the async Clipboard API is unavailable — a plain HTTP
      // origin, an older WebKit, or a page loaded without focus all lack it.
      //
      // The focus test and the deadline are both load-bearing. WebKit does not
      // reject `writeText` on an unfocused document: it returns a promise that
      // never settles, so an unguarded `await` here swallows the copy and the chip
      // never flashes. The fallback below works whether the page has focus or not.
      async function copyText(text) {
        try {
          if (navigator.clipboard && window.isSecureContext && document.hasFocus()) {
            const wrote = await Promise.race([
              navigator.clipboard.writeText(text).then(() => true, () => false),
              new Promise((resolve) => setTimeout(() => resolve(false), 500)),
            ]);
            if (wrote) return true;
          }
        } catch (error) {
          // fall through to the execCommand fallback
        }
        try {
          const area = document.createElement("textarea");
          area.value = text;
          area.style.position = "fixed";
          area.style.opacity = "0";
          document.body.appendChild(area);
          area.focus();
          area.select();
          const ok = document.execCommand("copy");
          area.remove();
          return ok;
        } catch (error) {
          return false;
        }
      }

      // Capture phase, so this runs and calls stopPropagation before the bubble-
      // phase listener above ever sees the click — an id chip copies and nothing
      // else happens, whatever element it sits inside.
      document.addEventListener(
        "click",
        (event) => {
          const chip = event.target.closest(".v-id-chip");
          if (!chip) return;
          event.preventDefault();
          event.stopPropagation();
          copyText(chip.dataset.copyId ?? "").then((ok) => {
            if (ok) flashCopied(chip);
          });
        },
        true
      );

      // The copied flash, for a chip and for the footer's button alike. Both carry their
      // resting word and the word `copied`, server-rendered; this owns the class that
      // says which one shows, and never a word of text (`ymsE0s`). The resting word keeps
      // the box's width, so a flash moves nothing beside it.
      function flashCopied(element) {
        element.classList.add("is-copied");
        clearTimeout(Number(element.dataset.copyTimer));
        element.dataset.copyTimer = String(
          setTimeout(() => element.classList.remove("is-copied"), 1200)
        );
      }

      // The variables panel's collapse, remembered per file so it survives a
      // reload. Best-effort: a private window or blocked site data leaves the
      // panel expanded rather than throwing.
      function variablesStorageKey() {
        return `woodcase.variables.collapsed:${fileID() ?? "dashboard"}`;
      }

      function restoreVariablesCollapse() {
        const panel = document.querySelector(".v-variables");
        if (!panel) return;
        try {
          if (localStorage.getItem(variablesStorageKey()) === "1") {
            panel.classList.add("is-collapsed");
          }
        } catch (error) {
          // localStorage unavailable — leave it expanded.
        }
      }

      document.addEventListener("click", (event) => {
        const toggle = event.target.closest(".v-variables-toggle");
        if (!toggle) return;
        event.preventDefault();
        const panel = toggle.closest(".v-variables");
        if (!panel) return;
        const collapsed = panel.classList.toggle("is-collapsed");
        try {
          localStorage.setItem(variablesStorageKey(), collapsed ? "1" : "0");
        } catch (error) {
          // best effort only
        }
      });

      // A fragment swap replaces the whole `.v-variables` element with a freshly
      // server-rendered (and therefore always-expanded) one, so the collapse is
      // re-applied whenever one lands, rather than by editing the swap function
      // above.
      new MutationObserver(() => restoreVariablesCollapse()).observe(document.body, {
        childList: true,
        subtree: true,
      });

      restoreVariablesCollapse();
      // ==== END copy-chip + collapsible variables (z54mg) ==================

      // ==== BEGIN artboard map (B1sAM) ==============================      //
      // The bird's-eye map ships server-rendered and already zoomed for an assumed
      // pane, so it is correct before this runs and correct with the script off. All
      // this block owns is the one number the server cannot know: how wide the pane
      // actually is. It writes `--v-map-scale`, and every box follows — each is placed
      // in layout points and multiplied by it, the same contract `fitStage` has with
      // `--v-scale` over the render.
      //
      // The bounds are `ArtboardMap`'s, interpolated rather than retyped: below the
      // minimum the map scrolls instead of shrinking, which is what keeps a 40 000-point
      // canvas legible rather than a row of hairlines.
      //
      // It also owns the focus ring, because a ring is a fact about this screen: which
      // box the keyboard is on, mirrored onto the artboard listing beside it so the two
      // views of the same list never disagree about where you are.

      const MAP_MIN_SCALE = \#(ArtboardMap.minimumScale);
      const MAP_MAX_SCALE = \#(ArtboardMap.maximumScale);

      function fitMap() {
        const map = mapCanvas();
        if (!map) return;
        const width = parseFloat(map.style.getPropertyValue("--v-map-w"));
        const height = parseFloat(map.style.getPropertyValue("--v-map-h"));
        if (!(width > 0) || !(height > 0)) return;
        const styles = getComputedStyle(map);
        const insetX = parseFloat(styles.paddingLeft) + parseFloat(styles.paddingRight);
        const insetY = parseFloat(styles.paddingTop) + parseFloat(styles.paddingBottom);
        const available = map.clientWidth - insetX;
        const pane = map.clientHeight - insetY;
        if (!(available > 0) || !(pane > 0)) return;
        const fit = Math.min(available / width, pane / height);
        map.style.setProperty(
          "--v-map-scale",
          String(Math.min(MAP_MAX_SCALE, Math.max(MAP_MIN_SCALE, fit)))
        );
      }

      // ---- the focus ring --------------------------------------------------

      // Every box, in document order — read off the DOM rather than kept in a variable,
      // because a `change` replaces the whole map and any index this block was holding
      // would be an index into a list that no longer exists.
      const mapBoxes = () =>
        Array.from(document.querySelectorAll("#v-map .v-map-board"));

      // The artboard listing beside the map, which mirrors the ring.
      const artboardRows = () =>
        Array.from(document.querySelectorAll("#v-outline .v-artboard-row"));

      function focusedArtboard() {
        return document.querySelector("#v-map .v-map-board.is-focused")?.dataset.artboard ?? null;
      }

      // At the minimum zoom the plane is wider than the pane, so the focused box can be
      // off screen — scrolled to the least amount that shows it.
      //
      // The map's own `scrollLeft`/`scrollTop`, never `scrollIntoView`: that walks every
      // scroll container up to the viewport, and doing so here raced with
      // `revealSelection`'s scroll of the outline in the same task and left the selected
      // row out of sight. This block owns the map's scroll and nothing else's.
      function revealBox(box) {
        const map = mapCanvas();
        if (!map || !box) return;
        const rect = box.getBoundingClientRect();
        const frame = map.getBoundingClientRect();
        if (rect.left < frame.left) map.scrollLeft += rect.left - frame.left;
        else if (rect.right > frame.right) map.scrollLeft += rect.right - frame.right;
        if (rect.top < frame.top) map.scrollTop += rect.top - frame.top;
        else if (rect.bottom > frame.bottom) map.scrollTop += rect.bottom - frame.bottom;
      }

      // One ring, drawn twice: on the box and on its row. `focus` moves with it so
      // Tab and a screen reader agree with what is highlighted, with `preventScroll`
      // because the scrolling is done above, on the one container this block owns.
      function setMapFocus(artboard) {
        for (const box of mapBoxes()) {
          box.classList.toggle("is-focused", box.dataset.artboard === artboard);
        }
        for (const row of artboardRows()) {
          row.classList.toggle("is-focused", row.dataset.artboard === artboard);
        }
        const box = mapBoxes().find((item) => item.dataset.artboard === artboard);
        if (!box) return;
        try {
          box.focus({ preventScroll: true });
        } catch (error) {
          // An older engine without the option: the ring is still drawn.
        }
        revealBox(box);
      }

      // Moves the ring one step in document order. From nowhere, forwards starts at the
      // first box and backwards at the last, which is the same rule the outline's own
      // arrow stepping uses. The ends clamp rather than wrapping.
      function stepMapFocus(direction) {
        const boxes = mapBoxes();
        if (boxes.length === 0) return;
        const current = focusedArtboard();
        const index = boxes.findIndex((box) => box.dataset.artboard === current);
        const next = index === -1
          ? (direction > 0 ? 0 : boxes.length - 1)
          : index + direction;
        if (next < 0 || next >= boxes.length) return;
        setMapFocus(boxes[next].dataset.artboard);
      }

      // Enter drills in — a real click on the box's own link, so it takes exactly the
      // path a pointer takes, follow-drop and all.
      function openFocusedArtboard() {
        const box = document.querySelector("#v-map .v-map-board.is-focused");
        if (box) box.click();
      }

      // Clicking a box moves the ring to it, so a keyboard picked up after a click
      // carries on from where the pointer left off rather than from the start.
      document.addEventListener("click", (event) => {
        const box = event.target.closest(".v-map-board, .v-artboard-row");
        if (box && box.dataset.artboard) setMapFocus(box.dataset.artboard);
      });

      window.addEventListener("resize", fitMap);

      // ---- the loading shimmer ----------------------------------------------
      //
      // A box ships shimmering, because the render behind it may still be being drawn.
      // Whether it has painted *on this screen* is a fact only this screen has, which is
      // the class of fact this file owns — so the server always says "loading" and here
      // is where it stops being true. An image that failed is settled too: a box
      // shimmering forever is a worse lie than an empty one.
      function settleThumb(image) {
        image.closest(".v-map-frame")?.classList.remove("is-loading");
      }

      function settleLoadedThumbs() {
        for (const image of document.querySelectorAll("#v-map .v-map-thumb")) {
          if (image.complete) settleThumb(image);
        }
      }

      // `load` and `error` do not bubble, so both are captured rather than delegated.
      for (const name of ["load", "error"]) {
        document.addEventListener(
          name,
          (event) => {
            const image = event.target;
            if (image instanceof Element && image.classList.contains("v-map-thumb")) {
              settleThumb(image);
            }
          },
          true
        );
      }

      // A `change` replaces the whole map with a freshly rendered one, carrying the
      // server's assumed zoom again and no ring. Re-fitting on any body mutation catches
      // that without reaching into `swap`, which is shared with three other panels; the
      // ring is put back on the same artboard, which survives because it is read from
      // the DOM before the swap and written to it after.
      let ring = null;
      new MutationObserver(() => {
        fitMap();
        // A swapped-in `<img>` whose bytes are already cached may never fire `load`, so
        // the sweep is what settles it. `--wait-for js:images-complete` sees the same
        // `complete` flag, so a screenshot never catches a settled box still shimmering.
        settleLoadedThumbs();
        const showing = focusedArtboard();
        if (showing) {
          ring = showing;
        } else if (ring && mapBoxes().some((box) => box.dataset.artboard === ring)) {
          setMapFocus(ring);
        }
      }).observe(document.body, { childList: true, subtree: true });

      fitMap();
      settleLoadedThumbs();
      // ==== END artboard map (B1sAM) =======================================
      // ==== BEGIN keyboard (xmGCG) ==========================================
      //
      // One table, one dispatcher: KEY_TABLE is the entire key model, exposed as
      // `window.__woodcaseKeys` so a browser test reads the same rows this code
      // reacts to. Each row is a JS object — `JSON.stringify` drops its `run` function
      // silently, so a test that fetches the table over `evaluate` sees only
      // `{ key, context, label }`, never the closure.
      //
      // Self-contained, like the block above it: its own click and keydown listeners,
      // its own MutationObserver, nothing shared with the code above except the
      // `stage`/`artboardID`/`select`/`go`/`fitStage` helpers the main script already
      // defines.

      // Whether a node is selected — the same fact `select()` reads and writes, kept
      // in the query rather than a class, so a reload or a pasted link sees it too.
      function hasSelection() {
        return new URL(location.href).searchParams.has("node");
      }

      // A field that keeps its own key: an input mid-edit, a select being driven from
      // the keyboard, a button about to be pressed by Space. `isContentEditable`
      // covers a rich-text region even though it carries no matching tag name.
      function isFormControlTarget(target) {
        if (!target) return false;
        if (target.isContentEditable) return true;
        const tag = target.tagName ? target.tagName.toLowerCase() : "";
        return tag === "input" || tag === "select" || tag === "textarea" || tag === "button";
      }

      // ---- artboard stepping ------------------------------------------------

      // Moves to the previous or next artboard by clicking the footer's own step link —
      // the same element a pointer clicks, so the key and the click cannot take
      // different paths. A file with one artboard renders no steps, and either end
      // renders a dimmed `<span>` rather than a link, so both cases do nothing without
      // this having to know why.
      function stepArtboard(direction) {
        const step = document.querySelector(
          direction < 0 ? "a.v-step-previous" : "a.v-step-next"
        );
        if (step) step.click();
      }

      // ---- up to the map ----------------------------------------------------

      // The breadcrumb's own way back. It exists only when the file has a map to go up
      // to, which is what makes "Escape goes up" a no-op on a single-artboard file
      // rather than a navigation to a page that would redirect straight back.
      function upToMap() {
        return document.querySelector(".v-crumb-map");
      }

      // ---- outline stepping --------------------------------------------------

      function visibleOutlineRows() {
        const panel = document.getElementById("v-outline");
        if (!panel) return [];
        return Array.from(panel.querySelectorAll(".v-outline-row")).filter((row) => !row.hidden);
      }

      // Selects the previous or next row a person could currently see — a row hidden
      // by a collapsed ancestor is skipped, the same as it is invisible to a click.
      function stepOutlineRow(direction) {
        const rows = visibleOutlineRows();
        if (rows.length === 0) return;
        const index = rows.findIndex((row) => row.classList.contains("is-selected"));
        const nextIndex = index === -1 ? (direction > 0 ? 0 : rows.length - 1) : index + direction;
        if (nextIndex < 0 || nextIndex >= rows.length) return;
        select(rows[nextIndex].dataset.node);
      }

      // ---- outline collapse ---------------------------------------------------
      //
      // The outline ships flat, one `<a>` per row with its depth on `--v-depth`; there
      // is no parent/child structure in the DOM beyond that number. Collapsing a row
      // hides every following row whose depth is greater, until one at or above its
      // own depth ends the run — which is also what makes a leaf (no such row follows)
      // a no-op. State lives only as an `is-row-collapsed` class and the `hidden`
      // attribute this recomputes from it; a fragment swap replaces the rows outright,
      // so a freshly rendered outline is always fully expanded.

      function rowDepth(row) {
        const depth = parseInt(row.style.getPropertyValue("--v-depth"), 10);
        return Number.isNaN(depth) ? 0 : depth;
      }

      function rowHasChildren(row) {
        const next = row.nextElementSibling;
        return !!next && next.classList.contains("v-outline-row") && rowDepth(next) > rowDepth(row);
      }

      // One forward pass derives every row's visibility from the collapsed rows above
      // it, so a collapsed row's own state survives an ancestor collapsing and
      // uncollapsing around it, rather than being overwritten by that ancestor's toggle.
      function applyOutlineCollapse() {
        const rows = Array.from(document.querySelectorAll("#v-outline .v-outline-row"));
        let hideBelowDepth = null;
        for (const row of rows) {
          const depth = rowDepth(row);
          if (hideBelowDepth !== null && depth > hideBelowDepth) {
            row.hidden = true;
            continue;
          }
          row.hidden = false;
          hideBelowDepth = row.classList.contains("is-row-collapsed") ? depth : null;
        }
      }

      function toggleRowCollapsed(row) {
        if (!row || !rowHasChildren(row)) return;
        row.classList.toggle("is-row-collapsed");
        applyOutlineCollapse();
      }

      // Sets (rather than toggles) collapsed state, so the keyboard's ← always
      // collapses and → always expands, whatever the row's current state was.
      function setSelectedRowCollapsed(collapsed) {
        const row = document.querySelector("#v-outline .v-outline-row.is-selected");
        if (!row || !rowHasChildren(row)) return;
        row.classList.toggle("is-row-collapsed", collapsed);
        applyOutlineCollapse();
      }

      // The disclosure triangle every row with children gets, inserted client-side —
      // the server always renders a flat, fully expanded outline, so this is the only
      // place a row's "does it have children" fact is drawn at all. A row with none
      // gets a blank spacer instead, so every row's name still lines up in one column.
      function markOutlineDisclosure() {
        for (const row of document.querySelectorAll("#v-outline .v-outline-row")) {
          if (row.firstElementChild && row.firstElementChild.classList.contains("v-disclose")) continue;
          const marker = document.createElement("span");
          marker.className = "v-disclose";
          if (rowHasChildren(row)) {
            marker.classList.add("has-children");
            marker.textContent = "▾";
          }
          row.insertBefore(marker, row.firstChild);
        }
      }

      function refreshOutlineDisclosure() {
        markOutlineDisclosure();
        applyOutlineCollapse();
      }

      // Every fragment swap and every marker timing out replaces or removes DOM nodes
      // under `<body>`, so re-deriving on any mutation — rather than hooking `swap()`
      // itself — is what keeps this in step without touching shared code.
      new MutationObserver(() => refreshOutlineDisclosure()).observe(document.body, {
        childList: true,
        subtree: true,
      });

      // A disclosure triangle toggles on its own click, ahead of the outline row's own
      // click handler — the same capture-phase pattern the id chip above uses, and for
      // the same reason: the triangle sits inside a row that is itself a link.
      document.addEventListener(
        "click",
        (event) => {
          const disclosure = event.target.closest(".v-disclose");
          if (!disclosure || !disclosure.classList.contains("has-children")) return;
          event.preventDefault();
          event.stopPropagation();
          toggleRowCollapsed(disclosure.closest(".v-outline-row"));
        },
        true
      );

      // ---- presentation mode ---------------------------------------------------

      // Presentation hides every control there is, including the ones that would say how
      // to leave, so the way out is flashed once on the way in. The text is the server's
      // (`PresentationHint`); all the client owns is the *timing*, which is the same
      // division the edit markers are under.
      let presentationHintTimer = 0;

      function flashPresentationHint() {
        const hint = document.getElementById("v-present-hint");
        if (!hint) return;
        clearTimeout(presentationHintTimer);
        hint.classList.add("is-flashing");
        presentationHintTimer = setTimeout(
          () => hint.classList.remove("is-flashing"),
          PRESENTATION_HINT_LIFETIME
        );
      }

      function togglePresentation() {
        if (document.body.classList.toggle("is-presenting")) flashPresentationHint();
        fitStage();
      }

      function exitPresentation() {
        document.body.classList.remove("is-presenting");
        fitStage();
      }

      // The way in without the keyboard. A person who has never pressed `f` has no
      // reason to know the mode exists, which is the whole argument for the button.
      document.addEventListener("click", (event) => {
        if (event.target.closest("#v-present")) togglePresentation();
      });

      // Escape backs out one level, and the levels are presentation, then the map, then
      // the selection — in that order, as the design words it: "Esc goes up to the map
      // before it clears a selection". On the map itself, and on a single-artboard file,
      // there is no map to go up to and it clears the selection instead.
      function handleEscape() {
        if (document.body.classList.contains("is-presenting")) {
          exitPresentation();
          return;
        }
        // Esc climbs the hierarchy one node at a time: the selection's parent, then
        // that node's parent, up to the artboard's root; the level above the root is the
        // map. Nothing is ever skipped, and nothing selected is ever merely dropped.
        if (hasSelection()) {
          const parent = selectedRowParent();
          if (parent) {
            select(parent.dataset.node);
            return;
          }
        }
        const up = upToMap();
        if (up) {
          up.click();
          return;
        }
        if (hasSelection()) select();
      }

      // The selected outline row's parent row: the nearest row above it one level
      // shallower, read from the `--v-depth` the server writes on every row. `null` at
      // a root, or when nothing is selected.
      function selectedRowParent() {
        const row = document.querySelector("#v-outline .v-outline-row.is-selected");
        if (!row) return null;
        const depth = parseInt(row.style.getPropertyValue("--v-depth"), 10);
        if (!(depth > 0)) return null;
        let previous = row.previousElementSibling;
        while (previous) {
          if (previous.classList.contains("v-outline-row")
              && parseInt(previous.style.getPropertyValue("--v-depth"), 10) === depth - 1) {
            return previous;
          }
          previous = previous.previousElementSibling;
        }
        return null;
      }

      // ---- the table itself ---------------------------------------------------
      //
      // `context` is which of three mutually exclusive states a keypress landed in.
      // "map" is the whole map page; on the artboard page "none-selected" and "selected"
      // split it in two, so ArrowLeft/ArrowRight mean one thing with nothing selected and
      // a different thing with something selected, never a fallback from one to the
      // other. "any" matches regardless.
      const KEY_TABLE = [
        { key: "ArrowLeft", context: "map", label: "previous artboard box", run: () => stepMapFocus(-1) },
        { key: "ArrowRight", context: "map", label: "next artboard box", run: () => stepMapFocus(1) },
        { key: "ArrowUp", context: "map", label: "previous artboard box", run: () => stepMapFocus(-1) },
        { key: "ArrowDown", context: "map", label: "next artboard box", run: () => stepMapFocus(1) },
        { key: "Enter", context: "map", label: "open the artboard on the ring", run: () => openFocusedArtboard() },
        { key: "ArrowLeft", context: "none-selected", label: "previous artboard", run: () => stepArtboard(-1) },
        { key: "ArrowRight", context: "none-selected", label: "next artboard", run: () => stepArtboard(1) },
        { key: "ArrowUp", context: "selected", label: "previous outline row", run: () => stepOutlineRow(-1) },
        { key: "ArrowDown", context: "selected", label: "next outline row", run: () => stepOutlineRow(1) },
        {
          key: "ArrowLeft",
          context: "selected",
          label: "collapse the selected row's children",
          run: () => setSelectedRowCollapsed(true),
        },
        {
          key: "ArrowRight",
          context: "selected",
          label: "expand the selected row's children",
          run: () => setSelectedRowCollapsed(false),
        },
        { key: "f", context: "any", label: "toggle presentation mode", run: () => togglePresentation() },
        {
          key: "Escape",
          context: "any",
          label: "leave presentation, else select the parent, else go up to the map",
          run: () => handleEscape(),
        },
      ];
      window.__woodcaseKeys = KEY_TABLE;

      document.addEventListener("keydown", (event) => {
        if (isFormControlTarget(event.target)) return;
        const context = isMapMode()
          ? "map"
          : hasSelection() ? "selected" : "none-selected";
        const row = KEY_TABLE.find(
          (entry) => entry.key === event.key && (entry.context === "any" || entry.context === context)
        );
        if (!row) return;
        event.preventDefault();
        row.run();
      });

      refreshOutlineDisclosure();
      // ==== END keyboard (xmGCG) ============================================

      // ==== BEGIN follow + unread (MehU9) ==================================
      //
      // Two pieces of behavior the server cannot hold. *Follow* is view state and
      // lives in the query, but acting on it needs an event the server has already
      // sent and a history entry only the browser can push. *Unread* is per viewer
      // and per browser by definition — it starts at this page load, not at the
      // file's history — so it lives in localStorage and nowhere else.

      const FOLLOW_PAUSED = "paused:";

      // ---- follow, as it is spelled in the query --------------------------

      function readFollow(search) {
        const value = new URLSearchParams(search ?? location.search).get("follow");
        if (!value || value === "nobody") return { target: null, active: false };
        if (value.startsWith(FOLLOW_PAUSED)) {
          const target = value.slice(FOLLOW_PAUSED.length);
          return { target: target && target !== "nobody" ? target : null, active: false };
        }
        return { target: value, active: true };
      }

      function followMatches(follow, identity) {
        if (!follow.active || !follow.target) return false;
        // An unattributed write matches nothing, "anyone" included: the page moves
        // because somebody wrote, and nobody claimed that one.
        if (!identity) return false;
        return follow.target === "anyone" || follow.target === identity;
      }

      // ---- unread, per viewer and per artboard ----------------------------

      const unreadKey = (artboard) => `woodcase.unread:${fileID() ?? ""}:${artboard}`;

      function markUnread(artboard) {
        try {
          localStorage.setItem(unreadKey(artboard), "1");
        } catch (error) {
          // No site data: this browser simply shows no dots.
        }
      }

      function markViewed(artboard) {
        try {
          localStorage.removeItem(unreadKey(artboard));
        } catch (error) {
          // best effort only
        }
      }

      function isUnread(artboard) {
        try {
          return localStorage.getItem(unreadKey(artboard)) === "1";
        } catch (error) {
          return false;
        }
      }

      // The map and the artboard listing are re-rendered on every change, so the marks
      // cannot be in the markup the server sends: they are re-applied here after each
      // swap, and they hang on `data-artboard` rather than on a class so that any other
      // view of the artboards inherits them by carrying the same attribute.
      //
      // The breadcrumb's map crumb gets one too, for a different question: the artboard
      // page has no boxes to mark, and what you want to know there is whether the news
      // is somewhere else in the file. It is the way up, so it is where that goes.
      // The elements this script put a dot on. A dot is taken off only where the script
      // put it: one the *server* wrote is a declared state — a preview declares exactly
      // the attribute this block would set — and this browser's storage knowing nothing
      // about the file is not knowing better (`wNhNQp`). In production the server never
      // writes one, so every dot on the page is in here and nothing changes.
      const markedUnread = new WeakSet();

      function showUnread(element, unread) {
        if (unread) {
          element.dataset.unread = "1";
          markedUnread.add(element);
        } else if (markedUnread.has(element)) {
          delete element.dataset.unread;
          markedUnread.delete(element);
        }
      }

      function applyUnread() {
        const current = artboardID();
        if (current) markViewed(current);
        let elsewhere = false;
        for (const box of document.querySelectorAll("[data-artboard]")) {
          const id = box.dataset.artboard;
          const unread = !!id && id !== current && isUnread(id);
          showUnread(box, unread);
          if (unread) elsewhere = true;
        }
        const up = document.querySelector(".v-crumb-map");
        if (!up) return;
        // A dot on the way up means "somewhere in this file", not "on one of the two
        // artboards the footer happens to link to", so every artboard this browser has
        // ever marked for this file counts — the page need not be showing it.
        for (const id of unreadArtboards()) {
          if (id !== current) elsewhere = true;
        }
        showUnread(up, elsewhere);
      }

      // Every artboard of this file this browser has marked unread. Read back out of
      // storage rather than kept in a variable, so a second tab's marks are seen too.
      function unreadArtboards() {
        const prefix = `woodcase.unread:${fileID() ?? ""}:`;
        const found = [];
        try {
          for (let index = 0; index < localStorage.length; index += 1) {
            const key = localStorage.key(index);
            if (key && key.startsWith(prefix) && localStorage.getItem(key) === "1") {
              found.push(key.slice(prefix.length));
            }
          }
        } catch (error) {
          // No site data: this browser simply shows no dots.
        }
        return found;
      }

      // ---- moving the page --------------------------------------------------

      // The control's form submits back to the page you are on, so the fragment names
      // the artboard when there is one and the file alone on the map.
      const followURL = () => {
        const artboard = artboardID();
        const scope = artboard
          ? `/artboards/${encodeURIComponent(artboard)}/follow`
          : "/follow";
        return `/files/${fileID()}${scope}${location.search}`;
      };

      function refreshFollow() {
        if (fileID()) swap(followURL(), "v-follow");
      }

      // The same path an artboard click takes — which, for an artboard, is a plain
      // navigation: the strip's tabs are ordinary links that nothing above intercepts.
      //
      // It is *not* a pushState with fragment swaps, and that is deliberate. The
      // `change` listener above captured the fragment URLs for the artboard that was on
      // screen the moment the event arrived — synchronously, before this block's
      // listener ever ran — so its render and its strip are already in flight for the
      // old artboard. Swapping in the new one beside them is a race whose loser
      // silently wins about half the time. A navigation cannot lose it: the document
      // being replaced is the one holding the stale requests.
      //
      // Nothing is lost by going the long way round. Every piece of view state is in
      // the URL — the theme pins above all, which is why they are carried across
      // untouched — and the unread marks are in storage, so the page that arrives is
      // the page a swap would have assembled.
      function goToArtboard(artboard) {
        const file = fileID();
        if (!file) return;
        const url = new URL(location.href);
        url.pathname = `/files/${encodeURIComponent(file)}/artboards/${encodeURIComponent(artboard)}`;
        // The selection belonged to the artboard being left.
        url.searchParams.delete("node");
        markViewed(artboard);
        location.assign(url.pathname + url.search);
      }

      // ---- manual navigation drops follow -----------------------------------

      // Capture phase, so the query is rewritten before the bubble-phase handlers
      // above read `location.href` and before the browser reads an anchor's `href` —
      // which the server rendered while follow was still on.
      document.addEventListener(
        "click",
        (event) => {
          if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
          // Copying an id is not navigating anywhere.
          if (event.target.closest(".v-id-chip")) return;
          if (!event.target.closest(".v-outline-row, .v-render, [data-artboard], .v-crumb-map")) return;

          const follow = readFollow();
          if (!follow.active) return;
          const paused = FOLLOW_PAUSED + follow.target;

          const here = new URLSearchParams(location.search);
          here.set("follow", paused);
          history.replaceState({}, "", location.pathname + "?" + here.toString());

          const link = event.target.closest("a[href]");
          if (link) {
            const url = new URL(link.href, location.href);
            url.searchParams.set("follow", paused);
            link.href = url.pathname + url.search;
          }
          // The control has to stop claiming it is following, and it is server-
          // rendered like everything else — so it is re-fetched once the handlers
          // that follow this one have settled the URL.
          setTimeout(refreshFollow, 0);
        },
        true
      );

      // The dropdown applies on change; the submit button behind it is what works
      // when this listener never runs.
      document.addEventListener("change", (event) => {
        const control = event.target.closest(".v-follow-select");
        if (control) control.form.requestSubmit();
      });

      // ---- the stream, again ------------------------------------------------

      // A second listener rather than an edit to the one above: this block owns
      // following and unread, and the refresh that block does is correct whether or
      // not this one moves the page.
      source.addEventListener("change", (event) => {
        let payload;
        try {
          payload = JSON.parse(event.data);
        } catch (error) {
          return;
        }
        if (!fileID() || payload.file !== fileID()) return;

        const current = artboardID();
        const touched = payload.changedArtboards ?? [];
        for (const id of touched) {
          if (id !== current) markUnread(id);
        }

        if (followMatches(readFollow(), payload.identity)) {
          const target = touched.find((id) => id !== current);
          if (target) {
            goToArtboard(target);
            return;
          }
        }
        applyUnread();
      });

      window.addEventListener("popstate", () => {
        applyUnread();
        refreshFollow();
      });

      // A swap replaces the strip with freshly server-rendered markup that carries no
      // marks, so they are re-applied whenever one lands. Only `childList` is
      // observed, so writing `data-unread` here cannot re-trigger this.
      new MutationObserver(() => applyUnread()).observe(document.body, {
        childList: true,
        subtree: true,
      });

      applyUnread();
      // ==== END follow + unread (MehU9) ====================================

      // ==== BEGIN right pane + resize (k92mT) ===============================
      //
      // Four pieces of behavior, and every one of them is a *fallback* rather
      // than the mechanism: with this block deleted the tabs are still links,
      // the language picker is still a form, the export button still downloads
      // and the panes still have their default widths. What it adds is not
      // reloading to do any of it, and two preferences that belong to this
      // browser rather than to the view — pane sizes and the code pane's
      // language. Both are wrapped in try/catch, so a private window loses the
      // memory and nothing else.

      const PANE_SIZES_KEY = "woodcase.panes";
      const CODE_LANG_KEY = "woodcase.code.lang";
      const MINIMUM_PANE = 120;

      function readJSON(key) {
        try {
          return JSON.parse(localStorage.getItem(key) ?? "null");
        } catch (error) {
          return null;
        }
      }

      function writeJSON(key, value) {
        try {
          localStorage.setItem(key, JSON.stringify(value));
        } catch (error) {
          // best effort only
        }
      }

      // This block's own swap. Deliberately not the one above: that is another
      // block's closure, and a fragment landing here must not depend on the
      // order the two are pasted in.
      async function paneSwap(url, targetID) {
        const target = document.getElementById(targetID);
        if (!target) return false;
        let html;
        try {
          const response = await fetch(url, { headers: { Accept: "text/html" } });
          if (!response.ok) return false;
          html = await response.text();
        } catch (error) {
          return false;
        }
        const holder = document.createElement("div");
        holder.innerHTML = html;
        const next = holder.firstElementChild;
        if (!next) return false;
        target.replaceWith(next);
        return true;
      }

      const rightPane = () => document.getElementById("v-right");
      const paneStage = () => document.getElementById("v-stage");
      const paneFile = () => paneStage()?.dataset.file ?? null;

      // ---- the tabs -------------------------------------------------------

      // The same rule ViewState.tab(forSelection:) keeps on the server, so a
      // pushState here and a page load there agree about which tab is showing.
      function tabFromLocation() {
        const url = new URL(location.href);
        const tab = url.searchParams.get("tab");
        if (tab) return tab;
        return url.searchParams.get("node") ? "details" : "activity";
      }

      // The URL this view has with one tab showing, spelled exactly the way
      // ViewState.query spells it — a tab is written whenever anything is
      // selected, so the Activity tab's own link is not `?node=…` with no tab,
      // which would parse straight back to Details.
      function tabHref(tab) {
        const url = new URL(location.href);
        if (tab === "activity" && !url.searchParams.get("node")) {
          url.searchParams.delete("tab");
        } else {
          url.searchParams.set("tab", tab);
        }
        return url.pathname + url.search;
      }

      // Which panel shows, which pill is lit, and where each pill points. All
      // three, always: the pane's `data-tab` alone left a selection showing
      // Details under a highlighted Activity, and a stale `href` — written by
      // the server before anything was selected — sent the Details tab to a URL
      // with no `?node=`, which dropped the selection on the way to its own tab.
      function showTab(tab) {
        const pane = rightPane();
        if (!pane) return;
        pane.dataset.tab = tab;
        for (const link of pane.querySelectorAll(".v-tab")) {
          link.classList.toggle("is-current", link.dataset.tab === tab);
          link.setAttribute("href", tabHref(link.dataset.tab));
        }
      }

      function refreshDetails() {
        const file = paneFile();
        if (file) paneSwap(`/files/${file}/details${location.search}`, "v-details");
      }

      // A selection happened: `select()` has already pushed the URL, so this
      // only has to write the tab the selection implies and fetch the pane.
      // `replaceState`, not push: the selection is the history entry, and the
      // tab it implies is part of the same one.
      function syncSelectionTab() {
        // The selection decides, not the `?tab=` already on the URL: selecting
        // from the Export tab moves to Details, which is what
        // ViewState.selecting(_:) does on the server.
        const tab = new URL(location.href).searchParams.get("node") ? "details" : "activity";
        history.replaceState({}, "", tabHref(tab));
        showTab(tab);
        refreshDetails();
      }

      document.addEventListener("click", (event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;

        const tab = event.target.closest(".v-tab");
        if (tab && rightPane()) {
          event.preventDefault();
          // From `location`, never from the link: the selection may have moved
          // since the server wrote this href, and switching tabs must not
          // navigate away from what is selected.
          history.pushState({}, "", tabHref(tab.dataset.tab));
          showTab(tab.dataset.tab);
          if (tab.dataset.tab === "details") refreshDetails();
        }
      });

      window.addEventListener("popstate", () => {
        if (!rightPane()) return;
        showTab(tabFromLocation());
        refreshDetails();
      });

      // ---- the code pane --------------------------------------------------

      const codePane = () => document.getElementById("v-code");

      function storedLanguage() {
        try {
          return localStorage.getItem(CODE_LANG_KEY);
        } catch (error) {
          return null;
        }
      }

      function refreshCode(language) {
        const pane = codePane();
        if (!pane) return;
        const url = new URL(location.href);
        if (language) url.searchParams.set("lang", language);
        paneSwap(
          `/files/${pane.dataset.file}/artboards/` +
            `${encodeURIComponent(pane.dataset.artboard)}/code${url.search}`,
          "v-code"
        );
      }

      document.addEventListener("change", (event) => {
        const picker = event.target.closest(".v-code-lang");
        if (!picker) return;
        const language = picker.value;
        try {
          localStorage.setItem(CODE_LANG_KEY, language);
        } catch (error) {
          // best effort only
        }
        const url = new URL(location.href);
        url.searchParams.set("lang", language);
        history.replaceState({}, "", url.pathname + url.search);
        refreshCode(language);
      });

      // Which output file you read is a fact about you, not about the artboard,
      // so it is not in the URL — a link you paste opens the design, not your
      // taste in generated files. Which means only this can restore it.
      function restoreLanguage() {
        const pane = codePane();
        if (!pane) return;
        const wanted = storedLanguage();
        if (!wanted || wanted === pane.dataset.lang) return;
        refreshCode(wanted);
      }

      // ---- resizable panes ------------------------------------------------

      function restorePanes() {
        const sizes = readJSON(PANE_SIZES_KEY);
        if (!sizes) return;
        for (const grip of document.querySelectorAll(".v-grip")) {
          const size = sizes[grip.dataset.grip];
          if (size) grip.parentElement?.style.setProperty(grip.dataset.property, size);
        }
      }

      let drag = null;

      document.addEventListener("pointerdown", (event) => {
        const grip = event.target.closest(".v-grip");
        if (!grip || !grip.parentElement) return;
        const after = grip.dataset.edge === "after";
        const sized = after ? grip.nextElementSibling : grip.previousElementSibling;
        if (!sized) return;
        const horizontal = grip.dataset.axis === "x";
        const box = sized.getBoundingClientRect();
        drag = {
          grip,
          container: grip.parentElement,
          horizontal,
          // Dragging right widens the track on the left of the seam and narrows
          // the one on the right; the sign is which of the two is being sized.
          sign: after ? -1 : 1,
          origin: horizontal ? event.clientX : event.clientY,
          size: horizontal ? box.width : box.height,
        };
        grip.classList.add("is-dragging");
        try {
          grip.setPointerCapture(event.pointerId);
        } catch (error) {
          // a synthetic pointer has nothing to capture
        }
        event.preventDefault();
      });

      document.addEventListener("pointermove", (event) => {
        if (!drag) return;
        const moved = (drag.horizontal ? event.clientX : event.clientY) - drag.origin;
        const size = Math.max(MINIMUM_PANE, drag.size + drag.sign * moved);
        drag.container.style.setProperty(drag.grip.dataset.property, `${Math.round(size)}px`);
      });

      document.addEventListener("pointerup", () => {
        if (!drag) return;
        drag.grip.classList.remove("is-dragging");
        const sizes = readJSON(PANE_SIZES_KEY) ?? {};
        sizes[drag.grip.dataset.grip] =
          drag.container.style.getPropertyValue(drag.grip.dataset.property);
        writeJSON(PANE_SIZES_KEY, sizes);
        drag = null;
      });

      // A `change` event refreshes the render region but knows nothing about
      // this pane, so the arrival of a fresh region is the signal that the file
      // moved under us and the details and the code are stale.
      new MutationObserver((records) => {
        for (const record of records) {
          for (const added of record.addedNodes) {
            if (added.nodeType !== 1 || added.id !== "v-render-region") continue;
            refreshDetails();
            refreshCode(storedLanguage());
            return;
          }
        }
      }).observe(document.body, { childList: true, subtree: true });

      restorePanes();
      restoreLanguage();
      // ==== END right pane + resize (k92mT) =================================

      // ==== BEGIN in-place artboard navigation (lS7YE) ======================
      //
      // Stepping to the next artboard used to replace the document, and replacing the
      // document throws away everything that is not in the URL: the event stream, the
      // panes' widths, where the outline is scrolled, an outline row's collapsed state,
      // and — the one that made this a bug rather than a slowness — presentation mode,
      // which is a class on `<body>`. Holding an arrow key walked the file by reloading
      // it once per press.
      //
      // So the step is a `pushState` and a swap, like every other navigation here. What
      // is different is how much it swaps: an artboard is most of the page, and the two
      // pieces that name it loudest — the breadcrumb and the tab title — have no
      // fragment endpoint of their own. Rather than assemble those two strings in
      // JavaScript, which is the one thing this file is not allowed to do, it fetches
      // the page it is moving to and takes the elements out of it. That is the same
      // move `swapFromPage` makes for the dashboard, and it costs the server exactly the
      // render a reload would have cost it, minus the document.

      // The pieces of an artboard page that name the artboard. Everything else — the
      // variables, the presence stack, the pane widths, the classes on `<body>` — belongs
      // to the file or to this browser, and is left alone, which is the entire point.
      const ARTBOARD_PIECES = [
        "#v-render-region",
        "#v-outline",
        "#v-right",
        "#v-follow",
        ".v-crumbs",
      ];

      // Replaces those pieces with the ones the server rendered for `href`.
      //
      // `importNode` rather than handing `replaceWith` a node from the parsed document:
      // adopting across documents is the sort of thing engines disagree about, and this
      // is one line either way.
      async function swapArtboardPage(href, sailed) {
        let html;
        try {
          const response = await fetch(href, { headers: { Accept: "text/html" } });
          if (!response.ok) return false;
          html = await response.text();
        } catch (error) {
          return false;
        }
        if (voyage !== sailed) return false;
        const parsed = new DOMParser().parseFromString(html, "text/html");
        let replaced = 0;
        for (const selector of ARTBOARD_PIECES) {
          const next = parsed.querySelector(selector);
          const current = document.querySelector(selector);
          if (!next || !current) continue;
          const arriving = document.importNode(next, true);
          replaceKeepingScroll(current, arriving);
          armMarkers(arriving);
          replaced += 1;
        }
        if (replaced === 0) return false;
        // The tab title is a server string too, and a stale one is how a person with
        // three windows open loses track of which is which.
        if (parsed.title) document.title = parsed.title;
        fitStage();
        revealSelection();
        return true;
      }

      // Moves to another artboard without a page load.
      //
      // The URL moves first, so every listener that reads `location` — the right pane's
      // observer refreshing Details and Code, the unread marks, the follow control — is
      // reading where the page now is rather than where it was. If the fetch fails there
      // is nothing sensible to show under the new URL, so the address is put back and the
      // browser is asked to navigate, which is always correct.
      async function goToArtboardInPlace(href) {
        const previous = location.pathname + location.search;
        const sailed = departed();
        history.pushState({}, "", href);
        if (await swapArtboardPage(href, sailed)) return;
        if (voyage !== sailed) return;
        history.replaceState({}, "", previous);
        location.assign(href);
      }

      // The footer's `‹`/`›` links, which are also what ← and → click. Intercepted here
      // rather than in the main click handler because this block owns the whole-page
      // swap; the capture-phase handler that drops follow has already rewritten this
      // link's `href` by the time this reads it, which is why it is read and not rebuilt.
      //
      // A map box and the map crumb are *not* intercepted: those move between the map and
      // an artboard, two different pages with two different canvases, and a navigation is
      // the honest way to change which one you are on.
      document.addEventListener("click", (event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;

        const step = event.target.closest("a.v-step[data-artboard]");
        if (step && stage()) {
          event.preventDefault();
          goToArtboardInPlace(step.getAttribute("href"));
          return;
        }

        // Clicking the canvas around the artboard means "nothing", the same as clicking
        // the desktop behind a window. The stage itself is the render's own hit test, a
        // level up; the footer is chrome *about* the selection, so clicking it — to copy
        // an address, to step — is not a place to lose one.
        if (!event.target.closest("#v-canvas-body")) return;
        if (event.target.closest("#v-stage, .v-selection")) return;
        if (new URL(location.href).searchParams.get("node")) select();
      });

      // Back and forward between artboards. The main block's own `popstate` handler
      // stands aside for exactly this case, so the two never both answer.
      window.addEventListener("popstate", () => {
        if (!stage()) return;
        const wanted = artboardFromLocation();
        if (!wanted || wanted === artboardID()) return;
        swapArtboardPage(location.pathname + location.search, departed());
      });
      // ==== END in-place artboard navigation (lS7YE) ========================
    })();
    """#
}
