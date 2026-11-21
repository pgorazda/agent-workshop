//! Small helpers that copy the way JavaScript reads loosely typed JSON.
//!
//! The adapters read payloads where every field is optional and may have any type. The Node
//! bridge relies on JavaScript rules for that (`??`, truthiness, `String(x)`). The helpers here
//! give the same answers for the values that JSON can hold.

use serde_json::{Map, Value};

/// A JSON object. Event objects are always maps.
pub type Object = Map<String, Value>;

/// `value.key` in JavaScript, for a value that came from JSON: only objects have named
/// properties here. A missing key and `undefined` are the same thing.
pub fn get<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    value.as_object().and_then(|o| o.get(key))
}

/// `a ?? b` for properties: a missing key or `null` counts as "not there".
pub fn non_nullish(value: Option<&Value>) -> Option<&Value> {
    value.filter(|v| !v.is_null())
}

/// JavaScript truthiness of a value that may be missing (`undefined`).
pub fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().is_some_and(|f| f != 0.0 && !f.is_nan()),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(_) | Value::Object(_)) => true,
    }
}

/// `String(value)` in JavaScript. A missing value gives `"undefined"`.
pub fn to_js_string(value: Option<&Value>) -> String {
    match value {
        None => "undefined".to_string(),
        Some(Value::Null) => "null".to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(Value::Number(n)) => number_to_js_string(n),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Object(_)) => "[object Object]".to_string(),
        Some(Value::Array(items)) => items
            .iter()
            .map(|item| {
                if item.is_null() {
                    String::new()
                } else {
                    to_js_string(Some(item))
                }
            })
            .collect::<Vec<_>>()
            .join(","),
    }
}

/// `String(number)` in JavaScript for the common cases: whole numbers have no `.0`, `-0` is `0`, and from 1e21 on the
/// text has an exponent. (Very small numbers keep the text of Rust: that is a known small difference.)
fn number_to_js_string(n: &serde_json::Number) -> String {
    if n.is_i64() || n.is_u64() {
        return n.to_string();
    }
    let f = n.as_f64().unwrap_or(0.0);
    if f == 0.0 {
        "0".to_string()
    } else if f.fract() == 0.0 && f.abs() < 1e21 {
        format!("{f:.0}")
    } else if f.abs() >= 1e21 {
        let text = format!("{f:e}"); // 1e21 or 1.5e22
        text.replacen('e', "e+", 1)
    } else {
        f.to_string()
    }
}

/// Parses JSON. JavaScript writes a lone surrogate as `\ud83d` (for example when a text is cut in the middle of an emoji), which a
/// strict parser rejects. Such an escape is replaced by U+FFFD and the text is parsed again, so the event is not lost.
pub fn parse_json(text: &str) -> Result<Value, serde_json::Error> {
    match serde_json::from_str(text) {
        Ok(value) => Ok(value),
        Err(err) => match replace_lone_surrogates(text) {
            Some(fixed) => serde_json::from_str(&fixed),
            None => Err(err),
        },
    }
}

/// The text with every `\uD800`-`\uDFFF` escape that is not half of a valid pair replaced by `\ufffd`, or `None` when there is none.
fn replace_lone_surrogates(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let hex = |at: usize| -> Option<u32> {
        let digits = bytes.get(at..at + 4)?;
        u32::from_str_radix(std::str::from_utf8(digits).ok()?, 16).ok()
    };
    let mut out = String::with_capacity(text.len());
    let mut changed = false;
    let mut i = 0;
    let mut copied = 0;
    while i < bytes.len() {
        if bytes[i] != b'\\' {
            i += 1;
            continue;
        }
        // A backslash starts an escape of two or more characters. `\\` is skipped as a pair, so `\\u` is not an escape.
        if bytes.get(i + 1) == Some(&b'u')
            && let Some(code) = hex(i + 2)
        {
            let pair_follows = bytes.get(i + 6) == Some(&b'\\') && bytes.get(i + 7) == Some(&b'u');
            let low_next = if pair_follows { hex(i + 8) } else { None };
            let is_high = (0xD800..0xDC00).contains(&code);
            let is_low = (0xDC00..0xE000).contains(&code);
            if is_high && low_next.is_some_and(|c| (0xDC00..0xE000).contains(&c)) {
                i += 12; // a valid pair
                continue;
            }
            if is_high || is_low {
                out.push_str(&text[copied..i]);
                out.push_str("\\ufffd");
                changed = true;
                i += 6;
                copied = i;
                continue;
            }
            i += 6;
            continue;
        }
        i += 2;
    }
    if !changed {
        return None;
    }
    out.push_str(&text[copied..]);
    Some(out)
}

