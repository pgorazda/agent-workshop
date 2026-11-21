//! Canonical Agent Workshop event schema, version 1.
//! Keep in sync with `schema/event.schema.json` (a test guards the enums).

use crate::js::{Object, get, to_js_string};
use serde_json::Value;
use std::time::{SystemTime, UNIX_EPOCH};

pub const SCHEMA_VERSION: u64 = 1;

pub const CATEGORIES: [&str; 9] = [
    "read",
    "search",
    "write",
    "exec",
    "web",
    "delegate",
    "think",
    "ask_permission",
    "other",
];

pub const EVENT_TYPES: [&str; 9] = [
    "session_start",
    "tool_start",
    "tool_end",
    "subagent_start",
    "subagent_end",
    "thinking",
    "waiting_permission",
    "error",
    "done",
];

const MAX_TARGET: usize = 120;
const MAX_ERROR: usize = 200;

/// Milliseconds since the Unix epoch, like `Date.now()`.
pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Cuts a text to `max` characters, with an ellipsis as the last one.
fn truncate(text: &str, max: usize) -> String {
    if text.chars().count() > max {
        let mut out: String = text.chars().take(max - 1).collect();
        out.push('…');
        out
    } else {
        text.to_string()
    }
}

/// Fills defaults and clamps long strings. Returns a new value and never changes the input.
/// Unknown extra fields are kept so that newer adapters keep working with older bridges.
pub fn normalize_event(input: &Value, redact_targets: bool) -> Value {
    let Some(object) = input.as_object() else {
        return input.clone();
    };
    let mut e: Object = object.clone();
    if !e.contains_key("agent") {
        e.insert("agent".into(), Value::String("main".into()));
    }
    if !e.contains_key("ts") {
        e.insert("ts".into(), Value::from(now_ms()));
    }
    if let Some(target) = e.get("target") {
        let text = truncate(&to_js_string(Some(target)), MAX_TARGET);
        e.insert("target".into(), Value::String(text));
    }
    if let Some(error) = e.get("error") {
        let text = truncate(&to_js_string(Some(error)), MAX_ERROR);
        e.insert("error".into(), Value::String(text));
    }
    if redact_targets {
        e.shift_remove("target");
        e.shift_remove("error");
    }
    Value::Object(e)
}

fn is_non_empty_string(value: Option<&Value>) -> bool {
    matches!(value, Some(Value::String(s)) if !s.is_empty())
}

