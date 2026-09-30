# 2026-09-30 — An intro deck, designed in Woodcase

Ben asked for a short 16:9 deck that tells a technical audience what Woodcase is: people who already use Claude Code and may use agentic design tools such as Pen or Paper. It is designed in Woodcase, exported as a PDF by Woodcase, and read alone. Restraint and boldness are the balance; every element earns its place.

## Rulings (Ben, 2026-09-30)

- **Read alone**, not presented. The CTA is `brew install bensyverson/tap/woodcase`.
- **Thesis:** "Woodcase is the design layer for agents: a tight loop of command, view, iterate — headless, with a robust CLI, and embeddable anywhere from a CGContext to a SwiftUI project." JavaScript execution (`woodcase js`) is named, because it is what agents reach for.
- **Position:** Woodcase lives in, and expands, the `.pen` ecosystem. Pen is first-party and built for human–agent collaboration; Woodcase is agent-first with no human GUI, headless or inside a larger app (the original use case: agentic title design in a video editor).
- **Main feature:** the tight editing loop, refined through user-centered design with agents as the users.
- **Identity:** start fresh. `DESIGN.md` is the viewer's dashboard system and does not apply. Keep any logo simple.
- **Self-reference:** the deck reveals it was built by an agent through the CLI and shows its own activity log. The `.pen`, the scripts that generate it and the PDF live in the repo together.
- **Process:** the UFTI method from nobedan (`project/2026-09-12-ufti-round-4.md` and `kb/frameworks/llm-creativity.md` there), with no worry about token cost.

## Where things live

- `examples/intro-deck/`: the deliverable. The `.pen`, the build scripts, the PDF, a short README with the one rebuild command; one link from the main README.
- `project/2026-09-30-intro-deck/`: the dated record. The brief, the concept pool and its scores, the critic's notes, the findings.
- `local/intro-deck/`: transients (baseline builds, draft renders, strips).

DocC needs nothing installed: `swift-docc-plugin` is already a dependency, `docc` ships with Xcode 26, and its output goes to the ignored `.build/`.

## Method

Carried over from the UFTI rounds, and why:

1. **Hand the concept; the method is the smaller lever.** Five concept agents, run bare (a domain lens at the idea stage leaked in as a costume), each write ten complete directions and rank them from most to least common. The spread comes from the independent samples, not from the ranking.
2. **Dedupe, then select on facts kept apart from taste.** Pool the directions and merge the duplicates. Count convergence (how many agents reached each idea). A fresh judge scores facts, not taste: visual richness, show-don't-tell, costume (how far the deck is dressed up as something else, inverted). Ben picks from a short list ordered rare-first among the ones that clear the bar.
3. **Baselines as ground.** Two decks built from the bare brief with no direction, so the critic can read the draft against what an undirected agent makes.
4. **Draft, critique, finish.** One designer builds the chosen concept through the CLI and `woodcase js` scripts. An art director in a fresh context reads only the renders against the baselines and returns notes as questions. The same designer session finishes.
5. **Give rules, not descriptions of what to avoid; ask for less.** The brief states the reference standard and the balance, and names no look to avoid.

The brief is [brief.md](2026-09-30-intro-deck/brief.md).

```yaml
tasks:
  - title: "Intro deck: what Woodcase is, designed in Woodcase"
    desc: "A 16:9 PDF deck for developers who use coding agents, designed and rendered by Woodcase, read alone. Plan and rulings: project/2026-09-30-intro-deck.md; brief: project/2026-09-30-intro-deck/brief.md."
    children:
      - title: Baselines, two undirected decks from the bare brief
        ref: baselines
        desc: Two agents each build a deck from brief.md alone, through the woodcase CLI, into local/intro-deck/baseline-N/. Rendered to PNG per slide. They are the critic's ground.
        criteria:
          - Two baseline decks rendered, one PNG per slide
      - title: Concept pool, dedupe and fact scores
        ref: concepts
        desc: Five bare concept agents, ten directions each, ranked most to least common. Dedupe into concepts with convergence counts; a fresh judge scores visual richness, show-don't-tell and costume. A short list for Ben, rare-first.
        criteria:
          - The pool, the merged concepts and their scores are in project/2026-09-30-intro-deck/concepts/
          - A short list of four to six concepts is ready for Ben
      - title: Ben picks the concept
        ref: pick
        labels: [ben, decision]
        blockedBy: [concepts]
      - title: Draft the deck through the CLI and JS scripts
        ref: draft
        desc: A designer agent builds the chosen concept into examples/intro-deck/ with a reproducible build (woodcase new, then woodcase js scripts), renders it, and stops before finishing.
        blockedBy: [pick, baselines]
        criteria:
          - examples/intro-deck/ rebuilds the .pen from scratch with one command
          - Every slide renders, and lint is clean
      - title: Art-director critique of the draft
        ref: critic
        desc: A fresh agent reads the draft's slide renders against the baselines and writes notes as questions (What's working / What's not).
        blockedBy: [draft]
      - title: Finish, export the PDF, README
        ref: finish
        desc: The designer's session resumes with the critic's notes and finishes. Export the PDF with woodcase render --format pdf; examples/intro-deck/README.md; one link from the main README.
        blockedBy: [critic]
        criteria:
          - The PDF is in examples/intro-deck/ and every page is 16:9
          - The activity-log reveal shows the deck's own real log
          - Ben accepts the deck
      - title: Findings
        desc: A dated findings doc in project/ on what the method did here, with every figure's command.
        blockedBy: [finish]
```
