# Architecture

DSH Computer Use is a text-first DSH plugin backed by one signed macOS application.

```text
DSH agent session
  -> computer_observe / computer_action
  -> DSH Host service
       -> Chromium: Playwright + CDP Accessibility/DOM
       -> macOS: Unix socket RPC
            -> DSH Computer Use.app --agent
                 -> Accessibility tree
                 -> Vision OCR
                 -> ScreenCaptureKit
                 -> AX / SkyLight / CoreGraphics input
```

## Product process

`DSH Computer Use.app` has two launch modes with one bundle identifier and designated requirement:

- Finder launch: regular AppKit/SwiftUI setup center for permissions and DSH bundle installation.
- `--agent --socket <path>`: accessory background process with no activating window or Dock workflow.

Using one signed bundle keeps Accessibility and Screen Recording attached to a stable TCC identity. DSH starts a separate agent instance with LaunchServices so the setup window can remain closed.

## Perception

Browser observations combine CDP accessibility data, DOM state, geometry, frames, tabs, and optional OCR. Desktop observations begin with AX and add Vision OCR only when semantic coverage is insufficient. Every actionable node carries a stable snapshot-scoped ref.

Post-action observation is mandatory. Event transport success does not prove that a target application consumed the event.

## Input routing

1. AX semantic action when the target exposes one.
2. Process/window-targeted SkyLight event recipe on supported macOS builds.
3. Public `CGEvent.postToPid` fallback.
4. Global HID only for an explicit action without a target.

The targeted mouse route stamps PID, window ID, local location, event phase, click group, handling window, and window-under-pointer fields. Synthetic focus records are sent only to the target and are revoked after the action; the real foreground app is not resigned or reactivated.

## Capture and Stage Manager

Normal windows use `SCContentFilter(desktopIndependentWindow:)`, the filter's `contentRect` and `pointPixelScale`, and `SCScreenshotManager`. `/usr/sbin/screencapture -l` is a compatibility fallback.

On macOS 26, a window moved to the Stage Manager shelf may be represented only by a small WindowServer thumbnail. Constructing a desktop-independent filter for that representation can abort inside SkyLight. The helper compares AX geometry with WindowServer geometry first, skips the unsafe call, retains AX observation, and returns an explicit degradation warning. It never stretches a thumbnail into a fake full-window screenshot.

## Trust boundaries

The Host owns browser processes, the native socket, and per-session state. Browser contexts are isolated by DSH session. Upload paths are fenced to the session workspace. UI/OCR strings are rendered as untrusted data. See [SECURITY.md](../SECURITY.md) for reporting and release verification.
