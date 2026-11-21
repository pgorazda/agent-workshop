//! Bridge server: accepts events from adapters over HTTP and streams them to clients over WebSocket.
//!
//! ```text
//! POST /event              canonical event (or array of events)
//! POST /hook/claude-code   raw Claude Code hook payload
//! POST /hook/opencode      { event } as seen by an OpenCode plugin's event hook
//! POST /hook/pi            { session, event } with a Pi session event
//! POST /hook/hermes        raw Hermes shell-hook payload
//!                          (raw payloads are mapped by the built-in adapters)
//! GET  /health             liveness and counters
//! WS   /ws                 clients receive canonical events as JSON text frames
//! ```
//!
//! Binds to `127.0.0.1` by default: events can contain commands and file names.

use crate::adapters::Adapters;
use crate::js::{get, to_js_string, truthy};
use crate::schema::{SCHEMA_VERSION, normalize_event, validate_event};
use axum::Router;
use axum::body::{Body, to_bytes};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{FromRequestParts, Request};
use axum::http::{Method, StatusCode, header};
use axum::response::{IntoResponse, Response};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use std::io;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::net::TcpListener;
use tokio::sync::{broadcast, watch};
use tokio::task::JoinHandle;

/// Hook payloads can contain whole tool outputs (the bridge is local and only forwards a few
/// fields), so the limit is generous: a rejected post would silently lose a `tool_end`.
const MAX_BODY_BYTES: usize = 10_000_000;

/// Events that wait for one slow client. When a client falls further behind, it loses the oldest
/// events. The bridge keeps no history, so they cannot be sent later.
const CLIENT_QUEUE: usize = 4096;

/// A client that takes no event for this long is dropped. It would otherwise hold the events in memory for ever.
const CLIENT_SEND_TIMEOUT: Duration = Duration::from_secs(10);

/// A function that receives the log lines of the bridge.
pub type Log = Arc<dyn Fn(&str) + Send + Sync>;

pub struct BridgeOptions {
    pub host: String,
    pub port: u16,
    pub redact_targets: bool,
    pub log: Log,
}

impl Default for BridgeOptions {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".into(),
            port: 8787,
            redact_targets: false,
            log: Arc::new(|_| {}),
        }
    }
}

struct Shared {
    tx: broadcast::Sender<Arc<str>>,
    adapters: Mutex<Adapters>,
    events: AtomicU64,
    rejected: AtomicU64,
    clients: AtomicUsize,
    redact_targets: bool,
    /// True when the bridge listens on a loopback address. Then a `Host` header that names anything else is refused
    /// (DNS rebinding).
    check_host: bool,
    log: Log,
    shutdown: watch::Receiver<bool>,
}

impl Shared {
    fn broadcast(&self, event: &Value) {
        self.events.fetch_add(1, Ordering::Relaxed);
        // An error only means that no client listens right now.
        let _ = self.tx.send(Arc::from(event.to_string()));
        let tool = get(event, "tool");
        let tool_text = if truthy(tool) {
            format!(" {}", to_js_string(tool))
        } else {
            String::new()
        };
        (self.log)(&format!(
            "{}/{}/{} {}{}",
            to_js_string(get(event, "framework")),
            to_js_string(get(event, "session")),
            to_js_string(get(event, "agent")),
            to_js_string(get(event, "type")),
            tool_text
        ));
    }
}

/// The counters of the bridge, as `GET /health` reports them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stats {
    pub events: u64,
    pub rejected: u64,
    pub clients: usize,
}

pub struct Bridge {
    shared: Arc<Shared>,
    host: String,
    port: u16,
    shutdown: watch::Sender<bool>,
    task: Option<JoinHandle<()>>,
}

impl Bridge {
    pub fn new(options: BridgeOptions) -> Self {
        let (tx, _) = broadcast::channel(CLIENT_QUEUE);
        let (shutdown, shutdown_rx) = watch::channel(false);
        let shared = Arc::new(Shared {
            tx,
            adapters: Mutex::new(Adapters::default()),
            events: AtomicU64::new(0),
            rejected: AtomicU64::new(0),
            clients: AtomicUsize::new(0),
            redact_targets: options.redact_targets,
            check_host: is_loopback_host(&options.host),
            log: options.log,
            shutdown: shutdown_rx,
        });
        Self {
            shared,
            host: options.host,
            port: options.port,
            shutdown,
            task: None,
        }
    }

    pub fn stats(&self) -> Stats {
        Stats {
            events: self.shared.events.load(Ordering::Relaxed),
            rejected: self.shared.rejected.load(Ordering::Relaxed),
            clients: self.shared.clients.load(Ordering::Relaxed),
        }
    }

    /// Sends an event to all clients.
    pub fn broadcast(&self, event: &Value) {
        self.shared.broadcast(event);
    }

