# Tearoff — App Store Connect listing

Copy-paste source for the ASC "App Information" and version metadata fields.
App ID `6794405635`. Locale: **en-US** (primary).

Character counts are shown as `[used/limit]` — all fields are within Apple's caps.

---

## App Information (app-level, locale-independent)

| Field | Value |
|---|---|
| Primary category | **Shopping** |
| Secondary category | **Finance** |
| Age rating | 4+ (no objectionable content) |
| Support URL | `https://deegan4.github.io/Tearoff/#support` |
| Marketing URL | `https://deegan4.github.io/Tearoff/` |
| Privacy Policy URL | `https://deegan4.github.io/Tearoff/privacy.html` |
| License agreement | Apple Standard EULA |

> **Category note.** Shopping is the right primary: the return-deadline cohort
> (Return Hero, Reclaimo, ReturnTrack) all sit there, and it is far less
> crowded than Finance, where the receipt/expense giants live. Receipt Safe
> chose Finance and competes against every expense tracker on the store.

---

## Localizable metadata

### App Name `[26/30]`

```
Tearoff: Receipt Deadlines
```

### Subtitle `[27/30]`

```
Return & Warranty Reminders
```

### Keywords `[99/100]`

No spaces, no repeats of words already in the name or subtitle.

```
scanner,tracker,refund,expiry,policy,organizer,proof,purchase,alerts,window,exchange,slip,guarantee
```

### Promotional Text `[148/170]`

Editable without a new build — use it for seasonal pushes (post-holiday
returns in January, Prime Day, Black Friday).

```
Every purchase has a clock on it. Scan a receipt, and Tearoff tracks the return window and the warranty — then reminds you before either one closes.
```

### Description `[2,847/4,000]`

```
You didn't mean to keep it. You just forgot the receipt was in your pocket, the box was still in the hall, and the 30 days were up on Tuesday.

Tearoff puts a clock on every purchase. Scan the receipt, and it tracks two deadlines — when you can still return the item, and how long the warranty runs — then reminds you before either one closes.

SCAN IT, OR TYPE IT
Point the camera at a paper receipt and Tearoff reads it on your device: merchant, date, total, and any return or warranty terms printed on the slip itself. No account, no upload, no sign-up. Your first three scans are free, so you can see it work before you decide anything. Prefer to log it by hand? That takes about ten seconds and is free, forever.

IT TELLS YOU WHERE EVERY DATE CAME FROM
This is the part other trackers skip. A deadline is only worth trusting if you know where it came from, so Tearoff labels every single one:

• "You set this" — you entered or corrected it
• "Printed on your receipt" — read straight off the slip
• "Published return policy" — from a curated retailer policy table
• "Estimate" — a typical window for that kind of purchase, clearly flagged

When Tearoff isn't sure, it says so instead of inventing a date. It will never quietly hand you a confident-looking deadline it can't justify.

RETAILER POLICIES, DATED AND VERSIONED
Return policies change. Tearoff's policy table records when each one took
effect, so a purchase you made last spring keeps the policy that was actually in force when you bought it — not whatever the store switched to since.

A REMINDER WHILE IT STILL MATTERS
Alerts arrive with enough runway to actually drive to the store. The Home Screen widget keeps your next closing deadline in view, so the vault isn't something you have to remember to open.

PRINT A PROOF SLIP
Every saved purchase prints as a clean thermal-style receipt with the return-by date, the warranty date, and a scannable barcode — ready to hand over at the returns desk or share with whoever gave you the gift.

YOUR VAULT, YOUR DEVICE
No account. No ads. No analytics on your receipts. Everything lives on your iPhone and syncs through your own private iCloud account if you're signed in. Tearoff's usage counters are counts only, stored on-device, and never leave it.

FREE
• Log purchases by hand, unlimited
• Three receipt scans to try
• Return-deadline tracking and reminders
• Your full receipt vault

TEAROFF PRO
• Unlimited camera scanning with on-device receipt extraction
• Warranty tracking and warranty alerts
• One tap straight to the retailer's own returns page
• Home Screen widgets, with snooze
• A nudge when you're near a store where something is still returnable
• Export your vault as CSV, plus a Year in Review PDF

Pro is $2.99/month, $14.99/year, or $39.99 once for lifetime access.

Made for iOS 26. Built in SwiftUI, with the deadline logic in a separate, fully tested package — because the part that's least allowed to guess is the part most worth testing.

---
Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple Account at confirmation of purchase. Manage or cancel in your Apple Account settings.
Privacy Policy: https://deegan4.github.io/Tearoff/privacy.html
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### What's New (version 1.0.1) `[336/4,000]`

Written from the commits actually in 1.0.1 (`0fc4174`, `17c1923`, `7857f5f`,
`ed646e2`) — not invented. Re-check against the real diff if more lands before
you ship.

```
• Pro now unlocks correctly when you buy or restore it outside the app
• Redeem an offer code without leaving Tearoff
• Alerts and export no longer fail silently — if something goes wrong, it says so
• More reliable purchase verification behind the scenes

