---
name: run-tearoff
description: Build, launch, screenshot, and drive the Tearoff iOS app (SwiftUI/SwiftData) in the iOS Simulator. Use when asked to run Tearoff, start the app, take a screenshot, test a UI change, or capture App Store screenshots. Also covers running VaultCore and App test suites.
---

# Running Tearoff

Tearoff is a native iOS 26 SwiftUI/SwiftData app (see the repo root
`CLAUDE.md` for architecture). This skill is the **agent path**: build once
with `build.sh`, then drive the simulator with the
`mcp__Claude_Code_iOS_Simulator__control` tool that's built into this Claude
Code environment — no custom driver needed for interaction, only for build.

All paths below are relative to the repo root (`<unit>` = this repo).

## Prerequisites

- Xcode (this machine has it at a non-standard path — check
  `xcode-select -p`; if wrong, `sudo xcode-select -s /path/to/Xcode.app`).
- `xcodegen` on PATH (`brew install xcodegen`) — `project.yml` is the source
  of truth; `Tearoff.xcodeproj` is gitignored and regenerated from it.
- An iOS 26 simulator runtime installed (`xcrun simctl list devices
  available`).

## Build (agent path)

```bash
.claude/skills/run-tearoff/build.sh [udid]
```

Verified this session on `iPhone 17 Pro` (`AC1831CD-668B-474D-8643-F8ADF7B3B8F5`).
With no UDID given it uses the first booted iPhone simulator, or boots
"iPhone 17 Pro" if none is booted. It runs `xcodegen generate`, builds the
`Tearoff` scheme (Debug) for that simulator, installs, and launches it. It
prints a machine-readable summary on stdout:

```
UDID=AC1831CD-668B-474D-8643-F8ADF7B3B8F5
APP_PATH=/Users/.../Debug-iphonesimulator/Tearoff.app
BUNDLE_ID=com.tearoff.app
```

Debug builds auto-seed realistic mock data on first launch
(`App/DevSeed/MockData.swift`, gated `#if DEBUG` in `TearoffApp.swift`) — the
Vault is populated immediately, no manual seeding step. Re-running
`build.sh` against the same UDID reinstalls onto the same data container, so
seeded state and onboarding-completed state persist across rebuilds (verified
this session — a rebuild landed straight on the Vault, not onboarding).

`StoreManager.debugProUnlock` (`App/Paywall/StoreManager.swift`) also
defaults to `true` in DEBUG builds, so Pro-gated views (camera scan,
warranty, export, widgets) render without a real purchase.

## Drive it (agent path)

Use the `mcp__Claude_Code_iOS_Simulator__control` tool with the `UDID` from
`build.sh`:

1. `attach` — opens the live panel (call this *before* `build.sh` if the user
   wants to watch; it's cheap and no-ops harmlessly if nothing's booted yet).
2. `launch` — pass `udid`, `app_path`, `bundle_id` from `build.sh`'s output.
   (Optional if `build.sh` already launched it — `launch` is idempotent.)
3. `screenshot` — pass `udid`. Returns an inline image.
4. `tap` / `swipe` / `text` / `button` — coordinates are **device points**,
   origin top-left. The tool reports the coordinate space on `attach`/
   `launch` (e.g. `402x874` for iPhone 17 Pro).

For screenshots you'll composite or upload (e.g. App Store screenshots),
capture raw pixels directly instead of the inline image — see Gotchas.

## Test

```bash
cd Packages/VaultCore && swift test        # pure-Swift domain logic, fast, no simulator
```

Verified this session: 82/82 tests pass, runs in ~0.01s. Run this first on any
logic change.

There's also a `TearoffTests` target (sources in `AppTests/`) runnable via
`xcodebuild ... test` against a simulator destination — **not run this
session** (app-level test runs are slow and weren't needed for the changes
made), so treat that path as unverified until you've actually run it.

## Run (human path)

Open `Tearoff.xcodeproj` in Xcode (after `xcodegen generate`) and hit Run.
Useless in a headless/background session — use `build.sh` instead.

## Gotchas

- **`xcodegen generate` overwrites `App/Info.plist` and
  `TearoffWidgets/Info.plist` from `project.yml`'s `info.properties`.** A
  manual edit to those plist files (e.g. bumping `CFBundleVersion` by hand)
  gets silently reverted on the next `xcodegen generate`. Edit `project.yml`
  instead, then regenerate.
- **The app target and the widget extension must share the same
  `CFBundleVersion`,** or `xcodebuild archive` succeeds but prints
  `warning: The CFBundleVersion of an app extension (...) must match that of
  its containing parent app (...)` and App Store Connect validation rejects
  the upload. Set `CFBundleVersion` in **both** the `Tearoff` and
  `TearoffWidgets` target's `info.properties` in `project.yml`.
- **Tap coordinates for small/animated buttons are unreliable to eyeball
  from the tool's inline screenshot.** The onboarding flow
  (`App/Onboarding/OnboardingView.swift`) has a bottom "Continue"/"Get
  Started" button whose point-space Y position is easy to misjudge — several
  tap attempts at plausible coordinates landed on the animated receipt mock
  above it instead of the button. **Prefer `swipe` to page through a
  `TabView`** (reliable: swipe left anywhere mid-screen, e.g.
  `x:350,y:700 → x:50,y:700`) and only fall back to precise `tap` once
  you've confirmed the target's frame (e.g. by reading the SwiftUI source
  for `.padding`/alignment) rather than guessing from the screenshot.
- **The inline `screenshot` image from the MCP tool is downscaled** (roughly
  2.28x device points on iPhone 17 Pro, not the native 3x retina scale) —
  fine for visual inspection, but don't use it as a source for App Store
  screenshots or pixel-exact work. Capture raw pixels straight to disk
  instead:
  ```bash
  xcrun simctl io <udid> screenshot /path/to/out.png   # writes native 1206x2622 PNG (3x)
  ```
  Verified this session — `sips -g pixelWidth -g pixelHeight` confirmed
  `1206x2622` from this command vs. the tool's downscaled inline image.
- **Writes under the repo's `fastlane/screenshots/` can fail with
  `NSCocoaErrorDomain code=513` ("You don't have permission")** on this
  machine's external drive — write raw captures to the scratchpad or `/tmp`
  and copy/move into the repo afterward instead.
- **`simctl install` onto an already-installed bundle ID upgrades in place**
  and preserves the data container (UserDefaults, SwiftData store) — useful
  for iterating without re-seeding or re-onboarding, but remember stale state
  can mask a regression. Use `xcrun simctl uninstall <udid> com.tearoff.app`
  first if you need a truly clean install.

## Downstream: App Store screenshots

`tools/appshots-mcp-server` (not registered as an MCP server in this repo —
see its README) composites raw screenshots into exact-size App Store
marketing images via a pure `render()` function in `src/render.ts` /
`dist/render.js` (presets: `iphone-6.5` = 1284×2778, etc.). It can be
invoked directly from a small Node script without going through MCP.
`scripts/asc-upload-screenshots.py` then pushes framed PNGs to the inflight
App Store Connect version (`ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_PRIVATE_KEY_PATH`
env vars required).
