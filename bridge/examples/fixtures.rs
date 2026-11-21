//! Writes the fixtures of the Godot tests from the example sessions.
//!
//!   cargo run --example fixtures            write godot/test/fixtures/*.events.jsonl
//!   cargo run --example fixtures -- --check fail when the files are out of date
//!
//! Run it when `schema/examples/` or the adapters change. `cargo test` fails when the files are out of date.

#[path = "../tests/common/fixtures.rs"]
mod fixtures;

fn main() {
    let check = std::env::args().any(|arg| arg == "--check");
    let mut stale = false;
    for name in fixtures::NAMES {
        let events = fixtures::example_events(name);
        let text = fixtures::fixture_text(&events);
        let path = fixtures::fixture_path(name);
        if check {
            if std::fs::read_to_string(&path)
                .map(|old| old.replace("\r\n", "\n"))
                .ok()
                .as_deref()
                != Some(text.as_str())
            {
                eprintln!("out of date: {}", path.display());
                stale = true;
            }
        } else {
            std::fs::write(&path, text).expect("the fixture is written");
            println!("wrote {name}.events.jsonl ({} events)", events.len());
        }
    }
    if stale {
        std::process::exit(1);
    }
}
