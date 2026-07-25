#!/usr/bin/env node
/**
 * appshots-mcp-server
 *
 * A local MCP server that turns raw app screenshots into App Store / Play Store
 * marketing images: device frames, captions, and gradient backgrounds rendered
 * at exact store canvas sizes. Everything runs locally with `sharp` — there is
 * no external API (AppScreens, the tool that inspired this, does not offer one).
 *
 * Transport: stdio (local integration).
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { promises as fs } from "fs";
import {
  PRESETS,
  PRESET_MAP,
  DEFAULT_BACKGROUND,
  DEFAULT_TEXT_COLOR,
} from "./constants.js";
import { render, RenderResult } from "./render.js";

const server = new McpServer({ name: "appshots-mcp-server", version: "1.0.0" });

/** Resolve the target canvas from a preset name or an explicit width/height. */
function resolveCanvas(
  preset: string | undefined,
  width: number | undefined,
  height: number | undefined
): { width: number; height: number } {
  if (preset) {
    const p = PRESET_MAP[preset];
    if (!p) {
      throw new Error(
        `Unknown preset "${preset}". Call appshots_list_presets for valid names, or pass width+height instead.`
      );
    }
    return { width: p.width, height: p.height };
  }
  if (width && height) return { width, height };
  throw new Error(
    "Provide either `preset` (see appshots_list_presets) or both `width` and `height`."
  );
}

async function assertReadable(path: string): Promise<void> {
  try {
    await fs.access(path);
  } catch {
    throw new Error(`Input image not found or unreadable: ${path}`);
  }
}

// Shared style fields reused by both the single and batch tools.
const styleFields = {
  preset: z
    .string()
    .optional()
    .describe("Canvas preset name (e.g. 'iphone-6.9'). See appshots_list_presets. Omit to use width+height."),
  width: z.number().int().min(1).max(10000).optional().describe("Custom canvas width in px (with height, instead of preset)."),
  height: z.number().int().min(1).max(10000).optional().describe("Custom canvas height in px (with width, instead of preset)."),
  caption_position: z.enum(["top", "bottom"]).default("top").describe("Where the caption band sits."),
  background: z
    .string()
    .default(DEFAULT_BACKGROUND)
    .describe("'#RRGGBB' for a solid colour, or '#RRGGBB,#RRGGBB' for a vertical gradient."),
  text_color: z.string().default(DEFAULT_TEXT_COLOR).describe("Caption colour as '#RRGGBB'."),
  device_frame: z.boolean().default(true).describe("Wrap the screenshot in a rounded device bezel."),
  padding_ratio: z.number().min(0).max(0.4).default(0.12).describe("Side padding around the device as a fraction of canvas width."),
};

