//! The scene timelines in `godot/demo/` hold canonical events. Each one must pass the bridge's own
//! validation, as if an adapter had posted it. (`godot/tools/export-scenes.test.mjs` checks the rest.)

use agent_workshop_bridge::schema::{normalize_event, validate_event};
use serde_json::Value;
use std::path::Path;

const SCENES: [&str; 7] = ["session", "multi", "arenas", "many", "follow", "ten", "tour"];

#[test]
fn every_event_of_every_scene_is_valid() {
    for name in SCENES {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../godot/demo")
            .join(format!("{name}.json"));
        let text = std::fs::read_to_string(&path).unwrap_or_else(|err| panic!("{}: {err}", path.display()));
        let timeline: Value = serde_json::from_str(&text).expect("a JSON file");
        let events = timeline["events"].as_array().expect("an events list");
        assert!(events.len() > 10, "{name}");
        for entry in events {
            let event = &entry["event"];
            let problems = validate_event(&normalize_event(event, false));
            assert!(problems.is_empty(), "{name}: {event}: {}", problems.join("; "));
        }
    }
}
