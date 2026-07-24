# iPrint — Warranty & Return-Window Vault

**Date:** 2026-07-19
**Status:** Design approved, pending review
**Scope of this spec:** P0 only. P1 (Siri surface) and P2 (merchant QR ingestion) get their own specs.

---

## 1. Product

**iPrint is the receipt vault that warns you before it's too late.**

Photograph a receipt. It is parsed on-device. The app knows the return window
closes on March 14 and the warranty runs to 2028, tells the user three days
before the window shuts, and produces the proof on demand a year later when the
product fails.

Positioning, in one line: **every other receipt app is built for accountants;
this one is built for the moment something breaks.** Expensify, Keeper, and
QuickBooks Self-Employed all optimize for year-end tax export. Nobody owns *"I
need to return this and I cannot find the receipt."*

Native Swift and SwiftUI, iOS and iPadOS. Everything on-device. No account.

### Non-goals

- Expense reporting, tax categorization, mileage — a different, crowded market.
- Any server component. There is no backend in P0.
- OCR of arbitrary documents. Receipts only.
- Selling, transmitting, or aggregating user purchase data. See §7.

---

## 2. Prior context

This replaces the earlier Expo/React Native prototype. Foundation Models has no
React Native binding, and `AppEntity`/`EntityQuery` — the mechanism that lets
Siri reason over app data — is Swift-native. The Apple Intelligence direction
requires native Swift.

Retained from the prototype: the receipt domain model, the discipline of storing
money as integer cents, and the QR codec design (deferred to P2).

Discarded: all React Native code.

---

## 3. Ingestion pipeline

The on-device model is **text-only**. It cannot accept an image. Three distinct
stages; conflating them is the common failure:

```
VisionKit capture
  → Vision OCR (VNRecognizeTextRequest) → plain text
    → Foundation Models @Generable extraction → ReceiptDraft
      → user confirmation screen
        → persisted Purchase
```

```swift
@Generable
struct ReceiptDraft {
    @Guide(description: "Merchant name exactly as printed")
    var merchant: String

    @Guide(description: "Purchase date, ISO 8601")
    var purchaseDate: String

    @Guide(.count(1...40))
    var items: [DraftItem]

    var totalCents: Int

    @Guide(description: "Return policy text if printed on the receipt, else empty")
    var printedPolicy: String
}
```

### Two non-negotiable rules

**Model output is never persisted without user confirmation.** Extraction lands
in a confirmation screen showing the parsed fields beside the raw OCR text. A
silently wrong date on a warranty record surfaces a year later, at the worst
possible moment, and is indistinguishable from the app lying.

**The app is fully functional with Apple Intelligence unavailable.** Foundation
Models requires an eligible device (iPhone 15 Pro and later), the feature
enabled, and a supported region. Every other configuration degrades to Vision
OCR plus manual field entry — slower, still complete. AI is an accelerant, never
a gate.

Availability is branched explicitly on `SystemLanguageModel.default.availability`
for `.available`, `.unavailable(.deviceNotEligible)`,
`.unavailable(.appleIntelligenceNotEnabled)`, `.unavailable(.modelNotReady)`, and
an unknown-reason fallback. Each branch has a tested UI.

---

## 4. Policy engine

This decides whether the product is trusted, and it must not touch the LLM.

Asking a ~3B on-device model for a retailer's return policy produces confident
fiction — that is world knowledge, which the model is explicitly not built for. A
wrong return date is worse than no date: the user relies on it, does not hurry,
and misses the window.

Windows resolve by a strict ladder, most authoritative first:

1. **Printed on the receipt.** Extracted from the OCR text. This is reading, not
   recall — legitimate model work, and the most authoritative source, being the
   actual contract.
2. **Curated policy table.** Bundled JSON keyed by merchant with category
   exceptions. Supplied to the model through the `Tool` protocol so it retrieves
   rather than recalls.
