import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import type { BrandConfig } from "../brand/types";

type Props = {
  brand: BrandConfig;
  name: string;
  title: string;
  durationInFrames: number;
};

export const LowerThird: React.FC<Props> = ({
  brand,
  name,
  title,
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const slideIn = spring({
    fps,
    frame,
    config: { damping: 140, stiffness: 200, mass: 0.8 },
    durationInFrames: 18,
  });

  const holdUntil = durationInFrames - 15;
  const exitProgress = spring({
    fps,
    frame: Math.max(0, frame - holdUntil),
    config: { damping: 140, stiffness: 300, mass: 0.6 },
    durationInFrames: 15,
  });

  const x = interpolate(slideIn, [0, 1], [-420, 0]);
  const exitX = interpolate(exitProgress, [0, 1], [0, -420]);
  const finalX = x + exitX;

  const opacity = interpolate(slideIn, [0, 0.3, 1], [0, 1, 1]);
  const exitOpacity = interpolate(exitProgress, [0, 0.5, 1], [1, 1, 0]);

  return (
    <div
      style={{
        position: "absolute",
        bottom: 120,
        left: 60,
        transform: `translateX(${finalX}px)`,
        opacity: opacity * exitOpacity,
        display: "flex",
        flexDirection: "column",
        gap: 0,
      }}
    >
      {/* accent bar */}
      <div
        style={{
          width: 4,
          height: "100%",
          backgroundColor: brand.accent_color ?? brand.primary_color,
          position: "absolute",
          left: 0,
          top: 0,
          bottom: 0,
          borderRadius: 2,
        }}
      />

      {/* name block */}
      <div
        style={{
          backgroundColor: brand.primary_color,
          paddingLeft: 20,
          paddingRight: 28,
          paddingTop: 10,
          paddingBottom: 4,
          borderRadius: "0 8px 0 0",
        }}
      >
        <span
          style={{
            color: brand.text_color ?? "#FFFFFF",
            fontFamily: brand.font_family ?? "Arial",
            fontWeight: 900,
            fontSize: 36,
            letterSpacing: "-0.01em",
            lineHeight: 1.1,
            textShadow: "none",
          }}
        >
          {name}
        </span>
      </div>

      {/* title block */}
      <div
        style={{
          backgroundColor: brand.accent_color ?? brand.secondary_color,
          paddingLeft: 20,
          paddingRight: 28,
          paddingTop: 4,
          paddingBottom: 10,
          borderRadius: "0 0 8px 0",
        }}
      >
        <span
          style={{
            color: brand.text_color ?? "#FFFFFF",
            fontFamily: brand.font_family ?? "Arial",
            fontWeight: 500,
            fontSize: 22,
            letterSpacing: "0.06em",
            textTransform: "uppercase",
            opacity: 0.92,
          }}
        >
          {title}
        </span>
      </div>
    </div>
  );
};