    /// Starts listening. Returns the address, which has the real port when the port was 0.
    pub async fn listen(&mut self) -> io::Result<SocketAddr> {
        let listener = TcpListener::bind((self.host.as_str(), self.port)).await?;
        let addr = listener.local_addr()?;
        let shared = self.shared.clone();
        let mut stop = self.shutdown.subscribe();
        let app = Router::new().fallback(move |req: Request| {
            let shared = shared.clone();
            async move { handle(shared, req).await }
        });
        self.task = Some(tokio::spawn(async move {
            let _ = axum::serve(listener, app)
                .with_graceful_shutdown(async move { stopped(&mut stop).await })
                .await;
        }));
        Ok(addr)
    }

    /// Closes the clients and stops listening.
    pub async fn close(mut self) {
        let _ = self.shutdown.send(true);
        if let Some(mut task) = self.task.take()
            && tokio::time::timeout(Duration::from_secs(2), &mut task).await.is_err()
        {
            // A connection that does not end in time is cut.
            task.abort();
        }
    }
}

fn json_response(status: StatusCode, body: &Value) -> Response {
    let text = body.to_string();
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::CONTENT_LENGTH, text.len())
        .body(Body::from(text))
        .expect("a valid response")
}

fn error_response(status: StatusCode, message: &str) -> Response {
    json_response(status, &json!({ "error": message }))
}

/// The host part of a `Host` value (`name:port`) or an `Origin` value (`scheme://name:port`), with no port and no brackets
/// around an IPv6 address.
fn host_of(value: &str) -> &str {
    let rest = value.split_once("://").map_or(value, |(_, rest)| rest);
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let authority = authority.rsplit_once('@').map_or(authority, |(_, host)| host);
    if let Some(inner) = authority.strip_prefix('[') {
        return inner.split(']').next().unwrap_or("");
    }
    authority.split(':').next().unwrap_or("")
}

/// True for `localhost` and for a loopback address (`127.0.0.1`, `::1`).
fn is_loopback_host(name: &str) -> bool {
    let name = host_of(name);
    name.eq_ignore_ascii_case("localhost") || name.parse::<std::net::IpAddr>().is_ok_and(|ip| ip.is_loopback())
}

/// A web page can reach `127.0.0.1` too. A browser always sends `Origin` on a WebSocket and on a cross-site `POST`, and the
/// Godot app, `curl` and the hooks send none. So a request with an `Origin` that is not local comes from a page and is
/// refused: it could read the stream or send fake events. A page on a rebound DNS name sends a foreign `Host`, which is
/// refused when the bridge listens on a loopback address.
fn check_origin(shared: &Shared, req: &Request) -> Option<Response> {
    if let Some(origin) = req.headers().get(header::ORIGIN) {
        let local = origin
            .to_str()
            .is_ok_and(|value| is_loopback_host(value) && value != "null");
        if !local {
            return Some(error_response(StatusCode::FORBIDDEN, "forbidden origin"));
        }
    }
    if shared.check_host
        && let Some(host) = req.headers().get(header::HOST)
        && !host.to_str().is_ok_and(is_loopback_host)
    {
        return Some(error_response(StatusCode::FORBIDDEN, "forbidden host"));
    }
    None
}

async fn handle(shared: Arc<Shared>, req: Request) -> Response {
    if let Some(refusal) = check_origin(&shared, &req) {
        return refusal;
    }
    let path = req.uri().path().to_string();
    let method = req.method().clone();

    // WebSocket upgrade on /ws. Any other request to /ws is an ordinary request and gets a 404.
    let req = if path == "/ws" && method == Method::GET {
        let (mut parts, body) = req.into_parts();
        match WebSocketUpgrade::from_request_parts(&mut parts, &()).await {
            Ok(upgrade) => {
                let shared = shared.clone();
                return upgrade
                    .on_upgrade(move |socket| client_loop(shared, socket))
                    .into_response();
            }
            Err(_) => Request::from_parts(parts, body),
        }
    } else {
        req
    };

    if method == Method::GET && path == "/health" {
        return json_response(
            StatusCode::OK,
            &json!({
                "ok": true,
                "schema": SCHEMA_VERSION,
                "clients": shared.clients.load(Ordering::Relaxed),
                "events": shared.events.load(Ordering::Relaxed),
                "rejected": shared.rejected.load(Ordering::Relaxed),
            }),
        );
    }

    if method == Method::POST && path == "/event" {
        return match read_json(req).await {
            Ok(body) => post_event(&shared, body),
            Err((status, message)) => error_response(status, &message),
        };
    }

    let hook = if method == Method::POST {
        path.strip_prefix("/hook/")
    } else {
        None
    };
    if let Some(framework) = hook.filter(|f| is_framework_name(f) && Adapters::knows(f)) {
        let framework = framework.to_string();
        return match read_json(req).await {
            Ok(payload) => post_hook(&shared, &framework, &payload),
            Err((status, message)) => error_response(status, &message),
        };
    }

    // The answer comes before the body is read. Read it now (up to the limit): on Windows, closing a connection with unread data
    // resets it, and the client would never see the answer.
    let _ = to_bytes(req.into_body(), MAX_BODY_BYTES).await;
    error_response(StatusCode::NOT_FOUND, "not found")
}

