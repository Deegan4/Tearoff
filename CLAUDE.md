# CLAUDE.md — Tearoff

Operational guide for working in this repo. Read before building or committing.

## What Tearoff is

A native iOS 26 (SwiftUI + SwiftData) app: scan a paper receipt, and Tearoff
tracks its **return** and **warranty** deadlines and alerts you before they
close. Renamed from the earlier Expo/React Native "iPrint" prototype, which is
gone — ignore any lingering references to it.

## Architecture

Two layers, deliberately separated:

- **`Packages/VaultCore/`** — a pure Swift package (Foundation only, Swift 6
  strict concurrency). All domain logic lives here: money (`Cents`),
  categories + the returnable/consumable gate, the append-only versioned
  `PolicyTable` + `PolicyResolver`, `WarrantyResolver`, the receipt parser
  (`ReceiptParser`/`ParsedReceipt`/`LineItem`), extraction telemetry
  (`ExtractionAudit`/`AccuracyLedger`), entitlements (`Entitlement`/`ProTier`),
  and export (`VaultExport`). **No UIKit, SwiftUI, SwiftData, StoreKit, or
  Vision imports** — enforced by `ModuleBoundaryTests`. If logic can be pure,
  it goes here so it is unit-testable with `swift test` (no simulator).
- **`App/`** — the SwiftUI/SwiftData shell. Persistence (`StoredPurchase`),
  camera/OCR (Vision), notifications, StoreKit (`StoreManager`), the paywall,
  and all views. Maps `StoredPurchase` ⇄ VaultCore value types in
  `PurchaseMapping.swift` (`ResolverStore.shared`).

Rule of thumb: **new domain logic → VaultCore + tests; UI/IO → App.**

## Build & test

- Core tests (fast, do this first): `cd Packages/VaultCore && swift test`
- App build (simulator):
  `xcodebuild -project Tearoff.xcodeproj -scheme Tearoff -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- The Xcode project is **generated** — `project.yml` is the source of truth and
  `*.xcodeproj` is gitignored. After adding/removing/moving any file under
  `App/`, run `xcodegen generate` before building or the target's file list is
  stale. VaultCore sources are globbed by SPM and need no regeneration.

### Install to a physical device
```bash
xcodebuild -project Tearoff.xcodeproj -scheme Tearoff \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates \
  -derivedDataPath build/DD build
xcrun devicectl device install app --device <UDID> build/DD/Build/Products/Debug-iphoneos/Tearoff.app
```
List devices: `xcrun devicectl list devices`. `build/` is gitignored — never
commit it (a stray `git add -A` once swept 2822 derived-data files into the
repo; do not repeat — stage specific paths, not `-A`, after a device build).

## Conventions

- **Money is always `Cents`** (integer minor units). Never route amounts
  through `Double`/`Float`.
- **Provenance is sacred.** Every resolved window records whether it came from
  the receipt (`printed`), the retailer table, a category default (estimate),
  or the user. The UI shows it; estimates are visually flagged. Never invent a
  window the parser/tables can't justify.
- **Parser is conservative** — it must never fabricate a value it can't find.
- **Telemetry is counts-only, on-device** — the accuracy ledger stores no
  receipt contents and never leaves the device.
- **Policy table is append-only** with `effectiveDate`; historical purchases
  keep the policy in force when they were bought. Adding a retailer requires a
  collision check (see `PolicyTable` docs).
- **Pro gating** (spec §7): Free = manual receipts, alerts, full vault. Pro
  ($2.99/mo · $14.99/yr · $39.99 lifetime) = camera+AI extraction, warranty
  tracking, export, widgets. Product IDs and the pure entitlement logic live in
  VaultCore (`TearoffProduct`, `Entitlement.tier`); `Tearoff.storekit` mirrors
  them for local testing (wired into the run scheme).

## Workflow expectations

- Commit messages: conventional (`feat(app):`, `test(core):`, `chore:`), with
  the `Co-Authored-By: Claude Opus 4.8` trailer.
- Land work on a feature branch and open a PR to `main`; the human runs the
  merge (the sandbox's classifier blocks `gh pr merge`).
- Keep `swift test` green and the app building before committing.

## Specs & plans

- Design spec: `docs/superpowers/specs/2026-07-19-warranty-vault-design.md`
- P0a plan + ledger: `docs/superpowers/plans/` and `.superpowers/sdd/`
