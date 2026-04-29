export interface BrandConfig {
  company: string;
  primary_color: string;
  secondary_color: string;
  accent_color?: string;
  text_color?: string;
  font_family?: string;
  logo_path?: string;
  tagline?: string;
  social?: {
    instagram?: string;
    youtube?: string;
    linkedin?: string;
    website?: string;
  };
  host?: {
    name: string;
    title: string;
  };
}

export interface GraphicCue {
  type:
    | "intro_bumper"
    | "outro_bumper"
    | "lower_third"
    | "keyword_bubble"
    | "quote_card"
    | "topic_title";
  start_s: number;
  duration_s: number;
  content: Record<string, string>;
}

export interface BrandCues {
  cues: GraphicCue[];
}

export const defaultBrand: BrandConfig = {
  company: "Empresa",
  primary_color: "#1A1A2E",
  secondary_color: "#16213E",
  accent_color: "#E94560",
  text_color: "#FFFFFF",
  font_family: "Arial",
};
