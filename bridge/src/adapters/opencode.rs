//! OpenCode adapter (<https://opencode.ai>). Input is the `Event` objects OpenCode passes to a
//! plugin's `event` hook (types: `@opencode-ai/sdk`), wrapped as `{ event }` by the plugin.
//!
//! Events used:
//!
//! ```text
//! session.created / session.updated   Session { id, parentID? }: a parentID marks a subagent
//! session.idle                         root: done; subagent: subagent_end
//! session.deleted, session.error, session.status (retry)
//! message.updated                      role "user" means the agent starts thinking
//! message.part.updated                 ToolPart { callID, tool, state } and ReasoningPart
//! permission.updated                   waiting_permission
//! ```
//!
//! Tool lifecycle comes from `ToolPart.state.status` (pending, running, completed, error), which
//! reports failures reliably, unlike the `tool.execute.after` hook.
//!
//! Subagents run in child sessions. Their events are reported under the root session with
//! agent = the child session id, which is also the id of the `subagent_start` event, so the game
//! can attach the activity to the helper penguin.

use crate::categories::category_for;
use crate::event::{base, with, with_str, with_text};
use crate::js::{Object, get, key_of, non_nullish, s, to_js_string, truthy};
use crate::targets::describe_target;
use serde_json::Value;
use std::collections::{HashMap, HashSet};

const FRAMEWORK: &str = "opencode";
const MAX_REMEMBERED: usize = 5000;

fn remember(set: &mut HashSet<String>, value: String) {
    if set.len() >= MAX_REMEMBERED {
        set.clear();
    }
    set.insert(value);
}

/// Where the events of a session are reported.
#[derive(Clone)]
struct Context {
    root: Value,
    agent: Value,
    parent: Option<Value>, // the id of the parent session
}

#[derive(Default)]
pub struct OpenCodeAdapter {
    sessions: HashMap<String, Context>,
    started_tools: HashSet<String>,
    ended_tools: HashSet<String>,
    thinking_parts: HashSet<String>,
    user_messages: HashSet<String>,
    open_subagents: HashSet<String>,
}