/// A string value that is not empty (`typeof x === 'string' && x.length > 0`).
pub fn non_empty_str(value: Option<&Value>) -> Option<&str> {
    match value {
        Some(Value::String(s)) if !s.is_empty() => Some(s),
        _ => None,
    }
}

/// A key for sets and maps that follows JavaScript's identity rules for ids: the number 1 and
/// the string "1" are different keys.
pub fn key_of(value: &Value) -> String {
    value.to_string()
}

/// Clones a value into `Some`, so that a present `null` stays `null`.
pub fn cloned(value: Option<&Value>) -> Option<Value> {
    value.cloned()
}

/// A string as a JSON value.
pub fn s(text: &str) -> Value {
    Value::String(text.to_string())
}

/// A string option as an optional JSON value.
pub fn opt_s(text: Option<&str>) -> Option<Value> {
    text.map(s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn truthiness_follows_javascript() {
        assert!(!truthy(None));
        assert!(!truthy(Some(&json!(null))));
        assert!(!truthy(Some(&json!(false))));
        assert!(!truthy(Some(&json!(0))));
        assert!(!truthy(Some(&json!(0.0))));
        assert!(!truthy(Some(&json!(""))));
        assert!(truthy(Some(&json!("0"))));
        assert!(truthy(Some(&json!([]))));
        assert!(truthy(Some(&json!({}))));
        assert!(truthy(Some(&json!(-1))));
    }

    #[test]
    fn string_conversion_follows_javascript() {
        assert_eq!(to_js_string(None), "undefined");
        assert_eq!(to_js_string(Some(&json!(null))), "null");
        assert_eq!(to_js_string(Some(&json!(true))), "true");
        assert_eq!(to_js_string(Some(&json!(5))), "5");
        assert_eq!(to_js_string(Some(&json!(1.5))), "1.5");
        assert_eq!(to_js_string(Some(&json!({"a": 1}))), "[object Object]");
        assert_eq!(to_js_string(Some(&json!([1, null, "x", [2, 3]]))), "1,,x,2,3");
    }

    #[test]
    fn only_objects_have_properties() {
        let v = json!({"a": 1});
        assert_eq!(get(&v, "a"), Some(&json!(1)));
        assert_eq!(get(&v, "b"), None);
        assert_eq!(get(&json!([1]), "a"), None);
        assert_eq!(get(&json!("text"), "length"), None);
    }

    #[test]
    fn nullish_skips_null_and_missing() {
        assert_eq!(non_nullish(Some(&json!(null))), None);
        assert_eq!(non_nullish(None), None);
        assert_eq!(non_nullish(Some(&json!(0))), Some(&json!(0)));
        assert_eq!(non_nullish(Some(&json!(""))), Some(&json!("")));
    }

    #[test]
    fn numbers_are_written_like_javascript() {
        let s = |v: Value| to_js_string(Some(&v));
        assert_eq!(s(json!(5.0)), "5");
        assert_eq!(s(json!(-0.0)), "0");
        assert_eq!(s(json!(1.5)), "1.5");
        assert_eq!(s(json!(1e20)), "100000000000000000000");
        assert_eq!(s(json!(1e21)), "1e+21");
        assert_eq!(s(json!(1.5e22)), "1.5e+22");
        assert_eq!(s(json!(-3)), "-3");
    }

    #[test]
    fn a_lone_surrogate_escape_is_replaced_and_the_rest_is_kept() {
        let v = parse_json(r#"{"a":"x\ud83d","b":"\ude00y","c":"ok \ud83d\ude00","d":"\\ud83d"}"#).unwrap();
        assert_eq!(v["a"], "x\u{fffd}");
        assert_eq!(v["b"], "\u{fffd}y");
        assert_eq!(v["c"], "ok 😀", "a valid pair stays");
        assert_eq!(
            v["d"], "\\ud83d",
            "an escaped backslash is not an escape of a surrogate"
        );
        assert_eq!(parse_json(r#"{"a":"\ud83d\ud83d"}"#).unwrap()["a"], "\u{fffd}\u{fffd}");
        assert!(parse_json("{nope").is_err());
        assert!(parse_json(r#"{"a":"\u12"}"#).is_err());
    }

    #[test]
    fn keys_tell_numbers_from_strings() {
        assert_ne!(key_of(&json!(1)), key_of(&json!("1")));
    }
}
