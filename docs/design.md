# Design decisions

The main decisions behind Agent Workshop, with the reason for each. This page is short on purpose. The code and the other documents say how things work. This page says why they are this way.

## One event format between the agents and the app

Every agent reports activity in its own way. An adapter turns each one into the same small event format, and the app reads only that format ([event-schema.md](event-schema.md)). The app chooses a station from the event's `category`, never from a tool name. So a new agent needs an adapter and no change to the app. The format is a versioned schema, and the bridge and the app are tested against it.

## A local bridge between the adapters and the app

A small program, the bridge, receives events over HTTP and sends them to the app over a WebSocket. It listens on `127.0.0.1` only, keeps no history, stores nothing and broadcasts only the fields of the schema. Agents' hooks can carry commands, file names and tool output, so the bridge keeps the guarantees simple: it never binds to the network, and `--redact-targets` can drop targets and error text too. Because the bridge keeps no history, start the app first and then the session.

## A Godot app, not a browser page

The client is a desktop app made with Godot, with downloadable builds for Windows, Linux and macOS. A browser client was planned first. Godot gave one codebase for 2D drawing, sound, recording and exports for every system, with no server to host and no browser to support. The cost is a larger download, and unsigned apps that the operating system warns about.

## A look of its own

The room, the penguin and the music take their look from Polish folk art and dances, drawn in pixels at 480×270. The project does not use Anthropic or Claude logos, the Claude Code mascot, Anthropic's typefaces, a Claude colour scheme, or layouts copied from Claude Code's terminal. The project is independent and is not made by or affiliated with any agent's maker.

## Several rooms, one on screen

One room holds four agents. When it is full, another opens, and a camera moves between them. One room is on screen at a time, because a room at full size is where the story can be read. The camera follows what needs a person first, such as an approval, and it never moves faster than a person can follow ([arenas.md](arenas.md)).

## The bridge is a Rust binary

The bridge was first a Node program. A person who only wanted live events had to install Node and run `npm ci`. It is now one static Rust binary for each system: Windows and Linux (x86_64 and arm64) and macOS (universal), with no runtime and no install step. It is about 2 MB and uses a few MB of memory. The behaviour did not change, and the tests compared the Rust output with the Node output on hundreds of thousands of inputs. The few differences that remain are edge cases (for example very deep JSON) and are listed in the tests. Node stays a development tool for the scripts in `godot/tools/`.

The bridge has its own release archives, separate from the apps. A person downloads the app, and the bridge only if they want live events.

## The app can start the bridge, if you ask

To get live events you start two programs: the bridge, then the app. The app can start the bridge for you, but only when you ask (`--start-bridge`, or a line in its settings file). The rules keep it safe:

- It is off by default. The app never runs a program that you did not choose, and never downloads one.
- It starts a bridge only for a local address, and only when none answers there yet. An existing bridge is used and never stopped.
- It stops only the bridge that it started. If the app crashes, that bridge ends too.
- There is no switch in the interface. The command-line option and the settings file are enough.

## Licenses

The code is MIT. The art is all rights reserved: the drawing and sound code, the images and sounds made from it, and the preview images. The art lives only in `godot/art/` folders, and a test checks the split. This keeps the code reusable and the look of the project its own.