Thanks for trying Tearoff. If something isn't working, the support link on our site reaches us directly.
```

---

## Screenshot captions

Four existing screenshots in `fastlane/screenshots/en-US-6.5-framed/`. Captions
go in the frame, top-aligned, two lines max.

| File | Headline | Subline |
|---|---|---|
| `01-vault.png` | Every purchase, on a clock | See what closes next, before it closes |
| `02-detail.png` | Know where the date came from | Printed, published policy, or flagged estimate |
| `03-print.png` | A proof slip for the returns desk | Deadline, total, and a scannable barcode |
| `04-add.png` | Scan it, or type it in ten seconds | Nothing saves until you've checked it |

**Add a fifth if you can:** the notification or widget on a Home Screen, captioned
*"A reminder while you can still act on it."* The return-deadline cohort all lead
with the alert — it's the moment that sells the app, and right now it's the one
screen you don't show.

---

## In-App Purchases

Product IDs must match `TearoffProduct` in VaultCore and `Tearoff.storekit`.
Verify before submitting.

| Product | Display Name `[/30]` | Description `[/45]` |
|---|---|---|
| Monthly | `Tearoff Pro — Monthly` | `Scanning, warranties, widgets, and export.` |
| Annual | `Tearoff Pro — Yearly` | `A year of Pro. Best value of the plans.` |
| Lifetime | `Tearoff Pro — Lifetime` | `Pay once. Every Pro feature, permanently.` |

Subscription group: **Tearoff Pro**. Monthly = level 2, Yearly = level 1
(higher level ranks first in the group and controls upgrade/downgrade paths).

Each IAP needs its own review screenshot of the paywall — a build screenshot of
the paywall sheet is sufficient.

---

## App Privacy (nutrition labels)

Answer **"Data Not Collected"** for every category. Justification for the
questionnaire:

- Receipts, images, and purchase records never leave the device except through
  the user's own private CloudKit database, which is not accessible to you as
  the developer — Apple's guidance treats this as not collected.
- The accuracy ledger stores counts only, on-device, and is never transmitted.
- Proximity reminders read location only while the app is open, use it on-device
  to fire a local notification, and neither store nor transmit it — so location
  is still "not collected." Make sure `NSLocationWhenInUseUsageDescription`
  says exactly that; reviewers check the string against the behaviour.
- No third-party SDKs, no ads, no analytics, no tracking. Answer **No** to
  "Used for Tracking."

---

## App Review notes

```
No account or login is required — open the app and everything is reachable.

TO TEST PRO FEATURES
Please use the StoreKit sandbox. Tearoff Pro unlocks unlimited camera scanning,
warranty tracking, retailer returns links, widgets, proximity reminders, and
export. Free functionality
(unlimited manual entry, three receipt scans, return reminders, the full vault)
is available without any purchase.

TO TEST SCANNING
Any paper retail receipt works, and the first three scans need no purchase. If
no receipt is at hand, the manual-entry form (+ button) produces an identical
record, and the return and warranty windows resolve the same way.

ON DEADLINE ACCURACY
Return and warranty dates are derived from (1) terms printed on the scanned
receipt, (2) a curated table of published retailer return policies, or (3) a
category-typical estimate. The source of each date is labelled in the UI, and
estimates are visually flagged. The app does not present an unverified date as
authoritative.

PRIVACY
All processing (Vision OCR, parsing, resolution) is on-device. There is no
server, no analytics, and no third-party SDK. Sync uses the user's own private
CloudKit database.
```

---

## Pre-submission checklist

- [ ] Product IDs in ASC match `TearoffProduct` exactly
- [ ] All three IAPs attached to the version and each has a review screenshot
- [ ] Subscription group display name and localizations filled in
- [ ] 6.9" and 6.5" screenshot sets uploaded (6.5" set already framed)
- [ ] Privacy Policy URL resolves (GitHub Pages live)
- [ ] Age rating questionnaire completed as 4+
- [ ] Encryption export compliance: `ITSAppUsesNonExemptEncryption = false` in Info.plist
