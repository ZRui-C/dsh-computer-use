# Contributing

## Development setup

Requirements: macOS 14+, Xcode/Swift 5.9+, Node.js 22+, pnpm 11+, DSH, and Google Chrome.

```bash
pnpm install
pnpm run typecheck
pnpm run test
pnpm run test:native
COMPUTER_USE_ARCHS=arm64 pnpm run build
```

The default release build is Universal 2. Set `COMPUTER_USE_ARCHS=arm64` for faster Apple Silicon iteration or `x86_64` on Intel.

## Native permissions

Grant Accessibility and Screen Recording to the exact built `DSH Computer Use.app`. Ad-hoc signatures can change identity after rebuilds; use a stable Apple Development identity for repeated local testing.

Permission-gated tests skip when the test process is not authorized. Tests must not prompt for or modify TCC permissions.

## Change requirements

- Keep the browser and desktop protocols text-first.
- Prefer AX semantic actions before coordinate input.
- Never report event transport success as verified target state; preserve post-action observation.
- Keep PID/window targeting through every input layer.
- Add availability checks and a public or fail-closed path for every private API change.
- Do not weaken workspace upload boundaries or local socket permissions.
- Do not overwrite user-authored DSH profiles or presets.
- Update English and Chinese documentation for user-visible behavior.

Run the complete checks before opening a pull request:

```bash
pnpm run check
pnpm run test:native
pnpm run smoke:native
```

Do not commit generated app bundles, DMGs, signing certificates, notarization keys, API keys, sockets, screenshots, or local DSH state.
