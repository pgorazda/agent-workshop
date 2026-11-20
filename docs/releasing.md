# Releasing

A release is made by a tag. The workflow `.github/workflows/release.yml` builds the apps and makes a **draft** release. You publish the draft by hand.

## The apps

| File | System |
|---|---|
| `AgentWorkshop-<version>-windows-x86_64.zip` | Windows, Intel or AMD |
| `AgentWorkshop-<version>-windows-arm64.zip` | Windows on ARM |
| `AgentWorkshop-<version>-linux-x86_64.tar.gz` | Linux, Intel or AMD |
| `AgentWorkshop-<version>-linux-arm64.tar.gz` | Linux on ARM |
| `AgentWorkshop-<version>-macos-universal.zip` | macOS, Intel and Apple silicon (one app for both) |
| `SHA256SUMS` | The SHA-256 hash of each file |

Each archive holds one folder with the app, `LICENSE` and `LICENSE-ASSETS`. The apps are **not signed or notarized**. The release notes tell the user what to expect (Windows SmartScreen, macOS Gatekeeper). The files also have a build attestation: `gh attestation verify <file> --repo <owner>/<repo>`.

## Make a release

1. Pick the version, for example `0.2.0`. Change it in every file at once:

   ```bash
   node godot/tools/version.mjs bump 0.2.0
   ```

   The version is in `bridge/package.json`, `bridge/package-lock.json`, `godot/project.godot` and `godot/export_presets.cfg`. CI fails when the places disagree (`node godot/tools/version.mjs check`).
2. Open a pull request with the change and merge it into `main`.
3. Tag the merge commit and push the tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

   Use a suffix for a pre-release: `v0.2.0-alpha.1`. The files still hold `0.2.0`. A tag with a suffix makes a GitHub pre-release.
4. The workflow checks that the tag is on `main` and matches the files, runs the tests, exports the five apps, starts the Linux app once with no window, makes the archives and makes the draft release.
5. Open the draft under Releases, download and try at least one app, edit the notes, and publish.

A tag cannot be moved after the release is published when immutable releases are on. To fix a bad release, delete the draft and the tag before publishing, or publish a new version.

## Try the build without a release

Open Actions, choose "Release" and "Run workflow". It builds everything and keeps the files as the workflow artifact `release-files` for 14 days. It makes no release.

## Build on your computer

```bash
cd godot
node tools/export.mjs --platform all          # out/export/<platform>/
node tools/package.mjs --version 0.2.0        # out/release/ (needs zip, unzip and tar)
```

## Good to know

* One Linux job exports all five apps. Godot can export every target from one host. The templates are about 1.3 GB, so the workflow caches them.
* The first release runs the Linux, macOS and ARM64 exports for the first time. Only the Windows x86_64 app was run on real hardware. Make the first releases pre-releases.
* The macOS bundle identifier in `godot/export_presets.cfg` is a placeholder. Set a real one before the first release (an app's identity should not change later).
* The release job uses the environment `release`. Add required reviewers to it in the repository settings to approve each release.
* Signing is not done. It needs an Apple Developer ID for macOS and a code-signing certificate for Windows.
