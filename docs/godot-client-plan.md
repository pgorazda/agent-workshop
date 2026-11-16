# Plan: the Godot client

**State: phases G-0 to G-10 are done (G-4 to G-10 on 2026-11-16, the others on 2026-11-15). G-9 is done for Windows only: the owner postponed the Linux and macOS exports, and tablets. G-10 removed the JavaScript mockup; it is in the git history. The owner waived some conditions of that removal (see "The two code bases"). The owner listened to the sound and found it fine.** The rest is a plan. The decision is ADR 0008 (accepted on 2026-11-15). It replaces the drawing technology of the browser client (ADR 0002 and ADR 0003) with a Godot 4 project. The look (ADR 0004), the license split (ADR 0006) and the sound made by code (ADR 0007) stay as the source of the art. The client plays the result as image and sound files, which the old code renders at build time. The rules of the [2D view](2d-view-plan.md) and of the [arenas](2d-arenas-plan.md) stay too. This plan changes only how the client is built.

## Goal

A Godot 4 project in `godot/`, written in GDScript. It reads the bridge's WebSocket stream (`/ws`) and shows the workshop as the 2D mockup shows it today. It exports downloadable apps for Windows, macOS and Linux. Tablets and other mobile devices are postponed (see "Decided").

The client is ready when:

* every mockup scene plays in it (default, `multi`, `arenas`, `many`, `follow`, `ten`, `tour`);
* a real session from the bridge plays on one desktop platform (ADR 0008 is accepted, and this session is the proof that the decision holds on desktop; the tablet proof is postponed with tablets; if the proof fails, a new ADR replaces ADR 0008);
* the `ten` scene keeps 60 fps during long camera moves on a named reference machine;
* the app stays light beside a coding agent: it meets the budgets for CPU, memory and start-up (see "Performance").

Not in scope: changes to the schema, the adapters or the bridge, a 3D view, and a bridge that listens on the local network (see "Open questions"). This plan writes no ADR.

## Decided by the project owner on 2026-11-15

1. **Sound is audio files.** The existing JavaScript synthesiser renders them at build time. No synthesiser is ported to GDScript. See "Sound".
2. **The test framework is kept in the repository.** GUT is vendored in `godot/addons/gut/`. See "Testing". The Godot editor is not kept in the repository (item 7).
3. **The app must be fast and light.** It runs on the same machine as a coding agent. So its cost beside the agent is a goal of its own, with budgets for CPU, memory and start-up. See "Performance".
4. **Images are static files, like the sounds.** The existing JavaScript art code renders the sprites, the props, the rooms and the glyphs into PNG files at build time. The client loads them. Only what depends on data or time at each frame is drawn by GDScript. See choice 8. This drops the sprite code from the port and the start-up cost of making textures.

5. **The language stays GDScript for now.** C# with Godot .NET was considered. It would allow tests with `dotnet test`, and it is faster. Its Android and iOS export is marked experimental, and its runtime may add start-up time, memory and size. The owner chose GDScript for now. To revisit, run a spike first: export a small C# project and a GDScript one to a desktop and a tablet, and compare start-up, memory and size with the budgets. Do not mix the two languages.
6. **The reference machine is a low-end laptop with 8 GB of memory.** The speed and cost budgets use it. The agent, the editor and a browser share that memory with the client. See "Performance".
7. **The Godot editor is downloaded, not stored.** A script downloads the pinned version from godotengine.org and checks its hash. The repository does not hold the editor.
8. **ADR 0008 is accepted** (2026-11-15). ADR 0003 and ADR 0007 have notes that say what changed. ADR 0002 is now `superseded by ADR-0008`.
9. **Tablets and other mobile devices are postponed** (2026-11-15). This covers Android and iOS exports, touch controls (open question 5), a bridge on the local network (open question 1), the `adb reverse` path, and every run on a tablet. Keep the door open: no desktop-only call in `src/core/`, and the 480×270 viewport with integer scaling stays. Work that waits: the G-9 mobile exports, the touch part of G-6, risk 5.
10. **Sound files are WAV.** Not OGG. Spike S-4 now only checks that one exact loop per tune renders, and fixes the sample rate and the size.
11. **The engine stays Godot.** A Rust engine or library (macroquad, Bevy) and other engines (Defold, Flutter with Flame, MonoGame) were considered for broader devices. The owner chose to stay with Godot. Revisit only if the first measurement of idle memory and CPU on the reference machine is far over the budgets. A new engine would need a new ADR.

## What already exists

This table describes the state before phase G-0. The JavaScript mockup is removed now (phase G-10). Its files are in the git history.

| Piece | Where it is now | What to do with it |
|---|---|---|
| Event stream | Bridge, `WS /ws`. Each connection first gets `{"v":1,"type":"hello"}`. The bridge keeps no history for late clients | Use as it is |
| Event schema | [`schema/event.schema.json`](../schema/event.schema.json) | Read the same fields. Keep the enums in step (a test) |
| Example sessions | [`schema/examples/`](../schema/examples/) and `npm run replay` in `bridge/` | Fixtures for tests and for the replay check |
| Arena rules, with no drawing, and their 34 tests | `arena-rules.js` and `arena-rules.test.mjs` of the mockup (removed in G-10) | Port to GDScript with the same cases |
| Drawing and sound code (about 120 KB of JavaScript) | The art code of the mockup (removed in G-10) | Move `look.js` and `sound.js` to `godot/art/` as the source that renders image and sound files. Port the code that draws each frame (effects, interface) to GDScript |
| Scripted scenes, recorder, tests | The mockup (removed in G-10) | Scenes become data. The recorder gets a Godot counterpart |
| The behaviour modules (event parsing, director, actor, clock, bridge client, timeline player) | Only planned: [the client plan](browser-client-plan.md) and [the demo mode plan](demo-mode-plan.md). **Not written in any language** | Write them in GDScript, from those designs |

The last row matters. The mockup does not read events. It plays hand-written timelines, and every frame is a function of the time (`renderAt(t)`). The Godot client must be event-driven, with a state that moves forward. So the choreography of `crowd.js` is not ported. It is written again as a live actor (see choice 5).

## Design

### Godot version

Pin one stable Godot 4 version in a file, `godot/GODOT_VERSION`. Every script and the container read it. The export templates, the test framework and the CI image use the same version.

Which version: **Godot 4.7.x**, chosen by the owner on 2026-11-15. The owner named 4.7.2. When phase G-0 starts, take the newest 4.7 patch release that godotengine.org lists, and write its exact number in `GODOT_VERSION`. Do not move to 4.8 or later without a new decision: each minor version needs new export templates and a matching GUT release. The Godot .NET build is not used (the language is GDScript). **The 4.7 line and its patch releases were seen only in third-party listings, not on the official site.** Search results said that GUT has a branch for 4.7 (`godot_4_7`); check that it exists and works (spike S-2).

Use typed GDScript. Treat GDScript warnings as errors in the check script.

### Layout

