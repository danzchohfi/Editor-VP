import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import type { BrandConfig } from "../brand/types";

type Props = {
  brand: BrandConfig;
  quote: string;
  author?: string;
  durationInFrames: number;
};

export const QuoteCard: React.FC<Props> = ({
  brand,
  quote,
  author,
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fadeIn = spring({
    fps,
    frame,
    config: { damping: 200, stiffness: 80, mass: 1.2 },
    durationInFrames: 20,
  });

  const holdUntil = durationInFrames - 18;
  const fadeOut = spring({
    fps,
    frame: Math.max(0, frame - holdUntil),
    config: { damping: 200, stiffness: 80, mass: 1.2 },
    durationInFrames: 18,
  });

  const bgOpacity = interpolate(fadeIn, [0, 1], [0, 0.88]);
  const exitBgOpacity = interpolate(fadeOut, [0, 1], [0.88, 0]);

  const textY = interpolate(fadeIn, [0, 1], [30, 0]);
  const textOpacity = interpolate(fadeIn, [0, 0.5, 1], [0, 0.7, 1]);
  const exitTextOpacity = interpolate(fadeOut, [0, 0.5, 1], [1, 0.5, 0]);

  const wordScale = spring({
    fps,
    frame: Math.max(0, frame - 5),
    config: { damping: 200, stiffness: 120, mass: 1 },
    durationInFrames: 25,
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: `rgba(${_hexToRgb(brand.secondary_color ?? brand.primary_color)}, ${bgOpacity - exitBgOpacity})`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexDirection: "column",
        padding: "80px 120px",
        zIndex: 30,
      }}
    >
      {/* accent line top */}
      <div
        style={{
          width: interpolate(wordScale, [0, 1], [0, 120]),
          height: 5,
          backgroundColor: brand.accent_color ?? brand.primary_color,
          borderRadius: 3,
          marginBottom: 40,
          opacity: textOpacity * exitTextOpacity,
        }}
      />

      {/* quote mark */}
      <div
        style={{
          color: brand.accent_color ?? brand.primary_color,
          fontFamily: "Georgia, serif",
          fontSize: 160,
          lineHeight: 0.6,
          marginBottom: 20,
          opacity: (textOpacity * exitTextOpacity) * 0.4,
          transform: `translateY(${textY}px)`,
          alignSelf: "flex-start",
        }}
      >
        "
      </div>

      {/* quote text */}
      <p
        style={{
          color: brand.text_color ?? "#FFFFFF",
          fontFamily: brand.font_family ?? "Arial",
          fontWeight: 700,
          fontSize: _quoteFontSize(quote),
          lineHeight: 1.35,
          textAlign: "center",
          margin: 0,
          transform: `translateY(${textY}px)`,
          opacity: textOpacity * exitTextOpacity,
          textShadow: "0 2px 12px rgba(0,0,0,0.6)",
          maxWidth: "80%",
        }}
      >
        {quote}
      </p>

      {/* author */}
      {author && (
        <p
          style={{
            color: brand.accent_color ?? brand.primary_color,
            fontFamily: brand.font_family ?? "Arial",
            fontWeight: 600,
            fontSize: 26,
            marginTop: 32,
            letterSpacing: "0.1em",
            textTransform: "uppercase",
            opacity: (textOpacity * exitTextOpacity) * 0.9,
            transform: `translateY(${textY * 0.5}px)`,
          }}
        >
          — {author}
        </p>
      )}

      {/* accent line bottom */}
      <div
        style={{
          width: interpolate(wordScale, [0, 1], [0, 80]),
          height: 3,
          backgroundColor: brand.accent_color ?? brand.primary_color,
          borderRadius: 3,
          marginTop: 40,
          opacity: (textOpacity * exitTextOpacity) * 0.6,
        }}
      />
    </AbsoluteFill>
  );
};

function _quoteFontSize(text: string): number {
  if (text.length < 60) return 58;
  if (text.length < 120) return 48;
  if (text.length < 200) return 40;
  return 34;
}

function _hexToRgb(hex: string): string {
  const clean = hex.replace("#", "");
  const r = parseInt(clean.slice(0, 2), 16);
  const g = parseInt(clean.slice(2, 4), 16);
  const b = parseInt(clean.slice(4, 6), 16);
  return `${r},${g},${b}`;
}
