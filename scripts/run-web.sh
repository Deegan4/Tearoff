#!/usr/bin/env bash
#
# Run iPrint from a headless environment via the web (React Native Web)
# target. This is the only runnable target in a container without a device
# or an accelerated Android/iOS emulator.
#
# Usage:
#   scripts/run-web.sh [port]
#
# Then open http://localhost:<port> (default 8081), or drive it with a
# headless browser. Stop with Ctrl-C.

set -euo pipefail

PORT="${1:-8081}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Free the port if a previous run is still listening.
if command -v lsof >/dev/null 2>&1; then
  lsof -ti:"$PORT" -sTCP:LISTEN | xargs -r kill 2>/dev/null || true
fi

echo "Starting Expo web on http://localhost:$PORT ..."
npx expo start --web --port "$PORT" &
SERVER_PID=$!

# Wait for Metro to actually serve before returning.
for _ in $(seq 1 60); do
  if curl -sf "http://localhost:$PORT" >/dev/null 2>&1; then
    echo "Serving at http://localhost:$PORT (pid $SERVER_PID)"
    break
  fi
  sleep 2
done

wait "$SERVER_PID"
