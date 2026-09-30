# The intro deck

A nine-slide introduction to Woodcase for developers who work with coding agents — [intro-deck.pdf](intro-deck.pdf).

The deck is its own demonstration. It is a `.pen` file an agent built through the `woodcase` CLI, one attributed write at a time; every quote on a slide is real output read from the tool during the build, and slide 8 shows the deck's own activity log. The PDF is rendered by Woodcase.

## Rebuild it

```bash
examples/intro-deck/build.sh
```

About twelve seconds, from nothing: it warms the font cache, shoots and reads the `banking.pen` fixture for the quotes and the stack's planes, writes each slide with `woodcase js`, lints, renders every slide to PNG (in `local/intro-deck/final/` by default, or the directory you pass) and exports `intro-deck.pdf`.

It uses the checkout's own build at `.build/debug/woodcase` when there is one, otherwise `woodcase` on `PATH`; set `WOODCASE` to choose another. It needs Woodcase with the PDF export fix of 2026-09-30 (after 0.1.2); older releases export blank Letter pages. The deck keeps its own activity log (`WOODCASE_HOME=examples/intro-deck/.woodcase`, ignored by git), emptied at the start of each build, so the log on slide 8 is exactly that build's writes.

The four `clipped` warnings `lint` prints are the deliberate crops of the stack running off the page.

## What is here

| Path | What it is |
|---|---|
| `build.sh` | The one command |
| `slides/01.js` … `09.js` | One `woodcase js` program per slide |
| `lib/` | Shared helpers: the plane builder, the stack projector, the page-by-part writer, the quote and log readers |
| `quotes/measure.js` | The script slide 5 runs and shows |
| `assets/` | The rendered planes and thumbnails the slides fill with; not committed, so run `build.sh` once before opening `deck.pen` |
| `deck.pen`, `intro-deck.pdf` | The result |

How it was designed — the brief, the concept pool, the critique — is in [project/2026-09-30-intro-deck.md](../../project/2026-09-30-intro-deck.md).
