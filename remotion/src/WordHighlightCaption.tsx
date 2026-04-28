import React, { useMemo } from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";

type WordSegment = {
  start: number;
  end: number;
  text: string;
  words: Array<{ word: string; start: number; end: number }>;
};

type Props = {
  segment: WordSegment;
  currentTimeMs: number;
  highlightColor: string;
  textColor: string;
  fontSize: number;
};

export const WordHighlightCaption: React.FC<Props> = ({
  segment,
  currentTimeMs,
  highlightColor,
  textColor,
  fontSize,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const segmentStartFrame = useMemo(
    () => Math.round((segment.start * fps)),
    [segment.start, fps]
  );

  const fadeIn = spring({
    fps,
    frame: frame - segmentStartFrame,
    config: { damping: 200, stiffness: 300, mass: 0.5 },
    durationInFrames: 8,
  });

  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        justifyContent: "center",
        alignItems: "center",
        gap: "0 12px",
        opacity: fadeIn,
        transform: `translateY(${interpolate(fadeIn, [0, 1], [12, 0])}px)`,
        maxWidth: "90%",
        textAlign: "center",
      }}
    >
      {segment.words.map((wordInfo, idx) => (
        <WordChip
          key={idx}
          wordInfo={wordInfo}
          currentTimeMs={currentTimeMs}
          highlightColor={highlightColor}
          textColor={textColor}
          fontSize={fontSize}
          fps={fps}
        />
      ))}
    </div>
  );
};

type WordChipProps = {
  wordInfo: { word: string; start: number; end: number };
  currentTimeMs: number;
  highlightColor: string;
  textColor: string;
  fontSize: number;
  fps: number;
};

const WordChip: React.FC<WordChipProps> = ({
  wordInfo,
  currentTimeMs,
  highlightColor,
  textColor,
  fontSize,
  fps,
}) => {
  const frame = useCurrentFrame();
  const wordStartFrame = Math.round(wordInfo.start * fps);

  const isActive =
    currentTimeMs >= wordInfo.start * 1000 &&
    currentTimeMs <= wordInfo.end * 1000;

  const isPast = currentTimeMs > wordInfo.end * 1000;

  const activePop = spring({
    fps,
    frame: isActive ? frame - wordStartFrame : 0,
    config: { damping: 180, stiffness: 400, mass: 0.4 },
    durationInFrames: 6,
  });

  const scale = isActive ? interpolate(activePop, [0, 1], [1, 1.08]) : 1;

  const bgColor = isActive
    ? highlightColor
    : isPast
    ? "rgba(255,255,255,0.15)"
    : "rgba(0,0,0,0.6)";

  const color = isActive ? "#000000" : isPast ? "rgba(255,255,255,0.55)" : textColor;

  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: bgColor,
        color,
        fontSize,
        fontFamily: "'Arial Black', 'Arial Bold', Arial, sans-serif",
        fontWeight: 900,
        padding: "6px 14px",
        borderRadius: 10,
        transform: `scale(${scale})`,
        transition: "background-color 0.1s",
        textShadow: isActive ? "none" : "0 2px 4px rgba(0,0,0,0.8)",
        letterSpacing: "-0.02em",
        lineHeight: 1.2,
        whiteSpace: "pre",
      }}
    >
      {wordInfo.word}
    </span>
  );
};
