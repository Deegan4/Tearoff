# iPrint

A small [Expo](https://expo.dev/) / React Native app for previewing and
"printing" receipts. It renders a thermal-printer style receipt from
structured data and exposes a print action that you can wire up to a real
printer module.

## Tech stack

- Expo SDK 56 (React Native 0.85, New Architecture)
- TypeScript (strict)
- `react-native-reanimated` / `react-native-worklets`
- `react-native-gesture-handler`
- `pressto` for tactile button interactions
- `@expo/vector-icons`

## Getting started

```bash
# install dependencies
npm install

# start the dev server (press i / a / w for iOS / Android / web)
npm start

# or launch a platform directly
npm run ios
npm run android
npm run web
```

> Native builds (`run:ios` / `run:android`) require the corresponding native
> toolchains. The web target runs anywhere.

### Running in a headless environment (no device/emulator)

In a container or CI box there is no device to run Expo Go and no
accelerated emulator, so the **web** target is the runnable path:

```bash
scripts/run-web.sh            # starts Expo web on :8081 and waits for it to serve
scripts/run-web.sh 19006      # custom port
```

Then drive it with a headless browser (e.g. Playwright/Chromium) against
`http://localhost:8081`. All app logic — editing, persistence
(`AsyncStorage` maps to `localStorage` on web), totals, and the print/PDF
HTML — exercises on web. Printing opens the browser print dialog rather than
a native print sheet.

## Project structure

```
App.tsx                    App shell: edit/preview toggle, print + PDF actions
index.ts                   Entry point (registerRootComponent)
src/
  types.ts                 Receipt / ReceiptItem models
  data.ts                  Default receipt (seed) used on first launch
  state/receiptReducer.ts  Edit operations (add / remove / update item)
  utils/format.ts          Money / date formatting, total + input calculations
  utils/storage.ts         AsyncStorage load/save
  utils/receiptHtml.ts     Printable HTML for expo-print
  utils/print.ts           Print / PDF-share via expo-print + expo-sharing
  components/Receipt.tsx    Receipt preview layout
  components/ItemEditor.tsx Editable item list
```

Amounts are stored in the smallest currency unit (cents) to avoid
floating-point rounding errors and formatted with `Intl.NumberFormat`.

## Editing & persistence

Tap **Edit** to add, remove, or change line items (name, quantity, unit
price); totals recompute live. Edits are dispatched through
`src/state/receiptReducer.ts` and persisted to `AsyncStorage`
(`src/utils/storage.ts`) on every change, so they survive app reloads. The
receipt in `src/data.ts` is only the seed used on first launch.

## Printing

Tapping **Print receipt** plays an animated thermal-printer sequence
(`src/components/PrinterOverlay.tsx`): a printer bezel drops from the top of
the screen and the receipt feeds out of a slot with a mechanical stepped
motion, a blinking status LED, a scan bar, and an SVG zigzag torn edge.
Reanimated drives the feed; the paper is the same `Receipt` component
rendered on white stock. When the feed finishes you can **Tear off** (which
animates the paper away and closes) or send it to a real printer.

Real output is handled by
[`expo-print`](https://docs.expo.dev/versions/latest/sdk/print/):

- **Print receipt** renders the receipt to HTML (`src/utils/receiptHtml.ts`,
  sized for an 80mm thermal roll) and opens the native print sheet via
  `Print.printAsync`. On iOS this is AirPrint; on Android the system print
  dialog; on web the browser print dialog.
- **Save PDF** uses `Print.printToFileAsync` to render the same HTML to a
  PDF, then shares it through `expo-sharing` (or opens it in a new tab on
  web).

Both actions live in `src/utils/print.ts`.

> Note: `expo-print` requires a development build or the platform's native
> print support — it is not available in a bare web-only Expo Go preview of
> native modules, but works on device/simulator and on web.

## Extending

To drive a specific hardware printer directly (for example an ESC/POS
Bluetooth thermal printer), add the relevant module and call it from
`src/utils/print.ts` alongside the `expo-print` path.
