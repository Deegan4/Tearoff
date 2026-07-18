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

## Project structure

```
App.tsx                 App shell: header, receipt preview, print button
index.ts                Entry point (registerRootComponent)
src/
  types.ts              Receipt / ReceiptItem models
  data.ts               Sample receipt used for the preview
  utils/format.ts       Money / date formatting and total calculations
  components/Receipt.tsx Receipt layout
```

Amounts are stored in the smallest currency unit (cents) to avoid
floating-point rounding errors and formatted with `Intl.NumberFormat`.

## Printing

Printing is handled by [`expo-print`](https://docs.expo.dev/versions/latest/sdk/print/):

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