```
godot/
  GODOT_VERSION        the pinned Godot version
  project.godot        2D only, Compatibility renderer, 480x270 viewport, integer scaling
  export_presets.cfg   no secrets: signing data comes from the environment
  README.md            how to run, test, record and export
  src/                 MIT: everything that is not art
    main.tscn, main.gd start-up, options, the frame
    core/              no nodes, no drawing: RefCounted classes, tested headless
      event.gd           parse a schema v1 event; category enum (checked against the schema)
      clock.gd           the simulation clock: fixed steps
      rng.gd             mulberry32, with 32-bit masking
      stations.gd        the station table (the client plan)
      spots.gd           spots and the queue per station (the 2D view plan)
      director.gd        one penguin per framework + session + agent, helpers, limits, the backlog rule
      penguin_actor.gd   the event queue and the behaviour: position, facing, pose
      focus.gd           the focus: AUTO and MANUAL, the hold
      log_model.gd       the activity log and the cards
      arena_rules.gd     port of arena-rules.js: names, pages, moves, the camera
      sound_model.gd     which event plays which sound; the sound state
    net/
      bridge_client.gd   WebSocketPeer, reconnect every 2 s, at most 64 events per frame
      timeline_player.gd demo mode: plays a timeline file on the same clock
    view/              glue that calls the art: depth order, projection, input, camera view, scene menu
  art/                 all rights reserved: the art, as code and as files (see LICENSE-ASSETS)
    draw_kit.gd        the drawing primitives for _draw: pixel, fill, box, ellipse, line, bitmap, icon, text
    text_art.gd        text drawn from the glyph atlas
    effects_art.gd  log_art.gd  crowd_art.gd  arenas_art.gd  overview_art.gd  tour_art.gd  sound_ui_art.gd
    atlas_data.gd      generated: the name and the rectangle of every picture in the atlases
    images/            PNG files: sprite atlases (penguins by cord colour, props), the rooms (one per rug colour), the glyph atlas, the app icons
    sound/             four tunes and five event sounds (audio files)
    MANIFEST.txt       the SHA-256 hash of every file in images/ and sound/
    image_src/         look.js: the JavaScript art code that renders images/ (moved from the mockup)
    sound_src/         sound.js: the JavaScript synthesiser that renders sound/ (moved from the mockup)
  addons/gut/          GUT, kept in the repository, with its MIT license file
  fonts/               the OFL texts of Tiny5 and Silkscreen (and the font files only if spike S-3 needs them)
  demo/                scene timelines (JSON, made up, no real data): session, multi, arenas, many, follow, ten, tour
  test/                GUT tests; fixtures/ holds data made from the JavaScript reference
  tools/               get-godot.mjs, record.mjs, render-art.mjs, render-sound.mjs, export-scenes.mjs, dump-fixtures.mjs, license.test.mjs, Dockerfile
```

Every `.gd` file in `godot/art/` starts with this header. A GDScript comment starts with `#`:

```
# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
```

The art folder holds `.gd` files, image and sound files, and the JavaScript that renders them. It holds no scenes, resources or shaders. Each kind has its own rule in the license check (see "Testing"). A `.js` file there starts with the same two lines behind `//`. The generated `atlas_data.gd` starts with the header too.

### Choices

1. **One low-resolution viewport.** The project is 480×270 with `stretch/mode = viewport` and `scale_mode = integer`. Leftover window space shows the log's background colour. This is choice 2 of the 2D view plan.
2. **The Compatibility renderer.** The client is 2D only. This renderer runs on the widest range of devices and has a software path for recording. **Not verified.**
3. **The core has no nodes.** Everything in `src/core/` is a `RefCounted` class that takes events and a clock and returns state. GUT tests run these classes headless, with no renderer. This is choice 2 of the arenas plan.
4. **Fixed steps and a continuous camera.** The simulation advances in steps of 1/60 s, whatever the frame rate. The camera's decisions use the rule step of 1/30 s (`DEFAULTS.step`), and the camera pose is a function of the time (`poseAt`), so it is smooth. A recording at 30 fps and a play at 144 fps show the same story.
5. **A live actor in place of generators.** Choice 5 of the client plan uses JavaScript generators. GDScript has none. The actor is an explicit state machine with an event queue and a list of motion segments, stepped by the clock. `await` is not used, because a test cannot step it frame by frame.
6. **Scenes are data.** Each mockup scene becomes a timeline: schema v1 events with times, plus the person's clicks and keys. A Node tool makes the files from the mockup (see phase G-4). The timeline player is also demo mode of the demo mode plan. It runs with no bridge, so a tablet can play every scene.
7. **Arenas in one world.** All arenas have a place in one world, as the arena rules define it (pages of four, with a gutter). Arenas that are not in view are hidden and do not draw. How a room is drawn when it is scaled down needs a spike (see "Risks", item 3).
8. **Bake what is a fixed picture. Draw what depends on data or time.** `tools/render-art.mjs` runs `look.js` in headless Chromium and saves PNG files: the penguin in every pose, direction and frame for each cord colour; the props; one room for each rug colour; the 7×7 icons and the sparks; and a glyph atlas of the pixel font. `atlas_data.gd` names every picture and its rectangle. Textures use nearest filtering and no compression. The client draws the rest with `_draw`: effects (dust, sparks, smoke, confetti, the candle), notices, ribbons, the bar, cards, tabs, boxes, the overview and the follow switch. Those are rectangles, lines, pictures from the atlas and text from the glyph atlas. A shape that is fixed goes into a file. A shape that changes by the pixel at each frame is drawn.
9. **The bridge address.** On desktop: `-- --bridge=ws://127.0.0.1:8787/ws` on the command line, with that value as the default. On tablets, which have no command line: a setting kept in `user://`. The app sends no `Origin` header when native (**not verified**), so the origin checks planned for the bridge do not block it.
10. **Hidden or paused app.** The engine may stop or slow down. Mobile systems suspend an app and close its socket. The client reconnects, and the director applies the backlog rule of the client plan (choice 7): when a queue is longer than about 20, drop the oldest finished calls.
11. **Determinism.** Effects use the simulation clock and the seeded random numbers. No code reads the wall clock for the picture.
12. **The schema stays the contract.** The client reads only schema fields and picks stations by `category`, never by tool name (rule 2). A test compares the category list in `event.gd` with the schema.
13. **Light beside an agent.** The client runs next to a coding agent, often visible but not focused. It caps its frame rate when it has no focus, stops drawing when it is minimized, does no synthesis at run time, and keeps per-frame work small. The budgets are in "Performance".

## Mapping: the mockup to the Godot project

"Hard" marks the parts that do not port line by line.

