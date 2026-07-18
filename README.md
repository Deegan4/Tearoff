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

## Extending

The `handlePrint` callback in `App.tsx` currently simulates dispatching the
receipt. Replace it with a real integration (for example an ESC/POS
Bluetooth printer module, or `expo-print` for PDF/AirPrint) to print for
real.