// ---- appshots_list_presets -------------------------------------------------
server.registerTool(
  "appshots_list_presets",
  {
    title: "List store screenshot presets",
    description: `List the built-in App Store / Play Store canvas presets (exact pixel sizes).

Returns JSON: { "presets": [ { "name": string, "width": number, "height": number, "label": string } ] }

Use a preset's "name" as the \`preset\` argument to appshots_frame_screenshot / appshots_frame_batch. If none fits, pass explicit width+height to those tools instead.`,
    inputSchema: {},
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async () => {
    const output = { presets: PRESETS };
    return {
      content: [{ type: "text", text: JSON.stringify(output, null, 2) }],
      structuredContent: output,
    };
  }
);

// ---- appshots_frame_screenshot ---------------------------------------------
const FrameInput = z
  .object({
    input_path: z.string().min(1).describe("Absolute path to the raw screenshot (PNG/JPEG)."),
    output_path: z.string().min(1).describe("Absolute path to write the framed PNG to. Parent dirs are created."),
    caption: z.string().max(200).optional().describe("Optional marketing caption drawn in the caption band (wraps to ≤3 lines)."),
    ...styleFields,
  })
  .strict();

type FrameInputT = z.infer<typeof FrameInput>;

function summarize(r: RenderResult): string {
  return `Wrote ${r.width}×${r.height} PNG (${Math.round(r.bytes / 1024)} KB) → ${r.outputPath}`;
}

server.registerTool(
  "appshots_frame_screenshot",
  {
    title: "Frame one screenshot",
    description: `Turn a single raw screenshot into an App Store-ready marketing image: gradient/solid background, optional caption, and a rounded device frame, rendered at an exact store canvas size.

Args:
  - input_path (string): absolute path to the raw screenshot
  - output_path (string): absolute path for the framed PNG (parent dirs created)
  - preset (string, optional): canvas preset name — OR pass width+height
  - width, height (number, optional): custom canvas size in px
  - caption (string, optional): marketing text, wraps to ≤3 lines
  - caption_position ('top'|'bottom', default 'top')
  - background (string, default gradient): '#RRGGBB' or '#RRGGBB,#RRGGBB'
  - text_color (string, default '#FFFFFF')
  - device_frame (boolean, default true)
  - padding_ratio (number 0–0.4, default 0.12)

Returns JSON: { "output_path": string, "width": number, "height": number, "bytes": number }

Errors: unreadable input, unknown preset, missing size (no preset and no width+height), or a malformed background/colour string — each with a message describing the fix.`,
    inputSchema: FrameInput.shape,
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async (params: FrameInputT) => {
    try {
      const canvas = resolveCanvas(params.preset, params.width, params.height);
      await assertReadable(params.input_path);
      const result = await render({
        inputPath: params.input_path,
        outputPath: params.output_path,
        width: canvas.width,
        height: canvas.height,
        caption: params.caption,
        captionPosition: params.caption_position,
        background: params.background,
        textColor: params.text_color,
        deviceFrame: params.device_frame,
        paddingRatio: params.padding_ratio,
      });
      return {
        content: [{ type: "text", text: summarize(result) }],
        structuredContent: result as unknown as Record<string, unknown>,
      };
    } catch (error) {
      return {
        content: [{ type: "text", text: `Error: ${error instanceof Error ? error.message : String(error)}` }],
        isError: true,
      };
    }
  }
);

// ---- appshots_frame_batch --------------------------------------------------
const BatchInput = z
  .object({
    items: z
      .array(
        z.object({
          input_path: z.string().min(1).describe("Absolute path to a raw screenshot."),
          output_path: z.string().min(1).describe("Absolute path for this item's framed PNG."),
          caption: z.string().max(200).optional().describe("Per-item caption (overrides none; optional)."),
        })
      )
      .min(1)
      .max(30)
      .describe("Screenshots to frame; each gets the shared style below."),
    ...styleFields,
  })
  .strict();

type BatchInputT = z.infer<typeof BatchInput>;

server.registerTool(
  "appshots_frame_batch",
  {
    title: "Frame a set of screenshots",
    description: `Frame many screenshots with one shared style (same preset, background, and options). Each item may carry its own caption. Ideal for producing a full App Store screenshot set in one call.

Args:
  - items (array, 1–30): { input_path, output_path, caption? }
  - preset OR width+height, plus the same style fields as appshots_frame_screenshot

Returns JSON: { "count": number, "results": [ { "output_path", "width", "height", "bytes" } ], "errors": [ { "input_path", "error" } ] }

Processing continues past a failing item; failures are collected in "errors" so one bad file never aborts the batch.`,
    inputSchema: BatchInput.shape,
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async (params: BatchInputT) => {
    const canvas = (() => {
      try {
        return resolveCanvas(params.preset, params.width, params.height);
      } catch (e) {
        return e instanceof Error ? e.message : String(e);
      }
    })();
    if (typeof canvas === "string") {
      return { content: [{ type: "text", text: `Error: ${canvas}` }], isError: true };
    }

    const results: RenderResult[] = [];
    const errors: { input_path: string; error: string }[] = [];
    for (const item of params.items) {
      try {
        await assertReadable(item.input_path);
        const r = await render({
          inputPath: item.input_path,
          outputPath: item.output_path,
          width: canvas.width,
          height: canvas.height,
          caption: item.caption,
          captionPosition: params.caption_position,
          background: params.background,
          textColor: params.text_color,
          deviceFrame: params.device_frame,
          paddingRatio: params.padding_ratio,
        });
        results.push(r);
      } catch (error) {
        errors.push({ input_path: item.input_path, error: error instanceof Error ? error.message : String(error) });
      }
    }

    const output = { count: results.length, results, errors };
    const lines = [
      `Framed ${results.length}/${params.items.length} screenshot(s) at ${canvas.width}×${canvas.height}.`,
      ...results.map((r) => `  ✓ ${r.outputPath}`),
      ...errors.map((e) => `  ✗ ${e.input_path} — ${e.error}`),
    ];
    return {
      content: [{ type: "text", text: lines.join("\n") }],
      structuredContent: output,
      ...(errors.length && !results.length ? { isError: true } : {}),
    };
  }
);

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("appshots-mcp-server running on stdio");
}

main().catch((error) => {
  console.error("Fatal:", error);
  process.exit(1);
});