| Mockup file | Godot counterpart | Notes |
|---|---|---|
| `arena2d.html` | `src/main.tscn`, `src/main.gd` | URL options become command-line arguments and settings. The scene menu becomes a menu in the app |
| `base.js` (canvas, `mulberry32`, overlays, warm-ups) | `core/rng.gd`, start-up code in `view/` | **Hard, small:** `Math.imul` and `>>>`. Mask to 32 bits after each multiply. A test compares the first outputs with JavaScript |
| `player.js` (play, pause, keys, sound state, scene menu, `renderAudio`) | `view/scene_player.gd`, `core/sound_model.gd` | Keys need touch counterparts (see "Open questions"). `renderAudio` is used only by `tools/render-sound.mjs` (see "Sound") |
| `record.mjs`, `Dockerfile` | `tools/record.mjs`, `tools/Dockerfile` | Movie Maker mode replaces `window.renderAt` and the page. See "Recording" |
| `session.js` | `demo/session.json` | The scripted session becomes a timeline. The page start-up code goes to `main.gd` |
| `multi-agent.js`, `arenas.js`, `arenas-many.js`, `arenas-ten.js`, `arenas-follow.js` (scene data) | `demo/*.json`, made by `tools/export-scenes.mjs` | The play code of `arenas.js` becomes `view/scene_player.gd` |
| `tour.js`, `art/tour-art.js` | `demo/tour.json`, `art/tour_art.gd` | The tour stops the scene clock but not the clip clock. The last phase to port |
| `crowd.js` (choreography, spots, cards, focus label, sound cues, `fillWork`) | `core/penguin_actor.gd`, `spots.gd`, `director.gd`, `focus.gd`, `log_model.gd`, `sound_model.gd` | **Hard:** the mockup scripts the motion, the Godot client reacts to events. `fillWork` stays in the Node export tool |
| `arena-rules.js` | `core/arena_rules.gd` | **Hard:** nested closures, sorts, rounding (see "Porting traps"). The batch camera must become incremental |
| `arena-rules.test.mjs` (34 tests) | `test/test_arena_rules.gd` | Same cases, same names (see "Testing") |
| `license.test.mjs` | `tools/license.test.mjs` | Header is `#`. Adds the check for drawing code outside `art/` |
| `page.test.mjs` | A test that the scene menu lists the files in `demo/` | |
| `art/look.js` (palette, `Spr`, penguin, props, room, pixel text, icons) | `godot/art/image_src/look.js` (moved, not ported). Its output is `godot/art/images/*` and `art/atlas_data.gd`. The primitives it offers to the frame code (`px`, `fill`, `box`, `pxEll`, `pxLine`, `bitmap`, `icon`, `text`, `rich`) become `art/draw_kit.gd` and `art/text_art.gd` | **Hard, but less:** the baker must list every picture the client may ask for (pose × direction × cord colour × frame), not only those that the mockup scenes drew. A test finds a missing one (see "Testing"). The text path is spike S-3 |
| `art/session-art.js` | `art/effects_art.gd`, `art/log_art.gd`, `view/view2d.gd` | `renderAt(t)` becomes the frame of the view. The effects are drawn with `draw_kit.gd` |
| `art/crowd-art.js` | `art/crowd_art.gd` | Chips, focus ring, notices, bar, cards, mouse pointer |
| `art/arenas-art.js` | `art/arenas_art.gd`, `art/overview_art.gd` | Camera view, tabs, page boxes, follow switch, overview, key caps |
| `art/sound.js` | `godot/art/sound_src/sound.js` (moved, not ported). Its output is `godot/art/sound/*` | The code stays JavaScript and runs at build time in Chromium, through `tools/render-sound.mjs`. See "Sound" |
| `art/sound-ui.js` | `art/sound_ui_art.gd` | Hit tests are in 480×270 coordinates |
| `package.json` (the two fonts) | The baker reads them from npm. The client reads the glyph atlas. `fonts/` holds their OFL texts | The OFL terms for a bitmap made from the fonts need a check (open question 4) |

### The hard parts in detail

**Baking the pictures.**

* `look.js` draws into a global canvas `g`, and `onCanvas` swaps it. The baker runs it unchanged in Chromium. It calls the penguin, prop and room functions for each wanted variant, reads the canvas and saves a PNG. The result is the same as the mockup's, by construction.
* The baker needs a table of every variant: poses, directions (the left view is the right one, mirrored by `flip_h` in Godot), cord colours of the four frameworks (and a default for an unknown one), animation frames, and rug colours. The table lives next to `look.js`. The first version comes from the poses that the scenes use. Then the Godot actor adds the ones it needs.
* Atlases: one PNG per kind (penguins, props, effects pieces, glyphs), with names and rectangles in `atlas_data.gd`. The tool packs them in a fixed order, so the output is the same on every run.
* Filtering: the textures use nearest filtering. A room that is scaled down in a fly or the overview needs smoothing. Mipmaps on the room textures may give it (spike S-6).
* Pixel snapping: set the project to draw at whole pixels, and round positions with `floor(x + 0.5)` (see "Porting traps").

**Drawing the rest.**

