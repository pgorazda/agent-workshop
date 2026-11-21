//! A test tool. It reads JSON lines from standard input and writes one JSON line for each.
//! The Node script `tools/diff.mjs` uses it to compare the adapters with the Node bridge.
//!
//! Input lines:
//!   {"op":"reset"}                                    new adapters, no state
//!   {"op":"hook","framework":"pi","payload":{...}}    what `POST /hook/<framework>` does
//!   {"op":"event","body":{...}}                       what `POST /event` does (one event or an array)
//!   {"op":"transcript","text":"..."}                  a Claude Code transcript, as `replay` reads it
//!   options: "redact": true
//! Output line: {"events":[...valid events...],"dropped":[[...problems...],...]}

use agent_workshop_bridge::adapters::Adapters;
use agent_workshop_bridge::adapters::claude_code::transcript_to_events;
use agent_workshop_bridge::js::get;
use agent_workshop_bridge::schema::{normalize_event, validate_event};
use serde_json::{Value, json};
use std::io::{BufRead, Write};

fn main() {
    let stdin = std::io::stdin();
    let mut out = std::io::stdout().lock();
    let mut adapters = Adapters::new();
    for line in stdin.lock().lines() {
        let line = line.expect("a line of input");
        if line.trim().is_empty() {
            continue;
        }
        let op: Value = serde_json::from_str(&line).expect("a JSON line");
        let redact = get(&op, "redact") == Some(&Value::Bool(true));
        let raw: Vec<Value> = match get(&op, "op").and_then(Value::as_str) {
            Some("reset") => {
                adapters = Adapters::new();
                writeln!(out, "{}", json!({"reset": true})).unwrap();
                continue;
            }
            Some("hook") => {
                let framework = get(&op, "framework").and_then(Value::as_str).unwrap_or("");
                let payload = get(&op, "payload").cloned().unwrap_or(Value::Null);
                adapters.map(framework, &payload).unwrap_or_default()
            }
            Some("event") => match get(&op, "body").cloned().unwrap_or(Value::Null) {
                Value::Array(items) => items,
                single => vec![single],
            },
            Some("transcript") => transcript_to_events(get(&op, "text").and_then(Value::as_str).unwrap_or("")),
            other => panic!("unknown op {other:?}"),
        };
        let mut events = Vec::new();
        let mut dropped = Vec::new();
        for item in &raw {
            let event = normalize_event(item, redact);
            let problems = validate_event(&event);
            if problems.is_empty() {
                events.push(event);
            } else {
                dropped.push(problems);
            }
        }
        writeln!(out, "{}", json!({"events": events, "dropped": dropped})).unwrap();
    }
}
