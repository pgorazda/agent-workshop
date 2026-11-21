# Arenas

An arena is one copy of the workshop room, with the same nine stations. When a room is full, more arenas open. One arena is on screen at a time, and a camera moves between them. This page states the rules the app follows. The code is in `godot/src/core/arena_rules.gd`, `director.gd` and `camera.gd`. The tests are `test_arena_rules.gd`, `test_director_arenas.gd` and `test_scene_camera.gd`.

## When an arena opens, and closes

- **An arena holds up to four agents** (`--arena-size=<n>`, `0` for one room for everyone). Helpers stay in their parent's arena and do not count.
- **A new agent goes to the first arena with room**, in letter order. An agent that left and comes back goes to its old arena if there is room. If every arena is full, a new arena opens.
- **An agent never changes arena while it is present.** Penguins do not walk between rooms.
- **An agent leaves after 10 minutes without an event** (`--leave-after=<s>`), unless a tool call or an approval of it is still open. It walks out through the door, and its number is freed.
- **An arena closes 30 s after its last agent has left**, unless it is the only arena.
- **Names.** Arenas are lettered A, B, C, ... and after Z, AA, AB, ... A new arena takes the lowest free name.
- **Colours.** Each arena has its own kilim rug, in turn: red, cobalt, emerald, yellow, teal, then red again. The four arenas of a page never share a colour.
- **A limit.** The app shows at most 200 penguins (`--limit=<n>`). An agent that finds every arena full is not shown, and the list of arenas shows a gold "+N".

## Pages of four

Arenas sit in pages of four, each a 2×2 matrix. An arena's place comes from its letter and stays while it is open. A page exists while one of its arenas is open. The list of arenas in the bar and the overview show one page at a time, so the mechanism is the same for five arenas or for forty.

## The bar and the overview

With one arena the bar shows the connection, counts, the follow switch and one card for each agent. With two or more arenas the top line becomes the list of arenas: one tab for each arena of the page on screen, then a box for each page. A tab shows the arena's letter, a chip with the number of each agent, and the arena's state, the most urgent of its agents' states: WAIT (gold, blinking), FAIL (red), running, DONE (green), idle, empty (closing). A page box is outlined in the colour of the most urgent state on its page, so an approval on a page that is not shown still blinks in the bar.

**Tab** opens the overview: one page as a 2×2 matrix at half size, with the rooms still playing. It turns a page at a time.

## The camera

The camera looks at the world of pages and moves with an ease in and out:

| Move | Time |
|---|---|
| Slide to another arena on the same page | 0.5 s |
| Fly to an arena on another page (it widens first, then closes in) | 0.7 s, plus 0.15 s for each extra page, at most 1 s |
| Zoom between an arena and its page (the overview) | 0.3 s |
| Scroll from one page of the overview to another | 0.5 s, plus 0.15 s for each extra page, at most 0.8 s |

If the target changes during a move, the camera turns from where it is, without a jump. With `--reduced-motion` the room does not shake after a failure.

### Follow: AUTO and MANUAL

In **AUTO** the camera moves when another arena pulls it. In **MANUAL** it moves only when you choose an arena (a tab, the arrow keys, N, or a cell of the overview). Choosing an arena in AUTO switches to MANUAL. **F** switches back.

The pulls, most urgent first:

1. An approval is needed (the oldest first).
2. A failure. Off by default.
3. A new arena has opened. A ribbon with its name shows on the wall.
4. A main agent has finished its turn. A helper never pulls.
5. A new agent joined an arena that had room. Off by default.

Also "busy arenas" (on by default): when the arena on screen has had no event for 3 s, the camera goes to the arena with the newest event.

Each cause pulls once. A pull for a new arena or a finished turn that is not served within 10 s expires. An approval pulls until it is answered. After any move the camera stays at least 1.5 s, and while an approval notice is on screen it stays 4 s, or until the approval is answered.

The **follow menu** (click the follow switch) ticks or unticks each kind of pull (keys 1 to 6), sets the pace, and has "manual only" (key 0). The pace limits how often the camera may move by itself: by default at most 3 moves in 10 s. Approvals are let past the pace. What the person does is never limited.

## Keys and mouse

| Input | What happens |
|---|---|
| Click a tab | The camera slides to that arena; follow becomes MANUAL |
| Hover over a tab | The cards show that arena's agents; the camera does not move |
| Click a penguin or a card | Focus on that agent |
| F | Switch between AUTO and MANUAL |
| ← and → | The previous or next arena (in the overview: the previous or next page); follow becomes MANUAL |
| N | The next arena that needs you: the oldest waiting approval, then a failure, then a finished turn |
| Tab | The overview on or off (with two arenas or more) |
| Click an arena in the overview | Zoom into it; follow becomes MANUAL |
| Click a page box | The overview on that page |
| Esc | Leave the overview |

Other keys: M turns all sound on or off, S opens the sound menu, C hides the bar. In demo mode Space pauses, 1 to 3 set the speed, R restarts the scene and D lists the scenes.

## Demo scenes

`--demo=<name>` (or D in the app) plays a made-up scene from `godot/demo/`:

| Scene | What it plays |
|---|---|
| `session` | One Claude Code session |
| `multi` | Six agents at once in one room |
| `arenas` | Nine agents in three arenas, with a camera between them |
| `many` | Nine arenas on three pages of four |
| `ten` | Forty arenas on ten pages |
| `follow` | The follow switch and its pace |
| `tour` | A guided tour of one arena: it stops at each event and each station, and a callout explains what you see |
