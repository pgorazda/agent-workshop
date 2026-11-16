# Plan: several arenas in the 2D view

> **Note (phase G-10):** the Godot client builds this plan (see [the Godot client plan](godot-client-plan.md)). The rules in this plan stay the specification. The browser client is not built: ADR 0008 replaced it. The Godot client plays the same scenes from `godot/demo/`, and the pictures below come from it.

**State: a plan. A mockup scene plays its rules (see "The scenes"); the view itself is not built.** The decision is ADR 0005 (proposed). It extends the [2D view plan](2d-view-plan.md) (ADR 0003) and keeps its look (ADR 0004).

## Goal

The 2D view starts with one room, the arena, as it does now. When the arena is full, a second one opens next to it, then a third, and so on. The arenas sit in pages of four, each a 2×2 matrix. One arena is on screen at a time. A camera moves between them, either by itself (follow AUTO) or only when you choose (follow MANUAL). A list of arenas in the bar shows what happens in the arenas, including those not on screen, one page at a time, and Tab shows the overview: one page of four, which scrolls page by page.

Not in scope: a 3D view, changes to the schema, the adapters or the bridge, and grouping agents by project (see "What opens an arena").

## What already exists

| Piece | Where it is | What to do with it |
|---|---|---|
| The room, the props, the penguins and the effects | The 2D view plan, phases 2D-1 and 2D-2 | Draw one room per arena |
| Number chips, the focus and its auto/click switch (AUTO/MANUAL here), the cards, extra spots and the queue, stacked approval notices | The 2D view plan, "Several agents" (phase 2D-3); the mockup's `?scene=multi` | Keep, and apply them per arena |
| The director: one penguin per agent, never removed, at most 12 penguins | The browser client plan, `director.js` | Two new settings (see Design) |
| A demo with several agents | The demo mode plan, the `four-agents` scenario (phase 5c) | The browser test |
| The rules of this plan, with no drawing, and their tests | `arena-rules.js` and `arena-rules.test.mjs` of the JavaScript mockup; ported to `godot/src/core/arena_rules.gd` and `godot/test/test_arena_rules.gd` | Start `arenas2d.js` and `camera2d.js` from them |

## What an arena is

An arena is one copy of the workshop room. Every arena has the same nine stations from the station table. Only its name and its rug differ.

### What opens an arena

