# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and semantic versioning.

## [Unreleased]

### Fixed

- Discover AX semantic actions through the proper action-name API.
- Traverse deep desktop AX trees with bounded depth/node budgets and explicit truncation diagnostics.
- Add `ocrLanguages` configuration and automatic OCR language detection, including browser and display fallback paths.
- Test against the DSH 0.2.1-alpha.1 dependency family while preserving existing peer ranges.

- Register the Computer Use tools in the global DSH tool layer so every agent preset inherits them.
- Detect and repair profiles where the package dependency exists but `dsh.profile.bundles` does not enable it.

## [0.3.0] - 2026-08-14

### Added

- Universal 2 `DSH Computer Use.app` with a first-run permission and DSH installation center.
- DSH bundle manifest that installs the Host and model-facing tools without manual profile YAML edits.
- Process/window-targeted SkyLight and CoreGraphics input with a software cursor overlay.
- Target-pinned AX observation and independent window capture.
- Developer ID signing, notarization, stapled DMG, checksum, CI, and tagged release automation.
- Apache-2.0 project license and third-party attribution notices.

### Changed

- Replaced the development-only DeepSeek-branded helper identity with the neutral `tech.zrui.dsh-computer-use` product identity.
- Window capture now fails closed with an explicit AX-only warning when Stage Manager exposes only a shelf thumbnail.

### Security

- Private input APIs are dynamically resolved and never treated as semantically successful without post-action observation.
- Physical cursor movement is avoided for targeted background input.
