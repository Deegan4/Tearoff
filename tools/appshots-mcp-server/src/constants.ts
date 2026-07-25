/**
 * App Store / Play Store screenshot canvas presets (portrait, in pixels).
 * Names are stable identifiers used by the `preset` tool parameter.
 * Values are the exact pixel dimensions the stores accept for that device class.
 */
export interface Preset {
  name: string;
  width: number;
  height: number;
  label: string;
}

export const PRESETS: Preset[] = [
  { name: "iphone-6.9", width: 1290, height: 2796, label: "iPhone 6.9\" (16/17 Pro Max)" },
  { name: "iphone-6.9-max", width: 1320, height: 2868, label: "iPhone 6.9\" alt (1320×2868)" },
  { name: "iphone-6.5", width: 1284, height: 2778, label: "iPhone 6.5\" (11 Pro Max / XS Max)" },
  { name: "iphone-6.1", width: 1179, height: 2556, label: "iPhone 6.1\" (15/16)" },
  { name: "ipad-13", width: 2064, height: 2752, label: "iPad 13\" (M4)" },
  { name: "ipad-12.9", width: 2048, height: 2732, label: "iPad 12.9\"" },
];

export const PRESET_MAP: Record<string, Preset> = Object.fromEntries(
  PRESETS.map((p) => [p.name, p])
);

/** Default marketing background: a calm vertical gradient. */
export const DEFAULT_BACKGROUND = "#4F46E5,#7C3AED";
export const DEFAULT_TEXT_COLOR = "#FFFFFF";
export const DEFAULT_BEZEL_COLOR = "#0B0B0F";
