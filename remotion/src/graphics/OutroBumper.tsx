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

export const OutroBumper: React.FC<Props> = ({ brand, durationInFrames }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const reveal = spring({
    fps,
    frame,
    config: { damping: 180, stiffness: 100, mass: 1 },
    durationInFrames: 25,
  });

  const socialReveal = spring({
    fps,
    frame: Math.max(0, frame - 15),
    config: { damping: 160, stiffness: 120, mass: 0.9 },
    durationInFrames: 20,
  });

  const ctaReveal = spring({
    fps,
    frame: Math.max(0, frame - 25),
    config: { damping: 160, stiffness: 100, mass: 1 },
    durationInFrames: 18,
  });

  const { social } = brand;

  return (
    <AbsoluteFill style={{ zIndex: 50 }}>
      {/* Background */}
      <AbsoluteFill
        style={{
          background: `linear-gradient(160deg, ${brand.secondary_color ?? "#000"} 0%, ${brand.primary_color} 100%)`,
        }}
      />

      {/* Dot pattern */}
      <AbsoluteFill
        style={{
          backgroundImage: `radial-gradient(circle, ${brand.accent_color ?? "#fff"}20 1.5px, transparent 1.5px)`,
          backgroundSize: "48px 48px",
          opacity: 0.35,
        }}
      />

      <AbsoluteFill
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 32,
          padding: "60px 120px",
        }}
      >
        {/* Logo */}
        <div
          style={{
            opacity: interpolate(reveal, [0, 1], [0, 1]),
            transform: `scale(${interpolate(reveal, [0, 1], [0.85, 1])})`,
          }}
        >
          {brand.logo_path ? (
            <Img
              src={brand.logo_path}
              style={{
                width: 140,
                height: 140,
                objectFit: "contain",
                filter: "drop-shadow(0 2px 16px rgba(0,0,0,0.5))",
              }}
            />
          ) : (
            <span
              style={{
                color: brand.text_color ?? "#FFFFFF",
                fontFamily: brand.font_family ?? "Arial",
                fontWeight: 900,
                fontSize: 56,
                letterSpacing: "-0.02em",
              }}
            >
              {brand.company}
            </span>
          )}
        </div>

        {/* Divider */}
        <div
          style={{
            width: interpolate(reveal, [0.5, 1], [0, 160]),
            height: 3,
            backgroundColor: brand.accent_color ?? "#fff",
            borderRadius: 2,
          }}
        />

        {/* Social links */}
        {social && (
          <div
            style={{
              display: "flex",
              gap: 40,
              opacity: interpolate(socialReveal, [0, 1], [0, 1]),
              transform: `translateY(${interpolate(socialReveal, [0, 1], [20, 0])}px)`,
              flexWrap: "wrap",
              justifyContent: "center",
            }}
          >
            {Object.entries(social).map(([platform, handle]) => (
              <div key={platform} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <span
                  style={{
                    color: brand.accent_color ?? "#FFD700",
                    fontFamily: brand.font_family ?? "Arial",
                    fontWeight: 700,
                    fontSize: 18,
                    letterSpacing: "0.1em",
                    textTransform: "uppercase",
                  }}
                >
                  {platform}
                </span>
                <span
                  style={{
                    color: brand.text_color ?? "#FFFFFF",
                    fontFamily: brand.font_family ?? "Arial",
                    fontWeight: 500,
                    fontSize: 22,
                  }}
                >
                  {handle}
                </span>
              </div>
            ))}
          </div>
        )}

        {/* CTA */}
        <div
          style={{
            opacity: interpolate(ctaReveal, [0, 1], [0, 1]),
            transform: `translateY(${interpolate(ctaReveal, [0, 1], [16, 0])}px)`,
            backgroundColor: brand.accent_color ?? brand.primary_color,
            paddingLeft: 40,
            paddingRight: 40,
            paddingTop: 16,
            paddingBottom: 16,
            borderRadius: 50,
            marginTop: 8,
          }}
        >
          <span
            style={{
              color: "#000",
              fontFamily: brand.font_family ?? "Arial",
              fontWeight: 900,
              fontSize: 26,
              letterSpacing: "0.06em",
              textTransform: "uppercase",
            }}
          >
            Inscreva-se e ative o sino 🔔
          </span>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
