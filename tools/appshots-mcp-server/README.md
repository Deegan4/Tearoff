# appshots-mcp-server

A local [MCP](https://modelcontextprotocol.io) server that turns raw app
screenshots into **App Store / Play Store–ready marketing images** — device
frames, captions, and gradient backgrounds rendered at exact store canvas
sizes.

It does locally what [appscreens.com](https://appscreens.com) does in the
browser. AppScreens has no public API ([their own KB confirms
it](https://help.appscreens.com/api/do-you-have-an-api)), so this server calls
nothing external — all compositing is done on-device with
[`sharp`](https://sharp.pixelplumbing.com/).

## Tools

| Tool | What it does |
|------|--------------|
| `appshots_list_presets` | List built-in store canvas presets (exact pixel sizes). |
| `appshots_frame_screenshot` | Frame one screenshot → a marketing PNG. |
| `appshots_frame_batch` | Frame up to 30 screenshots with one shared style. |

### Presets

`iphone-6.9` (1290×2796), `iphone-6.9-max` (1320×2868), `iphone-6.5`
(1284×2778), `iphone-6.1` (1179×2556), `ipad-13` (2064×2752), `ipad-12.9`
(2048×2732). Or pass explicit `width`+`height`.

### Style options (both framing tools)

- `caption` — marketing text, wraps to ≤3 lines
- `caption_position` — `top` (default) or `bottom`
- `background` — `#RRGGBB` (solid) or `#RRGGBB,#RRGGBB` (vertical gradient)
- `text_color` — `#RRGGBB` (default white)
- `device_frame` — rounded bezel on/off (default on)
- `padding_ratio` — side padding as a fraction of width (default `0.12`)

## Build

```bash
cd tools/appshots-mcp-server
npm install
npm run build
```

## Register with Claude Code

```bash
claude mcp add appshots -- node "/Volumes/SAMSUNG 1TB/Tearoff/tools/appshots-mcp-server/dist/index.js"
```

Or add it to your MCP client config manually:

```json
{
  "mcpServers": {
    "appshots": {
      "command": "node",
      "args": ["/Volumes/SAMSUNG 1TB/Tearoff/tools/appshots-mcp-server/dist/index.js"]
    }
  }
}
```

## Example

> "Frame `~/shots/vault.png` at the `iphone-6.5` preset with the caption
> *Never miss a return window* on a `#4F46E5,#7C3AED` gradient, and write it to
> `~/shots/out/01.png`."

→ a 1284×2778 PNG: gradient background, bold caption, the screenshot inside a
rounded device frame — ready to drag into App Store Connect.

## Notes

- Output is always PNG at the exact requested canvas size (App Store requires
  exact dimensions).
- The device frame is a clean rounded bezel drawn in-code, not a photoreal
  device mock — no large frame assets to ship, and it reads well on the store.
- Fonts come from the host system (via fontconfig); on macOS the default
  sans-serif renders as San Francisco/Helvetica.
