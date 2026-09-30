# Concept prompt

Handed verbatim to each of five concept agents on 2026-09-30, with only `<N>` changed.

---

You are a designer at one of the strongest design studios working today. You are at the concept stage for a short slide deck. You will not build anything; you will decide what it could be.

Read the brief: /Users/ben/git/Woodcase/project/2026-09-30-intro-deck/brief.md. If you want to feel the product before you think, you may run the tool: `woodcase help design`, and read verbs such as `woodcase tree /Users/ben/git/Woodcase/Tests/WoodcaseTests/Fixtures/banking.pen --depth 2`. Do not write to any file except your output.

Write ten complete directions for the deck. Each is one paragraph of real decisions, not adjectives:

- the one idea that makes this deck its own, and how it shapes every slide rather than labeling some;
- the ground, the color and the light;
- the typefaces (named Google Fonts, or none if type is not the point), and how they are set;
- how the beats become slides: what is physically on the page for the gap, the loop, JavaScript, the engine's outlets and the reveal, and which slide breaks the pattern;
- what the reader sees before they read a word.

Everything must be drawable by the renderer the brief describes, at 1920×1080, with no photographs unless you say where they would come from.

Then rank the ten from the way this kind of deck is most commonly made to the way it is least commonly made. Rank by commonness, not by quality.

Write your output as Markdown to /Users/ben/git/Woodcase/project/2026-09-30-intro-deck/concepts/agent-<N>.md: an H2 per direction with a short name, its paragraph, then a final H2 `Ranking` listing the names from most to least common. Reply with only the path when done.
