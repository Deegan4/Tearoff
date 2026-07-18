# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm install          # install dependencies (use `npx expo install <pkg>` to add SDK-compatible native modules)
npm start            # start the Metro dev server (press i / a / w for iOS / Android / web)
npm run ios          # native iOS build + run (requires Xcode toolchain)
npm run android      # native Android build + run (requires Android toolchain)
npm run web          # run in the browser
npx tsc --noEmit     # typecheck — this is the only check in the repo; run it before committing
```

There is no test runner, linter, or CI configured. `npx tsc --noEmit` is the sole gate.

## Architecture

iPrint is an Expo SDK 56 / React Native app (New Architecture enabled) that previews and prints receipts. The entry point is `index.ts` → `App.tsx`; there is no navigation library — `App.tsx` is the single screen.

The design separates **domain data**, **rendering**, and **output**:

- **Money is stored in the smallest currency unit (cents)** everywhere in `Receipt`/`ReceiptItem` (`src/types.ts`). Never store fractional currency as floats. All arithmetic (subtotal → tax → total) and display formatting lives in `src/utils/format.ts` and consumes cents; `formatMoney` converts to display strings via `Intl.NumberFormat`. Any new totals logic belongs here so the on-screen and printed receipts stay consistent.

- **The receipt is rendered twice from the same model**, and both must be kept in sync:
  - `src/components/Receipt.tsx` — the on-screen React Native preview.
  - `src/utils/receiptHtml.ts` — a printable HTML document (sized for an 80mm thermal roll) fed to `expo-print`. This path builds raw HTML strings, so all interpolated text goes through the `escapeHtml` helper.

- **The print animation** (`src/components/PrinterOverlay.tsx`) is a Reanimated overlay that feeds the receipt out of a printer slot. The illusion is structural: a `feedWindow` clips at the slot line while the paper translates from `-paperHeight` to `0`, so it appears to emerge from the slot; the bezel is drawn on top. Paper height is measured via `onLayout` and mirrored into a shared value (`paperH`) because the translate range depends on it — the feed effect only starts once `paperHeight > 0`. The mechanical stepping comes from a custom `feedEasing` worklet (floor-quantized `t`); the torn edge is an SVG `Polygon` (react-native-svg). "Tear off" drives the same `feed`/`tear` shared values to slide the paper away before `onClose`.

- **Printing/output** is isolated in `src/utils/print.ts`: `printReceipt` opens the native/web print dialog via `Print.printAsync`, and `shareReceiptPdf` renders a PDF with `Print.printToFileAsync` and shares it via `expo-sharing` (falls back to opening the PDF in a new tab on web). `expo-print`/`expo-sharing` behave differently per platform, so branch on `Platform.OS` for web vs. native rather than assuming a single code path.

- **State & persistence**: the receipt lives in a `useReducer` in `App.tsx`. All mutations go through `src/state/receiptReducer.ts` (add/remove/update item), which normalizes input — quantity and `unitPrice` are coerced to non-negative integers (cents). `src/data.ts` is only the **seed** used on first launch; `src/utils/storage.ts` loads/saves the receipt to `AsyncStorage`. Persistence is gated on a `hydratedRef` so the default seed is not written over stored data before the initial async load completes — preserve that guard when touching the load/save effects. The `ItemEditor` lets users type prices in major units (dollars); `inputToCents`/`centsToInput` in `format.ts` bridge to the cents representation.

## Conventions

- Buttons use `PressableScale` from `pressto`; icons come from `@expo/vector-icons` (`Ionicons`).
- `babel.config.js` must keep `react-native-worklets/plugin` as the **last** Babel plugin (reanimated requirement).
- Adding native Expo modules: use `npx expo install <pkg>` (not plain `npm install`) so versions match the SDK, and register any required config plugin in `app.json`.
