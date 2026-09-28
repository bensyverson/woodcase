# Woodcase Viewer & Editor

Drafted: 2026-08-29\
Author: Ben Syverson

## Overview
Woodcase is used as a library in other apps, but I think the CLI itself could be extremely useful for "headless" designing by an agent or agents (given that we have CRDT support). This is the “Editor.” I want to think through the shape this could take, and not jump straight to "MCP." Separately, humans want to be able to see their changes live. This is the “Viewer.”

Let's zoom out and take a human-centered (and user-centered in the case of agents) design approach for both components. I want to think through our two types of users, their needs, and then talk through a potential plan.

## Users

### Human Developer

The human developer may be someone non-technical, who is using a workflow that happens to leverage agents to perform visual or screen design. Or they may be highly technical. In both cases, the human is letting the agent “drive” the design session, and they don’t want to have to manage or configure anything.

#### Human Developer needs

**Primary need:** the human needs to be able to visually *see* a design as it evolves.

They do not need to *edit* a design as it involves (that’s a role for Penumbra). Woodcase could provide a view-only window into what’s happening in a design. The analog is the live web preview for HTML files in BBEdit. Just like a live web preview, the visual output should change anytime the design/file has changed. The human may want to see both a *specific* design file or artboard, or they may want to see what's happening across *all* Woodcase sessions. These may take different forms (e.g. a thin native app for the artboard viewer vs a web dashboard for the overview)

### Agent Designer

Primary need:** the agent needs to be able to both see and *edit* a design.

The agent designer is a vision-capable LLM, tasked with implementing or iterating a visual design. For them, Woodcase provides the format (.pen), editing tools and text or visual output to verify their changes.

#### Agent Designer needs

You will know the agent's needs better than I would, but here's what I suspect:

- The agent might want to see some kind of token-efficient textual representation of a file, artboard or individual element (e.g. the node tree), to quickly understand the structure.
- The agent will want the ability to easily kick out a PNG from a file, artboard or element so it can “see” it via a vision model. These commands might be modeled on SleepyHollow's capabilities, which allow the agent to specify the max dimension it can read, overlay grids, etc.
- The agent needs the ability to easily create and edit files in a token-efficient and fault-tolerant manner. You can read an experience report of an agent who used the MCP here: @project/2026-03-26-Gemini-DX.md … I'm open to MCP being the interface, but I think we should also explore alternatives such as CLI, REST API, stdin (interactive use via tmux), and others.
- The agent may want to see a comprehensive textual representation of a node. Obviously we could just export the JSON for any node, but you tell me: would a YAML or simplified output be easier to parse and reason about? Should it include refs, slots and overrides like the JSON, should it be the fully materialized tree, or should there be an option?
- The agent may be exporting code, not images, and will need to utilize the existing CLI features related to code-gen.

## Topics for Discussion

1. **CRUD best practices:** When it comes to the editing workflow, we may want to learn from what works in Claude Code and other coding harnesses; failing loudly on "write before read", etc, keeping track of when the read happened vs changes from others in the same file.
2. **Stateful or stateless?:** An agent will likely stay in a single file for multiple iterations; making an edit, viewing the result, then making further changes. Given this behavior, our editing interface could either be entirely stateless, or it could be session-based, so we know a bit more about the operations that have come before. Both have their advantages and disadvantages. Let’s discuss.
3. **Agent Identities:** One nice pattern from Pen.app: you can see a virtual “cursor” as an agent makes a change to an element. Related: In Jobs (`job`), agents can claim and complete work using an identity. I wonder if we want to take inspiration from this, to better visualize *which* agent is taking action, and what they’re editing. This might imply sessions, some kind of registration prior to editing, or a Jobs-like `--as` flag.
4. **Project type:** If this becomes a native app rather than a web app, what form does this take? A new Xcode project, a SPM-based SwiftUI app with no Xcode project at all?
5. **Cross-file or cross-artboard visibility:** What’s the best way to let users see a “dashboard” view of Woodcase activity? How might we expose that information to other tools, who may want to consume or represent Woodcase activity in their own dashboards? An example hypothetical consumer would be the Jobs dashboard.
6. **CRDT support:** What’s the best way to enable multiplayer/CRDT editing of a local document? Do we require the use of a server? Is there a case for a SQLite sidecar next to each .pen? Do we have a single Woodcase daemon manage all sessions, or fire up short-lived Woodcase hosts and pass them around by port or reference ID?

## Design Principles

As we think through a design, there are some factors that we need to keep in mind to ensure the tool stays nimble and usable.

1. **Viewing is opt-in.** The human should not be surprised by 12 windows spawning as agents fan out to edit design files. The human should be in control of what they monitor. This could be via CLI (`woodcase view`) or by making the macOS app (if that’s the best expression) a Viewer for the .pen file type, and offering minimalistic navigation (View all artboards, or select from a list)
2. **Speed is non-optional.** Any viewer needs to start quickly, not consume too many resources, and update quickly.
3. **Don’t compete with Penumbra.** If the user wants to make their own changes, select objects, inspect objects, change theme, zoom in and out smoothly, they should use Penumbra, not the Woodcase viewer.
4. **Agent-first.** The editing features and interface will be co-designed with agents, for agents. That could mean leveraging some of the principles used in the CLI design of SleepyHollow and Jobs; progressive discoverability, success and error messages that teach an agent how to use the tool, and a stated goal to avoid the need for a specialized skill or heavy agent-facing documentation.

## Next steps

I’m sure I’ve left a lot out. What questions do you have about this effort? Why don’t you browse the codebase and come back to me so we can discuss a path forward. We’ll end our discussion with a concrete implementation plan in the form of a project/ doc with a YAML block in `job schema` format.