* `draw_kit.gd` gives the primitives that the interface and the effects use. Each is a call to `draw_rect`, `draw_texture_rect_region` or a short loop of rectangles (an ellipse is one rectangle for each row, as in the mockup's speed fix).
* Alpha (the 0.16 shadows) is drawn with a colour that has alpha. Blending may differ by 1 per channel from the canvas. A person reviews it.
* Text comes from the glyph atlas: the baker renders each character with the mockup's own text routine, so the result is the mockup's. The atlas holds a fixed set: ASCII, the Polish letters and the few symbols the mockup uses. Another character shows as "?" (open question 4). The other way is a Godot font with antialiasing and hinting off (spike S-3).
* The number of calls: a frame has some hundreds of small rectangles. They go into a few batches in the engine (**not measured**).

**Web Audio.** Not ported. The existing code renders audio files (see "Sound").

### Porting traps (JavaScript to GDScript)

| Trap | What happens | What to do |
|---|---|---|
| `Math.round(-0.5)` is `-0`. GDScript `round(-0.5)` is `-1` | Rounding differs for negative halves | Use `floor(x + 0.5)` everywhere the JavaScript rounds. `js_round` in `arena_rules.gd` is exact (it tests `x - floor(x) >= 0.5`) |
| `/` on two integers is integer division in GDScript | Silent wrong value | Divide floats, or use `floori()`. Turn the integer-division warning into an error |
| `Array.sort` is stable in JavaScript, not in GDScript | Ties give another order. `sorted()` and the pull order have ties | Add a tie-break key (id or index) to every sort comparator |
| `Infinity` and `null` in options (`maxArenas`, `until`) | Wrong comparisons | Use `INF`. Use a typed `Variant` with `null`, and test each case |
| Lambdas copy local variables | A closure that changes `view`, `move` or `mode` changes nothing outside (verified in phase G-1) | `simulateCamera` keeps its state in member fields of a class, not in closures |
| `%` on floats | Not allowed in GDScript | Use `fmod` |
| `Set`, `Map`, `Object.entries` | Other types | Use `Dictionary`. Keep the insertion order in mind. Both languages keep it |
| `JSON.stringify` as a cache key | No such call | Build a string key by hand, with a fixed field order |

## Testing

### Test framework: GUT

Use **GUT** (Godot Unit Test, MIT). Reasons:

* its command-line runner is simple (`godot --headless -s addons/gut/gut_cmdln.gd ...`) and it writes JUnit XML;
* the core classes need no renderer, so headless is enough;
* its releases follow the Godot minor version, so the pin is clear.

GdUnit4 is the alternative. It has more features (scene runner, mocks). Search results said that its `--headless` flag has changed between versions and that one version refused to run headless without an extra option. **Not verified.** Phase G-0 runs both in a one-test project for a few minutes and keeps GUT unless it fails. The choice is open until then.

GUT is kept in the repository, in `godot/addons/gut/`, with its MIT license file (decided on 2026-11-15). A change of the Godot pin updates GUT in the same pull request. The license, header and look checks skip `godot/addons/`. The Godot editor is not kept in git: `tools/get-godot.mjs` downloads it.

### Layers of tests

1. **Unit tests (GUT, headless).** Events, director, actor, spots, focus, log model, arena rules, sound model, projection. They run with a fake clock and no renderer.
2. **The ported arena rules.** `test/test_arena_rules.gd` holds the 34 cases of `arena-rules.test.mjs`. Each GDScript test has the comment `# JS: <title>` with the exact title of the JavaScript test. A Node test (`tools/parity.test.mjs`) reads both files and fails when a title has no counterpart. No case can be dropped without notice.
3. **Golden data from the JavaScript reference.** `tools/dump-fixtures.mjs` runs `simulateCamera`, `createArenas`, `placeOf` and the other pure functions on a list of specs. It writes the results to `test/fixtures/*.json`. The GUT tests run the same specs and compare. Floats must agree within 1e-9. A fixture file holds provenance (the commit of the mockup). The specs include the camera input of each arena scene (events, focus events, inputs), so every scene's camera log is checked, not only the small test cases.
4. **The atlases, headless.** The pictures come from the JavaScript art code itself, so they match the mockup by construction. The tests check the files and their use: every file matches its hash in `MANIFEST.txt`; `atlas_data.gd` and the PNG sizes agree (each rectangle lies inside its image, none overlap); and every picture that the code can ask for exists. The last test reads the pose table (pose, direction, cord colour, frame, rug colour) and looks up each name in the atlas data. A missing picture fails a test, not a person's eye later.
5. **Behaviour.** A fixed trace is the expected behaviour: for each event, the station and the pose. The Claude Code transcript in `schema/examples/` goes through the real bridge adapter once, and the canonical events are saved as a fixture. A GUT test feeds them to the director and the actor in fixed steps. The penguin must visit the stations in this order: map table, bookshelf, workbench, forge, sign post, flop, helper desk and its helper, telescope, workbench, forge, celebration (the order of the client plan). This trace is language-neutral, so a later JavaScript client could use it.
6. **Bridge link.** A Node test starts a bridge on a free port, runs the Godot client headless with a script that prints each event it gets, posts a few events and a replay, and compares the printed list with what the bridge sent. The test needs only the network, not a renderer. **Whether a headless Godot connects with `WebSocketPeer` was not checked.**
7. **Schema.** `event.gd` lists the categories. A GUT test loads `schema/event.schema.json` (from the source tree, not from an export) and compares the enum.
8. **The license split.** `godot/tools/license.test.mjs` (see below).
9. **The look (ADR 0004).** A Node test fails if a file in `godot/` contains the listed markers: the asterisk spinner's characters, transcript bullets and result lines, "esc to interrupt", or logo files.
10. **Screens, for a person.** Stills at fixed moments, to look at. They are not compared pixel by pixel, because the interface and the effects are drawn by new code and blending may differ. A person compares them with the mockup's stills at the same moments.

What headless cannot do: draw. Godot's `--headless` mode uses a dummy renderer. Tests that need a picture run under a virtual display (`xvfb`) with a software renderer, or on a machine with a screen. Only the recorder and the screen checks need this.

### The license check

`godot/tools/license.test.mjs` runs with `node --test` (Node is already needed for the bridge). It checks that:

* each `.gd` file in `godot/art/` starts with the header above, and each `.js` file there starts with the same lines behind `//`;
* `godot/art/images/` and `godot/art/sound/` hold only image and sound files (and the `.import` files that Godot makes). `godot/art/MANIFEST.txt` starts with the copyright line and lists the SHA-256 hash of each file in both folders. The hashes match the files, so nobody edits a rendered file by hand;
* `LICENSE-ASSETS` names `godot/art/` (it covers the images and the sounds in it);
* no `.gd` file outside `godot/art/` and `godot/addons/` calls drawing or sound APIs: `set_pixel`, `fill_rect`, `blend_rect`, `Image.create`, `ImageTexture`, `_draw`, `draw_rect`, `draw_string`, `draw_texture`, `AudioStreamGenerator`, `AudioStreamWAV`. Sound comes from files, so code that makes sound is a sign of a mistake;
* no `.gdshader` file exists in `godot/` (so there is no shader to license);
* `godot/` holds no image or sound files outside `godot/art/` and `godot/addons/`.

This is a heuristic. It finds the usual ways to draw, not every way. A person reviews each change near the line.

## Sound

Decided on 2026-11-15: the client plays **audio files**, and the existing JavaScript synthesiser renders them. The sound is still made by code, but the code runs at build time, not at run time. ADR 0007 says "no audio files" and names Web Audio at run time, so this changes it in part (see "Open questions", item 2).

1. **The files.** Four tunes and five event sounds (a hammer's tink, the desk bell, a flop, a chime, a fanfare) in `godot/art/sound/`. A tune is rendered for one whole loop. The loop includes the change of the lead's sound on every second round.
2. **The renderer.** `godot/tools/render-sound.mjs` opens the synthesiser in headless Chromium, as the recorder does, and calls its offline render (`OfflineAudioContext`) once for each tune and each sound. Noise is seeded, so a render is the same every time. The tool prints the peak and the RMS level of each file, and fails on silence or clipping.
3. **The source moves.** In phase G-7, a copy of the mockup's `sound.js` goes to `godot/art/sound_src/sound.js`, with its header. The files can then be rendered again after the mockup is gone. The sound is the same as the mockup's, because the same code makes it.
4. **Format and size.** The format is WAV (decided on 2026-11-15). WAV loops exactly. It is large: one minute at 44.1 kHz, mono, 16 bits is about 5 MB, so four tunes may take about 20 MB at that rate. At 22.05 kHz it is about half, and chiptune sound may not need more (a listening check). Proposed budget: 10 MB for all files. Spike S-4 measures the real loop lengths and picks the sample rate. Each new render adds its full size to the git history, so render rarely.
5. **The manifest.** `godot/art/MANIFEST.txt` lists the SHA-256 hash of each file (images and sounds). The license test checks it. A rendered file is never edited by hand.
6. **Playing** (done in G-7). One looping player for the tune and a small pool of four for event sounds, with a hard limiter on the master bus and the tune at -3 dB (the files carry their own limiter, and a tune and an event sound can add up above full scale). Sound starts off. `core/sound_model.gd` decides which event plays which sound (unit tests). The chime and the fanfare sound from every arena. The other event sounds come only from the arena the camera rests on (the rule of the 2D view plan).
7. **The clock.** The simulation clock drives the picture, and sounds start from it. The 2D view plan says the picture follows the audio clock while sound is on. The Godot client drops this, because the simulation must stay deterministic. The delay is the output latency (a few tens of milliseconds). This deviates from the 2D view plan (see "Open questions", item 3).
8. **Speed.** Nothing is synthesised at run time. This saves start-up time and CPU beside the agent. A tune costs only the memory of its file and the decoding.

## Recording

The mockup draws any frame from the time alone, so `record.mjs` can step through a scene. The Godot client is stateful, so recording uses **Movie Maker mode** (`--write-movie`), with a fixed frame rate (`--fixed-fps`). Both are in the Godot documentation. **Not run yet, and not checked headless (spike S-5).**

* **Done in G-8:** the recorder, the check, the container and the tour are in `godot/README.md`, "Phase G-8".
* `godot/tools/record.mjs` is the counterpart of `record.mjs`. It starts the client with a scene name, a tune and options. Godot writes a PNG sequence and a WAV file. `ffmpeg` joins them into the same 1920×1080 H.264 clip with AAC sound. The options keep the mockup's names where they still make sense: `--scene`, `--fps`, `--out`, `--stills`, `--music`, `--events`, `--silent`, `--reduced`.
* The window is 1920×1080. The viewport is 480×270 with integer scaling, so each pixel is a 4×4 block. Nothing scales the picture again.
* The audio mix rate must divide by the frame rate (for example 48000 and 30). Movie Maker captures the audio that the client plays, so play and recording use the same sound files.
* `--stills 7,22.5` runs the simulation without drawing up to each time, draws one frame and saves it as PNG.
* A container (`tools/Dockerfile`) holds Godot, `xvfb`, a software renderer (Mesa), Node and `ffmpeg`. Official clips come from it, so they do not depend on a GPU.
* **Same on every run:** the check records a scene twice and compares the hash of every frame. It holds on one machine and one container image. Across different GPUs it is unknown: scaled-down rooms use filtering that may differ. The container removes this risk. **Measured in G-8:** the seven scenes give equal frames and an equal WAV file on two runs on the Windows machine, and `session` does so in the container. A frame from the GPU and a frame from the container are not equal: about 1000 to 2000 pixels differ by one level of one channel (the glows). The WAV files are equal on both systems.

## Performance

**Target.** The `ten` scene (157 agents, 40 arenas, 10 pages) keeps 60 fps during its long camera moves on a named reference machine. The owner chose the kind of machine: a low-end laptop with 8 GB of memory. The result file records its exact CPU, GPU, OS and the Godot version.

The mockup's baseline is in ADR 0008: up to 236 ms for a frame in a long move before the one-`fillRect`-per-row fix, and some frames over 16.7 ms after it. The Godot client is better only if the same measurement shows it.

**How to measure.**

1. The client has a `--benchmark=<scene>` mode. It plays the scene in real time with the interface and the sound off, writes one line per frame (`t`, frame time, process time, move id) to a CSV file and exits.
2. A Node tool reads the CSV and the camera log of the same run. It picks the windows of long moves (flies and scrolls that widen the view to 4 rooms across or more; `ten` has several, for example the fly across eight pages). It prints the count, median, 95th and 99th percentile, the worst frame and the share of frames over 16.7 ms for each window and for the whole scene.
3. Run it twice: with vsync on (the real condition) and off (the headroom).
4. Run the mockup in Chromium on the same machine with a real-time loop, and compare. This gives a baseline in the same units.
5. A headless GUT test measures the cost of the simulation alone: stepping 157 agents. It prints the time and fails above a generous limit (10 ms a step). It finds a slow simulation on any machine, with no screen.

**Pass rule (a proposal; confirm it):** in each long-move window, at most 1% of frames take longer than 20 ms, and no frame takes longer than 33 ms. The process time of the 99th percentile frame is at most 8 ms, to leave room for a 120 Hz screen.

**Also measure, but do not gate on:** the same run on a mid-range tablet.

### Cost beside a coding agent

The client runs on the same machine as a coding agent, next to the editor or the terminal. It is often visible but not focused, while the agent builds and tests. So it must take little CPU, GPU and memory, start fast and cost almost nothing when hidden. The `ten` rule above is the worst case. The everyday case is one to a dozen agents.

Rules that follow from this:

1. **Cap the frame rate without focus.** Draw at 30 fps (a setting) when the window has no focus. The simulation keeps its step of 1/60 s, so the story does not change. Godot has settings for this (`Engine.max_fps`, low-processor mode). **Not verified.**
2. **Stop drawing when minimized or hidden.** Keep reading events. Apply the backlog rule when the window shows again.
3. **No per-frame allocation** in the frame loop, and no thread that wakes on its own. The socket is polled once per frame.
4. **Hide what is out of view.** Arenas that are not in view do not draw.
5. **No synthesis and no texture making at run time.** Sounds and pictures are files. Start-up only loads them. Load the atlases first, and the rest while the first frame shows.

Budgets. These numbers are guesses. Measure the first working version, then fix them in this plan:

| What | Budget | Condition |
|---|---|---|
| Time to the first frame of the room | 2 s or less | Cold start, reference machine |
| CPU, no focus, 1 agent working | 2% of one core or less | 30 fps cap |
| CPU, no focus, 12 agents working | 5% of one core or less | 30 fps cap |
| CPU, minimized | 0.5% of one core or less | |
| Memory in use | 200 MB or less | Scene `multi` |
| Frame time, focus, long camera move | The `ten` rule above | 60 fps |

The reference machine is a low-end laptop with 8 GB of memory (decided on 2026-11-15). Memory is shared with the agent, the editor and a browser, so the budget for memory is tight. The Compatibility renderer and the 480×270 viewport help here.

**Measured in G-6** (a fast machine with a discrete GPU, the editor build of Godot 4.7.2 running from source; the reference laptop was not measured; details in `godot/README.md`): an empty Godot project costs 6.4 % of a core at 30 fps and 193 MB here, which is more than the budgets for 1 and 12 agents (2 % and 5 %). The client costs 10 to 15 % of a core with 1 to 9 agents at 30 fps without focus, and 0.5 to 1 % minimized. It starts in 2.2 s (1.3 s of it is the engine, about 0.8 s the scripts). Memory is 228 MB with `multi`. So the budgets stand as guesses that this build cannot meet; open question 9 asks the owner for numbers and for a measurement of a release export. The client draws at 60 frames a second with focus (a screen above 60 Hz would otherwise cost a whole core), at 30 without focus, and at 4 minimized with no drawing.

How to measure: `tools/benchmark.mjs` starts the client, plays a replayed session (and the `multi` scene) for 60 s in each state (focus, no focus, minimized), and reads the process's CPU time and memory from the operating system once a second. It prints the mean and the peak. It runs the mockup in Chromium the same way as a baseline. A smaller number than the baseline is a hope, not a fact, until the tool shows it.

**Finding of G-6 (2026-11-16):** the budgets above are not met, and some are below what the engine costs alone. In the editor build run from source, an empty Godot project costs 6.4% of one core at 30 fps and about 193 MB. The client costs 10 to 15% of one core with 1 to 9 agents and no focus, about 45% with 157 agents, and 228 MB. A minimized window costs about 1%. Decision for the rest of the work: measure a release export in phase G-9 (an export build should be lighter than the editor build), then fix the budget numbers from that measurement and the reference laptop, which has not been measured yet.

**Measured in G-9 (2026-11-16), a release export for Windows on the same fast machine** (details and caveats: `godot/README.md`, "Phase G-9"): CPU with focus 19 to 26 % (`ten` 55 %), without focus 10 to 14 % (`ten` 32 %; forced by option, as in G-6), minimized about 0.6 to 1.3 %, memory 205 to 207 MB (`multi`; `ten` 219 MB), start-up 1.9 to 2.1 s warm. This is a little lighter than the editor build (memory 20 to 30 MB lower, `ten` 30 % lower in CPU), and it does **not** change the finding of G-6. The Windows app is 115.7 MiB, not 30 to 70 MB. **Proposed budgets (proposals until the reference laptop is measured; not decisions):** first frame 3 s (warm), CPU without focus 15 % (1 agent) and 20 % (12 agents), with focus 30 %, minimized 1.5 %, memory 250 MB, app size 130 MB. The reference laptop was **not** measured and the table above still holds the original guesses.

**Measured in G-7 (2026-11-16):** sound costs less than 0.5 point of one core and 3 to 5 MB with a tune playing (about 1 MB for the event sounds), on the same fast machine, with the dummy audio driver (so no tune played through speakers). The runs with a window varied by 4 points or more, so the audio part could not be told from noise there; a headless run gave 0.4 % without sound and 0.5 % with it. The cost of a real audio device, a release export and the reference laptop were not measured. Details: `godot/README.md`, "Phase G-7".

## Phases

Each phase is one pull request and leaves every test green. The mockup does not change until G-10, except for fixes to its rules (see "The two code bases"). The tools that read from it live in `godot/tools/`.

| Phase | Content | Done when |
|---|---|---|
| G-0. Skeleton and link (done 2026-11-15) | Check the facts that block the plan (see "Facts"; spikes S-1 and S-2). Pin Godot. The project, GUT (kept in the repository), and a script that downloads the pinned Godot from godotengine.org and checks its hash. `event.gd`, `bridge_client.gd`, a text view of the connection and the events. The files named in ADR 0008 (`CLAUDE.md` rule 7, `LICENSE-ASSETS`, the license test) now name `godot/art/` | The GUT tests pass headless from the command line. The bridge-link test passes (events in order, reconnect after the bridge restarts). The license test passes on a sample art file. With `npm run replay`, the app lists the events |
| G-1. Arena rules (done 2026-11-15) | `core/arena_rules.gd`, `core/rng.gd`. `tools/dump-fixtures.mjs` and its first fixtures. The parity test | The 34 ported cases pass, the parity test finds all 34 titles, and the golden data agree within 1e-9. The first version is a faithful batch port of `simulateCamera` |
| G-2. Art as files (done 2026-11-15) | Spike S-3. `tools/render-art.mjs` and the moved `image_src/look.js`. The variant table. The atlases, the rooms, the glyph atlas, `atlas_data.gd`, `MANIFEST.txt`. Import settings (nearest filter, no compression). `draw_kit.gd` and `text_art.gd`. A gallery scene that shows every picture and a line of text. `LICENSE-ASSETS` names `godot/art/` | The atlas tests pass (hashes, rectangles, every requested picture exists). The gallery shows every pose and the text. Load time is measured and written down |
| G-3. Room and stations (done 2026-11-15) | `stations.gd`, projection, `spots.gd`. One arena: the baked room, penguins and props in depth order, one penguin standing at each station | The spot tests pass. A person compares a screenshot with the mockup's still, and against ADR 0004 |
| G-4. Behaviour and scenes (done 2026-11-16) | `clock.gd`, `director.gd`, `penguin_actor.gd` (the event-to-animation mapping), `focus.gd`, `effects_art.gd`, the backlog rule, `timeline_player.gd`. The frame cap without focus and the stop when minimized. `tools/export-scenes.mjs` makes `demo/session.json` and `demo/multi.json` | The behaviour trace test passes. The `session` and `multi` scenes play from their timelines. A live session from the bridge shows one room with several agents |
| G-5. Arenas and camera (done 2026-11-16) | The arena model on live events. An **incremental** camera that gives the same results as the batch port (golden data). The camera view, slides, flies, zooms, scrolls, the ribbon. Scenes `arenas`, `many`, `follow`, `ten`. First performance run, without the interface | The camera tests and the golden data pass on both versions. The four arena scenes play. The first benchmark result is written down |
| G-6. Interface and log (done 2026-11-16) | Bar, cards, number chips, focus ring and label, notices, tabs, page boxes, follow switch and menu, overview, `log_model.gd`, the keys (touch controls are postponed) | The log, focus and card tests pass. A scripted input test (the `arenas` scene's clicks and keys) gives the expected camera log. **The `ten` target and the budgets beside an agent are checked on the reference machine** (G-6 measured them on a fast machine, not on the reference one: the `ten` rule is met there; the budgets beside an agent and the 2 s start-up are not met, and the engine alone costs more than the budgets; see `godot/README.md`, "Phase G-6") |
| G-7. Sound (done 2026-11-16, **except the listening**: no person has heard the files, the players or the limiter; see `godot/README.md`, "Phase G-7") | Spike S-4. `tools/render-sound.mjs` and the moved `sound_src/sound.js`. The rendered files and `MANIFEST.txt`. `sound_model.gd`, the players, the sound switch and menu. `LICENSE-ASSETS` names `godot/art/sound/` | The sound-model tests pass. The manifest check passes. The render tool reports no silence and no clipping. The players load and play every file under the dummy audio driver. Sound starts off and the keys work. The numbers for memory and CPU are written down. **A person listens to all four tunes and the five sounds** |
| G-8. Replay, recording and the tour (done 2026-11-16) | Spike S-5. `tools/record.mjs`, the container, `--stills`. The `tour` scene. `npm run replay` through the bridge into the client | A replayed session plays and the penguin visits the stations in order. A scene recorded twice gives the same frames. All seven scenes record. **Checked on Windows with a GPU and in a Linux container (Docker); not on a real Linux host, on macOS, or with Podman.** Frames from the GPU and from the container differ by one level in some pixels; the sound is equal (see `godot/README.md`, "Phase G-8") |
| G-9. Exports (done 2026-11-16 for Windows; Linux and macOS postponed by the owner) | Presets and scripts for Windows, macOS, Linux (Android, iOS and tablets are postponed; the web only if open question 10 allows). Unsigned builds first | The exports for Windows, macOS and Linux each connect to a real bridge and play a real session. **Windows: holds.** The unsigned `AgentWorkshop.exe` (115.7 MiB) connects to a real bridge, plays a replayed Claude Code session and the scene menu, and the icon and version information are set (screenshots looked at, on a fast machine; the release numbers and proposed budgets are in `godot/README.md`, "Phase G-9"). **Linux and macOS: not done.** The presets and the tool exist and are tested, but the owner postponed the builds. (Both were built once before the order arrived; Linux ran once in the G-8 container; macOS was never run. This is not a result.) |
| G-10. Remove the mockup (done 2026-11-16) | Regenerate the six preview images in `docs/images/` with the Godot recorder. Freeze the golden data and the scene files, with a note of their origin. Make the tests and the tools independent of `tools/mockup-2d/`. Delete the folder. Update the README, `LICENSE-ASSETS`, `CLAUDE.md` and the other plans | The tests pass without `tools/mockup-2d/` (run with the folder renamed, then deleted). The images come from the Godot client. The owner waived some conditions: see "The two code bases". See `godot/README.md`, "Phase G-10" |

Spikes are short experiments. Each one answers one question and ends with a note of the result in `godot/README.md`. A spike that fails sends the question back to the project owner before more code is written.

| Spike | Question | Runs in |
|---|---|---|
| S-1 | Does `WebSocketPeer` connect to the bridge in a headless run, in a desktop app and in a web build? Does it send an `Origin` header? | G-0 |
| S-2 | Does GUT run headless with the pinned Godot? Does GdUnit4? | G-0 |
| S-3 | Which text path: the glyph atlas baked by the mockup's own text routine (the plan's default), or a Godot font? Does the atlas cover the characters that targets use? What do the font licenses (OFL) say about a bitmap made from the fonts? | G-2 |
| S-4 | Can the synthesiser render one exact loop per tune offline? What are the loop lengths, and which sample rate (44.1 or 22.05 kHz, mono) fits the size budget? Does Godot import the WAV loops? | Before G-7 starts (it can run any time after G-0). **Done 2026-11-15:** the tool renders nine WAV files, the loops join without a click, and the set is about 10 MB at 22.05 kHz (see `godot/README.md`). Nobody has listened to the files yet |
| S-5 | Does Movie Maker mode run under `xvfb` with a software renderer and capture audio? Are two runs the same? | Before G-8 starts (it can run any time after G-2). **Done 2026-11-16:** yes on Windows with a GPU (480x270 PNG frames, a 48 kHz stereo 32-bit WAV, every frame and the WAV equal on two runs), and yes under Xvfb with Mesa llvmpipe in a Debian container (see `godot/README.md`, "Spike S-5") |
| S-6 | What does one `SubViewport` per room cost with about 16 rooms in view, against one world with filtered textures? | Before G-5 starts. **Done 2026-11-16:** one shared world with mipmapped room textures (way B) wins on cost and on picture. A `SubViewport` per room has no mipmaps and drops pixels below scale 0.5 (see `godot/README.md`, "Spike S-6"). Decided for G-5: use way B, turn on mipmaps for the room PNGs, and turn off vertex snapping for the scaled world |

Notes on the order:

* G-1 comes before the art because the rules need no screen, and the golden data find port errors early.
* G-5 builds the incremental camera inside the phase and keeps the batch port as the oracle. The JavaScript batch camera knows the future: it reads when an approval ends (`until`). A live client does not. The incremental camera marks an approval open until the answer arrives. Both versions must agree on every fixture where the answer time is known.
* The mockup's scenes tell a story. The Godot actor reacts to events and walks at its own speed, so its timings can differ from the scripted ones. The check is: the same moves, in the same order, with the same reasons, with times within 1 s of the mockup's camera log. Frame-by-frame equality is not a goal.

## The two code bases

From the day G-0 started until G-10 (2026-11-16), two code bases existed. Now one is left: the Godot client. This section tells what the rule was and what happened on the deletion.

**The JavaScript mockup was a frozen reference.**

* It got no new features and no new scenes.
* A fix to `arena-rules.js` was copied to `arena_rules.gd` in the same pull request. The golden data were made again.
* It was the source of golden data, art hashes and scene timelines, and its recorder made the clips for `docs/images/` until the Godot recorder was ready.
* Its tests ran with `cd tools/mockup-2d && npm test`, next to `cd bridge && npm test`.

**The conditions for the deletion, and how each one stood on 2026-11-16:**

1. Every scene plays in the Godot client, with its phase check passed. **Held.**
2. The ported tests and the golden data pass, and the parity test shows no missing title. **Held.**
3. The Godot recorder makes all clips, and the preview images in `docs/images/` and the README come from it. **Held:** the six images were made again with `godot/tools/record.mjs --stills` (phase G-10).
4. The performance target is met on the reference machine. **Waived by the owner.** The reference laptop (low-end, 8 GB) was not measured. The budgets in "Performance" are proposals, not decisions. The `ten` rule was met only on a fast machine with a discrete GPU.
5. A real session ran on a desktop platform and on a tablet (the proof for ADR 0008). **Half held, half waived.** The desktop half held on Windows (phase G-9). Tablets are postponed, so the owner waived the tablet half. Linux and macOS builds are postponed too.
6. A last run of `dump-fixtures.mjs` and `export-scenes.mjs` is committed. After the deletion the fixtures are fixed snapshots with a note of where they came from. **Held:** both tools ran a last time. The output equalled the committed data. Only the commit id in the provenance of the golden data changed, to `1e6531a128cdf339385c0ef5df27cf8d3d3eceab`, the last commit before the removal. Then both tools were deleted with their tests. `godot/test/fixtures/README.md` and `godot/demo/README.md` say that these files are fixed. The sound and the images can still be rendered, because `render-sound.mjs`, `sound_src/sound.js`, `render-art.mjs` and `image_src/look.js` live in `godot/`.

**Other open points that the owner accepted at the removal (2026-11-16):**

* The font licence question for the glyph atlas (open question 4, the OFL terms of Tiny5 and Silkscreen) is undecided.
* The sound: the owner listened to the files and found them fine. The listening that phase G-7 left open is done.
* The name "Agent Workshop" is no longer claimed as a trademark.

**What changed on the deletion.** `LICENSE-ASSETS` dropped `tools/mockup-2d/art/`. `CLAUDE.md` lost the test line of the mockup, and rule 7 names `godot/art/` and later paths only. The README lost the section "2D mockup" and its status row, and it tells how to run the Godot client. The plans for the browser client, the 2D view, the arenas and the demo mode got a note that the Godot client builds them. The rules in the 2D view and arenas plans stay the specification. The links into `tools/mockup-2d/` became plain text. The browser client plan's origin and host checks for the bridge remain worth doing (ADR 0008 says so).

## Risks

1. **The port is large.** The art is about 120 KB of JavaScript, and the behaviour layer is new code. The phases are ordered so that each one gives a check that needs no screen where possible.
2. **Scripted to live.** The mockup's motion is scripted, and its camera knows the future. The live client has neither. Differences in timing can change which pulls the camera serves. The tolerance rule above handles the check, but the feel needs a person to watch the scenes.
3. **Smoothing of scaled-down rooms.** The mockup draws each room into its own 480×232 buffer and scales it with smoothing in the overview and in flies, because plain scaling would drop rows and columns. In Godot, each room could be a `SubViewport` (a texture that is scaled with filtering). Up to about 16 rooms may be in view. Spike S-6 measures a `SubViewport` per room against one world with a filtered mipmap, before G-5.
4. **GDScript speed.** It may be too slow for the start-up caches on a tablet and for the simulation of 157 agents. The start-up measurement and the headless simulation test find this early.
5. **A tablet cannot reach the bridge.** The bridge listens on `127.0.0.1` (rule 3). ADR 0008 is accepted, and a real session on a tablet is its proof. Without a decision on a network bridge, only a development path exists: an Android device over USB with `adb reverse tcp:8787 tcp:8787`, so that its local port reaches the computer's bridge. An Android emulator may also reach the host's local address. **Not verified.** An iPad has no such path. Tablets are postponed, so this risk waits. Until a decision, tablets would play the demo scenes only.
6. **Text.** The glyph atlas covers a fixed set of characters. Targets can hold any character. An unknown character shows as "?". The OFL terms for a bitmap made from the fonts are not checked.
7. **Headless is not rendering.** Pictures need a display or a software renderer. The container must give the same frames every time. Not verified.
8. **Engine and platform upkeep.** Each Godot release needs new export templates, a new GUT, and possibly fixes. The pin limits this.
9. **Signing and stores** cost money each year and need accounts (ADR 0008). The plan builds unsigned apps. Signing is outside it.
10. **Art license and downloaded apps.** `LICENSE-ASSETS` grants view-only terms. An app that users download and run is a different use (ADR 0008, question 6). The plan does not publish apps.
11. **Sound files grow the repository.** Each new render adds the whole size of the files to the git history. Render rarely, and keep the budget in "Sound".
12. **Idle cost.** A window that animates all the time may use more CPU than the budget. The measurements in "Cost beside a coding agent" find this. The fallbacks are a lower frame rate and a calm mode that stops idle animation.
13. **A missing picture.** The client may ask for a pose, direction, cord colour or frame that nobody baked. The atlas test finds it, and the fix is to add the variant and render again. Each render changes the PNG files in git.

## Open questions

These need a decision. The plan writes no ADR for them.

1. **A network bridge for tablets** (pairing, encryption, rule 3). Postponed with tablets. ADR 0008 says it needs an ADR of its own.
2. **The sound size budget.** ADR 0008 records the sound and image files, and ADR 0003 and ADR 0007 have notes. The format is WAV. Which sample rate and size budget (spike S-4)?
3. **The sound clock.** The Godot client drops "the picture follows the audio clock" of the 2D view plan. Is that acceptable? (G-7 follows the plan: sounds start from the simulation clock. The delay of the output was not measured.)
4. **Fonts in the baked text.** The glyph atlas holds a fixed set of characters. Which set? What happens to others ("?", or a Godot font as a fallback)? Do the OFL terms of Tiny5 and Silkscreen allow a bitmap atlas made from them in an app, and do they need a notice or a changed name? Do the app icons need other formats than PNG (`.ico`, `.icns`)? (Answered in G-9: no, the Godot export makes them from the PNG.)
5. **Controls without a keyboard.** Postponed with tablets. Tab, F, N, arrows, 1 to 6, S, E, M and the hover over a tab have no touch form. What are the touch controls?
6. **The tour.** Is the guided tour part of the product, or is it a mockup aid? If it is the second, drop it from G-8.
7. **Decided on 2026-11-15:** the Godot editor is downloaded from godotengine.org at the pinned version. A script checks the hash. Still open: where the hash comes from (godotengine.org publishes checksums with its releases; not checked).
8. **Continuous integration.** The repository has no CI workflow today. Add one for the GUT tests, the license test and the parity test? Where do exports build?
9. **The exact reference machine and the numbers.** The kind is decided: a low-end laptop with 8 GB of memory. Name the exact laptop, and confirm the frame-time rule and the budgets for CPU, memory and start-up. All numbers are guesses until the first version is measured.
10. **Browser path** (ADR 0008, question 1). If the web export stays, the bridge must serve it, and the origin checks of the browser client plan come first.11. **Platforms to sign and publish, and who pays** (ADR 0008, question 5). The plan builds only unsigned apps.
12. **Scene timelines as shipped content.** `demo/*.json` may ship in the app, so that it can play every scene with no bridge. Is that wanted, or are they test data only? (This mattered most for tablets.)
13. **License terms for downloaded apps** (ADR 0008, question 6).

## Facts that need checking

None of these is verified, unless the text says so. A short web search on 2026-11-15 gave only third-party pages and old documentation for some of them.

| Fact | Where it matters | Status |
|---|---|---|
| The newest 4.7 patch release (the owner named 4.7.2), and that GUT has a matching release | G-0, the pin | Checked in G-0: Godot 4.7.2 runs, and GUT 9.7.1 (branch `godot_4_7`) runs on it. Whether a newer 4.7 patch exists was not checked |
| GUT runs headless and exits with code 1 when a test fails | Testing | Checked in G-0 on Windows with Godot 4.7.2 (the project must be imported once first). JUnit XML output was not tried |
| GdUnit4's headless behaviour in the pinned version | Test framework choice | Search results disagree. Not run |
| `WebSocketPeer` connects to `ws://127.0.0.1:8787/ws` in a headless run and in each export | G-0, G-9 | Checked in G-0: it works in a headless run on Windows, and with no listener Windows took about 30 s to report failure (the client now has a 4 s connect timeout). Not checked in a web build or on other systems |
| A native Godot WebSocket sends no `Origin` header | The bridge's origin checks | Checked in G-0 on Windows: it sends none, and a test guards this |
| Movie Maker mode (`--write-movie`, `--fixed-fps`) works as documented, under `xvfb` with a software renderer, and captures audio | G-8 | Checked in G-8 on Windows with a GPU, and under Xvfb with Mesa llvmpipe in a Debian container (Godot 4.7.2): it writes a PNG sequence and a WAV file, the sound players are in the WAV, and two runs give the same bytes. Not checked on a real Linux host or on macOS |
| Mix rate must divide by the frame rate | G-8 | The default mix rate is 48000 Hz (stereo, 32 bit in the WAV file), and 30 fps gives 1600 samples for each frame. The seven scenes were recorded at 30 fps and one clip at 25 fps. The recorder accepts the rates that divide 48000 (24, 25, 30, 48, 60) |
| Godot imports WAV and loops it | G-7, S-4 | Checked in S-4 (import settings, loop mode and end of the loaded stream) and in G-7 (a tune loads, plays and loops under the dummy audio driver, and a test reads the loop of the loaded stream). **Not heard** |
| The synthesiser's offline render can give one exact loop per tune | G-7, S-4 | Checked in S-4: one exact loop per tune, and the loop lengths are measured (see `godot/README.md`, "Sound files"). **Not heard** |
| Godot can cap the frame rate without focus, and stop drawing when minimized | "Cost beside a coding agent" | Checked again in G-6 on Windows with a real minimized window (0.5 to 1 % of a core) and, in one run, a real loss of focus; other runs used `--force-focus=false` because the system kept the foreground window. Checked in G-4 on Windows with Godot 4.7.2 for minimizing: `Engine.max_fps` and `RenderingServer.render_loop_enabled` took the policy, and a minimized window ran at 10 frames a second with no drawing. The cap for a window without focus is set by the same code, and a unit test checks the values. A real loss of focus and other systems were not checked |
| GitHub refuses files over 100 MB, and a Godot editor build is near that size | Open question 7 | From memory, not checked |
| The Compatibility renderer runs on Windows, macOS, Linux, Android, iOS and a software path | Choice 2 | Not checked |
| The canvas to PNG path in headless Chromium gives the same bytes on every run (the baker and the atlases depend on it) | G-2 | Checked in G-2 with an installed Chrome and Playwright 1.49.1 on Windows: the baker reads the pixels and encodes the PNG itself. Two runs in one process and one run in a new process gave the same bytes. Only the glyph atlas depends on the browser's text rasterizer (see `godot/README.md`, spike S-3) |
| Godot imports PNG with nearest filtering and no compression, and mipmaps give smooth scaling of a room | G-2, S-6 | Checked in G-2 for the first part: lossless, no mipmaps, and the project default filter is nearest. Smooth scaling with mipmaps is not checked (S-6) |
| Godot makes `.ico` and `.icns` app icons from a PNG | G-9, open question 4 | Checked in G-9 with Godot 4.7.2: the Windows export set the icon and the version information from the PNG with no `rcedit` (file properties and the icon were looked at), and the macOS export wrote `icon.icns` (seen in the zip; not run) |
| The OFL terms of Tiny5 and Silkscreen allow a bitmap atlas made from them | S-3 | The license texts were read in G-2 and the relevant terms are listed in `godot/README.md`. Whether the atlas is a derivative is **not decided** (open question 4) |
| Godot reads WOFF2 fonts and can draw crisp 8 px text | S-3, only if the atlas is not used | Not checked |
| GDScript lambdas copy local variables | Porting traps | Checked in phase G-1 with Godot 4.7.2: yes. A test keeps the fact |
| `SubViewport` cost for about 16 rooms, and the filtering of a scaled-down room | G-5 | Measured in S-6 (one shared world with mipmapped rooms wins), and used in G-5. The first run of `ten` is in `godot/README.md` ("Phase G-5"): on a fast machine with a discrete GPU the long moves took about 4 ms a frame once far rooms were simple, and about 20 ms before. The reference machine was not measured |
| Godot exports to Windows, macOS, Linux, Android, iOS and the web, with an export of about 30 to 70 MB | G-9 | Checked in G-9 for Windows: it exports, and the app is **115.7 MiB** with the official template (the release template alone is 104 MiB), not 30 to 70 MB. A macOS zip (66.5 MiB) and a Linux binary (81.7 MiB) were built once; nothing else was checked for them. The other platforms were not tried |
| C# projects cannot export to the web in Godot 4 | Why GDScript | The 4.3 export page said so (seen in search results). Newer status not checked |
| Single-threaded web export (4.3 and later) needs no cross-origin isolation headers | Open question 10 | From ADR 0008. Not checked |
| A macOS export and its notarization can run outside macOS | G-9 | The export ran on Windows and gave a zip with `AgentWorkshop.app`, `icon.icns` and an ad-hoc signature (the owner postponed macOS; it was built once and never run). Notarization was not tried |
| `adb reverse` lets an Android device reach the computer's `127.0.0.1` bridge, and an emulator does too | Risk 5 | Not checked |
| An Apple Developer ID costs 99 USD a year | Signing | From ADR 0008. Not checked |
| godotengine.org publishes a checksum for each editor download | `tools/get-godot.mjs` | Checked in G-0: the 4.7.2 release has an official `SHA512-SUMS.txt`, and the script uses it. The download itself was not run |

## Rough size

A guess, from the mockup's size:

* `godot/art/`: 1,500 to 2,000 lines of GDScript (the frame drawing: effects, interface, overview, tour; about 60 KB of the mockup's JavaScript), plus the moved `look.js` and `sound.js` (about 650 lines of JavaScript), plus the PNG and sound files. The PNG files should be small (pixel art; the sizes were not measured).
* `godot/src/`: 2,000 to 2,500 lines, most of it new (the behaviour layer and the view glue).
* `godot/test/`: about 1,800 lines, including the 34 ported cases and the behaviour trace.
* `godot/tools/`: about 700 lines of JavaScript, a Dockerfile. The tools include the sound renderer and the benchmark.
* `godot/demo/`: seven JSON files. The `ten` timeline is the largest, probably a few hundred KB.
