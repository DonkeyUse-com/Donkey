"use client";

import {
  Headline,
  NumberBadge,
  SectionLabel,
  TapedCard,
} from "@/app/_components/landing/LandingPrimitives";
import { workflowSteps } from "@/app/_components/landing/data";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { BLACK } from "@/app/_components/landing/theme";

export function HowItWorks() {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  return (
    <section
      style={{
        padding: isDesktop ? "96px 48px" : "80px 24px",
        maxWidth: 1400,
        margin: "0 auto",
      }}
    >
      <SectionLabel number={4}>How it works</SectionLabel>
      <Headline>
        Ask. Watch. <span style={{ fontStyle: "italic" }}>Approve.</span>
      </Headline>
      <p
        style={{
          marginTop: 24,
          fontSize: 17,
          lineHeight: 1.55,
          maxWidth: 600,
          color: "#454545",
        }}
      >
        Donkey runs locally on your Mac. You stay in the loop on every important
        step, without being on the hook for every keystroke.
      </p>

      <div style={{ marginTop: 48, display: "grid", gap: 24 }}>
        {workflowSteps.map((step) => (
          <TapedCard
            key={step.n}
            color="cream"
            shadowColor="coral"
            tapeColor={step.color}
          >
            <div
              style={{
                padding: 24,
                display: "flex",
                alignItems: "flex-start",
                gap: 20,
              }}
            >
              <NumberBadge n={step.n} color={step.color} />
              <div style={{ flex: 1 }}>
                <h3
                  style={{
                    fontWeight: 900,
                    fontSize: 26,
                    lineHeight: 1.15,
                    margin: "0 0 8px",
                  }}
                >
                  {step.title}
                </h3>
                <p
                  style={{
                    fontSize: 15,
                    lineHeight: 1.55,
                    color: "#222",
                    margin: "0 0 12px",
                  }}
                >
                  {step.body}
                </p>
                <div
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    borderRadius: 999,
                    border: `2px solid ${BLACK}`,
                    padding: "4px 14px",
                    fontSize: 11,
                    fontWeight: 800,
                    letterSpacing: "0.08em",
                    textTransform: "uppercase",
                    background: "rgba(255,255,255,0.5)",
                  }}
                >
                  {step.timing}
                </div>
              </div>
            </div>
          </TapedCard>
        ))}
      </div>
    </section>
  );
}
