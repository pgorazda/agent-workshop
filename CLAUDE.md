# CLAUDE.md

Agent Workshop shows AI coding agents at work as penguins in a pixel-art workshop. The layout is in `README.md`.

## Tests

```bash
cd bridge && cargo test                # the bridge (Rust)
node --test adapters/test              # the adapter scripts against the real bridge (Node 22+)
cd godot && npm test                   # needs the Godot editor (set GODOT, see godot/README.md) and builds the bridge
```

## Rules

1. Write documents and comments in simple technical English.
2. The event schema (`schema/event.schema.json`) is the contract. Adapters map native events to it; clients read only the schema and pick stations by `category`, never by tool name. Keep `bridge/src/schema.rs` in step with it (a test checks the enums).
3. The bridge listens on `127.0.0.1` only, stores nothing and broadcasts only schema fields.
4. The 2D view has a look of its own. Do not use Anthropic or Claude logos, the Claude Code mascot, Anthropic's typefaces, Claude's colours as a colour scheme, the asterisk spinner and its verbs, or layouts copied from Claude Code's terminal.
5. This repository is public. Do not add personal data, real transcripts, real paths or names, or references to private projects. Example sessions are made up. The copyright holder's name in license and copyright notices is fine.
6. "Agent Workshop" is the project; an "arena" is one room of the 2D view. Existing code names (`ARENA_*` variables, `arena.js`) stay as they are.
7. Code is MIT; art is all rights reserved (`LICENSE-ASSETS`). Drawing and sound code (the palette, sprites, props, room, effects, interface drawing, music and event sounds) lives only in `art/` folders (`godot/art/`, later `web/src/view2d/art/`), and each file there starts with the copyright header. Images and sounds made from the art code are art too: in `godot/art/` they live in `images/` and `sound/`, and `MANIFEST.txt` holds their hashes. Code outside `art/` may call the art but must not contain it. `cd godot && node --test` checks the headers and the split.
