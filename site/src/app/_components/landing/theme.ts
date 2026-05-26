import type { CSSProperties } from "react";

export const BG = "#F5EFE0";
export const CREAM = "#FAF6EC";
export const CORAL = "#EC7868";
export const BLACK = "#0F0E0D";

export const CARD = {
  coral: "#EC7868",
  blue: "#A8D5E8",
  yellow: "#F5D875",
  pink: "#F2B5C4",
  mint: "#B7E4C7",
  purple: "#C8BEE5",
  cream: "#FAF6EC",
  white: "#FFFFFF",
} as const;

export const tagPill: CSSProperties = {
  display: "inline-block",
  background: BLACK,
  color: "#fff",
  fontSize: 11,
  fontWeight: 600,
  letterSpacing: "0.08em",
  padding: "6px 12px",
  borderRadius: 6,
  marginBottom: 24,
};

export type CardColor = keyof typeof CARD;
