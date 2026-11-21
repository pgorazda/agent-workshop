//! Hermes Agent adapter (<https://github.com/NousResearch/hermes-agent>, package `hermes-agent`).
//!
//! Input is the JSON that Hermes pipes to a configured shell hook (`agent/shell_hooks.py`):
//!
//! ```text
//! { hook_event_name, tool_name, tool_input, session_id, cwd, extra }
//! ```
//!
//! `extra` holds every other hook kwarg. Events used:
//!
//! ```text
//! on_session_start          session_start
//! pre_api_request           thinking, only for the first API call of a turn (extra.api_call_count == 1)
//! pre_tool_call             tool_start   (tool_input = args, extra.tool_call_id)
//! post_tool_call            tool_end     (extra.status "ok" | "error" | "blocked", extra.error_message)
//! pre_approval_request      waiting_permission
//! subagent_start / _stop    helper penguin (extra.child_session_id; session_id is the parent session)
//! on_session_end            done, or error when extra.completed == false
//! api_request_error         error
//! ```
//!
//! `pre_llm_call` is deliberately not used: its payload carries the whole conversation history.
//!
//! Notes:
//! - Approval events carry no `session_id`, so they are attributed to the session seen most recently.
//! - A subagent's own tool calls arrive with the child session id. They are reported under the
//!   parent's session with agent = the child session id, which is also the id of the
//!   `subagent_start` event, so the game attaches them to the helper penguin.

use crate::categories::category_for;
use crate::event::{base, with, with_str, with_text};
use crate::js::{get, non_empty_str, s, truthy};
use crate::targets::describe_target;
use serde_json::Value;
use std::collections::HashMap;

const FRAMEWORK: &str = "hermes";

/// Where the events of a session are reported.
#[derive(Clone)]
struct Context {
    root: String,
    agent: String,
    parent: Option<(String, String)>, // (session, agent)
}

#[derive(Default)]
pub struct HermesAdapter {
    sessions: HashMap<String, Context>,
    last_session: Option<String>,
}

fn make(root: &str, agent: &str, kind: &str) -> crate::js::Object {
    base(FRAMEWORK, &s(root), &s(agent), kind)
}

