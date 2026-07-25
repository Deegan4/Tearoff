# Project Memory — Tearoff

Durable record of what Tearoff is and the decisions behind it, so future
sessions pick up context fast. For build/test/convention mechanics see
`CLAUDE.md`.

## What Tearoff is

A native **iOS 26 SwiftUI + SwiftData** app. Scan a paper receipt → Tearoff
tracks its **return** and **warranty** deadlines and alerts before they close,
then produces proof-of-purchase on demand. This fully replaced the earlier
Expo/React Native "iPrint" prototype (that scope — a phone-as-thermal-printer
tool — was abandoned; do not resurrect it).

The product's moat is **trust machinery**, not AI: honest provenance, an
append-only retailer-policy table, a returnable/consumable gate that keeps the
vault from becoming a junk drawer, and honest "I don't know" states. AI
(on-device Vision OCR + Foundation Models) only fills fields the user then
confirms — it never decides a policy.

## Architecture (see CLAUDE.md for detail)

- **`Packages/VaultCore/`** — pure Foundation domain logic, `swift test`-able,
  no UI/IO imports (enforced by `ModuleBoundaryTests`).
- **`App/`** — SwiftUI/SwiftData shell, camera/OCR, notifications, StoreKit,
  paywall, views. `ResolverStore.shared` bridges the two.

## Current state (as of 2026-07-24)

Shipped to `main` and installed on a physical iPhone 15 ("iCrackU"):

- **P0a** — VaultCore engine (Cents, categories+gate, append-only PolicyTable +
  PolicyResolver, WarrantyResolver, provenance/WindowResolution) and the app
  shell: vault split view, manual entry, edit/delete, camera scan → Vision OCR
  → confirm → print, auto-filled category/windows, line items, subtotal/tax,
  payment, order #, barcode scan, return lifecycle, proof-of-purchase share,
  expiry notifications, search/sort, premium motion.
- **P0b** — golden receipt regression corpus (parser moved into VaultCore);
  on-device extraction-correction telemetry + Settings accuracy dashboard
  (counts-only); StoreKit Pro tiers + vault-computed paywall (camera scan
  gated).
- **P0c** — CSV/JSON vault export (RFC-4180 safe), Pro-gated; warranty tracking
  Pro-gated (free users get an upsell, no warranty term/alerts persisted).

Verification bar held throughout: VaultCore `swift test` green (62 tests),
app builds for simulator and signed device.

## Pricing / tiers (spec §7)

- Free — manual receipts, expiry alerts, full vault (permanently useful).
- Pro — $2.99/mo or $14.99/yr: camera + AI extraction, warranty tracking,
  export, widgets.
- Lifetime — $39.99 one-time, Family Sharing.
- Paywall is insurance-shaped: pitch computed from the user's own vault
  ("$X still inside a return window") and AI copy branches on
  `SystemLanguageModel.default.availability`.

## Known gaps / next

- **Widgets** — advertised on the paywall; being built now (Home Screen
  upcoming return/warranty deadlines).
- **App Store Connect products** — not created yet, so on-device the paywall
  shows no prices (local `.storekit` only applies to Xcode-run sessions). Needs
  the three IAPs created in ASC with IDs matching `TearoffProduct`.
- Warranty/export enforcement is done; widget enforcement lands with the widget.

## Longer-term (out of scope now)

Merchant SaaS (P2+): zero-PII QR receipt issuance sold per location — the real
business; consumer IAP funds the runway.