1. **An arena holds up to four agents.** Helpers stay in their parent's arena and do not count.
2. **A new agent goes to the first arena with room**, in letter order. An agent that left and comes back goes to its old arena if there is room. If every arena is full, a new arena opens.
3. **An agent never changes arena while it is present.** Penguins do not walk between rooms.
4. **No limit of their own.** Names go on after Z like the columns of a spreadsheet (AA, AB, …), so ten pages hold A to AN. Pages (below) are what lets the number grow: the bar and the overview show four arenas at a time, whatever the total. What caps the number is the director's penguin limit (see Design); with a limit set, an agent that finds every arena full is not shown, and the list of arenas shows a gold "+1".
5. **An agent leaves after 10 minutes without an event**, unless one of its tool calls or approvals is still open (a long build sends nothing until it ends). It walks out through the door in the bottom wall, and its place and number are freed.
6. **An arena closes 30 s after its last agent has left**, unless it is the only arena. Until then its tab says "empty".
7. **Names.** Arenas are lettered A, B, C and so on, and after Z, AA, AB and so on. A new arena takes the lowest free name, so a closed B is used again before F. Letters, not numbers, because agents already have numbers. The wooden sign on the wall, which says AGENT WORKSHOP today, says ARENA A, ARENA B and so on once there are two arenas.
8. **Colours.** Each arena has its own kilim rug, in the folk colours of ADR 0004 in turn: red (A, today's rug), cobalt, emerald, yellow, teal, then red again for F. The four arenas of a page never share a colour. The rest of the room is the same. The colour helps; the letter is what names the arena.

`?arena-size=N` sets how many agents an arena holds. `?arena-size=12` gives one room for everyone, as in the 2D view plan.

Other rules were considered:

| Rule | A new arena opens when | For | Against |
|---|---|---|---|
| Fill up (chosen) | every arena has four agents | No schema change. Keeps the rules for several agents in one room. A room never gets crowded | Which arena an agent lands in only says when it arrived |
| One per session | a session starts | Easy to explain. No schema change | From the second agent on, nothing is on screen together. One penguin per room, so the extra spots, the queue and the stacked notices go unused |
| One per project | an agent starts in a new directory | The most meaningful: agents on one repository share a room | Needs a `project` field in the schema and in all four forwarders, and a directory name leaves the agent (to be dropped with `--redact-targets`). A decision of its own |
| One per framework | a new framework appears | Trivial | Three Claude Code sessions crowd one room while the others stay empty |

Grouping by project could later be added on top of filling up: the agents of one project fill that project's arenas. That needs its own ADR.

### Pages of four

The arenas live in pages of four, each a 2×2 matrix, and the pages sit side by side with a gutter between them:

```
  page 1         page 2         page 3
 +---+---+      +---+---+      +---+---+
 | A | B |      | E | F |      | I |   |
 +---+---+      +---+---+      +---+---+
 | C | D |      | G | H |      |   |   |
 +---+---+      +---+---+      +---+---+
```

* **An arena's place comes from its letter**, and it keeps that place while it is open: A is always top left on the first page, F top right on the second. When an arena closes, its place stays free, and the next new arena takes it, because a new arena gets the lowest free letter. Nothing else moves.
* **A page exists while one of its arenas is open.** A page whose arenas have all closed is skipped.
* **Everything that shows several arenas shows one page:** the list of arenas in the bar (the page's four tabs, then a box per page) and the overview (one 2×2 matrix). Both turn a page at a time, so the mechanism is the same for five arenas or for forty.

## The screen

The room stays 480×232 and the bar 480×38, as in the 2D view plan.

### One arena

Exactly as in the 2D view plan: no list of arenas, the top line, and the cards.

```
+------------------------------------------------------------------------------+
| [AGENT WORKSHOP]                        wall                                     |
|                                                                              |
|             the room: stations, penguins with their number chips             |
|                                                                              |
+------------------------------------------------------------------------------+
| o online  3 agents . 1 helper . 14 calls    follow [AUTO]   focus: #1 ...    |
| [1 claude-code 4f2a  src/app.ts ...] [2 opencode ses_7 ...] [3 pi 31 ...]    |
+------------------------------------------------------------------------------+
```

### Two arenas or more

The top line of the bar becomes the list of arenas: the tabs of one page, then, when there is more than one page, a box per page. The cards below belong to the arena on screen.

```
+------------------------------------------------------------------------------+
| [ARENA B]                           wall                                     |
|                                                                              |
|                     the room of arena B (cobalt rug)                         |
|                                                                              |
+------------------------------------------------------------------------------+
| o  A 1 2 3 4 ..  |B 5 6 WAIT|  C 7 DONE  D :::: ..   [1] 2 3   follow [AUTO]  |  <- the page's tabs, the pages
| [5 hermes a8  pytest  WAIT] [6 pi 44  Makefile ...]                          |  <- the cards of arena B
+------------------------------------------------------------------------------+
```

The tabs are the four places of the page the camera is on, in their order on the page: top left, top right, bottom left, bottom right. A free place has no tab. Each tab shows:

* the letter on a plate in the arena's rug colour;
* a chip for each agent, with its number in its cord colour. A chip blinks gold while its agent waits for approval, and is red after a failure until that agent's next event. When the chips do not fit, as with two-digit numbers, each agent is a small pip in its cord colour instead; the cards, the penguins and the overview still show the numbers;
* the arena's state, which is the most urgent of its agents' states, in this order: WAIT (gold, blinking), FAIL (red), the running dots, DONE (green, a turn has finished), idle (dim), empty (dim, dashed outline, the arena is closing).

The tab of the arena on screen is lit and underlined in cream; the others are dark. The light at the left is the connection: green when connected, gold while reconnecting, red when the connection is lost. To make room, the word "online", the counts and the focus text of the one-arena top line are dropped: the tabs show who is where, and the focused penguin's label in the room and its highlighted card show what it is doing. After the tabs comes a box per page, with its number. The box of the page in the list is lit. Each box is outlined in the colour of its page's most urgent state: gold and blinking while an agent there waits for approval, red after a failure, green and blinking for a page that has just appeared. So an approval on a page that is not shown still blinks in the bar. A click on a box opens the overview on that page. The list shows at most five boxes, around the page it is on; with more pages, an arrow at either end stands for the pages beyond it, in the colour of the most urgent state there. So four tabs, five boxes and two arrows fit beside the light and the follow switch, however many pages there are. When agents are not shown because every arena is full, a gold "+N" follows the boxes.

### The overview (Tab)

```
+--------------------------------------+---------------------------------------+
| E  17 18 19 20                  ...  | F  21 22 23 24                  WAIT  |
|<                                     |                                      >|
|       room E at half size, live      |       room F at half size, live       |
|                                      |                                       |
+--------------------------------------+---------------------------------------+
| G  25 26 27 28                  FAIL | H  29 30                        DONE  |
|                                      |                                       |
|       room G at half size, live      |       room H at half size, live       |
|                                      |                                       |
+--------------------------------------+---------------------------------------+
| the list of arenas: the tabs of this page, and the boxes  1 [2] 3            |
| the cards of the arena under the mouse                                       |
+------------------------------------------------------------------------------+
```

The overview shows one page: its four places as a 2×2 matrix at half size (240×116 each), with the rooms still playing. Each arena has its letter, its agents' chips and its state, drawn at full size; a free place is dark and says "free". When there are pages to the left or the right, an arrow at that edge says so, in the colour of the most urgent state there. The overview opens on the page of the arena on screen, and turns a page at a time.

## Interactions

### The camera

The camera looks at the world of pages. At the scale of one arena it shows one room, on whole pixels; at the scale of a page it shows the overview. Every change is a move of that one camera, with an ease in and out:

* **A slide** to another arena of the same page: 0.5 s, sideways, up, down or diagonally, because the page is a 2×2 matrix.
* **A fly** to an arena on another page: midway the camera widens to the size of a page, crosses the gutter, and closes in on the arena again; 0.7 s to the next page, 0.15 s more for each page further, at most 1 s. It shows where the arena is without flashing every room in between. A longer fly widens the view further, by about a page for each page it crosses, up to 8 rooms across (about four pages): the pages in between pass by small, each with its number below it, the one the camera is going to in gold.
* **A zoom** between an arena and its page (the overview): 0.3 s.
* **A scroll** from one page of the overview to another: 0.5 s to the next page, 0.15 s more for each page further, at most 0.8 s. A scroll of more than one page widens the view the same way as a long fly.

The bar does not move. On a page, the lit tab slides along with the camera; in a fly or a scroll, the list turns to the new page halfway. If the target changes during a move, the camera turns from where it is, without a jump. When the browser asks for reduced motion (`prefers-reduced-motion`), every move is a cut with a 0.15 s fade.

Inside the arena on screen, the focus works as in the 2D view plan, among that arena's agents only. Events in other arenas never move the focus unless they move the camera.

### Follow AUTO

The camera moves when another arena pulls it, and only for the kinds of pull that are ticked in the follow switch (see "The follow switch"). The pulls, most urgent first:

1. **An approval is needed.** The oldest first.
2. **A failure.** Not ticked by default (see the switch).
3. **A new arena has opened.** When the camera arrives, a ribbon in the arena's colour says "ARENA B" on the wall, like the "turn complete" ribbon. The new penguin pops in 0.6 s after its arena opens, which is when a camera that slides there arrives.
4. **A main agent has finished its turn.** A helper finishing its work never pulls.
5. **A new agent has joined an arena that had room.** Not ticked by default.

When the camera arrives, the focus goes to the agent that pulled it.

Each cause pulls only once. Once the camera has shown it, or the cause has ended (the approval was answered), it does not pull again, although its tab keeps showing it. A pull for a new arena or a finished turn that the camera has not served within 10 s expires; an approval pulls until it is answered.

Two holds stop the camera from being tossed about:

* After any move it stays at least 1.5 s, the same hold as the focus.
* While an approval notice is on screen, it stays 4 s, or until the approval is answered, so the notice can be read.

Without a pull, ordinary activity ("busy arenas" in the switch, ticked by default) moves the camera only when the arena on screen has had no event for 3 s and the camera has been there for at least 5 s. It then goes to the arena with the newest event of the last 3 s. If every arena is quiet, it stays where it is.

A failure in another arena moves the camera only when failures are ticked; otherwise its tab and its page's box turn red. A failure in the arena on screen shakes the room, as with one arena.

### Follow MANUAL

MANUAL is what the 2D view plan calls click mode. It is renamed here because, next to a choice of what pulls the camera, the name says what it does: nothing moves the camera but you.


The camera moves only when you choose an arena: a tab, ← or →, N, or a cell of the overview. New arenas, approvals and finished turns do not move it. Their tabs and page boxes show them: an approval blinks gold, a new arena's tab fades in and blinks green twice, and a new page's box blinks green. If the arena on screen closes, the camera cuts to the arena before it in letter order, or after it if there is none.

Choosing an arena in AUTO switches the mode to MANUAL, because you have taken over; the switch turns blue. F goes back to AUTO, with the same kinds ticked as before.

### The follow switch

What may pull the camera in AUTO is a choice, made in a small menu that opens from the switch at the right end of the bar. Asked for by pgorazda on 2026-11-11, after the scene with ten pages showed that with many agents some kinds of pull come every second or two.

```
 FOLLOW
 [x] ? approvals        1
 [ ] x failures         2
 [x] # new arenas       3
 [ ] + new agents       4
 [x] v finished turns   5
 [x] ~ busy arenas      6
 ---------------------------
 at most 3 moves / 10 s  < >
 ---------------------------
 [ ]   manual only      0
```

* **Six kinds**, each ticked or not: approvals; failures; new arenas; new agents (joining an arena that had room); finished turns, of main agents only; and busy arenas, the move away from an arena that has been quiet for 3 s. Ticking only approvals keeps the camera still while arenas fill, fail and finish; ticking nothing is the same as MANUAL.
* **By default** approvals, new arenas, finished turns and busy arenas are ticked, and failures and new agents are not: with many agents both come every few seconds, and their tabs and page boxes show them anyway. pgorazda confirmed these defaults on 2026-11-11. With many agents they do not narrow by themselves; the pace (below) keeps the camera calm instead.
* **Manual only** at the bottom switches to MANUAL; it keeps the ticks, so F brings them back.
* **The switch shows the choice**: in AUTO a small mark for each kind, lit when it is ticked, in that kind's colour; in MANUAL the word MANUAL on blue.
* **The pace: at most x moves a second.** In AUTO the camera moves by itself at most x times a second, counted over 10 s: 0.3 by default, so at most 3 moves in any 10 s, which still lets it answer a quick burst after a calm spell. When it has moved as often as it may, the next move waits; the pulls keep their order, so the most urgent goes first when the camera may move again, and a pull that expires meanwhile is only shown in the bar. Approvals are let past the pace (pgorazda, 2026-11-11), since someone is blocked until they answer; they still count as moves, so the other kinds wait longer after them. While a move waits, the switch blinks gold, so that a camera that does not move does not look stuck. The menu shows x as moves in 10 s, with arrows to lower or raise it (1 to 10, or no limit). What the person does is never limited. Asked for by pgorazda on 2026-11-11, instead of narrowing the defaults by the number of agents: it limits what is tiring to watch, however many agents there are.
* **Keys**: in the open menu, 1 to 6 tick or untick a kind, [ and ] lower and raise the pace, and 0 is manual only; Esc or a click elsewhere closes it. Demo mode's keys 1 to 3 (speed) apply only while the menu is closed.

### Mouse and keys

| Input | What happens |
|---|---|
| Click a tab | The camera slides to that arena; follow becomes MANUAL |
| Hover over a tab | The row of cards shows that arena's cards, with its letter at the left, until the mouse leaves; the camera does not move |
| Click a penguin or a card | The focus, as in the 2D view plan |
| F | Switches between AUTO, with what is ticked, and MANUAL |
| Click the follow switch | Opens the follow menu: tick or untick each kind of pull (1 to 6), set the pace ([ and ]), or manual only (0); Esc or a click elsewhere closes it |
| ← and → | On an arena: the previous or next arena in letter order, across pages too; follow becomes MANUAL. In the overview: the previous or next page |
| N | The next arena that needs you: the oldest waiting approval, then a failure, then a finished turn; follow becomes MANUAL |
| Tab | The overview on or off, with two arenas or more |
| Click an arena in the overview | Zooms into that arena; follow becomes MANUAL |
| Click a page's box in the list | The overview on that page |
| Esc | Leaves the overview, back to the arena that was on screen |

Entering the overview zooms out from the arena on screen to its page in 0.3 s; leaving it zooms back in, or flies, if the overview has turned to another page. While the overview is on, the camera does not follow anything by itself: an arena that waits for approval blinks gold, and so do the arrow at the edge and the page's box when it is on another page. The overview stays until Tab, Esc or a click, and on the page the person chose: it does not turn to a page that needs them (pgorazda, 2026-11-11), since the page boxes and the arrows at its edges already show where something waits.

AUTO is the default (pgorazda, 2026-11-11); `?follow=manual` starts in MANUAL. Demo mode's keys (Space, and 1 to 3) do not clash with these.

### Arrivals and departures

| Moment | AUTO | MANUAL |
|---|---|---|
| An agent joins an arena that has room | As with one arena, in that arena. If it is not on screen, the agent's chip pops into its tab | The same |
| An agent opens a new arena | The new tab fades in at its place, the camera slides or flies to it, the ribbon says "ARENA C" and the penguin pops in | The new tab fades in and blinks green twice; the camera stays |
| The new arena is the first of a page | A box for the page appears in the list and blinks green, and the overview gets an arrow at its edge | The same |
| An agent leaves | It walks out through the door; its chip leaves the tab | The same |
| An arena is empty | Its tab says "empty" with a dashed outline, and it closes after 30 s. If the camera is there, it goes to the arena with the newest event | The camera stays until the arena closes, then goes to a neighbour. Meanwhile the row of cards says when the arena closes |
| An arena closes | Its tab shrinks away and its place stays free; nothing else moves. If it was the last arena of its page, the page goes | The same |
| Only one arena is left | The list disappears and the bar is the one-arena bar again | The same |

### An afternoon, step by step

| Time | What happens | On screen, in AUTO |
|---|---|---|
| 0:00 | #1 (claude-code) arrives | Arena A, as today, with no list |
| 0:40 | #2, #3 and #4 arrive | Arena A with four penguins |
| 1:10 | #5 (hermes) arrives; A is full | The list appears with tab A, and tab B slides in. The camera slides to B, the ribbon says "ARENA B", #5 pops in |
| 1:14 | #2, in A, asks for approval | B has been on screen for more than 1.5 s, so the camera slides back to A at once. Tab A blinks gold; the notice names #2 |
| 1:16 | #6 (pi) arrives and goes to B, which has room | The camera stays on A; chip 6 pops into tab B |
| 1:17 | #6 fails, in B | Tab B turns red; the camera stays on A |
| 1:21 | #2's approval is answered | The camera stays: A is not quiet yet |
| 1:25 | A has been quiet for 3 s, and B is busy | The camera has been on A for more than 5 s, so it slides to B |
| 1:40 | You click tab A | The camera slides to A, and the switch says MANUAL |
| 1:45 | #5, in B, finishes its turn | Tab B says DONE; the camera stays on A |
| 1:50 | You press Tab | The overview: A and B side by side |
| 1:52 | You click B's cell | The overview zooms into B |
| 1:55 | You press F | AUTO again |

## The scenes

![Several arenas in the Godot client: the camera slides to a new arena B; an approval in A brings it back while B's tab shows its agents; in MANUAL a new arena C opens without moving the camera; the overview behind Tab, with the cards of the arena under the mouse](images/arena-2d-arenas.png)

The scene `arenas` plays a 43 s afternoon of nine agents in three arenas (`godot/demo/arenas.json`); `node godot/tools/record.mjs --scene arenas` records it. Only the agents' work and the person's clicks and keys are scripted. The arena model places the agents, and the camera, the follow mode and the focus come from simulating the rules above with the starting values (`godot/src/core/arena_rules.gd`, ported from the mockup's `arena-rules.js`, with its 34 tests). Its camera does this, none of it scripted:

| Time | What happens | The camera |
|---|---|---|
| 0.5 to 3.5 s | #1 to #4 arrive | Arena A, with no list |
| 7.0 s | #5 arrives; A is full | B opens and pulls the camera; ribbon "ARENA B" |
| 9.7 s | #2, in A, asks for approval | Back to A at once; tab A says WAIT |
| 13.8 s | #6, in B, fails | Stays on A; tab B says FAIL |
| 16.6 s | A has been quiet for 3 s, and B is busy | To B |
| 21.5 s | #1, in A, finishes its turn | To A, for the confetti |
| 23.2 s | The mouse hovers over tab B | The cards row shows B's cards; the camera stays |
| 24.0 s | A click on tab B | To B; follow switches to MANUAL |
| 26.0 s | #9 arrives; A and B are full | C opens; its tab blinks green; the camera stays |
| 29.9 s | #8, on screen in B, fails | The room shakes |
| 30.5 s | Tab | The overview; the mouse hovers over B, then C |
| 34.0 s | A click on C's cell | Zooms into C; ribbon "ARENA C", because C is seen for the first time |
| 36.0 s | F | AUTO again |
| 37.5 s | #3, in A, asks for approval | From C up to A: C is below A on the page |

`?reduced=1` shows what reduced motion does: every move becomes a short cut, and the room does not shake.

What it showed:

* The rules as written give the storyboard above without any camera move being scripted, so they are at least consistent. Whether they feel right is for a person watching the clip to say; the numbers are untouched.
* The ribbon of a new arena must not sit where the "turn complete" ribbon goes, above the workbenches where penguins stand, nor on the rug, where the new penguin arrives and its label would hide under it. It sits on the wall, where nothing plays.
* The focus rule of the 2D view plan needs one more word: a failure, approval or finished turn of the agent that already has the focus counts as seen. Without that, as in the multi-agent scene, the focus stays on that agent until the next such event, whatever the others do. The arena rules do this; the multi-agent scene is unchanged.

### More than four arenas

![Nine arenas on three pages in the Godot client: a fly from page 1 to page 2, the pages as separate 2x2 matrices; the overview of page 2 as a third page appears (its box blinks green); the third page, with arena I and three free places; the overview scrolling past page 2 after a click on the box of page 3](images/arena-2d-many-arenas.png)

The scene `many` (`godot/demo/many.json`) plays a busy 53 s afternoon of 34 agents in nine arenas on three pages, with the same rules and starting values; `node godot/tools/record.mjs --scene many` records it. The story is pinned: who arrives, asks, fails or finishes, and when. The rest of each agent's afternoon is ordinary work written by a seeded generator, which never puts two penguins on one spot at once.

| Time | What happens | The camera, and the screen |
|---|---|---|
| Before the clip | A to E are full and F has two agents: 22 agents on two pages | Arena A, on page 1; the bar shows A to D and the boxes 1 and 2 |
| 2.0 and 3.0 s | #23 and #24 fill F | |
| 4.0 s | #25 arrives; A to F are full | G opens on page 2: the camera flies from A to G, out to the size of a page and in again |
| 6.0 to 9.0 s | #26 to #28 join G | Agent numbers have two digits: the tabs show pips |
| 11.0 s | #29 arrives | H opens next to G: a slide sideways, on the same page |
| 13.2 s | #6, in B on page 1, asks for approval | A fly back to B |
| 15.8 s | #18, in E on page 2, fails | Stays; the box of page 2 turns red |
| 17.0 s | Tab | The overview of page 1, with an arrow at the right edge for the pages after it |
| 18.5 s | → | The overview scrolls to page 2 |
| 22.0 s | #33 arrives; A to H are full | I opens on a new page 3: its box appears and blinks green, and so does the arrow at the right edge; the overview stays where it is |
| 23.5 s | → | Page 3: I, and three free places |
| 25.0 s | A click on I | Zooms into I; ribbon "ARENA I"; follow is MANUAL |
| 27.0 s | ← | To H, the arena before I: a fly back to page 2 |
| 29.2 s | #2, in A, asks for approval | Stays (MANUAL); the box of page 1 blinks gold |
| 30.0 s | N | A fly to A |
| 32.0 s | F | AUTO again |
| 38.2 s | #33, in I, asks for approval | A fly from A to I, two pages away |
| 41.7 s | #16, in D, finishes its turn | A fly back to D |
| 46.0 s | Tab | The overview of page 1 |
| 47.5 s | A click on the box of page 3 | The overview scrolls past page 2 to page 3 |
| 49.5 s | Esc | A fly back to D |

What it showed:

* **One mechanism for any number of arenas.** The bar and the overview always show one page of four, and both turn page by page. Nothing in the scene depends on there being three pages; the next scene has ten. This replaced a first version of the scene, which stretched the overview to a 3×2 grid at a third of the size and stopped at five arenas, because neither the grid nor the bar went further.
* **The page boxes carry the pages that are not shown.** An approval or a failure on another page shows on its box, and in the overview on the arrow at that edge.
* **Places that do not move are easier to follow.** An arena keeps its place on its page; a closed arena leaves a free place, and the next new arena fills it. On the strip of the first version, closing an arena moved every arena after it.
* **Flies instead of long slides.** On a page the camera slides, also up and down; to another page it widens to the size of a page midway. On the strip of the first version, a move from E to A flashed three rooms by in 0.8 s. The pages read as separate matrices only with a gutter between them: without one, a fly showed a single wall of rooms.
* **Two-digit numbers do not fit a tab.** From #10 on, four chips and a state do not fit in 80 px. The tabs then show pips in the cord colours, gold while waiting and red after a failure; the numbers stay on the cards, above the penguins and in the overview.
* **With every arena busy, AUTO only goes where it is needed.** The arena on screen is never quiet for 3 s, so every move of the camera came from a pull or from the person. AUTO is calmer with many agents than with few.
* From the first version, which had agents leave and an arena close: an agent that was not shown takes the first place freed, even in an arena that is emptying, so an arena only closes when nobody waits; and a place is freed when its agent starts walking out, so for about a second a room shows five penguins. The rules have not changed, and the tests cover them.

### Ten pages

![Forty arenas on ten pages in the Godot client: a long fly from page 1 to page 7, the pages passing by small with their numbers; arena Z on page 7, with five page boxes in the list and the arrow for the pages before them red after a failure on page 4; the overview of page 10, where AN has not opened yet; arena O in MANUAL while an approval waits on page 9, beyond the boxes, so the arrow at their right end blinks gold](images/arena-2d-ten-pages.png)

The scene `ten` (`godot/demo/ten.json`) plays 54 s of 157 agents in forty arenas, A to Z and AA to AN, on ten pages, with the same rules and starting values; `node godot/tools/record.mjs --scene ten` records it. As in the scene before it, the story is pinned and the rest of the work is written by a seeded generator.

| Time | What happens | The camera, and the screen |
|---|---|---|
| Before the clip | 150 agents fill A to AK and half of AL: nine full pages and half of the tenth | Arena A; the list shows the boxes 1 to 5 and an arrow for the pages after them |
| 5.7 s | #102, in Z on page 7, asks for approval | A long fly from page 1 to page 7: the view widens to about four pages, which pass by with their numbers |
| 8.7 s | #54, in N on page 4, fails | Stays; page 4 is beyond the boxes 5 to 9, so the arrow at their left end turns red |
| 10.7 s | #22, in F on page 2, asks for approval | A long fly back to page 2 |
| 14.2 s | AM opens on page 10 | A fly across eight pages; ribbon "ARENA AM" |
| 17.0 s | Tab | The overview of page 10: AK, AL, AM and a free place |
| 18.0 to 23.6 s | ← nine times | The overview turns back through all ten pages, one at a time; the boxes follow |
| 25.5 s | A click on the box of page 4 | The overview scrolls three pages, widening a little on the way |
| 28.0 s | A click on O | Zooms into O; follow is MANUAL |
| 30.2 s | #134, in AH on page 9, asks for approval | Stays (MANUAL); page 9 is beyond the boxes, so the arrow at their right end blinks gold |
| 31.5 s | N | A fly to AH |
| 33.5 s | F | AUTO again |
| 36.2 s | #10, in C on page 1, asks for approval | A fly across eight pages |
| 40.0 s | AN opens, the last place of page 10 | A fly across nine pages; ribbon "ARENA AN" |
| 44.3 s | #42, in K on page 3, finishes its turn | A fly back to page 3 |
| 49.0 s | Tab, then → three times | The overview of page 3, then pages 4, 5 and 6 |

What it showed:

* **The mechanism holds at ten pages.** Nothing else had to change: the bar's tabs, the overview, the slides, flies and scrolls work the same for forty arenas as for nine. Two things did: names after Z, and a window of five page boxes, because ten boxes do not fit beside the tabs.
* **The arrows at the ends of the boxes matter.** With ten pages most are beyond the boxes, and the arrows are what shows a failure or an approval there.
* **Long flies need to widen more.** Crossing up to nine pages at the size of one page smeared them; widening by about a page for each page crossed (up to four pages across) keeps them readable, and their numbers say where the camera is going. The world is one page high, so a wide view shows the pages as a strip with empty space above and below it; pages arranged in rows would fill the screen better on a long move, but would lose the simple left-to-right order of the list.
* **Turning through ten pages one at a time takes six seconds.** A person who knows where to go uses a box (or N for what needs them); ← and → are for looking around.
* **At this scale, finished turns would pull too often.** The story has a few approvals and one finished turn. With 150 real agents, a turn finishes every second or two, so if each one pulled, the camera would never rest. Open question: with many agents, should only approvals pull the camera?
* **It stays fast.** The camera's rules read events with a pointer per arena, so the 157 agents are simulated in a fraction of a second, and only the rooms in view are drawn.

### The follow switch

![The follow switch in the Godot client: with every kind ticked, a failure pulls the camera in time to see the flop; after an approval let past the pace, a failure waits for it, and the switch blinks gold; the follow menu with only approvals ticked and the pace lowered to 2 moves in 10 s; approvals only again, where a failure on page 1 only turns its box red](images/arena-2d-follow-switch.png)

The scene `follow` (`godot/demo/follow.json`) plays 50 s of 33 agents on two and then three pages; `node godot/tools/record.mjs --scene follow` records it. It starts with every kind ticked, so that the difference shows, and with the default pace.

| Time | What happens | The camera, and the screen |
|---|---|---|
| 2.6 s | #10, in C, fails | Everything ticked: the camera slides to C and arrives during the flop |
| 3.0 s | #31 joins H | To H, after the hold |
| 5.9 s | #18, in E, finishes its turn | To E: three moves in four seconds |
| 8.7 s | #6, in B, asks for approval | To B at once: approvals are let past the pace |
| 11.0 s | #28, in G, fails | Held back by the pace while the switch blinks gold (after B's notice has been read); to G at 14.6 s, when fewer than three moves are younger than 10 s |
| 16.0 to 19.8 s | The person opens the menu, unticks failures, new arenas, new agents, finished turns and busy arenas, and lowers the pace to 2 moves in 10 s | The switch shows only the mark for approvals |
| 20.5 s | #32 joins H | Stays; chip 32 pops into H's tab |
| 23.7 s | #22, in F, fails | Stays; the box of page 2 turns red |
| 24.5 s | #26, in G, finishes its turn | Stays; G's tab says DONE |
| 26.9 s | #14, in D, asks for approval | A slide to D: approvals still pull |
| 30.0 to 30.9 s | The menu again: manual only | The switch says MANUAL |
| 33.0 s | #33 opens I on a third page | Stays; the box of page 3 appears and blinks green |
| 35.4 s | #27, in G, asks for approval | Stays; the box of page 2 blinks gold |
| 37.0 s | N | To G |
| 40.0 s | F | AUTO again, with approvals only and the lower pace, as it was left |
| 42.3 s | #2, in A, fails | Stays; the box of page 1 turns red |
| 44.8 s | #33, in I, asks for approval | A fly to I on page 3 |

What it showed:

* **Approvals only keeps the camera still while the arenas fill, fail and finish**, and the bar still shows all of it: chips popping into tabs, red and DONE in tabs, page boxes turning red, gold or green. That answers the scene with ten pages, where finished turns would have pulled every second or two.
* **A failure pull arrives in time to see the flop** when the arena is on the same page (a slide of 0.5 s against a flop of 1.8 s), and catches the end of it from the next page. So the reason for leaving failures unticked by default is how often they come with many agents, not the timing.
* **The pace holds back the move that would be one too many, but never an approval.** Here the approval went straight through after three quick moves, and the failure after it waited: by the time the camera got to G, 3.6 s later, the flop was over and only FAIL on the card told of it. With approvals only, the pace never holds anything back.
* **MANUAL keeps the ticks and the pace**: F brought back approvals only and 2 moves in 10 s, not everything.
* **Six marks fit in the switch**, next to five page boxes and their arrows, with a few pixels to spare (the word MANUAL too); there is no room for a seventh kind without narrowing something else.

## Design

### Layout

New files next to those of the 2D view plan:

```
web/src/view2d/
  arenas2d.js     the arena model: who is where, letters, colours, leaving, closing (tested in Node)
  camera2d.js     what is on screen, an arena or a page: pulls, holds, AUTO and MANUAL, the follow switch, slides, flies, zooms, scrolls (tested in Node)
  art/overview2d.js   the overview: a page of four behind Tab, its labels and the arrows at its edges
```

As in the 2D view plan, drawing code goes in `art/` (all rights reserved, see LICENSE-ASSETS); the models stay MIT.

Changes elsewhere:

* `view2d.js` updates the arena model and the camera every frame, draws what the camera sees at its scale, and handles the keys and clicks.
* `art/props2d.js` draws the room once per arena, with its sign and its rug, and caches it, as it caches the one room now.
* `art/log2d-art.js` draws the list of arenas (a page's tabs and the page boxes) and the cards of a hovered tab.
* The spots and the queue of the 2D view plan work per arena.
* The director gets two settings. Both are off by default, so the director on its own behaves as before:
  * `leaveAfter`: an agent that has sent nothing for this long is removed, unless one of its tool calls or approvals is open. The 2D view with arenas sets it to 600 s.
  * `maxPenguins`: today's limit of 12, as a setting. The 2D view with arenas raises it; how far is open (ten pages of four arenas of four agents would be 160 penguins, with their helpers on top).

### Choices

1. **Arenas belong to the 2D view, not to the director.** The director and the actor keep one world. The 2D view decides which room it draws each agent in, and projects the actor's floor position into that room. Two penguins in different arenas can stand on the same floor position.
2. **Two models with no drawing in them.** `arenas2d.js` and `camera2d.js` take events and the simulation clock and return their state. Node tests step them with a fake clock, as the actor's tests do.
3. **Arenas not on screen keep running but are not drawn.** Their penguins keep working. Effects are functions of the clock, so an arena that comes on screen in the middle of its confetti shows it correctly.
4. **Places come from letters.** An arena's place on its page comes from its letter, so nothing moves when another arena opens or closes, and the camera needs nothing but an arena's letter to find it.
5. **One renderer for every scale.** The view draws whatever the camera covers: each room into its own 480×232 buffer, placed on whole pixels at the scale of one arena and scaled down with smoothing otherwise, and the overview's labels on top at full size, so the text stays sharp. Scaling pixel art to half size without smoothing would drop every other row and column of it. Only the rooms in view are drawn, so the cost does not grow with the number of arenas.
6. **Debug.** `window.__agentWorkshop.arenas` lists the arenas, their agents and states, and the camera's arena, mode and pending pulls, for the tests.
7. **Determinism.** The camera runs on the simulation clock, so a demo looks the same every time.

### Starting values

Every number here is a guess. The Godot client uses them as they are (`DEFAULTS` in `godot/src/core/arena_rules.gd`), so changing one there shows what it does.

| What | Starting value |
|---|---|
| Agents in an arena | 4 |
| Arenas at most | no limit of their own; names go on after Z (AA, AB, …) |
| Page boxes in the list | at most 5, around the page in the list, with an arrow at either end for the pages beyond |
| A long fly or scroll widens the view | by about a page for each page it crosses, at most 8 rooms across |
| A slide, to an arena of the same page | 0.5 s |
| A fly, to an arena on another page | 0.7 s to the next page, 0.15 s more for each page further, at most 1 s |
| A scroll of the overview | 0.5 s to the next page, 0.15 s more for each page further, at most 0.8 s |
| The gutter between pages | 0.1 of a room (48 px at the scale of one arena) |
| Hold after a move | 1.5 s |
| Hold while an approval notice is on screen | 4 s, or until it is answered |
| An ordinary move (busy arenas) | after 3 s without an event on screen, and at least 5 s there |
| What pulls the camera in AUTO | approvals, new arenas, finished turns and busy arenas; not failures or new agents |
| The pace: moves the camera makes by itself | at most 0.3 a second, counted over 10 s (3 in any 10 s) |
| A pull for a new arena or a finished turn expires after | 10 s |
| An agent leaves after | 10 minutes without an event, with no tool call or approval open |
| An empty arena closes after | 30 s |
| Zooming in or out of the overview | 0.3 s |
| The first penguin of a new arena pops in after | 0.6 s |

## Testing

* **Unit tests** (`node --test`):
  * the arena model: filling up in letter order; helpers in their parent's arena; going back to an old arena; a new arena when all are full; names after Z; a limit that can be set, and "+N not shown"; leaving after 10 minutes, but not with a tool call or an approval open; closing after 30 s, but never the last arena; the lowest free letter used again;
  * the world: the places of the arenas on their pages, pages with no open arena skipped; how far a long move widens the view;
  * the follow switch: each kind pulls only when ticked, the defaults, manual only and F keeping the ticks; the pace holding a move back, the most urgent pull going first, a changed or lifted pace, the person never limited;
  * the camera: slides on a page, flies between pages that widen to a page midway, the view staying inside the world, the overview turning page by page and opening on a page chosen in the list; the order of the pulls; each pull served once; expiry; both holds; the quiet rule; a failure elsewhere never moves it; MANUAL never moves it except when its arena closes; choosing an arena switches to MANUAL; a new target during a slide; a cut instead of a slide with reduced motion;
  * a tab's state: WAIT before FAIL, before running, before DONE, before idle, before empty.
* **Browser test**, with `?demo=four-agents&arena-size=2` (needs the demo plan's phase 5c): two arenas open; an approval in the other arena brings the camera; a click on a tab moves the camera and switches to MANUAL; Tab shows the overview and Esc leaves it; there are no page errors.
* `?arena-size=12` shows no list of arenas, as the one-room view.
* The rules' tests were in the mockup. They are ported to `godot/test/test_arena_rules.gd`.
* The look test of ADR 0004 covers the new files.
* **Screenshots** for a person to look at: halfway through a slide and through a fly, three tabs showing WAIT, FAIL and DONE, the page boxes, and the overview of a full page and of a page with free places.

## Phases

The arenas come after phase 2D-3 of the 2D view plan, which brings the chips, the focus and the cards. Each phase leaves every test green.

| Phase | Content | Done when |
|---|---|---|
| A-0 | Mockup scenes `arenas` (an afternoon like the one above), `many` (nine arenas on three pages), `ten` (forty arenas on ten pages) and `follow` (the follow switch), to try the rules and tune the numbers before the view exists. The JavaScript mockup is removed; the Godot client plays the scenes from `godot/demo/` | Recorded on 2026-11-11, and again with `node godot/tools/record.mjs --scene <name>`. The starting values are confirmed or changed (waiting for review) |
| A-1 | The arena model and its pages, the director's two settings, spots per arena, the sign and the rug per arena, the list of arenas with its page boxes; ← and → cut between arenas | The model tests pass; with `arena-size=2`, four agents open two arenas |
| A-2 | The camera: slides and flies, AUTO and MANUAL, the follow switch and its menu, N, reduced motion, the ribbon of a new arena | The camera tests pass; the browser test sees an approval bring the camera |
| A-3 | The overview, its scrolling and the arrows at its edges, and the cards of a hovered tab | The browser test of Tab, Esc and a click; screenshots reviewed against ADR 0004 |

Rough size: 450 to 600 lines in `web/src/view2d/` and about 250 lines of tests; the mockup scene of A-0 about 350 lines.

## Risks

* A camera that moves by itself can annoy more than it helps, above all with many busy agents. The holds and the quiet rule are guesses until the mockup plays them. MANUAL is the way out.
* Something in an arena that is not on screen can be missed. Its tab and its page's box show WAIT and FAIL, and N goes there, but a person looking elsewhere sees neither.
* Which arena an agent lands in is arbitrary: two sessions on the same repository can end up in different arenas. Grouping by project would fix that, but needs the schema.
* Leaving after 10 quiet minutes is new. An agent that waits longer for its user goes away and comes back as a new arrival, with a new number, and perhaps in another arena if its old one has filled up.
* The rug colours sit next to the cord colours: the cobalt rug near OpenCode's blue cord, the yellow rug near Hermes's gold one. The letter stays the name, and a tab's plate must not look like a chip.
