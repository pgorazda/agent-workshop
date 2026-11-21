//! Pi adapter (<https://github.com/badlogic/pi-mono>, package `@mariozechner/pi-coding-agent`).
//!
//! Input is a Pi session event, either from `pi --mode json` (JSON lines on stdout) or from an
//! extension's event handlers. Both use the same event shapes (`AgentSessionEvent`), so one mapper
//! serves both:
//!
//! ```text
//! session header            {"type":"session","id":"<uuid>",...}       (json mode only)
//! session_start             extension event
//! agent_start / agent_end   one per user prompt
//! message_update            assistantMessageEvent.type == "thinking_start" means reasoning began
//! tool_execution_start      { toolCallId, toolName, args }
//! tool_execution_end        { toolCallId, toolName, result, isError }
//! compaction_start, auto_retry_start
//! ```
//!
//! Pi has no built-in subagents or permission prompts. An extension tool that maps to the
//! "delegate" category (for example one named "subagent") produces subagent events.

use crate::categories::category_for;
use crate::event::{base, with, with_str, with_text};
use crate::js::{get, non_nullish, s, to_js_string, truthy};
use crate::targets::describe_target;
use serde_json::Value;

const FRAMEWORK: &str = "pi";

/// Tool results are `{ content: [{ type: 'text', text }], ... }`. Only used for error text.
fn result_text(result: Option<&Value>) -> Option<String> {
    let Some(Value::Array(items)) = result.and_then(|r| get(r, "content")) else {
        return None;
    };
    let first = items
        .iter()
        .find(|c| get(c, "type").and_then(Value::as_str) == Some("text"))?;
    match get(first, "text") {
        Some(Value::String(text)) => Some(text.clone()),
        _ => None,
    }
}

/// Maps one Pi event. `session` is the fallback session id, used when the event carries none.
pub fn pi_event_to_arena(session: Option<&Value>, event: &Value) -> Vec<Value> {
    if !event.is_object() {
        return Vec::new();
    }
    let sid = non_nullish(session).cloned().unwrap_or_else(|| s("pi"));
    let main = s("main");
    let ev = |session: &Value, kind: &str| base(FRAMEWORK, session, &main, kind);
    let tool_name = get(event, "toolName");

    match get(event, "type").and_then(Value::as_str).unwrap_or("") {
        "session" => {
            let id = match get(event, "id") {
                Some(id @ Value::String(_)) => id.clone(),
                _ => sid,
            };
            vec![Value::Object(ev(&id, "session_start"))]
        }
        "session_start" => vec![Value::Object(ev(&sid, "session_start"))],
        "agent_start" | "compaction_start" => vec![Value::Object(ev(&sid, "thinking"))],

        // Fires per token. Only the start of a reasoning block matters.
        "message_update" => {
            let started = get(event, "assistantMessageEvent")
                .and_then(|m| get(m, "type"))
                .and_then(Value::as_str)
                == Some("thinking_start");
            if started {
                vec![Value::Object(ev(&sid, "thinking"))]
            } else {
                Vec::new()
            }
        }

        "tool_execution_start" => {
            if !truthy(tool_name) {
                return Vec::new();
            }
            let category = category_for(FRAMEWORK, tool_name.and_then(Value::as_str));
            let mut e = ev(&sid, "tool_start");
            e = with(e, "id", get(event, "toolCallId").cloned());
            e = with(e, "tool", tool_name.cloned());
            e = with_str(e, "category", Some(category));
            e = with_text(e, "target", describe_target(get(event, "args")));
            let mut events = vec![Value::Object(e)];
            if category == "delegate" && truthy(get(event, "toolCallId")) {
                events.push(Value::Object(with(
                    ev(&sid, "subagent_start"),
                    "id",
                    get(event, "toolCallId").cloned(),
                )));
            }
            events
        }

        "tool_execution_end" => {
            if !truthy(tool_name) {
                return Vec::new();
            }
            let ok = get(event, "isError") != Some(&Value::Bool(true));
            let mut e = ev(&sid, "tool_end");
            e = with(e, "id", get(event, "toolCallId").cloned());
            e = with(e, "tool", tool_name.cloned());
            e = with(e, "ok", Some(Value::Bool(ok)));
            if !ok {
                e = with_text(e, "error", result_text(get(event, "result")));
            }
            let mut events = vec![Value::Object(e)];
            if category_for(FRAMEWORK, tool_name.and_then(Value::as_str)) == "delegate"
                && truthy(get(event, "toolCallId"))
            {
                events.push(Value::Object(with(
                    ev(&sid, "subagent_end"),
                    "id",
                    get(event, "toolCallId").cloned(),
                )));
            }
            events
        }

        "auto_retry_start" => {
            let message = format!(
                "retry {}/{}",
                to_js_string(get(event, "attempt")),
                to_js_string(get(event, "maxAttempts"))
            );
            vec![Value::Object(with_str(ev(&sid, "error"), "message", Some(&message)))]
        }

        "agent_end" => vec![Value::Object(ev(&sid, "done"))],

        _ => Vec::new(),
    }
}

/// The adapter for `POST /hook/pi`. The payload is `{ session?: string, event: <Pi event> }`.
#[derive(Default)]
pub struct PiAdapter;

