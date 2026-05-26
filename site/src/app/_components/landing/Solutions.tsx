"use client";

import {
  Headline,
  TapedCard,
} from "@/app/_components/landing/LandingPrimitives";
import { solutionCards } from "@/app/_components/landing/data";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { tagPill } from "@/app/_components/landing/theme";

export function Solutions() {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  return (
    <section
      style={{
        padding: isDesktop ? "96px 48px" : "80px 24px",
        maxWidth: 1400,
        margin: "0 auto",
      }}
    >
      <Headline>Built for the people who actually ship.</Headline>
      <p
        style={{
          marginTop: 24,
          fontSize: 17,
          lineHeight: 1.55,
          maxWidth: 600,
          color: "#454545",
        }}
      >
        Every role has its own grind. Donkey tunes the engine: research,
        drafting, ops, code, scheduling, to the way you actually work.
      </p>
      <div
        style={{
          marginTop: 48,
          display: "grid",
          gridTemplateColumns: isDesktop ? "1fr 1fr" : "1fr",
          gap: 24,
        }}
      >
        {solutionCards.map((card) => (
          <TapedCard key={card.tag} color={card.color} tapeColor="cream">
            <div style={{ padding: isDesktop ? "36px 32px 40px" : "28px" }}>
              <div style={tagPill}>{card.tag}</div>
              <h3
                style={{
                  fontWeight: 600,
                  fontSize: isDesktop ? 32 : 28,
                  lineHeight: 1.05,
                  margin: "0 0 16px",
                }}
              >
                {card.title}
              </h3>
              <p style={{ fontSize: 16, lineHeight: 1.55, color: "#222", margin: 0 }}>
                {card.body}
              </p>
            </div>
          </TapedCard>
        ))}
      </div>
    </section>
  );
}
