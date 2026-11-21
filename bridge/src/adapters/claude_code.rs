//! Claude Code adapter: turns hook payloads (live) and transcript lines (replay)
//! into canonical Agent Workshop events.
//!
//! Hook payload fields used: `hook_event_name`, `session_id`, `tool_name`, `tool_input`,
//! `tool_response`, `tool_use_id`, `message`. Field availability differs between Claude Code
//! versions, so every field is treated as optional.

use crate::categories::category_for;
use crate::event::{base, with, with_str, with_text};
use crate::js::{get, key_of, non_nullish, s, to_js_string, truthy};
use crate::targets::describe_target;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

const FRAMEWORK: &str = "claude-code";

/// Best effort: a hook response has no single failure flag across tools and versions.
pub fn response_failed(response: Option<&Value>) -> bool {
    let Some(response) = response.filter(|r| r.is_object()) else {
        return false;
    };
    get(response, "is_error") == Some(&Value::Bool(true))
        || get(response, "interrupted") == Some(&Value::Bool(true))
        || truthy(get(response, "error"))
}

fn response_error(response: Option<&Value>) -> Option<String> {
    let response = response.filter(|r| r.is_object())?;
    let err = non_nullish(get(response, "error")).or_else(|| non_nullish(get(response, "stderr")));
    match err {
        Some(Value::String(text)) if !text.is_empty() => Some(text.clone()),
        _ => None,
    }
}

fn contains_permission(text: &str) -> bool {
    text.to_lowercase().contains("permission")
}

/// The live adapter. It keeps a small per-session stack of open subagents.
#[derive(Default)]
pub struct ClaudeCodeAdapter {
    open_subagents: HashMap<String, Vec<Value>>,
    counter: u64,
}

impl ClaudeCodeAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_hook(&mut self, payload: &Value) -> Vec<Value> {
        if !payload.is_object() {
            return Vec::new();
        }
        let session = non_nullish(get(payload, "session_id"))
            .cloned()
            .unwrap_or_else(|| s("unknown"));
        let main = s("main");
        let ev = |kind: &str| base(FRAMEWORK, &session, &main, kind);
        let tool = get(payload, "tool_name");
        let name = get(payload, "hook_event_name").and_then(Value::as_str).unwrap_or("");

        match name {
            "SessionStart" => vec![Value::Object(ev("session_start"))],
            "UserPromptSubmit" => vec![Value::Object(ev("thinking"))],

            "PreToolUse" => {
                if !truthy(tool) {
                    return Vec::new();
                }
                let category = category_for(FRAMEWORK, tool.and_then(Value::as_str));
                let mut e = ev("tool_start");
                e = with(e, "id", get(payload, "tool_use_id").cloned());
                e = with(e, "tool", tool.cloned());
                e = with_str(e, "category", Some(category));
                e = with_text(e, "target", describe_target(get(payload, "tool_input")));
                let mut events = vec![Value::Object(e)];
                if category == "delegate" {
                    let id = match non_nullish(get(payload, "tool_use_id")) {
                        Some(id) => id.clone(),
                        None => {
                            self.counter += 1;
                            Value::String(format!("sub-{}", self.counter))
                        }
                    };
                    self.open_subagents
                        .entry(key_of(&session))
                        .or_default()
                        .push(id.clone());
                    events.push(Value::Object(with(ev("subagent_start"), "id", Some(id))));
                }
                events
            }

            "PostToolUse" => {
                if !truthy(tool) {
                    return Vec::new();
                }
                let response = get(payload, "tool_response");
                let mut e = ev("tool_end");
                e = with(e, "id", get(payload, "tool_use_id").cloned());
                e = with(e, "tool", tool.cloned());
                e = with(e, "ok", Some(Value::Bool(!response_failed(response))));
                e = with_text(e, "error", response_error(response));
                vec![Value::Object(e)]
            }

            "PostToolUseFailure" => {
                if !truthy(tool) {
                    return Vec::new();
                }
                let mut e = ev("tool_end");
                e = with(e, "id", get(payload, "tool_use_id").cloned());
                e = with(e, "tool", tool.cloned());
                e = with(e, "ok", Some(Value::Bool(false)));
                let error = get(payload, "error").filter(|v| v.is_string()).cloned();
                vec![Value::Object(with(e, "error", error))]
            }

            "Notification" => {
                let message = get(payload, "message");
                let text = to_js_string(non_nullish(message).or(Some(&s(""))));
                if contains_permission(&text) {
                    vec![Value::Object(with(
                        ev("waiting_permission"),
                        "message",
                        message.cloned(),
                    ))]
                } else {
                    Vec::new()
                }
            }

            "SubagentStop" => {
                let id = self
                    .open_subagents
                    .entry(key_of(&session))
                    .or_default()
                    .pop()
                    .unwrap_or_else(|| s("unknown"));
                vec![Value::Object(with(ev("subagent_end"), "id", Some(id)))]
            }

            "Stop" => {
                self.open_subagents.remove(&key_of(&session));
                vec![Value::Object(ev("done"))]
            }

            _ => Vec::new(),
        }
    }
}