impl PiAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn from_payload(&self, payload: &Value) -> Vec<Value> {
        if !payload.is_object() {
            return Vec::new();
        }
        match get(payload, "event") {
            Some(event) => pi_event_to_arena(get(payload, "session"), event),
            None => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{normalize_event, validate_event};
    use serde_json::json;

    const FIXTURE: &str = include_str!("../../../schema/examples/pi-json-mode.jsonl");

    /// One-line description of an event, used to compare streams in tests.
    fn summarize(e: &Value) -> String {
        match e["type"].as_str().unwrap() {
            "tool_start" => format!(
                "tool_start:{}:{}",
                e["category"].as_str().unwrap(),
                e.get("target").and_then(Value::as_str).unwrap_or("")
            ),
            "tool_end" => {
                if e["ok"] == false {
                    "tool_end(fail)".to_string()
                } else {
                    "tool_end".to_string()
                }
            }
            other => other.to_string(),
        }
    }

    fn fixture() -> Vec<Value> {
        FIXTURE
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }

    #[test]
    fn json_mode_stream_maps_to_the_expected_events_and_every_event_is_valid() {
        let mut events = Vec::new();
        let mut session = json!("fallback");
        for event in fixture() {
            if event["type"] == "session" {
                session = event["id"].clone();
            }
            events.extend(pi_event_to_arena(Some(&session), &event));
        }
        let summary: Vec<String> = events.iter().map(summarize).collect();
        assert_eq!(
            summary,
            [
                "session_start",
                "thinking",
                "thinking",
                "tool_start:read:app.py",
                "tool_end",
                "tool_start:write:app.py",
                "tool_end",
                "tool_start:exec:pytest -q",
                "tool_end(fail)",
                "tool_start:delegate:Investigate the failure",
                "subagent_start",
                "tool_end",
                "subagent_end",
                "tool_start:search:fixture",
                "tool_end",
                "error",
                "done",
            ]
        );
        for e in &events {
            assert!(validate_event(&normalize_event(e, false)).is_empty(), "{e}");
        }
        assert!(
            events
                .iter()
                .all(|e| e["framework"] == "pi" && e["session"] == "pi-session-1")
        );
    }

    #[test]
    fn failed_tools_carry_the_error_text_and_ok_tools_do_not() {
        let mut events = Vec::new();
        for event in fixture() {
            events.extend(pi_event_to_arena(Some(&json!("s")), &event));
        }
        let ends: Vec<_> = events.iter().filter(|e| e["type"] == "tool_end").collect();
        let c3 = ends.iter().find(|e| e["id"] == "c3").unwrap();
        assert_eq!(c3["ok"], false);
        assert!(c3["error"].as_str().unwrap().contains("exited with code 1"));
        assert!(ends.iter().find(|e| e["id"] == "c1").unwrap().get("error").is_none());
    }

    #[test]
    fn streaming_noise_produces_no_events() {
        let s = json!("s");
        for kind in [
            "turn_start",
            "turn_end",
            "message_start",
            "message_end",
            "tool_execution_update",
            "queue_update",
        ] {
            assert!(pi_event_to_arena(Some(&s), &json!({"type": kind})).is_empty(), "{kind}");
        }
        let delta = json!({"type": "message_update", "assistantMessageEvent": {"type": "text_delta", "delta": "x"}});
        assert!(pi_event_to_arena(Some(&s), &delta).is_empty());
        assert!(pi_event_to_arena(Some(&s), &json!(null)).is_empty());
        assert!(pi_event_to_arena(Some(&s), &json!({"type": "tool_execution_start"})).is_empty());
    }

    #[test]
    fn from_payload_reads_session_and_event_and_falls_back_to_a_default_session() {
        let adapter = PiAdapter::new();
        assert_eq!(
            adapter.from_payload(&json!({"session": "abc", "event": {"type": "agent_end"}}))[0]["session"],
            "abc"
        );
        assert_eq!(
            adapter.from_payload(&json!({"event": {"type": "agent_end"}}))[0]["session"],
            "pi"
        );
        assert_eq!(
            adapter.from_payload(&json!({"session": null, "event": {"type": "agent_end"}}))[0]["session"],
            "pi"
        );
        assert!(adapter.from_payload(&json!(null)).is_empty());
        assert!(adapter.from_payload(&json!({"session": "x"})).is_empty());
    }

    #[test]
    fn retry_text_and_a_session_header_without_a_string_id() {
        let e = pi_event_to_arena(
            Some(&json!("s")),
            &json!({"type": "auto_retry_start", "attempt": 2, "maxAttempts": 3}),
        );
        assert_eq!(e[0]["message"], "retry 2/3");
        let e = pi_event_to_arena(Some(&json!("s")), &json!({"type": "auto_retry_start"}));
        assert_eq!(e[0]["message"], "retry undefined/undefined");
        let e = pi_event_to_arena(Some(&json!("fallback")), &json!({"type": "session", "id": 5}));
        assert_eq!(e[0]["session"], "fallback");
    }

    #[test]
    fn a_tool_that_is_not_a_delegate_opens_no_subagent() {
        let events = pi_event_to_arena(
            Some(&json!("s")),
            &json!({"type": "tool_execution_start", "toolCallId": "x", "toolName": "bash", "args": {"command": "ls"}}),
        );
        assert_eq!(summarize(&events[0]), "tool_start:exec:ls");
        assert_eq!(events.len(), 1);
    }
}
