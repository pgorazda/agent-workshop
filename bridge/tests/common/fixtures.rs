//! Makes the fixtures of the Godot tests (`godot/test/fixtures/*.events.jsonl`) from the example
//! sessions in `schema/examples/`. Used by `tests/fixtures.rs` (it checks the files) and by
//! `examples/fixtures.rs` (it writes them).

use agent_workshop_bridge::adapters::Adapters;
use agent_workshop_bridge::adapters::claude_code::transcript_to_events;
use agent_workshop_bridge::adapters::pi::pi_event_to_arena;
use agent_workshop_bridge::js::Object;
use agent_workshop_bridge::schema::{normalize_event, validate_event};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

/// 2026-01-01T10:00:00Z, the time of the example sessions.
const FIRST_TS: i64 = 1_767_261_600_000;

pub const NAMES: [&str; 4] = ["claude-code", "hermes", "opencode", "pi"];

/// The root of the repository.
pub fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..")
}

pub fn fixture_path(name: &str) -> PathBuf {
    repo_root()
        .join("godot/test/fixtures")
        .join(format!("{name}.events.jsonl"))
}

fn lines(file: &str) -> Vec<Value> {
    let path = repo_root().join("schema/examples").join(file);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()))
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| serde_json::from_str(line).expect("a JSON line"))
        .collect()
}

/// The canonical events of one example, in order, before the times are fixed.
fn raw_events(name: &str) -> Vec<Value> {
    let mut adapters = Adapters::new();
    match name {
        "claude-code" => {
            let path = repo_root().join("schema/examples/claude-code-transcript.jsonl");
            transcript_to_events(&std::fs::read_to_string(path).expect("the transcript"))
        }
        "hermes" => lines("hermes-hooks.jsonl")
            .iter()
            .flat_map(|p| adapters.map("hermes", p).unwrap())
            .collect(),
        "opencode" => lines("opencode-events.jsonl")
            .into_iter()
            .flat_map(|event| adapters.map("opencode", &json!({ "event": event })).unwrap())
            .collect(),
        "pi" => {
            let mut session = json!("pi");
            let mut out = Vec::new();
            for event in lines("pi-json-mode.jsonl") {
                if event["type"] == "session" {
                    session = event["id"].clone();
                }
                out.extend(pi_event_to_arena(Some(&session), &event));
            }
            out
        }
        other => panic!("unknown example {other}"),
    }
}

/// The events of one example with fixed times: `ts` is first, 500 ms apart, unless the adapter
/// took a time from the example.
pub fn example_events(name: &str) -> Vec<Value> {
    raw_events(name)
        .into_iter()
        .enumerate()
        .map(|(i, event)| {
            let mut stamped = Object::new();
            stamped.insert("ts".into(), Value::from(FIRST_TS + i as i64 * 500));
            for (key, value) in event.as_object().expect("an event is an object") {
                stamped.insert(key.clone(), value.clone());
            }
            let normalized = normalize_event(&Value::Object(stamped), false);
            let problems = validate_event(&normalized);
            assert!(
                problems.is_empty(),
                "{name}: invalid event {normalized}: {}",
                problems.join("; ")
            );
            normalized
        })
        .collect()
}

/// The text of a fixture file: one JSON object per line.
pub fn fixture_text(events: &[Value]) -> String {
    let mut text = events.iter().map(Value::to_string).collect::<Vec<_>>().join("\n");
    text.push('\n');
    text
}
