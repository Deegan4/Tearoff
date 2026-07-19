# Project Memory — iPrint

Working notes and decisions for the iPrint app. Kept as a durable record so
future sessions can pick up context quickly.

## What iPrint is

An Expo SDK 56 / React Native app that previews, edits, and "prints"
receipts. Single screen (`App.tsx`), no navigation library. Money is stored
in cents throughout; all totals/formatting live in `src/utils/format.ts`.

## Current state

- **Scaffolded** the project from scratch (repo started with only a README):
  Expo config, strict TypeScript, babel/reanimated, entry point.
- **Receipt model + preview** — `src/types.ts`, `src/components/Receipt.tsx`,
  seed data in `src/data.ts`.
- **Editing + persistence** — `src/state/receiptReducer.ts` (add/remove/update,
  values normalized to non-negative integer cents), `src/components/ItemEditor.tsx`,
  and `src/utils/storage.ts` (AsyncStorage; hydrate-then-persist guarded by a
  `hydratedRef` so the seed can't clobber saved data).
- **Real printing** — `src/utils/receiptHtml.ts` builds 80mm-roll HTML (escaped),
  `src/utils/print.ts` opens the OS print dialog via `expo-print` and shares a
  PDF via `expo-sharing` (branches on `Platform.OS` for web).
- **Animated printer** — `src/components/PrinterOverlay.tsx`: a Reanimated
  overlay where the receipt feeds out of a slot at the top of the screen
  (paper translates from `-paperHeight` to `0` behind a clip at the slot line;
  bezel drawn on top), with a stepped `feedEasing` worklet, blinking LED, scan
  bar, and an SVG zigzag torn edge. "Tear off" slides the paper away.

Sole check: `npx tsc --noEmit` (no test/lint/CI configured).

## Running it

- **Web is the only target runnable in a headless/sandbox env** —
  `scripts/run-web.sh` starts Expo web; drive with a headless browser.
- **Expo Go is NOT possible from the sandbox.** The container's egress is
  proxy-only; `expo start --tunnel` fails because the ngrok agent endpoint
  (`connect.ngrok-agent.com`) is blocked at the proxy (TLS handshake failure),
  so no phone can reach a dev server started here. Run `npx expo start` from a
  normal machine (laptop on same Wi-Fi, or `--tunnel`) to use Expo Go.
- **Live web build (shareable, any browser/device):**
  https://claude.ai/code/artifact/55df2116-ba42-4cae-8ab5-1c28d0157a60
  (static export inlined into one HTML; refresh by re-exporting and
  republishing to the same URL).

## Product framing

The credible wedge: **turn a phone into a receipt printer for small/mobile
sellers (markets, food trucks, tradespeople, pop-ups) who don't want a POS
system.** Value = a correct, itemized, printable/shareable receipt in seconds.
Today it's a polished prototype, not yet a sharp solution.

## Open decisions / next steps

- **Native iOS (SwiftUI) vs stay on Expo** — native wins if the priority is
  Bluetooth/MFi thermal (ESC/POS) hardware printing and iOS-only; Expo wins for
  iOS+Android+web reach. Undecided (pending: target platforms + printer type).
- To become a real tool, needs: Bluetooth ESC/POS thermal printing, multiple
  receipts + history, and business identity (logo, tax ID, paid status).
- The printer-feed animation is delight/demo value, not the core problem-solver.

## Repo / branch notes

- Feature work lives on `claude/print-receipt-setup-cmxpqz` (draft PR #1 into
  `main`). This `memory.md` was committed directly to `main` at the user's
  explicit request.
