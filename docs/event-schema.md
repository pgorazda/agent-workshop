# Event schema

[`schema/event.schema.json`](../schema/event.schema.json) is the contract between the adapters and the app. An adapter turns an agent's native events into schema v1 events. The app picks stations from `category` only, never from tool names.

| `category` | Station | Example Claude Code tools |
|---|---|---|
| `read` | Bookshelf | Read |
| `search` | Map table | Grep, Glob |
| `write` | Workbench | Edit, Write |
| `exec` | Forge | Bash |
| `web` | Telescope | WebSearch, WebFetch |
| `delegate` | Helper desk (a helper penguin appears) | Task |
| `think` | Thinking chair | TodoWrite |
| `ask_permission` | Sign post | AskUserQuestion |
| `other` or unknown | Odd jobs | MCP tools, anything unmapped |

Also:

- `tool_end` with `ok: false` makes the penguin flop.
- `waiting_permission` sends it to the sign post.
- `done` starts a celebration.
- Unknown event types are accepted and shown as generic work.

Examples of whole sessions are in [`schema/examples/`](../schema/examples/). They are made up, from the documented formats of each agent.

## Cord colours

Each framework has a cord colour on the penguin, on its number chip and on its card: claude-code `#d97333`, opencode `#3380e6`, pi `#994dcc`, hermes `#e6bf33`.

## Adding an agent framework

1. Write an adapter in `bridge/src/adapters/` that turns the framework's native events into schema v1 events. Use `category_for()` from `bridge/src/categories.rs` and `describe_target()` from `bridge/src/targets.rs`. Add per-framework tool-name overrides to `categories.rs` if needed. `opencode.rs`, `pi.rs` and `hermes.rs` are short, complete examples.
2. Register it in `Adapters::map` and `Adapters::knows` in `bridge/src/adapters/mod.rs`. That gives it a `POST /hook/<framework>` route. Or run it beside the agent and `POST` canonical events to `/event`.
3. Ship a small forwarder for the agent (hook config, plugin or extension) that sends only the fields the adapter needs, and put it in `adapters/<framework>/`.
4. Give the framework a cord colour in the app's director (`godot/src/core/director.gd`).

The app logic does not change. To report subagent activity so it reaches the helper penguin, send `subagent_start` with an `id`, then use that same `id` as the `agent` of the subagent's own events (OpenCode does this).

Keep `bridge/src/schema.rs` in step with the schema file. A test checks the enums.