3. **Unknown.** Ask the user once; remember per-merchant permanently.

Every stored window records its provenance (`printed` / `table` / `user`), and
the UI displays it: *"Return by Mar 14 — printed on your receipt."* Provenance
is what converts a bare date into something a user will act on.

### The returnable/consumable gate

Not every receipt deserves a window. US households make roughly 146 grocery
trips a year, and essentially none of those purchases are returnable in any
meaningful sense. If every scanned receipt produces a tracked window, the vault
fills with noise and stops being trustworthy.

Before any window is assigned, each purchase is classified:

- **Returnable / warrantable** — electronics, appliances, tools, furniture,
  apparel, sporting goods. Gets a window.
- **Consumable** — groceries, fuel, restaurants, most pharmacy. Stored if the
  user wants a record, but no window, no alert, and visually de-emphasized.

Classification is a categorization task and is an appropriate use of the
on-device model. The user can always override.

This gate is what keeps the vault a vault rather than a junk drawer.

### Warranty duration is a separate problem

Return windows are set by the **merchant**. Warranty length is set by the
**manufacturer**, and the merchant is usually not the manufacturer — Best Buy
does not decide the warranty on a Sony television. The merchant-keyed policy
table therefore cannot supply warranty duration, and a second ladder is
required:

1. **Printed on the receipt.** Some receipts state warranty terms. Extract.
2. **Category default.** A conservative bundled table keyed by product
   category, not merchant: consumer electronics 1 year, major appliances
   1 year, tools 1 year. Presented explicitly as an estimate.
3. **User entry.** The user sets or corrects it; remembered per manufacturer.

Category assignment for rung 2 is a **classification** task and is a legitimate
use of the on-device model, unlike duration recall, which is not.

Warranty dates carry the same provenance marker as return windows, and estimated
durations are labelled as estimates in the UI. The app must never present an
inferred warranty date with the same confidence as a printed one.

### Policy table versioning

Rows carry an `effectiveDate` and are **append-only**. A purchase made under a
90-day policy keeps 90 days after the retailer cuts to 30. Purchases store a
resolved `PolicySnapshot`, never a reference to a mutable row — the same
snapshot-not-reference reasoning applied to merchant details. This is
unfixable retroactively once user records exist.

Maintaining this table is permanent manual labor. It is also the moat: it is the
one asset a competitor cannot generate from a prompt.

---

## 5. Architecture

SwiftUI and SwiftData. `NavigationSplitView` so iPad presents a genuine two-pane
vault rather than a stretched phone layout.

| Module | Responsibility |
|---|---|
| `Model/` | `Purchase`, `LineItem`, `MerchantSnapshot`, `PolicySnapshot`. Money is `Int` cents throughout. |
| `Ingest/` | VisionKit capture, Vision OCR, text normalization. |
| `Intelligence/` | `LanguageModelSession` wrapper, availability gating, fallback routing. |
| `Policy/` | Resolution ladder and curated table. |
| `Alerts/` | Notification scheduling and rescheduling. |
| `Paywall/` | StoreKit 2 entitlement state, availability-gated paywall copy. |

`Intelligence/` and `Policy/` import no SwiftUI, so both are testable without a
simulator.

### Alerts

`UNCalendarNotificationTrigger` at return window −3 days and warranty −30 days.
Alerts reschedule whenever a policy resolution is corrected by the user.

### Deferred: Wallet passes

A `.pkpass` must be signed with the Pass Type ID private key. Shipping that key
inside the app exposes it; signing it properly requires a server, which
contradicts the no-backend stance. Lock-screen presence in P0 is a widget, not a
pass. Revisit if iOS 27 ships user-created passes from scanned codes.

---

## 6. Siri surface (P1, designed now)

```swift
struct Purchase: AppEntity {
    static var defaultQuery = PurchaseQuery()
    @Property(title: "Item") var name: String
    @Property(title: "Return by") var returnDeadline: Date?
}
```