impl HermesAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    fn context_for(&mut self, session_id: &str) -> Context {
        self.sessions
            .entry(session_id.to_string())
            .or_insert_with(|| Context {
                root: session_id.to_string(),
                agent: "main".into(),
                parent: None,
            })
            .clone()
    }

    pub fn from_hook(&mut self, payload: &Value) -> Vec<Value> {
        if !payload.is_object() {
            return Vec::new();
        }
        let name = get(payload, "hook_event_name").and_then(Value::as_str).unwrap_or("");
        let empty = Value::Object(Default::default());
        let extra = get(payload, "extra")
            .filter(|e| e.is_object() || e.is_array())
            .unwrap_or(&empty);

        // Subagent hooks: session_id is the parent session.
        if name == "subagent_start" || name == "subagent_stop" {
            let parent_id = non_empty_str(get(payload, "session_id"))
                .map(str::to_string)
                .or_else(|| self.last_session.clone());
            let child_id = non_empty_str(get(extra, "child_session_id"))
                .or_else(|| non_empty_str(get(extra, "child_subagent_id")))
                .map(str::to_string);
            let (Some(parent_id), Some(child_id)) = (parent_id, child_id) else {
                return Vec::new();
            };
            let parent = self.context_for(&parent_id);
            if name == "subagent_start" {
                self.sessions.insert(
                    child_id.clone(),
                    Context {
                        root: parent.root.clone(),
                        agent: child_id.clone(),
                        parent: Some((parent.root.clone(), parent.agent.clone())),
                    },
                );
                let e = with(
                    make(&parent.root, &parent.agent, "subagent_start"),
                    "id",
                    Some(s(&child_id)),
                );
                return vec![Value::Object(e)];
            }
            let known = self.sessions.remove(&child_id);
            let (root, agent) = match known.and_then(|k| k.parent) {
                Some((session, agent)) => (session, agent),
                None => (parent.root.clone(), parent.agent.clone()),
            };
            return vec![Value::Object(with(
                make(&root, &agent, "subagent_end"),
                "id",
                Some(s(&child_id)),
            ))];
        }

        let session_id = non_empty_str(get(payload, "session_id"))
            .map(str::to_string)
            .or_else(|| self.last_session.clone())
            .or_else(|| non_empty_str(get(extra, "session_key")).map(str::to_string))
            .unwrap_or_else(|| "hermes".to_string());
        if let Some(id) = non_empty_str(get(payload, "session_id")) {
            self.last_session = Some(id.to_string());
        }
        let ctx = self.context_for(&session_id);
        let ev = |kind: &str| make(&ctx.root, &ctx.agent, kind);

        match name {
            "on_session_start" => {
                if ctx.agent == "main" {
                    vec![Value::Object(ev("session_start"))]
                } else {
                    Vec::new()
                }
            }

            "pre_api_request" => {
                let first = get(extra, "api_call_count").and_then(Value::as_f64) == Some(1.0);
                if first {
                    vec![Value::Object(ev("thinking"))]
                } else {
                    Vec::new()
                }
            }

            "pre_tool_call" => {
                let Some(tool) = non_empty_str(get(payload, "tool_name")) else {
                    return Vec::new();
                };
                let mut e = ev("tool_start");
                e = with_str(e, "id", non_empty_str(get(extra, "tool_call_id")));
                e = with_str(e, "tool", Some(tool));
                e = with_str(e, "category", Some(category_for(FRAMEWORK, Some(tool))));
                e = with_text(e, "target", describe_target(get(payload, "tool_input")));
                vec![Value::Object(e)]
            }

            "post_tool_call" => {
                let Some(tool) = non_empty_str(get(payload, "tool_name")) else {
                    return Vec::new();
                };
                let status = get(extra, "status");
                let ok = match status {
                    None => !truthy(get(extra, "error_type")),
                    Some(status) => status.as_str() == Some("ok"),
                };
                let mut e = ev("tool_end");
                e = with_str(e, "id", non_empty_str(get(extra, "tool_call_id")));
                e = with_str(e, "tool", Some(tool));
                e = with(e, "ok", Some(Value::Bool(ok)));
                if !ok {
                    let blocked = status.and_then(Value::as_str) == Some("blocked");
                    let error =
                        non_empty_str(get(extra, "error_message")).or(if blocked { Some("blocked") } else { None });
                    e = with_str(e, "error", error);
                }
                vec![Value::Object(e)]
            }

            "pre_approval_request" => {
                vec![Value::Object(with_str(
                    ev("waiting_permission"),
                    "message",
                    non_empty_str(get(extra, "description")),
                ))]
            }

            "on_session_end" => {
                if ctx.agent != "main" {
                    return Vec::new(); // a subagent ends with subagent_stop
                }
                if get(extra, "completed") == Some(&Value::Bool(false)) {
                    let message = if truthy(get(extra, "interrupted")) {
                        "interrupted"
                    } else {
                        "incomplete"
                    };
                    vec![Value::Object(with_str(ev("error"), "message", Some(message)))]
                } else {
                    vec![Value::Object(ev("done"))]
                }
            }

            "api_request_error" => {
                vec![Value::Object(with_str(
                    ev("error"),
                    "message",
                    non_empty_str(get(extra, "error_type")),
                ))]
            }

            _ => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{normalize_event, validate_event};
    use serde_json::json;

    const HOOKS: &str = include_str!("../../../schema/examples/hermes-hooks.jsonl");

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

    fn payloads() -> Vec<Value> {
        HOOKS
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }

    fn run(list: &[Value]) -> Vec<Value> {
        let mut adapter = HermesAdapter::new();
        list.iter().flat_map(|p| adapter.from_hook(p)).collect()
    }

    #[test]
    fn hook_payloads_map_to_the_expected_events_and_every_event_is_valid() {
        let out = run(&payloads());
        let summary: Vec<String> = out.iter().map(summarize).collect();
        assert_eq!(
            summary,
            [
                "session_start",
                "thinking",
                "tool_start:read:app.py",
                "tool_end",
                "tool_start:exec:rm -rf build",
                "waiting_permission",
                "tool_end",
                "tool_start:exec:pytest -q",
                "tool_end(fail)",
                "tool_start:delegate:Investigate the failing test",
                "subagent_start",
                "tool_start:search:fixture",
                "tool_end",
                "subagent_end",
                "tool_end",
                "tool_start:web:https://example.com/docs",
                "tool_end",
                "done",
            ]
        );
        for e in &out {
            assert!(validate_event(&normalize_event(e, false)).is_empty(), "{e}");
        }
        assert!(
            out.iter()
                .all(|e| e["framework"] == "hermes" && e["session"] == "sess_1")
        );
    }

    #[test]
    fn approvals_without_a_session_id_are_attributed_to_the_session_seen_last() {
        let out = run(&payloads());
        let ask = out.iter().find(|e| e["type"] == "waiting_permission").unwrap();
        assert_eq!(ask["session"], "sess_1");
        assert_eq!(ask["agent"], "main");
        assert_eq!(ask["message"], "recursive delete");
    }

    #[test]
    fn subagent_activity_is_reported_under_the_parent_with_the_child_as_agent() {
        let out = run(&payloads());
        let start = out.iter().find(|e| e["type"] == "subagent_start").unwrap();
        let end = out.iter().find(|e| e["type"] == "subagent_end").unwrap();
        let child: Vec<_> = out.iter().filter(|e| e["agent"] == "sess_child").collect();
        assert_eq!(
            (&start["id"], &start["agent"], &start["session"]),
            (&json!("sess_child"), &json!("main"), &json!("sess_1"))
        );
        assert_eq!(
            (&end["id"], &end["agent"], &end["session"]),
            (&json!("sess_child"), &json!("main"), &json!("sess_1"))
        );
        let kinds: Vec<_> = child.iter().map(|e| e["type"].as_str().unwrap()).collect();
        assert_eq!(kinds, ["tool_start", "tool_end"]);
        assert_eq!(out.iter().filter(|e| e["type"] == "session_start").count(), 1);
        assert_eq!(out.iter().filter(|e| e["type"] == "done").count(), 1);
    }

    #[test]
    fn a_failed_tool_carries_its_error_and_status_and_error_type_decide_the_outcome() {
        let mut adapter = HermesAdapter::new();
        let mut end = |extra: Value| {
            adapter.from_hook(&json!({"hook_event_name": "post_tool_call", "tool_name": "terminal", "session_id": "s", "extra": extra}))
                .remove(0)
        };
        assert_eq!(end(json!({"status": "ok"}))["ok"], true);
        let bad = end(json!({"status": "error", "error_message": "exit code 1"}));
        assert_eq!((&bad["ok"], &bad["error"]), (&json!(false), &json!("exit code 1")));
        let blocked = end(json!({"status": "blocked"}));
        assert_eq!((&blocked["ok"], &blocked["error"]), (&json!(false), &json!("blocked")));
        assert_eq!(end(json!({"error_type": "ValueError"}))["ok"], false);
        assert_eq!(end(json!({}))["ok"], true);
        assert_eq!(end(json!({"status": null}))["ok"], false);
    }

    #[test]
    fn only_the_first_api_call_means_thinking_and_interrupted_turns_are_errors() {
        let mut adapter = HermesAdapter::new();
        let mut hook = |name: &str, extra: Value| {
            adapter.from_hook(&json!({"hook_event_name": name, "session_id": "s", "extra": extra}))
        };
        assert_eq!(hook("pre_api_request", json!({"api_call_count": 1})).len(), 1);
        assert_eq!(hook("pre_api_request", json!({"api_call_count": 2})).len(), 0);
        assert_eq!(hook("pre_api_request", json!({})).len(), 0);
        assert_eq!(hook("on_session_end", json!({"completed": true}))[0]["type"], "done");
        let interrupted = hook("on_session_end", json!({"completed": false, "interrupted": true})).remove(0);
        assert_eq!(
            (&interrupted["type"], &interrupted["message"]),
            (&json!("error"), &json!("interrupted"))
        );
        assert_eq!(
            hook("on_session_end", json!({"completed": false}))[0]["message"],
            "incomplete"
        );
        assert_eq!(
            hook("api_request_error", json!({"error_type": "RateLimit"}))[0]["message"],
            "RateLimit"
        );
    }

    #[test]
    fn unknown_hooks_junk_and_missing_fields_produce_nothing() {
        let mut adapter = HermesAdapter::new();
        assert!(adapter.from_hook(&json!(null)).is_empty());
        assert!(adapter
            .from_hook(&json!({"hook_event_name": "pre_llm_call", "session_id": "s", "extra": {"conversation_history": []}}))
            .is_empty());
        assert!(
            adapter
                .from_hook(&json!({"hook_event_name": "pre_tool_call", "session_id": "s"}))
                .is_empty()
        );
        assert!(
            adapter
                .from_hook(&json!({"hook_event_name": "subagent_start", "session_id": "s", "extra": {}}))
                .is_empty()
        );
        // Without any session id, a fresh adapter falls back to a default. After one is seen it reuses it.
        let fresh = HermesAdapter::new().from_hook(&json!({"hook_event_name": "on_session_end", "extra": {}}));
        assert_eq!(fresh[0]["session"], "hermes");
        assert_eq!(
            adapter.from_hook(&json!({"hook_event_name": "on_session_end", "extra": {}}))[0]["session"],
            "s"
        );
        let keyed = HermesAdapter::new()
            .from_hook(&json!({"hook_event_name": "on_session_end", "extra": {"session_key": "k"}}));
        assert_eq!(keyed[0]["session"], "k");
    }

    #[test]
    fn a_subagent_stop_for_an_unknown_child_is_reported_under_the_parent() {
        let mut adapter = HermesAdapter::new();
        let out = adapter.from_hook(
            &json!({"hook_event_name": "subagent_stop", "session_id": "p", "extra": {"child_session_id": "c"}}),
        );
        assert_eq!(
            (&out[0]["session"], &out[0]["agent"], &out[0]["id"]),
            (&json!("p"), &json!("main"), &json!("c"))
        );
    }
}
