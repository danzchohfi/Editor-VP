import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import type { BrandConfig } from "../brand/types";

type Props = {
  brand: BrandConfig;
  keyword: string;
  context?: string;
  durationInFrames: number;
  side?: "left" | "right";
};

export const KeywordBubble: React.FC<Props> = ({
  brand,
  keyword,
  context,
  durationInFrames,
  side = "right",
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const popIn = spring({
    fps,
    frame,
    config: { damping: 120, stiffness: 400, mass: 0.5 },
    durationInFrames: 12,
  });

  const holdUntil = durationInFrames - 10;
  const popOut = spring({
    fps,
    frame: Math.max(0, frame - holdUntil),
    config: { damping: 200, stiffness: 500, mass: 0.4 },
    durationInFrames: 10,
  });

  const scale = interpolate(popIn, [0, 1], [0.4, 1]);
  const exitScale = interpolate(popOut, [0, 1], [1, 0.3]);
  const opacity = interpolate(popIn, [0, 0.4, 1], [0, 1, 1]);
  const exitOpacity = interpolate(popOut, [0, 0.5, 1], [1, 0.5, 0]);

  return (
    <div
      style={{
        position: "absolute",
        top: "30%",
        [side === "right" ? "right" : "left"]: 60,
        transform: `scale(${scale * exitScale})`,
        opacity: opacity * exitOpacity,
        transformOrigin: side === "right" ? "right center" : "left center",
        display: "flex",
        flexDirection: "column",
        alignItems: side === "right" ? "flex-end" : "flex-start",
        gap: 6,
        zIndex: 20,
      }}
    >
      {/* keyword pill */}
      <div
        style={{
          backgroundColor: brand.accent_color ?? brand.primary_color,
          borderRadius: 50,
          paddingLeft: 28,
          paddingRight: 28,
          paddingTop: 12,
          paddingBottom: 12,
          boxShadow: `0 8px 32px rgba(0,0,0,0.4), 0 0 0 3px ${brand.primary_color}`,
        }}
      >
        <span
          style={{
            color: "#000",
            fontFamily: brand.font_family ?? "Arial",
            fontWeight: 900,
            fontSize: 40,
            letterSpacing: "-0.02em",
            textTransform: "uppercase",
          }}
        >
          {keyword}
        </span>
      </div>

      {/* context tag */}
      {context && (
        <div
          style={{
            backgroundColor: brand.primary_color,
            borderRadius: 50,
            paddingLeft: 18,
            paddingRight: 18,
            paddingTop: 6,
            paddingBottom: 6,
            opacity: 0.9,
          }}
        >
          <span
            style={{
              color: brand.text_color ?? "#fff",
              fontFamily: brand.font_family ?? "Arial",
              fontWeight: 600,
              fontSize: 22,
              letterSpacing: "0.04em",
            }}
          >
            {context}
          </span>
        </div>
      )}
    </div>
  );
};
