# iPrint

Scan a paper receipt and iPrint logs the purchase, then tracks when you can
still **return** it and how long its **warranty** lasts — surfacing each
window with a clear, honest note about where the date came from.

> iOS 26+ · SwiftUI · SwiftData · on-device Vision OCR

## How it works

```
Camera → Vision OCR → ReceiptParser → Confirm form → SwiftData
                                                         ↓
                          VaultCore resolves return/warranty windows
                                                         ↓
                     Local notifications + animated receipt "print"
```

1. **Scan.** The camera captures a receipt; `ReceiptOCR` runs on-device text
   recognition (Vision, `VNRecognizeText`) and returns the lines top-to-bottom.
2. **Parse.** `ReceiptParser` lifts merchant, date, and total, and makes a
   conservative guess at the **category** and any **printed return/warranty
   terms** ("return within 30 days", "1 year warranty"). It never invents a
   value it cannot find.
3. **Confirm.** The scan opens an editable form pre-filled with those fields —
   the user corrects anything before saving. Nothing is committed silently.
4. **Resolve.** `VaultCore` computes the return and warranty windows and labels
   each with its **provenance** (below).
5. **Remind.** Windows schedule local notifications; the saved slip prints with
   a thermal-printer animation.

## Provenance ladder

Every window shows where its date came from. Sources are tried in priority
order — the app **never confabulates a duration**:

| Priority | Source | Shown as |
|----------|--------|----------|
| 1 | **User** — you entered or corrected it | "you set this" |
| 2 | **Printed** — read off the receipt | "printed on your receipt" |
| 3 | **Table** — curated retailer policy | "published return policy" |
| 4 | **Category default** — typical for the category | "estimate" (flagged) |

## Architecture

- **`App/`** — the iOS app: SwiftUI views, SwiftData model (`StoredPurchase`),
  Vision OCR, the receipt parser, and notification scheduling. Depends on
  `VaultCore`.
- **`Packages/VaultCore/`** — a pure Swift package with all the window logic:
  `PolicyResolver`, `WarrantyResolver`, the retailer `PolicyTable`, `Money`,
  and `PurchaseCategory`. No UIKit/SwiftUI — fully unit-tested in isolation.

Keeping the resolution logic in a UI-free package is deliberate: it is the
part most worth testing and least allowed to guess.

## Build & run

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so it is not committed —
generate it first:

```bash
brew install xcodegen   # once
xcodegen generate
open iPrint.xcodeproj
```

Or from the command line (Debug, simulator):

```bash
xcodebuild -project iPrint.xcodeproj -scheme iPrint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Tests

```bash
xcodebuild -project iPrint.xcodeproj -scheme iPrint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- **`AppTests/`** — `ReceiptParser` extraction and inference.
- **`Packages/VaultCore/Tests/`** — resolvers, policy table, money, categories.
  Run in isolation with `swift test` from `Packages/VaultCore`.

## Permissions

- **Camera** (`NSCameraUsageDescription`) — to scan receipts.
- **Notifications** — requested at launch, to remind you before a window closes.
