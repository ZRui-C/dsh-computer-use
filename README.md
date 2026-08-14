<p align="center">
  <img src="docs/assets/app-icon.png" width="112" height="112" alt="DSH Computer Use icon">
</p>

<h1 align="center">DSH Computer Use</h1>

<p align="center">
  Text-first browser and background macOS control for DSH.<br>
  Target the right process and window without taking over the user's pointer.
</p>

<p align="center">
  <a href="README.zh.md">简体中文</a> ·
  <a href="documentation/architecture.md">Architecture</a> ·
  <a href="documentation/distribution.md">Distribution</a> ·
  <a href="SECURITY.md">Security</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-202329?style=flat-square&logo=apple&logoColor=white">
  <img alt="Universal 2" src="https://img.shields.io/badge/Universal%202-arm64%20%7C%20x86__64-4DBD88?style=flat-square">
  <img alt="Apache 2.0" src="https://img.shields.io/badge/license-Apache--2.0-F06A5B?style=flat-square">
</p>

## Install

1. Download the latest `DSH-Computer-Use-*-universal.dmg` from [Releases](https://github.com/ZRui-C/dsh-computer-use/releases/latest).
2. Drag **DSH Computer Use** into **Applications** and open it.
3. Authorize **Accessibility** and **Screen Recording** when the setup center asks.
4. Select **Install** under **DSH Plugin**, then restart the running DSH Host.

The official DMG is Universal 2, Developer ID signed, Apple-notarized, and published with a SHA-256 checksum. Users do not need Xcode, Swift, or this source checkout. DSH and Google Chrome must already be installed.

<p align="center">
  <img src="docs/assets/setup-center.png" width="760" alt="DSH Computer Use setup center">
</p>

## What it does

| Surface | Perception | Input |
| --- | --- | --- |
| Chromium | Playwright, CDP accessibility/DOM, frames, tabs, optional OCR | Ref-pinned navigation, pointer, keyboard, forms, scroll, drag, upload |
| macOS | Accessibility tree first, Vision OCR for semantic gaps, independent window capture | AX actions, targeted SkyLight/CoreGraphics, global HID only without a target |

Every action returns a fresh bounded text observation. The model works with roles, names, values, state, geometry, and stable snapshot refs instead of assuming it can inspect screenshots. UI and OCR strings are explicitly untrusted data.

### Background macOS control

- Carries PID, WindowServer window ID, AX window frame, and element identity through every action.
- Prefers semantic AX actions before coordinate input.
- Routes supported pointer and keyboard events directly to the target process/window.
- Uses a click-through software cursor; targeted actions do not move the physical pointer.
- Keeps post-action observation pinned to the previous target, even while another app stays active.
- Falls back to public CoreGraphics or fails closed when a private capability is unavailable.

## Platform boundary

ScreenCaptureKit is public API. The optional background input path dynamically loads private SkyLight symbols and is intended for Developer ID distribution, not the Mac App Store. Private APIs are unsupported by Apple and can change between macOS releases.

On macOS 26, Stage Manager may expose a shelved window only as a small WindowServer thumbnail. Constructing a capture filter for that representation can abort inside SkyLight. DSH Computer Use detects the geometry mismatch first, preserves AX observation, returns an explicit warning, and never stretches a thumbnail into a fake full-window screenshot.

## DSH integration

The embedded package declares a DSH bundle in `package.json`. The setup center runs the official equivalent of:

```bash
dsh plugin --profile web add --save-exact file:/path/to/DSH\ Computer\ Use.app/Contents/Resources/Plugin
```

`cordis.patch.yml` installs both the Host runtime and the model-facing `computer_observe` / `computer_action` tools. No manual edits to user profile YAML or shipped presets are required. A running DSH Host must be restarted after install or upgrade.

## Build from source

Requirements: macOS 14+, Xcode/Swift 5.9+, Node.js 22+, pnpm 11+, DSH, and Google Chrome.

```bash
pnpm install
pnpm run typecheck
pnpm run test
pnpm run test:native
pnpm run build
```

`pnpm run build` creates:

```text
native/macos-helper/dist/DSH Computer Use.app
```

The default build is Universal 2. For faster local iteration:

```bash
COMPUTER_USE_ARCHS=arm64 pnpm run build
```

Create a local drag-to-Applications DMG:

```bash
pnpm run package:dmg
```

Public releases require a `Developer ID Application` identity and notarization. See [documentation/distribution.md](documentation/distribution.md) for the exact local and GitHub Actions flows.

## Tool contract

`computer_observe` returns `interactive`, `full`, or `changes` snapshots for `browser` and `desktop`, with optional query filtering and `auto | always | never` OCR.

`computer_action` performs exactly one browser or desktop action and returns the post-action semantic state. Ref and coordinate actions require the latest `snapshot_id`; stale targets fail closed and require another observation. File uploads are fenced to the DSH session workspace.

## Project

- [Architecture](documentation/architecture.md)
- [Distribution and notarization](documentation/distribution.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

Licensed under [Apache-2.0](LICENSE). This independent project is not endorsed by Apple. “DeepSeek” and related marks belong to their respective owners; the name is used only to describe compatibility with DeepSeek Harness/DSH.
