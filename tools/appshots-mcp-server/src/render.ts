/**
 * Pure image-compositing helpers. Given a raw screenshot, produce a marketing
 * image at an exact store canvas size: gradient/solid background, an optional
 * caption band, and the screenshot placed inside a rounded device frame.
 *
 * Uses `sharp` for all raster work and inline SVG for vector layers (gradient,
 * caption text, rounded-corner masks, bezel). No network, no external assets.
 */
import sharp from "sharp";
import { promises as fs } from "fs";
import path from "path";
import { DEFAULT_BEZEL_COLOR } from "./constants.js";

export interface RenderOptions {
  inputPath: string;
  outputPath: string;
  width: number;
  height: number;
  caption?: string;
  captionPosition: "top" | "bottom";
  /** "#RRGGBB" for a solid fill, or "#RRGGBB,#RRGGBB" for a vertical gradient. */
  background: string;
  textColor: string;
  deviceFrame: boolean;
  /** Side padding around the device as a fraction of canvas width (0–0.4). */
  paddingRatio: number;
}

export interface RenderResult {
  outputPath: string;
  width: number;
  height: number;
  bytes: number;
}

const HEX = /^#[0-9a-fA-F]{6}$/;

function escapeXml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

interface Background {
  kind: "solid" | "gradient";
  from: string;
  to: string;
}

/** Parse a background string into a solid colour or a two-stop gradient. */
export function parseBackground(bg: string): Background {
  const parts = bg.split(",").map((p) => p.trim());
  if (parts.length === 2 && HEX.test(parts[0]) && HEX.test(parts[1])) {
    return { kind: "gradient", from: parts[0], to: parts[1] };
  }
  if (parts.length === 1 && HEX.test(parts[0])) {
    return { kind: "solid", from: parts[0], to: parts[0] };
  }
  throw new Error(
    `Invalid background "${bg}". Use "#RRGGBB" for a solid colour or "#RRGGBB,#RRGGBB" for a gradient.`
  );
}

function backgroundSvg(w: number, h: number, bg: Background): string {
  if (bg.kind === "solid") {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="${w}" height="${h}" fill="${bg.from}"/></svg>`;
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">
    <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${bg.from}"/>
      <stop offset="1" stop-color="${bg.to}"/>
    </linearGradient></defs>
    <rect width="${w}" height="${h}" fill="url(#g)"/>
  </svg>`;
}

/** Greedy word-wrap into at most `maxLines` lines of ~`maxChars` chars each. */
export function wrapText(text: string, maxChars: number, maxLines = 3): string[] {
  const words = text.trim().split(/\s+/);
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= maxChars || current === "") {
      current = candidate;
    } else {
      lines.push(current);
      current = word;
      if (lines.length === maxLines - 1) break;
    }
  }
  const used = words.join(" ").split(" ");
  const consumed = lines.join(" ").split(" ").filter(Boolean).length;
  const rest = used.slice(consumed).join(" ");
  if (rest) lines.push(rest);
  else if (current && lines.length < maxLines) lines.push(current);
  return lines.slice(0, maxLines);
}

function captionSvg(
  w: number,
  h: number,
  lines: string[],
  centerY: number,
  fontSize: number,
  color: string
): string {
  const lineHeight = Math.round(fontSize * 1.22);
  const blockHeight = lines.length * lineHeight;
  const firstBaseline = Math.round(centerY - blockHeight / 2 + fontSize);
  const tspans = lines
    .map(
      (line, i) =>
        `<tspan x="${w / 2}" y="${firstBaseline + i * lineHeight}">${escapeXml(line)}</tspan>`
    )
    .join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">
    <text text-anchor="middle" font-family="-apple-system, 'Helvetica Neue', Arial, sans-serif"
      font-size="${fontSize}" font-weight="700" fill="${color}">${tspans}</text>
  </svg>`;
}

function roundedRectSvg(w: number, h: number, r: number, fill: string): Buffer {
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="${w}" height="${h}" rx="${r}" ry="${r}" fill="${fill}"/></svg>`
  );
}

/** Compose one marketing screenshot and write it to disk as PNG. */
export async function render(opts: RenderOptions): Promise<RenderResult> {
  const { width: W, height: H } = opts;
  const bg = parseBackground(opts.background);

  const src = sharp(opts.inputPath);
  const meta = await src.metadata();
  if (!meta.width || !meta.height) {
    throw new Error(`Could not read image dimensions from ${opts.inputPath}`);
  }
  const srcAspect = meta.height / meta.width;

  const pad = Math.round(W * Math.min(Math.max(opts.paddingRatio, 0), 0.4));
  const hasCaption = !!opts.caption?.trim();
  const captionBand = hasCaption ? Math.round(H * 0.17) : Math.round(H * 0.04);
  const topMargin = Math.round(H * 0.04);

  const deviceRegionY = opts.captionPosition === "top" ? captionBand : topMargin;
  const deviceRegionH = H - captionBand - topMargin;

  // Device sizing: start from the padded width, shrink to fit the region.
  let dw = W - 2 * pad;
  let dh = Math.round(dw * srcAspect);
  let bezel = opts.deviceFrame ? Math.max(6, Math.round(dw * 0.018)) : 0;
  let blockH = dh + 2 * bezel;
  if (blockH > deviceRegionH) {
    const scale = deviceRegionH / blockH;
    dw = Math.floor(dw * scale);
    dh = Math.round(dw * srcAspect);
    bezel = opts.deviceFrame ? Math.max(6, Math.round(dw * 0.018)) : 0;
    blockH = dh + 2 * bezel;
  }
  const radius = Math.round(dw * 0.085);

  const blockW = dw + 2 * bezel;
  const bx = Math.round((W - blockW) / 2);
  const by = deviceRegionY + Math.round((deviceRegionH - blockH) / 2);

  // Rounded screenshot: resize then clip corners with a dest-in mask.
  const resized = await src.resize(dw, dh, { fit: "fill" }).png().toBuffer();
  const cornerMask = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${dw}" height="${dh}"><rect width="${dw}" height="${dh}" rx="${radius}" ry="${radius}" fill="#fff"/></svg>`
  );
  const rounded = await sharp(resized)
    .composite([{ input: cornerMask, blend: "dest-in" }])
    .png()
    .toBuffer();

  const layers: sharp.OverlayOptions[] = [];
  if (opts.deviceFrame) {
    const bezelLayer = roundedRectSvg(blockW, blockH, radius + bezel, DEFAULT_BEZEL_COLOR);
    layers.push({ input: bezelLayer, top: by, left: bx });
  }
  layers.push({ input: rounded, top: by + bezel, left: bx + bezel });

  if (hasCaption) {
    const fontSize = Math.round(W * 0.058);
    const maxTextWidth = W - 2 * Math.round(W * 0.09);
    const maxChars = Math.max(8, Math.floor(maxTextWidth / (fontSize * 0.54)));
    const lines = wrapText(opts.caption!, maxChars);
    const centerY =
      opts.captionPosition === "top"
        ? Math.round(captionBand / 2)
        : H - Math.round(captionBand / 2);
    const svg = captionSvg(W, H, lines, centerY, fontSize, opts.textColor);
    layers.push({ input: Buffer.from(svg), top: 0, left: 0 });
  }

  const base = sharp(Buffer.from(backgroundSvg(W, H, bg))).png();
  const out = await base.composite(layers).png().toBuffer();

  await fs.mkdir(path.dirname(opts.outputPath), { recursive: true });
  await fs.writeFile(opts.outputPath, out);

  return { outputPath: opts.outputPath, width: W, height: H, bytes: out.length };
}