/// Milliseconds since the epoch of an RFC 3339 time text, or `None` when it cannot be read.
fn parse_time(value: Option<&Value>) -> Option<i64> {
    let text = value?.as_str()?;
    let parsed = OffsetDateTime::parse(text, &Rfc3339).ok()?;
    i64::try_from(parsed.unix_timestamp_nanos() / 1_000_000).ok()
}

/// The replay adapter. It converts the text of a Claude Code transcript (JSONL) into events with
/// timestamps taken from the transcript. Lines that are not understood are skipped.
pub fn transcript_to_events(text: &str) -> Vec<Value> {
    let mut events: Vec<Value> = Vec::new();
    let mut last_ts: Option<i64> = None;
    let mut last_session = s("replay");
    let mut delegate_ids: HashSet<String> = HashSet::new();

    for raw in text.split('\n') {
        let line = raw.trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}');
        if line.is_empty() {
            continue;
        }
        let Ok(entry) = crate::js::parse_json(line) else {
            continue;
        };
        if !entry.is_object() {
            continue;
        }

        let session = non_nullish(get(&entry, "sessionId"))
            .cloned()
            .unwrap_or_else(|| last_session.clone());
        last_session = session.clone();
        let ts = parse_time(get(&entry, "timestamp")).or(last_ts);
        if ts.is_some() {
            last_ts = ts;
        }
        let agent = if truthy(get(&entry, "isSidechain")) {
            let id = non_nullish(get(&entry, "agentId"))
                .cloned()
                .unwrap_or_else(|| s("sidechain"));
            Value::String(to_js_string(Some(&id)))
        } else {
            s("main")
        };
        let mk = |kind: &str| base(FRAMEWORK, &session, &agent, kind);
        // The time comes last, after the other fields, as in the Node adapter.
        let stamp = |e: crate::js::Object| with(e, "ts", ts.map(Value::from));

        let content = get(&entry, "message").and_then(|m| get(m, "content"));
        let entry_type = get(&entry, "type").and_then(Value::as_str);

        if entry_type == Some("assistant") {
            if let Some(Value::Array(blocks)) = content {
                for block in blocks {
                    let block_type = get(block, "type").and_then(Value::as_str);
                    if block_type == Some("thinking") {
                        events.push(Value::Object(stamp(mk("thinking"))));
                    } else if block_type == Some("tool_use") && truthy(get(block, "name")) {
                        let name = get(block, "name");
                        let category = category_for(FRAMEWORK, name.and_then(Value::as_str));
                        let mut e = mk("tool_start");
                        e = with(e, "id", get(block, "id").cloned());
                        e = with(e, "tool", name.cloned());
                        e = with_str(e, "category", Some(category));
                        e = with_text(e, "target", describe_target(get(block, "input")));
                        events.push(Value::Object(stamp(e)));
                        if category == "delegate" && truthy(get(block, "id")) {
                            let id = get(block, "id").cloned().unwrap_or(Value::Null);
                            delegate_ids.insert(key_of(&id));
                            events.push(Value::Object(stamp(with(mk("subagent_start"), "id", Some(id)))));
                        }
                    }
                }
            }
        } else if entry_type == Some("user") {
            let has_result = matches!(content, Some(Value::Array(blocks))
                if blocks.iter().any(|b| get(b, "type").and_then(Value::as_str) == Some("tool_result")));
            if has_result {
                if let Some(Value::Array(blocks)) = content {
                    for block in blocks {
                        if get(block, "type").and_then(Value::as_str) != Some("tool_result") {
                            continue;
                        }
                        let tool_use_id = get(block, "tool_use_id");
                        let ok = get(block, "is_error") != Some(&Value::Bool(true));
                        let mut e = mk("tool_end");
                        e = with(e, "id", tool_use_id.cloned());
                        e = with(e, "ok", Some(Value::Bool(ok)));
                        events.push(Value::Object(stamp(e)));
                        if let Some(id) = tool_use_id
                            && delegate_ids.remove(&key_of(id))
                        {
                            events.push(Value::Object(stamp(with(mk("subagent_end"), "id", Some(id.clone())))));
                        }
                    }
                }
            } else if !truthy(get(&entry, "isMeta")) {
                // A real user prompt: the agent starts thinking.
                events.push(Value::Object(stamp(mk("thinking"))));
            }
        }
    }

    if let Some(last) = events.last() {
        let session = get(last, "session").cloned().unwrap_or(Value::Null);
        let ts = get(last, "ts").cloned();
        let e = base(FRAMEWORK, &session, &s("main"), "done");
        events.push(Value::Object(with(e, "ts", ts)));
    }
    events
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{normalize_event, validate_event};
    use serde_json::json;

    fn hook(name: &str, extra: Value) -> Value {
        let mut payload = json!({"hook_event_name": name, "session_id": "c1"});
        for (k, v) in extra.as_object().unwrap() {
            payload[k] = v.clone();
        }
        payload
    }

    fn assert_all_valid(events: &[Value]) {
        for e in events {
            assert_eq!(validate_event(&normalize_event(e, false)), Vec::<String>::new(), "{e}");
        }
    }

    #[test]
    fn pre_tool_use_becomes_tool_start_with_category_and_target() {
        let mut adapter = ClaudeCodeAdapter::new();
        let events = adapter.from_hook(&hook(
            "PreToolUse",
            json!({"tool_name": "Edit", "tool_use_id": "tu1", "tool_input": {"file_path": "/repo/src/app.py"}}),
        ));
        assert_eq!(events.len(), 1);
        let e = &events[0];
        assert_eq!(
            (
                e["type"].clone(),
                e["category"].clone(),
                e["tool"].clone(),
                e["target"].clone(),
                e["id"].clone()
            ),
            (
                json!("tool_start"),
                json!("write"),
                json!("Edit"),
                json!("app.py"),
                json!("tu1")
            )
        );
        assert_all_valid(&events);
    }

    #[test]
    fn post_tool_use_maps_failure_heuristics_to_ok_false() {
        let mut adapter = ClaudeCodeAdapter::new();
        let ok = adapter.from_hook(&hook(
            "PostToolUse",
            json!({"tool_name": "Bash", "tool_response": {"stdout": "fine"}}),
        ));
        let bad = adapter.from_hook(&hook(
            "PostToolUse",
            json!({"tool_name": "Bash", "tool_response": {"is_error": true, "error": "boom"}}),
        ));
        let failure = adapter.from_hook(&hook(
            "PostToolUseFailure",
            json!({"tool_name": "Bash", "error": "denied"}),
        ));
        assert_eq!(ok[0]["ok"], true);
        assert_eq!(bad[0]["ok"], false);
        assert_eq!(bad[0]["error"], "boom");
        assert_eq!(failure[0]["ok"], false);
        assert_eq!(failure[0]["error"], "denied");
        let all: Vec<Value> = [ok, bad, failure].concat();
        assert_all_valid(&all);
    }

    #[test]
    fn the_error_comes_from_stderr_only_when_error_is_missing_or_null() {
        let end = |response: Value| {
            ClaudeCodeAdapter::new().from_hook(&hook(
                "PostToolUse",
                json!({"tool_name": "Bash", "tool_response": response}),
            ))
        };
        assert_eq!(end(json!({"stderr": "oops"}))[0]["error"], "oops");
        assert_eq!(end(json!({"error": null, "stderr": "oops"}))[0]["error"], "oops");
        assert!(end(json!({"error": "", "stderr": "oops"}))[0].get("error").is_none());
        assert_eq!(end(json!({"interrupted": true}))[0]["ok"], false);
        assert_eq!(end(json!("text"))[0]["ok"], true);
        assert_eq!(end(json!({"error": "x"}))[0]["ok"], false);
    }

    #[test]
    fn task_opens_a_subagent_and_subagent_stop_closes_it() {
        let mut adapter = ClaudeCodeAdapter::new();
        let start = adapter.from_hook(&hook(
            "PreToolUse",
            json!({"tool_name": "Task", "tool_use_id": "sub1", "tool_input": {"description": "x"}}),
        ));
        let kinds: Vec<_> = start.iter().map(|e| e["type"].as_str().unwrap().to_string()).collect();
        assert_eq!(kinds, ["tool_start", "subagent_start"]);
        assert_eq!(start[1]["id"], "sub1");
        let stop = adapter.from_hook(&hook("SubagentStop", json!({})));
        assert_eq!(
            (stop[0]["type"].clone(), stop[0]["id"].clone()),
            (json!("subagent_end"), json!("sub1"))
        );
        let all: Vec<Value> = [start, stop].concat();
        assert_all_valid(&all);
    }

    #[test]
    fn a_task_without_a_tool_use_id_gets_a_counted_id_and_an_empty_stack_gives_unknown() {
        let mut adapter = ClaudeCodeAdapter::new();
        let first = adapter.from_hook(&hook("PreToolUse", json!({"tool_name": "Task"})));
        let second = adapter.from_hook(&hook("PreToolUse", json!({"tool_name": "Task", "tool_use_id": null})));
        assert_eq!(first[1]["id"], "sub-1");
        assert_eq!(second[1]["id"], "sub-2");
        assert_eq!(adapter.from_hook(&hook("SubagentStop", json!({})))[0]["id"], "sub-2");
        assert_eq!(adapter.from_hook(&hook("SubagentStop", json!({})))[0]["id"], "sub-1");
        assert_eq!(adapter.from_hook(&hook("SubagentStop", json!({})))[0]["id"], "unknown");
    }

    #[test]
    fn stop_forgets_the_open_subagents_of_the_session() {
        let mut adapter = ClaudeCodeAdapter::new();
        adapter.from_hook(&hook("PreToolUse", json!({"tool_name": "Task", "tool_use_id": "a"})));
        adapter.from_hook(&hook("Stop", json!({})));
        assert_eq!(adapter.from_hook(&hook("SubagentStop", json!({})))[0]["id"], "unknown");
    }

    #[test]
    fn a_notification_about_permission_waits_and_other_notifications_are_ignored() {
        let mut adapter = ClaudeCodeAdapter::new();
        let ask = adapter.from_hook(&hook(
            "Notification",
            json!({"message": "Claude needs your PERMISSION to use Bash"}),
        ));
        assert_eq!(ask[0]["type"], "waiting_permission");
        assert!(
            adapter
                .from_hook(&hook(
                    "Notification",
                    json!({"message": "Claude is waiting for your input"})
                ))
                .is_empty()
        );
        assert!(adapter.from_hook(&hook("Notification", json!({}))).is_empty());
    }

    #[test]
    fn simple_hooks_and_junk() {
        let mut adapter = ClaudeCodeAdapter::new();
        assert_eq!(adapter.from_hook(&hook("Stop", json!({})))[0]["type"], "done");
        assert_eq!(
            adapter.from_hook(&hook("SessionStart", json!({})))[0]["type"],
            "session_start"
        );
        assert_eq!(
            adapter.from_hook(&hook("UserPromptSubmit", json!({})))[0]["type"],
            "thinking"
        );
        assert!(adapter.from_hook(&hook("PreCompact", json!({}))).is_empty());
        assert!(adapter.from_hook(&json!(null)).is_empty());
        assert!(adapter.from_hook(&json!([1])).is_empty());
        assert!(adapter.from_hook(&hook("PreToolUse", json!({}))).is_empty());
        assert_eq!(
            adapter.from_hook(&json!({"hook_event_name": "Stop"}))[0]["session"],
            "unknown"
        );
    }

    #[test]
    fn a_session_id_that_is_not_a_string_is_kept_so_that_validation_rejects_it() {
        let mut adapter = ClaudeCodeAdapter::new();
        let events = adapter.from_hook(&json!({"hook_event_name": "Stop", "session_id": 5}));
        assert_eq!(events[0]["session"], 5);
        assert!(!validate_event(&normalize_event(&events[0], false)).is_empty());
    }

    const TRANSCRIPT: &str = include_str!("../../../schema/examples/claude-code-transcript.jsonl");

    #[test]
    fn transcript_replay_produces_a_valid_ordered_event_stream() {
        let events = transcript_to_events(TRANSCRIPT);
        assert_all_valid(&events);
        let summary: Vec<String> = events
            .iter()
            .map(|e| {
                let kind = e["type"].as_str().unwrap();
                if kind == "tool_start" {
                    format!("{kind}:{}", e["category"].as_str().unwrap())
                } else {
                    kind.to_string()
                }
            })
            .collect();
        assert_eq!(
            summary,
            [
                "thinking",
                "thinking",
                "tool_start:search",
                "tool_end",
                "tool_start:read",
                "tool_end",
                "tool_start:write",
                "tool_end",
                "tool_start:exec",
                "tool_end",
                "tool_start:delegate",
                "subagent_start",
                "tool_end",
                "subagent_end",
                "tool_start:web",
                "tool_end",
                "done",
            ]
        );
        let failed: Vec<_> = events
            .iter()
            .filter(|e| e["type"] == "tool_end" && e["ok"] == false)
            .collect();
        assert_eq!(failed.len(), 1);
        assert_eq!(failed[0]["id"], "toolu_4");
        assert!(events.iter().all(|e| e["session"] == "demo-1"));
        for pair in events.windows(2) {
            assert!(
                pair[1]["ts"].as_i64() >= pair[0]["ts"].as_i64(),
                "timestamps are monotonic"
            );
        }
    }

    #[test]
    fn transcript_replay_skips_garbage_and_returns_nothing_for_empty_input() {
        assert!(transcript_to_events("").is_empty());
        assert!(transcript_to_events("not json\n{\"type\":\"summary\"}\n[1]\n5\n").is_empty());
    }

    #[test]
    fn transcript_times_in_rfc_3339_are_read_and_others_are_ignored() {
        assert_eq!(
            parse_time(Some(&json!("2026-01-01T10:00:00.000Z"))),
            Some(1_767_261_600_000)
        );
        assert_eq!(
            parse_time(Some(&json!("2026-01-01T11:00:00+01:00"))),
            Some(1_767_261_600_000)
        );
        assert_eq!(parse_time(Some(&json!("yesterday"))), None);
        assert_eq!(parse_time(Some(&json!(5))), None);
        assert_eq!(parse_time(None), None);
    }

    #[test]
    fn a_byte_order_mark_at_the_start_of_a_transcript_does_not_hide_the_first_line() {
        let line = r#"{"type":"user","sessionId":"s","timestamp":"2026-01-01T10:00:00Z","message":{"content":"hi"}}"#;
        let events = transcript_to_events(&format!("\u{feff}{line}\n"));
        assert_eq!(events.len(), 2, "a thinking event and the done event");
    }

    #[test]
    fn sidechain_entries_use_the_agent_id() {
        let text = r#"{"type":"assistant","sessionId":"s","isSidechain":true,"agentId":"ag1","timestamp":"2026-01-01T10:00:00Z","message":{"content":[{"type":"thinking"}]}}"#;
        let events = transcript_to_events(text);
        assert_eq!(events[0]["agent"], "ag1");
        assert_eq!(events.last().unwrap()["agent"], "main");
    }
}
