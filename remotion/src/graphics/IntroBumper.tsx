import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import type { BrandConfig } from "../brand/types";

type Props = {
  brand: BrandConfig;
  durationInFrames: number;
};

export const IntroBumper: React.FC<Props> = ({ brand, durationInFrames }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();

  // Background tiles animate in
  const bgScale = spring({
    fps,
    frame,
    config: { damping: 200, stiffness: 60, mass: 1.5 },
    durationInFrames: 30,
  });

  // Logo + text appear
  const logoReveal = spring({
    fps,
    frame: Math.max(0, frame - 8),
    config: { damping: 160, stiffness: 180, mass: 0.8 },
    durationInFrames: 20,
  });

  // Tagline comes after
  const taglineReveal = spring({
    fps,
    frame: Math.max(0, frame - 18),
    config: { damping: 160, stiffness: 120, mass: 1 },
    durationInFrames: 18,
  });

  // Exit
  const holdUntil = durationInFrames - 12;
  const exitFade = spring({
    fps,
    frame: Math.max(0, frame - holdUntil),
    config: { damping: 200, stiffness: 120, mass: 1 },
    durationInFrames: 12,
  });

  const opacity = 1 - interpolate(exitFade, [0, 1], [0, 1]);

  return (
    <AbsoluteFill style={{ opacity, zIndex: 50 }}>
      {/* Background */}
      <AbsoluteFill
        style={{
          background: `linear-gradient(135deg, ${brand.primary_color} 0%, ${brand.secondary_color ?? "#000"} 100%)`,
        }}
      />

      {/* Animated grid pattern overlay */}
      <AbsoluteFill
        style={{
          backgroundImage: `radial-gradient(circle, ${brand.accent_color ?? "#fff"}15 1px, transparent 1px)`,
          backgroundSize: "60px 60px",
          transform: `scale(${interpolate(bgScale, [0, 1], [1.2, 1])})`,
          opacity: 0.4,
        }}
      />

      {/* Center content */}
      <AbsoluteFill
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          gap: 24,
        }}
      >
        {/* Logo or company name */}
        <div
          style={{
            transform: `scale(${interpolate(logoReveal, [0, 1], [0.7, 1])}) translateY(${interpolate(logoReveal, [0, 1], [30, 0])}px)`,
            opacity: interpolate(logoReveal, [0, 0.5, 1], [0, 0.8, 1]),
          }}
        >
          {brand.logo_path ? (
            <Img
              src={brand.logo_path}
              style={{
                width: 200,
                height: 200,
                objectFit: "contain",
                filter: "drop-shadow(0 4px 24px rgba(0,0,0,0.5))",
              }}
            />
          ) : (
            <span
              style={{
                color: brand.text_color ?? "#FFFFFF",
                fontFamily: brand.font_family ?? "Arial",
                fontWeight: 900,
                fontSize: 72,
                letterSpacing: "-0.02em",
                textShadow: "0 4px 24px rgba(0,0,0,0.4)",
              }}
            >
              {brand.company}
            </span>
          )}
        </div>

        {/* Accent divider line */}
        <div
          style={{
            width: interpolate(logoReveal, [0, 1], [0, 200]),
            height: 4,
            backgroundColor: brand.accent_color ?? "#fff",
            borderRadius: 2,
            opacity: interpolate(logoReveal, [0.5, 1], [0, 1]),
          }}
        />

        {/* Tagline */}
        {brand.tagline && (
          <span
            style={{
              color: brand.text_color ?? "#FFFFFF",
              fontFamily: brand.font_family ?? "Arial",
              fontWeight: 400,
              fontSize: 28,
              letterSpacing: "0.15em",
              textTransform: "uppercase",
              opacity: interpolate(taglineReveal, [0, 1], [0, 0.85]),
              transform: `translateY(${interpolate(taglineReveal, [0, 1], [15, 0])}px)`,
            }}
          >
            {brand.tagline}
          </span>
        )}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