impl OpenCodeAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    fn context_for(&mut self, session_id: &Value) -> Context {
        self.sessions
            .entry(key_of(session_id))
            .or_insert_with(|| Context {
                root: session_id.clone(),
                agent: s("main"),
                parent: None,
            })
            .clone()
    }

    fn make(&mut self, session_id: &Value, kind: &str) -> Object {
        let ctx = self.context_for(session_id);
        base(FRAMEWORK, &ctx.root, &ctx.agent, kind)
    }

    /// Registers a session the first time it is seen. A child session also announces a subagent.
    fn register(&mut self, info: Option<&Value>) -> Vec<Value> {
        let Some(info) = info else { return Vec::new() };
        let Some(Value::String(id)) = get(info, "id") else {
            return Vec::new();
        };
        if self.sessions.contains_key(&key_of(&Value::String(id.clone()))) {
            return Vec::new();
        }
        let id_value = Value::String(id.clone());
        if truthy(get(info, "parentID")) {
            let parent_id = get(info, "parentID").cloned().unwrap_or(Value::Null);
            let parent = self.context_for(&parent_id);
            self.sessions.insert(
                key_of(&id_value),
                Context {
                    root: parent.root.clone(),
                    agent: id_value.clone(),
                    parent: Some(parent_id.clone()),
                },
            );
            remember(&mut self.open_subagents, id.clone());
            let e = with(self.make(&parent_id, "subagent_start"), "id", Some(id_value));
            return vec![Value::Object(e)];
        }
        self.sessions.insert(
            key_of(&id_value),
            Context {
                root: id_value.clone(),
                agent: s("main"),
                parent: None,
            },
        );
        vec![Value::Object(self.make(&id_value, "session_start"))]
    }

    fn end_subagent(&mut self, session_id: &Value) -> Vec<Value> {
        let Some(parent_id) = self.sessions.get(&key_of(session_id)).and_then(|c| c.parent.clone()) else {
            return Vec::new();
        };
        let was_open = match session_id {
            Value::String(id) => self.open_subagents.remove(id),
            _ => false,
        };
        if !was_open {
            return Vec::new();
        }
        let e = with(self.make(&parent_id, "subagent_end"), "id", Some(session_id.clone()));
        vec![Value::Object(e)]
    }

    fn map_tool_part(&mut self, part: &Value) -> Vec<Value> {
        let session_id = get(part, "sessionID");
        let key = non_nullish(get(part, "callID")).or_else(|| get(part, "id"));
        let state = get(part, "state");
        let status = state.and_then(|st| get(st, "status")).and_then(Value::as_str);
        if !truthy(session_id) || !truthy(key) || !truthy(get(part, "tool")) {
            return Vec::new();
        }
        let (session_id, key) = (session_id.unwrap().clone(), key.unwrap().clone());
        let tool = get(part, "tool").cloned();
        let mut events = Vec::new();

        let start = |this: &mut Self, events: &mut Vec<Value>| {
            if this.started_tools.contains(&key_of(&key)) {
                return;
            }
            remember(&mut this.started_tools, key_of(&key));
            let mut e = this.make(&session_id, "tool_start");
            e = with(e, "id", Some(key.clone()));
            e = with(e, "tool", tool.clone());
            let name = tool.as_ref().and_then(Value::as_str);
            e = with_str(e, "category", Some(category_for(FRAMEWORK, name)));
            e = with_text(e, "target", describe_target(state.and_then(|st| get(st, "input"))));
            events.push(Value::Object(e));
        };

        match status {
            // 'pending' is skipped: its input is usually still empty.
            Some("running") => start(self, &mut events),
            Some(done @ ("completed" | "error")) => {
                if self.ended_tools.contains(&key_of(&key)) {
                    return Vec::new();
                }
                start(self, &mut events);
                remember(&mut self.ended_tools, key_of(&key));
                let mut e = self.make(&session_id, "tool_end");
                e = with(e, "id", Some(key.clone()));
                e = with(e, "tool", tool.clone());
                e = with(e, "ok", Some(Value::Bool(done == "completed")));
                if done == "error"
                    && let Some(Value::String(text)) = state.and_then(|st| get(st, "error"))
                {
                    e = with_str(e, "error", Some(text));
                }
                events.push(Value::Object(e));
            }
            _ => {}
        }
        events
    }

    pub fn from_event(&mut self, event: &Value) -> Vec<Value> {
        if !event.is_object() {
            return Vec::new();
        }
        let empty = Value::Object(Default::default());
        let props = non_nullish(get(event, "properties")).unwrap_or(&empty);

        match get(event, "type").and_then(Value::as_str).unwrap_or("") {
            "session.created" | "session.updated" => self.register(get(props, "info")),

            "session.idle" => {
                let session_id = get(props, "sessionID");
                if !truthy(session_id) {
                    return Vec::new();
                }
                let session_id = session_id.unwrap().clone();
                let has_parent = self
                    .sessions
                    .get(&key_of(&session_id))
                    .is_some_and(|c| c.parent.is_some());
                if has_parent {
                    self.end_subagent(&session_id)
                } else {
                    vec![Value::Object(self.make(&session_id, "done"))]
                }
            }

            "session.deleted" => {
                let id = get(props, "info").and_then(|i| get(i, "id"));
                if !truthy(id) {
                    return Vec::new();
                }
                let id = id.unwrap().clone();
                let events = self.end_subagent(&id);
                self.sessions.remove(&key_of(&id));
                events
            }

            "session.error" => {
                let session_id = get(props, "sessionID");
                if !truthy(session_id) {
                    return Vec::new();
                }
                let message = get(props, "error").and_then(|e| get(e, "name")).cloned();
                let e = with(self.make(&session_id.unwrap().clone(), "error"), "message", message);
                vec![Value::Object(e)]
            }

            "session.status" => {
                let status = get(props, "status");
                let session_id = get(props, "sessionID");
                if status.and_then(|st| get(st, "type")).and_then(Value::as_str) != Some("retry") || !truthy(session_id)
                {
                    return Vec::new();
                }
                let attempt = status.and_then(|st| get(st, "attempt"));
                let message = format!("retry {}", to_js_string(attempt));
                let e = with_str(
                    self.make(&session_id.unwrap().clone(), "error"),
                    "message",
                    Some(&message),
                );
                vec![Value::Object(e)]
            }

            "message.updated" => {
                let Some(info) = get(props, "info") else {
                    return Vec::new();
                };
                if get(info, "role").and_then(Value::as_str) != Some("user")
                    || !truthy(get(info, "id"))
                    || !truthy(get(info, "sessionID"))
                {
                    return Vec::new();
                }
                let message_id = key_of(get(info, "id").unwrap());
                if self.user_messages.contains(&message_id) {
                    return Vec::new();
                }
                remember(&mut self.user_messages, message_id);
                let session_id = get(info, "sessionID").unwrap().clone();
                vec![Value::Object(self.make(&session_id, "thinking"))]
            }

            "message.part.updated" => {
                let Some(part) = get(props, "part").filter(|p| truthy(Some(p))) else {
                    return Vec::new();
                };
                match get(part, "type").and_then(Value::as_str) {
                    Some("tool") => self.map_tool_part(part),
                    Some("reasoning") => {
                        let ended = truthy(get(part, "time").and_then(|t| get(t, "end")));
                        if truthy(get(part, "sessionID")) && truthy(get(part, "id")) && !ended {
                            let part_id = key_of(get(part, "id").unwrap());
                            if self.thinking_parts.contains(&part_id) {
                                return Vec::new();
                            }
                            remember(&mut self.thinking_parts, part_id);
                            let session_id = get(part, "sessionID").unwrap().clone();
                            return vec![Value::Object(self.make(&session_id, "thinking"))];
                        }
                        Vec::new()
                    }
                    _ => Vec::new(),
                }
            }

            "permission.updated" | "permission.asked" => {
                let session_id = get(props, "sessionID");
                if !truthy(session_id) {
                    return Vec::new();
                }
                let title = get(props, "title").cloned();
                let e = with(
                    self.make(&session_id.unwrap().clone(), "waiting_permission"),
                    "message",
                    title,
                );
                vec![Value::Object(e)]
            }

            _ => Vec::new(),
        }
    }

    /// The adapter for `POST /hook/opencode`. The payload is `{ event }` or a bare event.
    pub fn from_payload(&mut self, payload: &Value) -> Vec<Value> {
        if !payload.is_object() {
            return Vec::new();
        }
        let event = non_nullish(get(payload, "event")).unwrap_or(payload);
        self.from_event(event)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{normalize_event, validate_event};
    use serde_json::json;

    const RAW: &str = include_str!("../../../schema/examples/opencode-events.jsonl");

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

    fn raw_events() -> Vec<Value> {
        RAW.lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }

    fn run(events: &[Value]) -> Vec<Value> {
        let mut adapter = OpenCodeAdapter::new();
        events
            .iter()
            .flat_map(|event| adapter.from_payload(&json!({"event": event})))
            .collect()
    }

    const EXPECTED: [&str; 17] = [
        "session_start",
        "thinking",
        "thinking",
        "tool_start:read:app.py",
        "tool_end",
        "tool_start:exec:pytest -q",
        "tool_end(fail)",
        "tool_start:delegate:Investigate failure",
        "subagent_start",
        "tool_start:search:fixture",
        "tool_end",
        "subagent_end",
        "tool_end",
        "waiting_permission",
        "tool_start:exec:rm -rf build",
        "tool_end",
        "done",
    ];

    #[test]
    fn events_map_to_the_expected_events_and_every_event_is_valid() {
        let out = run(&raw_events());
        let summary: Vec<String> = out.iter().map(summarize).collect();
        assert_eq!(summary, EXPECTED);
        for e in &out {
            assert!(validate_event(&normalize_event(e, false)).is_empty(), "{e}");
        }
        assert!(
            out.iter()
                .all(|e| e["framework"] == "opencode" && e["session"] == "ses_root")
        );
    }

    #[test]
    fn subagent_activity_is_reported_under_the_root_with_the_child_as_agent() {
        let out = run(&raw_events());
        let start = out.iter().find(|e| e["type"] == "subagent_start").unwrap();
        let end = out.iter().find(|e| e["type"] == "subagent_end").unwrap();
        let child: Vec<_> = out.iter().filter(|e| e["agent"] == "ses_child").collect();
        assert_eq!((&start["id"], &start["agent"]), (&json!("ses_child"), &json!("main")));
        assert_eq!(end["id"], "ses_child");
        let kinds: Vec<_> = child.iter().map(|e| e["type"].as_str().unwrap()).collect();
        assert_eq!(kinds, ["tool_start", "tool_end"]);
        assert!(out.iter().filter(|e| e["agent"] == "main").count() > child.len());
    }

    #[test]
    fn a_failed_tool_part_carries_its_error_text() {
        let out = run(&raw_events());
        let failed = out
            .iter()
            .find(|e| e["type"] == "tool_end" && e["ok"] == false)
            .unwrap();
        assert_eq!(failed["id"], "call_2");
        assert_eq!(failed["error"], "exit code 1");
    }

    #[test]
    fn a_tool_first_seen_as_completed_still_starts_and_ends_and_repeats_are_ignored() {
        let part = |status: &str| {
            json!({"type": "message.part.updated", "properties": {"part": {
                "type": "tool", "id": "p", "sessionID": "s", "callID": "c", "tool": "read",
                "state": {"status": status, "input": {"filePath": "/a/b.txt"}}}}})
        };
        let out = run(&[part("completed"), part("completed"), part("running")]);
        let summary: Vec<String> = out.iter().map(summarize).collect();
        assert_eq!(summary, ["tool_start:read:b.txt", "tool_end"]);
    }

    #[test]
    fn errors_retries_deletion_and_noise() {
        let mut adapter = OpenCodeAdapter::new();
        let mut one = |event: Value| adapter.from_event(&event);
        assert_eq!(
            one(json!({"type": "session.error", "properties": {"sessionID": "s", "error": {"name": "ApiError"}}}))[0]["message"],
            "ApiError"
        );
        assert_eq!(
            one(
                json!({"type": "session.status", "properties": {"sessionID": "s", "status": {"type": "retry", "attempt": 2}}})
            )[0]["message"],
            "retry 2"
        );
        assert!(
            one(json!({"type": "session.status", "properties": {"sessionID": "s", "status": {"type": "busy"}}}))
                .is_empty()
        );
        assert!(one(json!({"type": "file.edited", "properties": {}})).is_empty());
        assert!(one(json!({"type": "session.idle", "properties": {}})).is_empty());
        assert!(one(json!(null)).is_empty());
        // A child session deleted while still open ends its subagent exactly once.
        one(json!({"type": "session.created", "properties": {"info": {"id": "root"}}}));
        one(json!({"type": "session.created", "properties": {"info": {"id": "kid", "parentID": "root"}}}));
        let gone = one(json!({"type": "session.deleted", "properties": {"info": {"id": "kid"}}}));
        let pairs: Vec<_> = gone.iter().map(|e| (e["type"].clone(), e["id"].clone())).collect();
        assert_eq!(pairs, [(json!("subagent_end"), json!("kid"))]);
        // The deleted child is unknown now, so an idle event for it is a root "done".
        let idle = one(json!({"type": "session.idle", "properties": {"sessionID": "kid"}}));
        assert_eq!(
            idle.iter().map(|e| e["type"].as_str().unwrap()).collect::<Vec<_>>(),
            ["done"]
        );
    }

    #[test]
    fn a_bare_event_is_accepted_too() {
        let mut adapter = OpenCodeAdapter::new();
        let out = adapter.from_payload(&json!({"type": "session.idle", "properties": {"sessionID": "s"}}));
        assert_eq!(out[0]["type"], "done");
        assert!(adapter.from_payload(&json!(null)).is_empty());
        assert!(adapter.from_payload(&json!(5)).is_empty());
    }

    #[test]
    fn a_child_session_that_goes_idle_ends_its_subagent_once() {
        let mut adapter = OpenCodeAdapter::new();
        adapter.from_event(&json!({"type": "session.created", "properties": {"info": {"id": "root"}}}));
        adapter
            .from_event(&json!({"type": "session.created", "properties": {"info": {"id": "kid", "parentID": "root"}}}));
        let idle = json!({"type": "session.idle", "properties": {"sessionID": "kid"}});
        assert_eq!(adapter.from_event(&idle)[0]["type"], "subagent_end");
        assert!(adapter.from_event(&idle).is_empty());
    }

    #[test]
    fn user_messages_and_reasoning_parts_count_once() {
        let mut adapter = OpenCodeAdapter::new();
        let user =
            json!({"type": "message.updated", "properties": {"info": {"id": "m", "sessionID": "s", "role": "user"}}});
        assert_eq!(adapter.from_event(&user).len(), 1);
        assert!(adapter.from_event(&user).is_empty());
        let assistant = json!({"type": "message.updated", "properties": {"info": {"id": "a", "sessionID": "s", "role": "assistant"}}});
        assert!(adapter.from_event(&assistant).is_empty());
        let reasoning = |end: bool| {
            let mut part = json!({"type": "reasoning", "id": "r", "sessionID": "s"});
            if end {
                part["time"] = json!({"end": 5});
            }
            json!({"type": "message.part.updated", "properties": {"part": part}})
        };
        assert!(adapter.from_event(&reasoning(true)).is_empty());
        assert_eq!(adapter.from_event(&reasoning(false)).len(), 1);
        assert!(adapter.from_event(&reasoning(false)).is_empty());
    }

    #[test]
    fn remembered_ids_are_cleared_when_the_set_is_full() {
        let mut set = HashSet::new();
        for i in 0..MAX_REMEMBERED {
            remember(&mut set, i.to_string());
        }
        assert_eq!(set.len(), MAX_REMEMBERED);
        remember(&mut set, "new".into());
        assert_eq!(set.len(), 1);
    }

    #[test]
    fn permission_events_wait() {
        let mut adapter = OpenCodeAdapter::new();
        let out = adapter
            .from_event(&json!({"type": "permission.asked", "properties": {"sessionID": "s", "title": "Run rm"}}));
        assert_eq!(
            (&out[0]["type"], &out[0]["message"]),
            (&json!("waiting_permission"), &json!("Run rm"))
        );
    }
}
