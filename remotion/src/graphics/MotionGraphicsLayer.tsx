import React from "react";
import { AbsoluteFill, Sequence, useVideoConfig } from "remotion";
import type { BrandConfig, GraphicCue } from "../brand/types";
import { LowerThird } from "./LowerThird";
import { KeywordBubble } from "./KeywordBubble";
import { QuoteCard } from "./QuoteCard";
import { TopicTitle } from "./TopicTitle";
import { LogoBug } from "./LogoBug";

type Props = {
  brand: BrandConfig;
  cues: GraphicCue[];
};

export const MotionGraphicsLayer: React.FC<Props> = ({ brand, cues }) => {
  const { fps } = useVideoConfig();

  const overlays = cues.filter(
    (c) => c.type !== "intro_bumper" && c.type !== "outro_bumper"
  );

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {/* Persistent logo watermark */}
      <LogoBug brand={brand} position="top-right" size={64} opacity={0.8} />

      {/* Time-coded graphic cues */}
      {overlays.map((cue, idx) => {
        const startFrame = Math.round(cue.start_s * fps);
        const durationFrames = Math.max(1, Math.round(cue.duration_s * fps));

        return (
          <Sequence
            key={idx}
            from={startFrame}
            durationInFrames={durationFrames}
            layout="none"
          >
            {cue.type === "lower_third" && (
              <LowerThird
                brand={brand}
                name={cue.content.name ?? ""}
                title={cue.content.title ?? ""}
                durationInFrames={durationFrames}
              />
            )}

            {cue.type === "keyword_bubble" && (
              <KeywordBubble
                brand={brand}
                keyword={cue.content.keyword ?? ""}
                context={cue.content.context}
                durationInFrames={durationFrames}
                side={idx % 2 === 0 ? "right" : "left"}
              />
            )}

            {cue.type === "quote_card" && (
              <QuoteCard
                brand={brand}
                quote={cue.content.quote ?? ""}
                author={cue.content.author}
                durationInFrames={durationFrames}
              />
            )}

            {cue.type === "topic_title" && (
              <TopicTitle
                brand={brand}
                title={cue.content.title ?? ""}
                durationInFrames={durationFrames}
              />
            )}
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
