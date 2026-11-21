mod common;

use common::*;
use serde_json::json;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const BIN: &str = env!("CARGO_BIN_EXE_agent-workshop-bridge");
const TRANSCRIPT: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../schema/examples/claude-code-transcript.jsonl"
);
const PI_STREAM: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../schema/examples/pi-json-mode.jsonl");

struct Output {
    code: Option<i32>,
    stdout: String,
    stderr: String,
}

/// Runs the binary to the end, with some text on its standard input. The environment is cleaned
/// of the bridge's own variables.
async fn run_cli(args: &[&str], input: &str, envs: &[(&str, &str)]) -> Output {
    let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
    let input = input.to_string();
    let envs: Vec<(String, String)> = envs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    tokio::task::spawn_blocking(move || {
        let mut command = Command::new(BIN);
        command
            .args(&args)
            .env_remove("ARENA_HOST")
            .env_remove("ARENA_PORT")
            .env_remove("ARENA_REDACT_TARGETS")
            .env_remove("ARENA_BRIDGE_HTTP");
        for (k, v) in &envs {
            command.env(k, v);
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("the binary starts");
        let mut stdin = child.stdin.take().unwrap();
        let writer = std::thread::spawn(move || {
            let _ = stdin.write_all(input.as_bytes());
        });
        let out = child.wait_with_output().expect("the binary ends");
        let _ = writer.join();
        Output {
            code: out.status.code(),
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        }
    })
    .await
    .unwrap()
}

/// A running `serve` process. It is killed when dropped.
struct Server {
    child: Child,
    lines: std::sync::mpsc::Receiver<String>,
    port: u16,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn spawn_server(args: &[&str], envs: &[(&str, &str)]) -> Server {
    let mut command = Command::new(BIN);
    command
        .arg("serve")
        .args(args)
        .env_remove("ARENA_HOST")
        .env_remove("ARENA_PORT")
        .env_remove("ARENA_REDACT_TARGETS");
    for (k, v) in envs {
        command.env(k, v);
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("the binary starts");
    let stdout = child.stdout.take().unwrap();
    let (tx, lines) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            let _ = tx.send(line);
        }
    });
    let first = lines
        .recv_timeout(Duration::from_secs(5))
        .expect("the bridge prints its address");
    let port = first
        .split("http://127.0.0.1:")
        .nth(1)
        .and_then(|rest| rest.split(' ').next())
        .and_then(|p| p.parse().ok())
        .unwrap_or_else(|| panic!("unexpected first line: {first}"));
    assert!(first.ends_with("(ws path /ws)"), "{first}");
    Server { child, lines, port }
}

#[tokio::test]
async fn serve_listens_and_answers() {
    let server = spawn_server(&["--port", "0"], &[]);
    let (status, health) = get(&format!("http://127.0.0.1:{}/health", server.port)).await;
    assert_eq!((status, &health["ok"]), (200, &json!(true)));
    let mut client = connect(&format!("ws://127.0.0.1:{}/ws", server.port)).await;
    assert_eq!(client.next().await["type"], "hello");
    // The log shows the connection.
    let line = server.lines.recv_timeout(Duration::from_secs(3)).unwrap();
    assert_eq!(line, "[bridge] client connected (1)");
}

#[tokio::test]
async fn the_environment_sets_the_port_and_the_redaction() {
    let server = spawn_server(
        &[],
        &[
            ("ARENA_PORT", "0"),
            ("ARENA_REDACT_TARGETS", "1"),
            ("ARENA_HOST", "127.0.0.1"),
        ],
    );
    let mut client = connect(&format!("ws://127.0.0.1:{}/ws", server.port)).await;
    client.next().await;
    let payload = json!({"hook_event_name": "PreToolUse", "session_id": "c", "tool_name": "Bash", "tool_input": {"command": "echo hi"}});
    post(&format!("http://127.0.0.1:{}/hook/claude-code", server.port), &payload).await;
    let event = client.next().await;
    assert!(event.get("target").is_none());
}

