# Security policy

## Reporting a problem

Please report a security problem privately, not in a public issue. Use "Report a vulnerability" on the Security tab of this repository (GitHub private vulnerability reporting). Say what you found, how to reproduce it, and which version you used. You get an answer as soon as the maintainer can give one. This is a small project run by one person: there is no fixed response time.

## What to report

The bridge is a local server and the part that matters most. Examples:

- a way for another program, or for a web page, to read the event stream or send events to the bridge when it should not;
- a way to make the bridge listen on a non-local address without the person asking for it;
- data in the stream that the bridge should have dropped (message text, tool output, file contents, or targets when `--redact-targets` is on);
- a problem in the launcher that lets the app start a program that the person did not choose.

Also report a problem in a release archive or in the release workflow.

## What the bridge does to stay safe

- It listens on `127.0.0.1` only, unless you pass `--host`.
- It refuses requests that carry a foreign `Origin` header (a web page) and, on a loopback address, a foreign `Host` header.
- It stores nothing and broadcasts only the fields of the event schema.
- It has no authentication. Do not expose it to a network you do not trust: see [docs/adapters.md](docs/adapters.md#agent-on-another-machine).

## Supported versions

Only the latest release gets fixes. The releases are pre-releases for now, and the apps and the bridge are not signed.
