# DSHComputerUse native application

The macOS product combines a first-run setup center and a background NDJSON agent in one signed bundle.

## Modes

```bash
# Product UI
open 'dist/DSH Computer Use.app'

# Background agent
open -gjn 'dist/DSH Computer Use.app' --args \
  --agent --socket /tmp/dsh-computer-use.sock
```

Finder launch shows the permission and DSH installation center. `--agent` switches the same executable to an accessory process and starts the Unix socket server without activating a window.

## Build

From the repository root:

```bash
pnpm run build
```

The default build is Universal 2 and produces:

```text
native/macos-helper/dist/DSH Computer Use.app
```

For a single development architecture:

```bash
COMPUTER_USE_ARCHS=arm64 pnpm run build
```

Use a stable local identity when repeatedly testing TCC permissions:

```bash
COMPUTER_USE_CODESIGN_IDENTITY='Apple Development: ...' \
COMPUTER_USE_ARCHS=arm64 \
  pnpm run build
```

## Protocol

The socket carries newline-delimited JSON. Requests and responses have an `id`; successful responses set `ok: true` and failures carry a stable error code and message.

Core methods:

- `handshake`
- `status`
- `observeDesktop`
- `performDesktop`
- `ocrFile`
- `cancel`
- `shutdown`

A target descriptor may carry `bundleId`, `pid`, `windowId`, `windowFrame`, AX role/name/identifier/path/frame, or OCR text. Pointer and keyboard actions preserve that identity through AX, SkyLight, and public CoreGraphics routes.

## Permissions

- Accessibility: semantic desktop observation and input.
- Screen Recording: window/display pixels and OCR.

The setup center prompts only after a user selects **Authorize**. Agent status checks never mutate TCC. Both modes share bundle ID `tech.zrui.dsh-computer-use`, so a correctly signed upgrade retains one stable permission identity.

## Private APIs

SkyLight symbols are resolved with `dlopen`/`dlsym` and guarded at runtime. They enable targeted background input without moving the physical cursor. Public `CGEvent.postToPid`, AX actions, and fail-closed behavior remain available when the private route cannot be used.

On macOS 26, Stage Manager shelf thumbnails are detected before constructing the ScreenCaptureKit filter that can abort inside SkyLight. AX observation remains available with an explicit capture warning.

Private APIs make the full product unsuitable for Mac App Store review. Developer ID signing and notarized direct distribution are documented in [../../documentation/distribution.md](../../documentation/distribution.md).
