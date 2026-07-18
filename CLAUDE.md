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

- **Printing/output** is isolated in `src/utils/print.ts`: `printReceipt` opens the native/web print dialog via `Print.printAsync`, and `shareReceiptPdf` renders a PDF with `Print.printToFileAsync` and shares it via `expo-sharing` (falls back to opening the PDF in a new tab on web). `expo-print`/`expo-sharing` behave differently per platform, so branch on `Platform.OS` for web vs. native rather than assuming a single code path.

`src/data.ts` holds a hardcoded `sampleReceipt` used as the app's current data source — there is no persistence or editing yet.

## Conventions

- Buttons use `PressableScale` from `pressto`; icons come from `@expo/vector-icons` (`Ionicons`).
- `babel.config.js` must keep `react-native-worklets/plugin` as the **last** Babel plugin (reanimated requirement).
- Adding native Expo modules: use `npx expo install <pkg>` (not plain `npm install`) so versions match the SDK, and register any required config plugin in `app.json`.
