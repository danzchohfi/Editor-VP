import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import type { BrandConfig } from "../brand/types";

type Props = {
  brand: BrandConfig;
  title: string;
  durationInFrames: number;
};

export const TopicTitle: React.FC<Props> = ({
  brand,
  title,
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const slideDown = spring({
    fps,
    frame,
    config: { damping: 160, stiffness: 250, mass: 0.7 },
    durationInFrames: 15,
  });

  const holdUntil = durationInFrames - 12;
  const slideUp = spring({
    fps,
    frame: Math.max(0, frame - holdUntil),
    config: { damping: 160, stiffness: 350, mass: 0.6 },
    durationInFrames: 12,
  });

  const y = interpolate(slideDown, [0, 1], [-80, 0]);
  const exitY = interpolate(slideUp, [0, 1], [0, -80]);
  const opacity = interpolate(slideDown, [0, 0.4, 1], [0, 1, 1]);
  const exitOpacity = interpolate(slideUp, [0, 0.5, 1], [1, 0.6, 0]);

  return (
    <div
      style={{
        position: "absolute",
        top: 40,
        left: "50%",
        transform: `translateX(-50%) translateY(${y + exitY}px)`,
        opacity: opacity * exitOpacity,
        display: "flex",
        alignItems: "center",
        gap: 16,
        zIndex: 15,
      }}
    >
      {/* left accent */}
      <div
        style={{
          width: 5,
          height: 40,
          backgroundColor: brand.accent_color ?? brand.primary_color,
          borderRadius: 3,
        }}
      />

      <div
        style={{
          backgroundColor: `${brand.primary_color}E8`,
          backdropFilter: "blur(8px)",
          borderRadius: 8,
          paddingLeft: 24,
          paddingRight: 24,
          paddingTop: 10,
          paddingBottom: 10,
        }}
      >
        <span
          style={{
            color: brand.text_color ?? "#FFFFFF",
            fontFamily: brand.font_family ?? "Arial",
            fontWeight: 800,
            fontSize: 30,
            letterSpacing: "0.08em",
            textTransform: "uppercase",
          }}
        >
          {title}
        </span>
      </div>

      {/* right accent */}
      <div
        style={{
          width: 5,
          height: 40,
          backgroundColor: brand.accent_color ?? brand.primary_color,
          borderRadius: 3,
        }}
      />
    </div>
  );
};
