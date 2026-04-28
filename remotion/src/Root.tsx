import React from "react";
import { Composition } from "remotion";
import { CaptionedVideo, CaptionedVideoSchema } from "./CaptionedVideo";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="CaptionedVideo"
        component={CaptionedVideo}
        durationInFrames={300}
        fps={30}
        width={1920}
        height={1080}
        schema={CaptionedVideoSchema}
        defaultProps={{
          videoSrc: "",
          wordTiming: [],
          durationInFrames: 300,
          fps: 30,
          width: 1920,
          height: 1080,
          highlightColor: "#FFD700",
          textColor: "#FFFFFF",
          fontSize: 52,
          wordsPerLine: 5,
          marginBottom: 80,
        }}
      />
    </>
  );
};