#[tokio::test]
async fn the_flag_redact_targets_works_too() {
    let server = spawn_server(&["--port", "0", "--redact-targets"], &[]);
    let mut client = connect(&format!("ws://127.0.0.1:{}/ws", server.port)).await;
    client.next().await;
    let payload = json!({"hook_event_name": "PreToolUse", "session_id": "c", "tool_name": "Bash", "tool_input": {"command": "echo hi"}});
    post(&format!("http://127.0.0.1:{}/hook/claude-code", server.port), &payload).await;
    assert!(client.next().await.get("target").is_none());
}

#[tokio::test]
async fn serve_fails_with_a_clear_message_when_the_port_is_taken() {
    let server = spawn_server(&["--port", "0"], &[]);
    let port = server.port.to_string();
    let out = run_cli(&["serve", "--port", &port], "", &[]).await;
    assert_eq!(out.code, Some(1));
    assert!(
        out.stderr
            .starts_with(&format!("error: could not listen on 127.0.0.1:{port}")),
        "{}",
        out.stderr
    );
    // The text of the system differs: "Address already in use" on Unix, "Only one usage of each socket address" on Windows.
    let text = out.stderr.to_lowercase();
    assert!(
        text.contains("in use") || text.contains("only one usage"),
        "{}",
        out.stderr
    );
}

#[tokio::test]
async fn serve_rejects_a_port_that_is_not_a_port() {
    for bad in ["abc", "70000", "-1", ""] {
        let out = run_cli(&["serve", "--port", bad], "", &[]).await;
        assert_eq!(out.code, Some(1), "{bad:?}");
        assert!(out.stderr.contains("is not a port"), "{bad:?}: {}", out.stderr);
    }
    let out = run_cli(&["serve", "--host"], "", &[]).await;
    assert_eq!(out.code, Some(1));
    assert!(out.stderr.contains("--host needs a value"));
}