/// The `:framework` part of `/hook/:framework` is one or more of `a-z` and `-`.
fn is_framework_name(name: &str) -> bool {
    !name.is_empty() && name.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
}

/// Reads the body as JSON. The error is the status and the text of the answer.
async fn read_json(req: Request) -> Result<Value, (StatusCode, String)> {
    let bytes = to_bytes(req.into_body(), MAX_BODY_BYTES)
        .await
        .map_err(|_| (StatusCode::PAYLOAD_TOO_LARGE, "payload too large".to_string()))?;
    let text = String::from_utf8_lossy(&bytes);
    crate::js::parse_json(&text).map_err(|err| (StatusCode::BAD_REQUEST, err.to_string()))
}

fn post_event(shared: &Shared, body: Value) -> Response {
    let list = match body {
        Value::Array(items) => items,
        single => vec![single],
    };
    let mut accepted = Vec::new();
    let mut errors = Vec::new();
    for (index, raw) in list.iter().enumerate() {
        let event = normalize_event(raw, shared.redact_targets);
        let problems = validate_event(&event);
        if problems.is_empty() {
            accepted.push(event);
        } else {
            errors.push(json!({ "index": index, "errors": problems }));
        }
    }
    for event in &accepted {
        shared.broadcast(event);
    }
    shared.rejected.fetch_add(errors.len() as u64, Ordering::Relaxed);
    let status = if errors.is_empty() {
        StatusCode::ACCEPTED
    } else {
        StatusCode::BAD_REQUEST
    };
    json_response(status, &json!({ "accepted": accepted.len(), "rejected": errors }))
}

fn post_hook(shared: &Shared, framework: &str, payload: &Value) -> Response {
    // The adapters keep state, and the order of their events must reach the clients as it was made. So the mapping and the
    // broadcast happen under one lock (the broadcast does not wait), as the single thread of the Node bridge did.
    let mut adapters = shared.adapters.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(events) = adapters.map(framework, payload) else {
        return error_response(StatusCode::NOT_FOUND, "not found");
    };
    for raw in events {
        let event = normalize_event(&raw, shared.redact_targets);
        let problems = validate_event(&event);
        if problems.is_empty() {
            shared.broadcast(&event);
        } else {
            shared.rejected.fetch_add(1, Ordering::Relaxed);
            (shared.log)(&format!("dropped {framework} event: {}", problems.join("; ")));
        }
    }
    drop(adapters);
    StatusCode::NO_CONTENT.into_response()
}

/// Waits until the bridge is told to close.
async fn stopped(shutdown: &mut watch::Receiver<bool>) {
    let _ = shutdown.wait_for(|stopped| *stopped).await;
}

async fn client_loop(shared: Arc<Shared>, socket: WebSocket) {
    let (mut sink, mut stream) = socket.split();
    let mut events = shared.tx.subscribe();
    let mut shutdown = shared.shutdown.clone();
    let count = shared.clients.fetch_add(1, Ordering::Relaxed) + 1;

    let hello = json!({ "v": SCHEMA_VERSION, "type": "hello" }).to_string();
    if sink.send(Message::Text(hello.into())).await.is_ok() {
        (shared.log)(&format!("client connected ({count})"));
        loop {
            tokio::select! {
                received = events.recv() => match received {
                    Ok(text) => {
                        let sent = tokio::time::timeout(CLIENT_SEND_TIMEOUT, sink.send(Message::Text(text.as_ref().into()))).await;
                        if !matches!(sent, Ok(Ok(()))) {
                            if sent.is_err() {
                                (shared.log)("a client did not read for 10 seconds and was dropped");
                            }
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(missed)) => {
                        (shared.log)(&format!("a client was too slow and missed {missed} events"));
                    }
                    Err(broadcast::error::RecvError::Closed) => break,
                },
                incoming = stream.next() => match incoming {
                    None | Some(Err(_)) | Some(Ok(Message::Close(_))) => break,
                    // Clients send nothing that the bridge uses. Pings are answered by the library.
                    Some(Ok(_)) => {}
                },
                _ = stopped(&mut shutdown) => {
                    let _ = sink.close().await;
                    break;
                }
            }
        }
    }
    shared.clients.fetch_sub(1, Ordering::Relaxed);
}
