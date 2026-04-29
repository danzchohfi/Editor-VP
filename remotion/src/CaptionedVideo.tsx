import React, { useMemo } from "react";
import { AbsoluteFill, OffthreadVideo, useCurrentFrame, useVideoConfig } from "remotion";
import { z } from "zod";
import { WordHighlightCaption } from "./WordHighlightCaption";
import { MotionGraphicsLayer } from "./graphics/MotionGraphicsLayer";
import type { BrandConfig, GraphicCue } from "./brand/types";
import { defaultBrand } from "./brand/types";

export const WordTimingSchema = z.array(
  z.object({
    start: z.number(),
    end: z.number(),
    text: z.string(),
    words: z.array(
      z.object({
        word: z.string(),
        start: z.number(),
        end: z.number(),
      })
    ),
  })
);

const GraphicCueSchema = z.object({
  type: z.enum(["intro_bumper", "outro_bumper", "lower_third", "keyword_bubble", "quote_card", "topic_title"]),
  start_s: z.number(),
  duration_s: z.number(),
  content: z.record(z.string()),
});

export const CaptionedVideoSchema = z.object({
  videoSrc: z.string(),
  wordTiming: WordTimingSchema,
  graphicCues: z.array(GraphicCueSchema).default([]),
  brand: z.record(z.any()).default({}),
  durationInFrames: z.number(),
  fps: z.number(),
  width: z.number(),
  height: z.number(),
  highlightColor: z.string().default("#FFD700"),
  textColor: z.string().default("#FFFFFF"),
  fontSize: z.number().default(52),
  wordsPerLine: z.number().default(5),
  marginBottom: z.number().default(80),
});

type Props = z.infer<typeof CaptionedVideoSchema>;

export const CaptionedVideo: React.FC<Props> = ({
  videoSrc,
  wordTiming,
  graphicCues,
  brand: brandRaw,
  highlightColor,
  textColor,
  fontSize,
  marginBottom,
}) => {
  const { fps } = useVideoConfig();
  const frame = useCurrentFrame();
  const currentTimeMs = (frame / fps) * 1000;

  const brand: BrandConfig = { ...defaultBrand, ...brandRaw };
  const cues = graphicCues as GraphicCue[];

  const activeSegment = useMemo(() => {
    return wordTiming.find(
      (seg) =>
        currentTimeMs >= seg.start * 1000 && currentTimeMs <= seg.end * 1000
    ) ?? null;
  }, [wordTiming, currentTimeMs]);

  return (
    <AbsoluteFill>
      {/* Base video */}
      {videoSrc && (
        <OffthreadVideo
          src={videoSrc}
          style={{ width: "100%", height: "100%", objectFit: "contain" }}
        />
      )}

      {/* Motion graphics overlays (lower thirds, keywords, quotes, logo) */}
      {cues.length > 0 && (
        <MotionGraphicsLayer brand={brand} cues={cues} />
      )}

      {/* Word-by-word caption overlay */}
      {activeSegment && (
        <AbsoluteFill
          style={{
            display: "flex",
            alignItems: "flex-end",
            justifyContent: "center",
            paddingBottom: marginBottom,
            paddingLeft: 60,
            paddingRight: 60,
          }}
        >
          <WordHighlightCaption
            segment={activeSegment}
            currentTimeMs={currentTimeMs}
            highlightColor={highlightColor}
            textColor={textColor}
            fontSize={fontSize}
          />
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};