`AppEntity` plus `EntityQuery` is what allows Siri to resolve *"the headphones"*
to a stored record. Above it: `CheckReturnWindowIntent`, `FindReceiptIntent`,
`LogReceiptIntent`, an `AppShortcutsProvider` with suggested phrases, and Core
Spotlight indexing.

**Strategic note.** All of the above ships on iOS 26 and works today. Reported
iOS 27 features (a standalone Siri app, cross-app personal context) are
unreleased beta reporting and are treated strictly as upside: if they ship,
`AppEntity` is precisely the substrate they consume and the app improves with no
new code; if they are cut, a working Siri and Spotlight surface has still
shipped. No P0 or P1 requirement depends on an unreleased feature.

---

## 7. Monetization

### Permanent constraint

Itemized purchase data is among the most valuable consumer data that exists, and
selling it would destroy the product's only differentiator. The architecture —
on-device extraction, no backend, no account — makes it **structurally
impossible** rather than merely prohibited. This is a marketing asset, not just a
policy. It is not revisitable.

Also excluded: advertising, and extended-warranty affiliate revenue. The latter
pays when coverage lapses, which is directly opposed to the promise the app
makes, and is a regulated insurance referral with state-by-state licensing.

### Consumer pricing (P0)

| Tier | Price | Includes |
|---|---|---|
| Free | — | Unlimited manual receipts, expiry alerts, full vault |
| Pro | $2.99/mo or $14.99/yr | Camera + AI extraction, warranty tracking, export, widgets |
| Lifetime | $39.99 one-time | Pro, permanently. Family Sharing enabled. |

The free tier is permanently useful: a user who never pays still has a working,
trustworthy vault. Pro sells time saved, not access to the user's own records.

Lifetime exists because a "vault" is a thing people expect to own, and
low-frequency utilities suffer heavy subscription churn.

**Paywall framing.** This product is insurance-shaped — the user pays and
usually receives nothing, which is exactly the framing that makes it acceptable.
The paywall computes the pitch from the user's own vault: *"$2,340 of your
tracked purchases are still inside a return window."* One recovered $180 return
funds a decade of the app.

**Availability gating.** Paywall copy must branch on
`SystemLanguageModel.default.availability`. Advertising AI extraction to an
ineligible device produces refunds and a plausible §3.1.2 review problem.

### Implementation order

Per StoreKit 2 guidance, `.storekit` configuration is created and tested
**before** any purchase code is written: config → local testing → `StoreManager`
→ unit tests with a mocked store → sandbox.

### Longer-term revenue (out of scope here)

- **Merchant SaaS (P2+).** Zero-PII QR receipt issuance sold per location.
  Eliminates thermal paper cost, checkout friction, and PII liability. B2B pays
  substantially more per user and churns less. This is the business; consumer
  IAP funds the runway.
- **Policy dataset licensing.** The curated table has standalone value and is
  being maintained regardless.

---

## 8. Testing

Swift Testing, concentrated on the modules that can silently corrupt a
year-old record.

- **Golden corpus.** ~30 real receipt OCR texts as fixtures with asserted
  extraction. Must include adversarial cases: two-column layouts, faded thermal,
  `$1,234.56` versus `1234,56`, multi-page, and coupon lines producing negative
  amounts.
- **Policy ladder.** Provenance precedence, category exceptions, unknown-merchant
  path, and `effectiveDate` selection for historical purchases.
- **Availability paths.** Xcode's *Simulated Foundation Models Availability*
  scheme override to force each `.unavailable` reason and assert the fallback UI
  renders.
- **Money.** Cents arithmetic and rounding at tax boundaries.
- **StoreKit.** Entitlement resolution against a mocked store; restore purchases.

---

## 8a. Measurement

### North-star metric: extraction-correction rate

Defined as *fields the user edits on the confirmation screen ÷ fields
presented*. This is the only honest measure of whether the AI path beats manual
entry, and per-field breakdown tells you exactly where `@Guide` tuning pays off.

