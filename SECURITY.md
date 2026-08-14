# Security policy

## Supported versions

Security fixes are applied to the latest release. Private macOS APIs are version-gated and may be disabled on an OS version that has not been verified.

## Reporting a vulnerability

Use the repository's private GitHub Security Advisory form. Do not open a public issue for credential exposure, unintended cross-process input, socket authorization bypass, arbitrary file access, or permission-boundary defects.

Include the affected version, macOS build, architecture, minimal reproduction, and expected security boundary. Remove API keys, account data, screenshots, and unrelated system logs.

## Security boundaries

- The native RPC endpoint is a local Unix socket in a private user directory. It is not a network service.
- Accessibility and Screen Recording are granted by the user through macOS System Settings. The project never edits TCC databases.
- Targeted input carries a PID and window identity. Global HID input is reserved for explicit untargeted actions.
- Browser uploads are restricted to the active DSH workspace.
- UI text and OCR output are untrusted model input and cannot override user or system instructions.
- SkyLight symbols are loaded dynamically, checked at runtime, and paired with public or fail-closed fallbacks. Private APIs are unsupported by Apple and remain a compatibility risk.

Official release artifacts are Developer ID signed, notarized, and published with SHA-256 checksums. Never install a release whose signature, notarization, or checksum cannot be verified.