#[test]
fn serve_stops_when_its_standard_input_closes() {
    let mut command = Command::new(BIN);
    command.args(["serve", "--port", "0", "--exit-when-stdin-closes"]);
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut first = String::new();
    stdout.read_line(&mut first).unwrap();
    assert!(first.contains("listening"), "{first}");
    assert!(child.try_wait().unwrap().is_none(), "it runs while the pipe is open");
    drop(child.stdin.take());
    let started = Instant::now();
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success());
            break;
        }
        assert!(started.elapsed() < Duration::from_secs(5), "the bridge did not stop");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn serve_does_not_read_its_standard_input_without_the_flag() {
    // With the standard input closed at once, the bridge must keep running.
    let mut child = Command::new(BIN)
        .args(["serve", "--port", "0"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut first = String::new();
    stdout.read_line(&mut first).unwrap();
    std::thread::sleep(Duration::from_millis(300));
    assert!(child.try_wait().unwrap().is_none());
    child.kill().unwrap();
    child.wait().unwrap();
}

#[tokio::test]
async fn usage_version_and_unknown_commands() {
    let none = run_cli(&[], "", &[]).await;
    assert_eq!(none.code, Some(0));
    assert!(none.stdout.starts_with("Usage:"));
    let unknown = run_cli(&["nope"], "", &[]).await;
    assert_eq!(unknown.code, Some(1));
    assert!(unknown.stdout.starts_with("Usage:"));
    let help = run_cli(&["--help"], "", &[]).await;
    assert_eq!(help.code, Some(0));
    let version = run_cli(&["--version"], "", &[]).await;
    assert_eq!(
        (version.code, version.stdout.trim()),
        (Some(0), concat!("agent-workshop-bridge ", env!("CARGO_PKG_VERSION")))
    );
    let ingest_other = run_cli(&["ingest", "other"], "", &[]).await;
    assert_eq!(ingest_other.code, Some(1));
}

#[tokio::test]
async fn replay_posts_a_transcript_with_current_times() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let before = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64;
    let out = run_cli(
        &[
            "replay",
            TRANSCRIPT,
            "--speed",
            "0",
            "--url",
            &format!("{}/", running.http),
        ],
        "",
        &[],
    )
    .await;
    assert_eq!(out.code, Some(0), "{}", out.stderr);
    assert!(out.stdout.contains("[replay] 17 events from"), "{}", out.stdout);
    assert!(out.stdout.trim_end().ends_with("[replay] done"));
    let mut summary = Vec::new();
    for _ in 0..17 {
        let event = client.next().await;
        assert!(
            event["ts"].as_i64().unwrap() >= before,
            "replay stamps events with the current time"
        );
        summary.push(summarize(&event));
    }
    assert_eq!(summary.first().unwrap(), "thinking");
    assert_eq!(summary.last().unwrap(), "done");
    assert!(
        summary.contains(&"tool_start:delegate:Explore the repo layout".to_string())
            || summary.iter().any(|s| s.starts_with("tool_start:delegate"))
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn replay_keeps_the_timing_of_the_transcript_scaled_by_speed() {
    let running = start().await;
    let slow = Instant::now();
    let out = run_cli(
        &["replay", TRANSCRIPT, "--speed", "1000000", "--url", &running.http],
        "",
        &[],
    )
    .await;
    assert_eq!(out.code, Some(0));
    assert!(slow.elapsed() < Duration::from_secs(5));
    running.bridge.close().await;
}

#[tokio::test]
async fn replay_reports_a_missing_file_a_missing_bridge_and_a_rejected_event() {
    let out = run_cli(&["replay"], "", &[]).await;
    assert_eq!(
        (out.code, out.stderr.trim()),
        (Some(1), "error: replay needs a transcript file")
    );
    let out = run_cli(&["replay", "/nonexistent/file.jsonl"], "", &[]).await;
    assert_eq!(out.code, Some(1));
    assert!(out.stderr.starts_with("error: could not read /nonexistent/file.jsonl"));
    let out = run_cli(
        &["replay", TRANSCRIPT, "--speed", "0", "--url", "http://127.0.0.1:1"],
        "",
        &[],
    )
    .await;
    assert_eq!(out.code, Some(1), "nothing listens on port 1");
    assert!(out.stderr.starts_with("error: "));
}

#[tokio::test]
async fn ingest_pi_forwards_a_piped_stream_with_tee_and_survives_a_missing_bridge() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let input = std::fs::read_to_string(PI_STREAM).unwrap() + "not json\n";
    let out = run_cli(&["ingest", "pi", "--tee", "--url", &running.http], &input, &[]).await;
    assert_eq!(out.code, Some(0), "{}", out.stderr);
    assert!(
        out.stdout.contains("\"type\":\"agent_start\""),
        "--tee copies lines to stdout"
    );
    assert!(out.stdout.contains("not json"), "--tee copies every line");
    let expected = [
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
    ];
    let mut seen = Vec::new();
    for _ in 0..expected.len() {
        seen.push(summarize(&client.next().await));
    }
    assert_eq!(seen, expected);

    // Without --tee nothing is printed. A missing bridge changes nothing: the exit code is 0.
    let quiet = run_cli(&["ingest", "pi", "--url", "http://127.0.0.1:1"], &input, &[]).await;
    assert_eq!((quiet.code, quiet.stdout.as_str()), (Some(0), ""));
    running.bridge.close().await;
}

#[tokio::test]
async fn ingest_pi_uses_the_session_of_the_header_and_the_environment_address() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let input = "{\"type\":\"session\",\"id\":\"sess-9\"}\r\n{\"type\":\"agent_start\"}\r\n";
    let out = run_cli(&["ingest", "pi"], input, &[("ARENA_BRIDGE_HTTP", &running.http)]).await;
    assert_eq!(out.code, Some(0));
    assert_eq!(client.next().await["session"], "sess-9");
    assert_eq!(client.next().await["session"], "sess-9");
    running.bridge.close().await;
}

#[tokio::test]
async fn ingest_pi_gives_events_before_a_header_a_session_of_its_own() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    run_cli(
        &["ingest", "pi", "--url", &running.http],
        "{\"type\":\"agent_start\"}\n",
        &[],
    )
    .await;
    let session = client.next().await["session"].as_str().unwrap().to_string();
    assert!(session.starts_with("pi-"), "{session}");
    running.bridge.close().await;
}
