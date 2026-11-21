//! Picks the most useful single string describing what a tool call acts on.
//! Handles the argument names used by Claude Code, OpenCode, Pi and Hermes.

use crate::js::{get, non_nullish, to_js_string, truthy};
use serde_json::Value;

/// The last part of a path, split at `/` or `\`.
fn basename(path: &str) -> String {
    path.rsplit(['/', '\\']).next().unwrap_or("").to_string()
}

/// A short text for the target of a tool call, or `None` when the input has nothing useful.
pub fn describe_target(input: Option<&Value>) -> Option<String> {
    let input = input?;
    if !input.is_object() && !input.is_array() {
        return None; // null, a string, a number or a boolean
    }

    let file = non_nullish(get(input, "file_path"))
        .or_else(|| non_nullish(get(input, "filePath")))
        .or_else(|| non_nullish(get(input, "notebook_path")));
    if truthy(file) {
        return Some(basename(&to_js_string(file)));
    }
    let command = get(input, "command");
    if truthy(command) {
        let text = to_js_string(command);
        return Some(text.split('\n').next().unwrap_or("").to_string());
    }
    for key in ["pattern", "url", "query", "description", "goal"] {
        let value = get(input, key);
        if truthy(value) {
            return Some(to_js_string(value));
        }
    }
    if let Some(Value::Array(urls)) = get(input, "urls")
        && let Some(Value::String(first)) = urls.first()
    {
        return Some(first.clone());
    }
    let path = get(input, "path");
    if truthy(path) {
        return Some(basename(&to_js_string(path)));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn d(v: Value) -> Option<String> {
        describe_target(Some(&v))
    }

    #[test]
    fn picks_the_most_useful_field() {
        assert_eq!(d(json!({"file_path": "/a/b/c.txt"})).as_deref(), Some("c.txt"));
        assert_eq!(d(json!({"command": "ls -la\necho hi"})).as_deref(), Some("ls -la"));
        assert_eq!(d(json!({"pattern": "foo"})).as_deref(), Some("foo"));
        assert_eq!(d(json!({"url": "https://x.test"})).as_deref(), Some("https://x.test"));
        assert_eq!(d(json!(null)), None);
        assert_eq!(describe_target(None), None);
        assert_eq!(d(json!({})), None);
        assert_eq!(d(json!("text")), None);
    }

    #[test]
    fn handles_hermes_and_opencode_arguments() {
        assert_eq!(d(json!({"goal": "Do the thing"})).as_deref(), Some("Do the thing"));
        assert_eq!(
            d(json!({"urls": ["https://a.test", "https://b.test"]})).as_deref(),
            Some("https://a.test")
        );
        assert_eq!(d(json!({"path": "/a/b.py"})).as_deref(), Some("b.py"));
        assert_eq!(d(json!({"pattern": "x", "path": "src"})).as_deref(), Some("x"));
        assert_eq!(d(json!({"filePath": "C:\\work\\app.py"})).as_deref(), Some("app.py"));
        assert_eq!(
            d(json!({"notebook_path": "/n/book.ipynb"})).as_deref(),
            Some("book.ipynb")
        );
    }

    #[test]
    fn follows_javascript_rules_for_empty_and_odd_values() {
        // An empty file name is falsy, so the next field is tried.
        assert_eq!(d(json!({"file_path": "", "command": "ls"})).as_deref(), Some("ls"));
        // A null file name falls through `??` to the next name.
        assert_eq!(
            d(json!({"file_path": null, "filePath": "/x/y.rs"})).as_deref(),
            Some("y.rs")
        );
        // A number is turned into text.
        assert_eq!(d(json!({"pattern": 42})).as_deref(), Some("42"));
        // urls with a first item that is not a string gives nothing.
        assert_eq!(d(json!({"urls": [1]})), None);
        assert_eq!(d(json!({"urls": []})), None);
        // An array has no named fields.
        assert_eq!(d(json!(["a"])), None);
    }
}