Recorded fields: `merchant`, `purchaseDate`, `totalCents`, `itemCount`,
`policyResolution`, `category`.

**Counts only — never field contents.** Storing "the user corrected the
merchant" is a diagnostic; storing "the user corrected it to Planned
Parenthood" is the surveillance this product exists to avoid.

### The honest cost of having no backend

With no server and no account, **this data cannot be collected from users.**
That is a real, accepted cost of the privacy stance, not an oversight. The
mitigation ladder:

1. **Development and TestFlight** — a local diagnostics screen showing
   correction rates, plus manual export. Sufficient to tune extraction against
   real receipts during beta.
2. **Post-launch** — opt-in aggregate submission (counts only, no content, no
   identifier), off by default, with a plain-language explanation. If adoption
   is too low to be meaningful, accept flying blind rather than weaken the
   guarantee.

The guarantee is the product. Measurement yields to it, not the reverse.

### Market context (2026-07-19)

US consumers returned **$849.9B in 2025, 15.8% of retail sales**; e-commerce
return rate was 19.3% (NRF / Happy Returns, surveying 2,006 consumers and 358
e-commerce professionals). The behavior is enormous and mainstream.

Countervailing figure: households make ~146 grocery trips a year but only an
estimated 15–30 *durable-goods* purchases. The addressable receipt population is
small and infrequent. This is the central retention risk and the reason the
product must deliver value passively through notifications rather than by
requiring engagement.

## 9. Phasing

| Phase | Scope |
|---|---|
| **P0** | Capture → OCR → extraction → confirm → vault. Returnable/consumable gate. Policy ladder with ~20 curated returnable-goods retailers. Return and warranty notifications. iPad split view. StoreKit tiers. |
| **P1** | `AppEntity`, intents, App Shortcuts, Spotlight indexing. |
| **P2** | QR codec ingestion, merchant issuance, export, Wallet if signing resolves. |

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Vision OCR fails on faded thermal paper | Validate against the golden corpus **before** building extraction. If OCR is unusable, the P0 premise needs rethinking. |
| Long receipt overflows the ~4,096-token context | Measure on-device with a 40-line receipt during the spike; design chunk-and-merge if needed. |
| Wrong policy resolution causes a missed return | Provenance ladder, provenance shown in UI, never guess silently. |
| Apple Intelligence device gating shrinks the addressable market | Full manual fallback; paywall copy gated on availability. |
| Policy table maintenance burden | Accepted, and treated as the moat. Append-only with `effectiveDate`. |
| Subscription churn on a low-frequency utility | Insurance framing, vault-value paywall, lifetime tier. |

---

## 11. Open questions

1. **Should the Siri surface move from P1 into P0?** `AppEntity` is inexpensive
   once the model exists and it is the demo. Against: an empty vault makes every
   Siri query answer "nothing found."
2. ~~**Is a top-50 retailer table the right P0 size?**~~ **Resolved
   2026-07-19.** Ranking by revenue is the wrong axis — the NRF Top 100 is
   dense with grocery, pharmacy, and fuel, which are near-irrelevant to
   returns. P0 ships **~20 hand-curated returnable-goods retailers** instead,
   which likely covers more real return windows than 50 chosen by revenue.
   Scope reduced accordingly. Revisit once real correction-rate data exists.
3. **Should warranty tracking ship in P0 at all?** It needs a second ladder and
   a category table (§4), and its data is inherently weaker than return-window
   data. Deferring it to P1 would tighten P0 to a single well-sourced promise —
   return windows — at the cost of the product's name.
4. **Is P0 still too large for one implementation plan?** It currently spans
   capture, OCR, extraction, policy resolution, notifications, iPad layout, and
   StoreKit. A defensible split is P0a (vault, manual entry, policy ladder,
   alerts) and P0b (camera, OCR, AI extraction, paywall).
