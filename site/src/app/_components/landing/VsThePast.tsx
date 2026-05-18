"use client";

import { Check, X } from "lucide-react";

import { Headline, SectionLabel } from "@/app/_components/landing/LandingPrimitives";
import { comparisonRows } from "@/app/_components/landing/data";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { BLACK, CARD, CORAL } from "@/app/_components/landing/theme";

type ComparisonCellProps = {
  ok: boolean;
};

function ComparisonCell({ ok }: ComparisonCellProps) {
  return (
    <div style={{ display: "flex", justifyContent: "center" }}>
      <div
        style={{
          width: 32,
          height: 32,
          borderRadius: 999,
          border: `2px solid ${BLACK}`,
          background: ok ? CARD.mint : CORAL,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {ok ? <Check size={16} strokeWidth={3} /> : <X size={16} strokeWidth={3} />}
      </div>
    </div>
  );
}

export function VsThePast() {
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const colWidths = isDesktop
    ? "1.6fr 0.9fr 0.9fr 0.9fr"
    : "1.45fr 0.8fr 0.8fr 0.8fr";

  return (
    <section
      style={{
        padding: isDesktop ? "96px 48px" : "80px 24px",
        maxWidth: 1400,
        margin: "0 auto",
      }}
    >
      <SectionLabel number={5}>A new category</SectionLabel>
      <Headline>
        Donkey vs <span style={{ fontStyle: "italic" }}>the rest.</span>
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
        You have been choosing between cloud chatbots that cannot touch your
        files and human assistants who cannot scale past 9-5. Donkey is the
        third option.
      </p>
      <div style={{ marginTop: 48, position: "relative", overflowX: "auto" }}>
        <div
          style={{
            position: "absolute",
            inset: 0,
            transform: "translate(6px, 6px)",
            borderRadius: 16,
            background: BLACK,
          }}
        />
        <div
          style={{
            position: "relative",
            minWidth: 620,
            borderRadius: 16,
            border: `2px solid ${BLACK}`,
            background: "#fff",
            overflow: "hidden",
          }}
        >
          <div
            style={{
              display: "grid",
              gridTemplateColumns: colWidths,
              borderBottom: `2px solid ${BLACK}`,
            }}
          >
            <div style={{ padding: isDesktop ? "24px" : "16px 12px" }}>
              <div
                style={{
                  fontSize: 11,
                  fontWeight: 800,
                  letterSpacing: "0.1em",
                  textTransform: "uppercase",
                  color: "#777",
                  marginBottom: 4,
                }}
              >
                The capability
              </div>
              <div style={{ fontWeight: 900, fontSize: isDesktop ? 20 : 15 }}>
                What you need
              </div>
            </div>
            {["ChatGPT", "Donkey", "Humans"].map((label) => (
              <div
                key={label}
                style={{
                  padding: isDesktop ? "24px 12px" : "16px 8px",
                  borderLeft: `2px solid ${BLACK}`,
                  textAlign: "center",
                  background: label === "Donkey" ? CORAL : "#fff",
                }}
              >
                <div style={{ fontSize: 11, fontWeight: 800, marginBottom: 4 }}>
                  {label === "ChatGPT" ? "A" : label === "Donkey" ? "B" : "C"}
                </div>
                <div style={{ fontWeight: 900, fontSize: isDesktop ? 18 : 14 }}>
                  {label}
                </div>
              </div>
            ))}
          </div>
          {comparisonRows.map((row) => (
            <div
              key={row.label}
              style={{
                display: "grid",
                gridTemplateColumns: colWidths,
                borderBottom: "1px solid rgba(0,0,0,0.1)",
              }}
            >
              <div
                style={{
                  padding: isDesktop ? "20px 24px" : "14px 12px",
                  fontWeight: 800,
                  fontSize: isDesktop ? 15 : 13,
                }}
              >
                {row.label}
              </div>
              <div
                style={{
                  padding: isDesktop ? "20px 12px" : "14px 8px",
                  borderLeft: `2px solid ${BLACK}`,
                }}
              >
                <ComparisonCell ok={row.gpts} />
              </div>
              <div
                style={{
                  padding: isDesktop ? "20px 12px" : "14px 8px",
                  borderLeft: `2px solid ${BLACK}`,
                  background: "rgba(236,120,104,0.1)",
                }}
              >
                <ComparisonCell ok={row.donkey} />
              </div>
              <div
                style={{
                  padding: isDesktop ? "20px 12px" : "14px 8px",
                  borderLeft: `2px solid ${BLACK}`,
                }}
              >
                <ComparisonCell ok={row.humans} />
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
