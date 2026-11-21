//! The command line of the bridge: `serve`, `replay` and `ingest pi`.

use crate::adapters::claude_code::transcript_to_events;
use crate::js::get;
use crate::schema::now_ms;
use crate::server::{Bridge, BridgeOptions};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::io::{BufRead, Read, Write};
use std::sync::Arc;
use std::time::Duration;

pub const USAGE: &str = "Usage:
  agent-workshop-bridge serve [--port 8787] [--host 127.0.0.1] [--redact-targets] [--exit-when-stdin-closes]
  agent-workshop-bridge replay <transcript.jsonl> [--speed 4] [--max-gap 1500] [--url http://127.0.0.1:8787]
  pi --mode json \"prompt\" | agent-workshop-bridge ingest pi [--tee] [--url http://127.0.0.1:8787]
  agent-workshop-bridge --version

serve    run the bridge (HTTP in, WebSocket out)
         --exit-when-stdin-closes  stop when standard input is closed (a program that starts the bridge uses this)
replay   post a recorded Claude Code transcript to a running bridge, preserving timing
         --speed N     playback speed multiplier (0 = no delays)
         --max-gap MS  longest pause kept between two events, before the speed factor
ingest   read a framework's JSON event stream from stdin and forward it to a running bridge
         (only \"pi\" for now). --tee also copies each line to stdout.";

/// The value of a flag: `--name` alone is `Switch`, `--name value` is `Text`.
#[derive(Debug, Clone, PartialEq)]
pub enum Flag {
    Switch,
    Text(String),
}

pub struct Args {
    pub positional: Vec<String>,
    pub flags: HashMap<String, Flag>,
}

/// Splits the arguments like the Node bridge did. A flag takes the next argument as its value
/// unless that one is missing or starts with `--`.
pub fn parse_args(argv: &[String]) -> Args {
    let mut positional = Vec::new();
    let mut flags = HashMap::new();
    let mut i = 0;
    while i < argv.len() {
        let arg = &argv[i];
        if let Some(name) = arg.strip_prefix("--") {
            match argv.get(i + 1) {
                Some(next) if !next.starts_with("--") => {
                    flags.insert(name.to_string(), Flag::Text(next.clone()));
                    i += 1;
                }
                _ => {
                    flags.insert(name.to_string(), Flag::Switch);
                }
            }
        } else {
            positional.push(arg.clone());
        }
        i += 1;
    }
    Args { positional, flags }
}

impl Args {
    fn text(&self, name: &str) -> Result<Option<&str>, String> {
        match self.flags.get(name) {
            None => Ok(None),
            Some(Flag::Text(text)) => Ok(Some(text)),
            Some(Flag::Switch) => Err(format!("--{name} needs a value")),
        }
    }

    fn on(&self, name: &str) -> bool {
        self.flags.contains_key(name)
    }

    /// A number flag like JavaScript's `Number(...)`: an empty text is 0 and a text that is not a number is NaN.
    fn number(&self, name: &str, default: f64) -> f64 {
        match self.flags.get(name) {
            None => default,
            Some(Flag::Switch) => 1.0,
            Some(Flag::Text(text)) => {
                let trimmed = text.trim();
                if trimmed.is_empty() {
                    0.0
                } else {
                    trimmed.parse().unwrap_or(f64::NAN)
                }
            }
        }
    }
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok()
}

/// Runs the program. Returns the exit code.
pub fn run(argv: Vec<String>) -> i32 {
    let args = parse_args(&argv);
    if args.on("version") && args.positional.is_empty() {
        println!("agent-workshop-bridge {}", env!("CARGO_PKG_VERSION"));
        return 0;
    }
    let command = args.positional.first().map(String::as_str);
    let result = match (command, args.positional.get(1).map(String::as_str)) {
        (Some("serve"), _) => serve(&args),
        (Some("replay"), file) => replay(file, &args),
        (Some("ingest"), Some("pi")) => ingest_pi(&args),
        _ => {
            println!("{USAGE}");
            return if command.is_some() { 1 } else { 0 };
        }
    };
    match result {
        Ok(()) => 0,
        Err(message) => {
            eprintln!("error: {message}");
            1
        }
    }
}

fn serve(args: &Args) -> Result<(), String> {
    let host = match args.text("host")? {
        Some(host) => host.to_string(),
        None => env("ARENA_HOST").unwrap_or_else(|| "127.0.0.1".to_string()),
    };
    let port_text = match args.text("port")? {
        Some(port) => port.to_string(),
        None => env("ARENA_PORT").unwrap_or_else(|| "8787".to_string()),
    };
    let port: u16 = port_text
        .trim()
        .parse()
        .map_err(|_| format!("\"{port_text}\" is not a port (0 to 65535)"))?;
    let redact_targets = args.on("redact-targets") || env("ARENA_REDACT_TARGETS").as_deref() == Some("1");

    if args.on("exit-when-stdin-closes") {
        // A program that starts the bridge keeps a pipe to its standard input. When that program
        // ends, also by a crash, the pipe closes and the bridge ends with it.
        std::thread::spawn(|| {
            let mut sink = Vec::new();
            let _ = std::io::stdin().lock().read_to_end(&mut sink);
            std::process::exit(0);
        });
    }

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|err| err.to_string())?;
    runtime.block_on(async move {
        let mut bridge = Bridge::new(BridgeOptions {
            host: host.clone(),
            port,
            redact_targets,
            log: Arc::new(|line| {
                // A closed or full output must never stop the bridge.
                let _ = writeln!(std::io::stdout(), "[bridge] {line}");
            }),
        });
        let addr = bridge
            .listen()
            .await
            .map_err(|err| format!("could not listen on {host}:{port}: {err}"))?;
        println!(
            "[bridge] listening on http://{}:{} (ws path /ws)",
            addr.ip(),
            addr.port()
        );
        // The bridge runs until the process is stopped.
        std::future::pending::<()>().await;
        Ok(())
    })
}

/// An agent for the requests of `replay` and `ingest`. It never uses a proxy: the bridge is local.
fn http_agent(timeout: Option<Duration>) -> ureq::Agent {
    ureq::Agent::config_builder()
        .http_status_as_error(false)
        .proxy(None)
        .timeout_global(timeout)
        .build()
        .into()
}

fn base_url(flag: Option<&str>, fallback: &str) -> String {
    flag.unwrap_or(fallback).trim_end_matches('/').to_string()
}

fn replay(file: Option<&str>, args: &Args) -> Result<(), String> {
    let file = file.ok_or("replay needs a transcript file")?;
    let url = base_url(args.text("url")?, "http://127.0.0.1:8787");
    let speed = args.number("speed", 4.0);
    let max_gap = args.number("max-gap", 1500.0);
    let bytes = std::fs::read(file).map_err(|err| format!("could not read {file}: {err}"))?;
    let events = transcript_to_events(&String::from_utf8_lossy(&bytes));
    println!("[replay] {} events from {file} at speed {speed}", events.len());

    let agent = http_agent(None);
    let mut previous: Option<f64> = None;
    for event in events {
        let ts = get(&event, "ts").and_then(Value::as_f64);
        if speed > 0.0
            && let (Some(prev), Some(ts)) = (previous, ts)
        {
            let gap = (ts - prev).max(0.0).min(max_gap);
            let wait = gap / speed;
            if let Ok(pause) = Duration::try_from_secs_f64(wait / 1000.0) {
                std::thread::sleep(pause);
            }
        }
        previous = ts.or(previous);
        // Replay stamps events with the current time so that clients see them as live.
        let mut live = event;
        if let Some(object) = live.as_object_mut() {
            object.insert("ts".into(), Value::from(now_ms()));
        }
        let mut response = agent
            .post(&format!("{url}/event"))
            .header("content-type", "application/json")
            .send(live.to_string())
            .map_err(|err| err.to_string())?;
        let status = response.status();
        if !status.is_success() {
            let text = response.body_mut().read_to_string().unwrap_or_default();
            return Err(format!("bridge rejected an event ({}): {text}", status.as_u16()));
        }
    }
    println!("[replay] done");
    Ok(())
}

fn ingest_pi(args: &Args) -> Result<(), String> {
    let fallback = env("ARENA_BRIDGE_HTTP").unwrap_or_else(|| "http://127.0.0.1:8787".to_string());
    // A flag without a value is ignored here: the stream of the agent must go on whatever happens.
    let url = base_url(args.text("url").ok().flatten(), &fallback);
    let tee = args.on("tee");
    let mut session = format!("pi-{}", now_ms());
    let agent = http_agent(Some(Duration::from_secs(1)));

    let mut input = std::io::stdin().lock();
    let mut buffer = Vec::new();
    loop {
        buffer.clear();
        match input.read_until(b'\n', &mut buffer) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        let text = String::from_utf8_lossy(&buffer);
        let line = text.trim_end_matches(['\n', '\r']);
        if tee {
            let _ = writeln!(std::io::stdout(), "{line}");
        }
        // Not JSON: ignore it. The stream may contain other output.
        let Ok(event) = crate::js::parse_json(line) else {
            continue;
        };
        if get(&event, "type").and_then(Value::as_str) == Some("session")
            && let Some(Value::String(id)) = get(&event, "id")
        {
            session = id.clone();
        }
        let body = json!({ "session": session, "event": event }).to_string();
        // Fail open: a missing bridge must never break the agent's output.
        let _ = agent
            .post(&format!("{url}/hook/pi"))
            .header("content-type", "application/json")
            .send(body);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Args {
        parse_args(&list.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }

    #[test]
    fn flags_take_the_next_argument_unless_it_starts_with_two_dashes() {
        let a = args(&["serve", "--port", "9000", "--redact-targets", "--host", "0.0.0.0"]);
        assert_eq!(a.positional, ["serve"]);
        assert_eq!(a.flags["port"], Flag::Text("9000".into()));
        assert_eq!(a.flags["redact-targets"], Flag::Switch);
        assert_eq!(a.flags["host"], Flag::Text("0.0.0.0".into()));
        let b = args(&["replay", "file.jsonl", "--speed", "0", "--tee"]);
        assert_eq!(b.positional, ["replay", "file.jsonl"]);
        assert_eq!(b.flags["speed"], Flag::Text("0".into()));
        assert_eq!(b.flags["tee"], Flag::Switch);
    }

    #[test]
    fn a_negative_number_is_a_value_not_a_flag() {
        let a = args(&["replay", "f", "--max-gap", "-5"]);
        assert_eq!(a.flags["max-gap"], Flag::Text("-5".into()));
    }

    #[test]
    fn numbers_follow_javascript_rules() {
        assert_eq!(args(&[]).number("speed", 4.0), 4.0);
        assert_eq!(args(&["--speed", "0"]).number("speed", 4.0), 0.0);
        assert_eq!(args(&["--speed", "2.5"]).number("speed", 4.0), 2.5);
        assert_eq!(args(&["--speed", ""]).number("speed", 4.0), 0.0);
        assert_eq!(args(&["--speed"]).number("speed", 4.0), 1.0);
        assert!(args(&["--speed", "fast"]).number("speed", 4.0).is_nan());
    }

    #[test]
    fn a_flag_that_needs_a_value_says_so() {
        assert!(args(&["--host"]).text("host").is_err());
        assert_eq!(args(&[]).text("host"), Ok(None));
    }

    #[test]
    fn urls_lose_a_trailing_slash() {
        assert_eq!(base_url(Some("http://127.0.0.1:1/"), "x"), "http://127.0.0.1:1");
        assert_eq!(base_url(None, "http://a"), "http://a");
    }
}
