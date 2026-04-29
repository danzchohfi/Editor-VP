import React from "react";
import { Img, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import type { BrandConfig } from "../brand/types";

type Props = {
  brand: BrandConfig;
  position?: "top-left" | "top-right" | "bottom-left" | "bottom-right";
  size?: number;
  opacity?: number;
};

export const LogoBug: React.FC<Props> = ({
  brand,
  position = "top-right",
  size = 80,
  opacity = 0.85,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fadeIn = spring({
    fps,
    frame,
    config: { damping: 200, stiffness: 100, mass: 1 },
    durationInFrames: 20,
  });

  const positionStyles: Record<string, React.CSSProperties> = {
    "top-left": { top: 24, left: 24 },
    "top-right": { top: 24, right: 24 },
    "bottom-left": { bottom: 24, left: 24 },
    "bottom-right": { bottom: 24, right: 24 },
  };

  return (
    <div
      style={{
        position: "absolute",
        ...positionStyles[position],
        opacity: opacity * fadeIn,
        zIndex: 10,
      }}
    >
      {brand.logo_path ? (
        <Img
          src={brand.logo_path}
          style={{
            width: size,
            height: size,
            objectFit: "contain",
            filter: "drop-shadow(0 2px 8px rgba(0,0,0,0.6))",
          }}
        />
      ) : (
        <div
          style={{
            width: size * 2,
            height: size * 0.5,
            backgroundColor: brand.primary_color,
            borderRadius: 6,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: "0 12px",
          }}
        >
          <span
            style={{
              color: brand.text_color ?? "#fff",
              fontFamily: brand.font_family ?? "Arial",
              fontWeight: 900,
              fontSize: size * 0.3,
              letterSpacing: "0.04em",
              textTransform: "uppercase",
            }}
          >
            {brand.company}
          </span>
        </div>
      )}
    </div>
  );
};
