//! Helpers that build canonical event objects the way the Node adapters do.

use crate::js::Object;
use crate::schema::SCHEMA_VERSION;
use serde_json::Value;

/// The start of an event: `v`, `framework`, `session`, `agent` and `type`.
pub fn base(framework: &str, session: &Value, agent: &Value, kind: &str) -> Object {
    let mut e = Object::new();
    e.insert("v".into(), Value::from(SCHEMA_VERSION));
    e.insert("framework".into(), Value::String(framework.to_string()));
    e.insert("session".into(), session.clone());
    e.insert("agent".into(), agent.clone());
    e.insert("type".into(), Value::String(kind.to_string()));
    e
}

/// Sets a field. `None` leaves the field out, like an `undefined` value in JavaScript.
pub fn with(mut e: Object, key: &str, value: Option<Value>) -> Object {
    if let Some(value) = value {
        e.insert(key.to_string(), value);
    }
    e
}

/// A string field. `None` leaves the field out.
pub fn with_str(e: Object, key: &str, value: Option<&str>) -> Object {
    with(e, key, value.map(|v| Value::String(v.to_string())))
}

/// The same as `with`, for an optional text that was built by the adapter.
pub fn with_text(e: Object, key: &str, value: Option<String>) -> Object {
    with(e, key, value.map(Value::String))
}
