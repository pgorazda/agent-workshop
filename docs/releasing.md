# Releasing

A release is made by a tag. The workflow `.github/workflows/release.yml` builds the apps and the bridge and makes a **draft** release. You publish the draft by hand.

## The apps

| File | System |
|---|---|
| `AgentWorkshop-<version>-windows-x86_64.zip` | Windows, Intel or AMD |
| `AgentWorkshop-<version>-windows-arm64.zip` | Windows on ARM |
| `AgentWorkshop-<version>-linux-x86_64.tar.gz` | Linux, Intel or AMD |
| `AgentWorkshop-<version>-linux-arm64.tar.gz` | Linux on ARM |
| `AgentWorkshop-<version>-macos-universal.zip` | macOS, Intel and Apple silicon (one app for both) |
| `AgentWorkshopBridge-<version>-windows-x86_64.zip` | The bridge, Windows, Intel or AMD |
| `AgentWorkshopBridge-<version>-windows-arm64.zip` | The bridge, Windows on ARM |
| `AgentWorkshopBridge-<version>-linux-x86_64.tar.gz` | The bridge, Linux, Intel or AMD (a static binary) |
| `AgentWorkshopBridge-<version>-linux-arm64.tar.gz` | The bridge, Linux on ARM (a static binary) |
| `AgentWorkshopBridge-<version>-macos-universal.zip` | The bridge, macOS, Intel and Apple silicon (one file for both) |
| `SHA256SUMS` | The SHA-256 hash of each file |

Each app archive holds one folder with the app, `LICENSE` and `LICENSE-ASSETS`. Each bridge archive holds one folder with the program `agent-workshop-bridge` (`.exe` on Windows) and `LICENSE` (the bridge is code, so it has no `LICENSE-ASSETS`). The bridge is a separate program that needs no Node or other runtime; people download it only when they want live events. The apps and the bridge are **not signed or notarized**. The release notes tell the user what to expect (Windows SmartScreen, macOS Gatekeeper). The macOS bridge has a local (ad-hoc) signature, which Apple silicon needs to run a program at all; it is not a developer signature, so Gatekeeper still asks. The files also have a build attestation: `gh attestation verify <file> --repo <owner>/<repo>`.

## Make a release

1. Pick the version, for example `0.2.0`. Change it in every file at once:

   ```bash
   node godot/tools/version.mjs bump 0.2.0
   ```

   The version is in `bridge/Cargo.toml`, `bridge/Cargo.lock` (the entry of the bridge), `godot/project.godot` and `godot/export_presets.cfg`. CI fails when the places disagree (`node godot/tools/version.mjs check`).
2. Open a pull request with the change and merge it into `main`.
3. Tag the merge commit and push the tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

   Use a suffix for a pre-release: `v0.2.0-alpha.1`. The files still hold `0.2.0`. A tag with a suffix makes a GitHub pre-release.
4. The workflow checks that the tag is on `main` and matches the files, runs the tests, builds the bridge on a runner of each system (and starts each binary once to check `/health` and one event), exports the five apps, starts the Linux app once with no window, makes the archives and makes the draft release.
5. Open the draft under Releases, download and try at least one app and one bridge, edit the notes, and publish.

A tag cannot be moved after the release is published when immutable releases are on. To fix a bad release, delete the draft and the tag before publishing, or publish a new version.

## Try the build without a release

Open Actions, choose "Release" and "Run workflow". It builds everything and keeps the files as the workflow artifact `release-files` for 14 days. It makes no release.

## Build on your computer

```bash
cd bridge && cargo build --release            # target/release/agent-workshop-bridge (for your own system)
cd godot
node tools/export.mjs --platform all          # out/export/<platform>/
node tools/package.mjs --version 0.2.0        # out/release/ (needs zip, unzip and tar), the apps only
# With the bridge too: put a binary for each platform in out/bridge/<platform>/agent-workshop-bridge[.exe]
# (platforms: windows, windows-arm64, linux, linux-arm64, macos), then:
node tools/package.mjs --version 0.2.0 --bridge-in out/bridge
```

## Good to know

* One Linux job exports all five apps. Godot can export every target from one host. The templates are about 1.3 GB, so the workflow caches them.
* The bridge is built on five runners (Linux x86_64 and ARM, Windows x86_64 and ARM, macOS), each for its own system, because that is the only way to run each binary once before it is released. Linux binaries use musl, so they are static and run on any Linux. The runners `ubuntu-24.04-arm` and `windows-11-arm` must be available to the repository. If one is not, that job fails and the release stops: run the workflow by hand first ("Run workflow") to see.
* The first release runs the Linux, macOS and ARM64 exports for the first time. Only the Windows x86_64 app was run on real hardware. Make the first releases pre-releases.
* The macOS bundle identifier in `godot/export_presets.cfg` is a placeholder. Set a real one before the first release (an app's identity should not change later).
* The release job uses the environment `release`. Add required reviewers to it in the repository settings to approve each release.
* Signing is not done. It needs an Apple Developer ID for macOS and a code-signing certificate for Windows.