/// Validates a (normalized) event. Returns a list of error texts. An empty list means valid.
/// Unknown event types are accepted on purpose: clients fall back to a generic animation.
pub fn validate_event(e: &Value) -> Vec<String> {
    let Some(object) = e.as_object() else {
        return vec!["event must be an object".to_string()];
    };
    let mut errors = Vec::new();

    let version_ok = get(e, "v")
        .and_then(Value::as_f64)
        .is_some_and(|v| v == SCHEMA_VERSION as f64);
    if !version_ok {
        errors.push(format!("v must be {SCHEMA_VERSION}"));
    }
    for (key, label) in [
        ("framework", "framework must be a non-empty string"),
        ("session", "session must be a non-empty string"),
        ("agent", "agent must be a non-empty string"),
        ("type", "type must be a non-empty string"),
    ] {
        if !is_non_empty_string(object.get(key)) {
            errors.push(label.to_string());
        }
    }
    if !matches!(object.get("ts"), Some(Value::Number(_))) {
        errors.push("ts must be a number (epoch ms)".to_string());
    }
    if let Some(category) = object.get("category") {
        let known = category.as_str().is_some_and(|c| CATEGORIES.contains(&c));
        if !known {
            errors.push(format!("category must be one of: {}", CATEGORIES.join(", ")));
        }
    }
    if let Some(ok) = object.get("ok")
        && !ok.is_boolean()
    {
        errors.push("ok must be a boolean".to_string());
    }
    if let Some(cost) = object.get("cost")
        && !cost.is_number()
    {
        errors.push("cost must be a number".to_string());
    }
    for key in ["tool", "target", "error", "id", "message"] {
        if let Some(value) = object.get(key)
            && !value.is_string()
        {
            errors.push(format!("{key} must be a string"));
        }
    }

    match object.get("type").and_then(Value::as_str) {
        Some("tool_start") => {
            if !object.contains_key("category") {
                errors.push("tool_start requires category".to_string());
            }
            if !is_non_empty_string(object.get("tool")) {
                errors.push("tool_start requires tool".to_string());
            }
        }
        Some("tool_end") => {
            if !matches!(object.get("ok"), Some(Value::Bool(_))) {
                errors.push("tool_end requires ok".to_string());
            }
        }
        Some(kind @ ("subagent_start" | "subagent_end")) if !is_non_empty_string(object.get("id")) => {
            errors.push(format!("{kind} requires id"));
        }
        _ => {}
    }
    errors
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn base() -> Value {
        json!({"v": 1, "framework": "pi", "session": "s1", "type": "thinking"})
    }

    fn with(extra: Value) -> Value {
        let mut e = base();
        for (k, v) in extra.as_object().unwrap() {
            e[k] = v.clone();
        }
        e
    }

    fn errs(extra: Value) -> Vec<String> {
        validate_event(&normalize_event(&with(extra), false))
    }

    #[test]
    fn normalize_fills_agent_and_ts_and_does_not_change_the_input() {
        let input = base();
        let e = normalize_event(&input, false);
        assert_eq!(e["agent"], "main");
        assert!(e["ts"].is_number());
        assert!(input.get("agent").is_none());
    }

    #[test]
    fn normalize_keeps_a_given_agent_and_ts() {
        let e = normalize_event(&with(json!({"agent": "a1", "ts": 5})), false);
        assert_eq!((e["agent"].clone(), e["ts"].clone()), (json!("a1"), json!(5)));
    }

    #[test]
    fn normalize_truncates_long_targets_and_can_redact_them() {
        let long = "x".repeat(500);
        let e = normalize_event(&with(json!({"target": long})), false);
        assert_eq!(e["target"].as_str().unwrap().chars().count(), 120);
        assert!(e["target"].as_str().unwrap().ends_with('…'));
        let long_error = "y".repeat(500);
        let e = normalize_event(&with(json!({"error": long_error})), false);
        assert_eq!(e["error"].as_str().unwrap().chars().count(), 200);
        let redacted = normalize_event(&with(json!({"target": "secret", "error": "secret"})), true);
        assert!(redacted.get("target").is_none());
        assert!(redacted.get("error").is_none());
    }

    #[test]
    fn normalize_turns_a_target_that_is_not_a_string_into_text() {
        let e = normalize_event(&with(json!({"target": 5, "error": null})), false);
        assert_eq!(e["target"], "5");
        assert_eq!(e["error"], "null");
    }

    #[test]
    fn normalize_leaves_values_that_are_not_objects() {
        assert_eq!(normalize_event(&json!(null), false), json!(null));
        assert_eq!(normalize_event(&json!([1]), false), json!([1]));
        assert_eq!(normalize_event(&json!("x"), false), json!("x"));
    }

    #[test]
    fn a_minimal_event_and_unknown_types_are_valid() {
        assert!(validate_event(&normalize_event(&base(), false)).is_empty());
        assert!(errs(json!({"type": "something_new"})).is_empty());
    }

    #[test]
    fn per_type_requirements_are_enforced() {
        assert!(errs(json!({"type": "tool_start"})).len() >= 2);
        assert!(errs(json!({"type": "tool_start", "category": "read", "tool": "Read"})).is_empty());
        assert!(errs(json!({"type": "tool_end"})).iter().any(|m| m.contains("ok")));
        assert!(errs(json!({"type": "subagent_start"})).iter().any(|m| m.contains("id")));
        assert!(
            errs(json!({"type": "tool_start", "category": "nope", "tool": "x"}))
                .iter()
                .any(|m| m.contains("category"))
        );
        assert!(errs(json!({"v": 2})).iter().any(|m| m.contains("v must be")));
        assert!(!validate_event(&json!("nope")).is_empty());
        assert!(!validate_event(&json!(null)).is_empty());
        assert!(!validate_event(&json!([])).is_empty());
    }

    #[test]
    fn error_texts_are_the_ones_of_the_node_bridge() {
        assert_eq!(
            validate_event(&json!({"type": "tool_start", "category": "nope"})),
            vec![
                "v must be 1",
                "framework must be a non-empty string",
                "session must be a non-empty string",
                "agent must be a non-empty string",
                "ts must be a number (epoch ms)",
                "category must be one of: read, search, write, exec, web, delegate, think, ask_permission, other",
                "tool_start requires tool",
            ]
        );
    }

    #[test]
    fn field_types_are_checked() {
        assert!(errs(json!({"ok": "yes"})).iter().any(|m| m == "ok must be a boolean"));
        assert!(errs(json!({"cost": "1"})).iter().any(|m| m == "cost must be a number"));
        assert!(errs(json!({"tool": 5})).iter().any(|m| m == "tool must be a string"));
        assert!(
            errs(json!({"message": null}))
                .iter()
                .any(|m| m == "message must be a string")
        );
        assert!(errs(json!({"v": 1.0})).is_empty());
        assert!(errs(json!({"ts": "5"})).iter().any(|m| m.starts_with("ts must")));
    }

    #[test]
    fn enums_match_the_json_schema_file() {
        let schema: Value = serde_json::from_str(include_str!("../../schema/event.schema.json")).unwrap();
        let list = |v: &Value| -> Vec<String> {
            v.as_array()
                .unwrap()
                .iter()
                .map(|x| x.as_str().unwrap().to_string())
                .collect()
        };
        let props = &schema["properties"];
        assert_eq!(list(&props["category"]["enum"]), CATEGORIES.to_vec());
        let documented = props["type"]["description"].as_str().unwrap();
        for kind in EVENT_TYPES {
            assert!(documented.contains(kind), "{kind} is missing from the schema text");
        }
        assert_eq!(props["v"]["const"], json!(SCHEMA_VERSION));
    }
}
