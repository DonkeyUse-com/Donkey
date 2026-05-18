"use client";

import { ArrowRight } from "lucide-react";

import { GITHUB_REPO_URL } from "@/app/_components/landing/data";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { BLACK, CREAM } from "@/app/_components/landing/theme";

export function TrustedBy() {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  return (
    <section
      style={{
        borderTop: `2px solid ${BLACK}`,
        borderBottom: `2px solid ${BLACK}`,
        background: CREAM,
      }}
    >
      <a
        href={GITHUB_REPO_URL}
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 16,
          maxWidth: 1400,
          margin: "0 auto",
          padding: isDesktop ? "20px 48px" : "18px 24px",
          color: BLACK,
          textDecoration: "none",
          flexWrap: "wrap",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 12,
            flexWrap: "wrap",
          }}
        >
          <span
            style={{
              fontSize: 12,
              fontWeight: 800,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              whiteSpace: "nowrap",
              background: BLACK,
              color: "#fff",
              padding: "4px 10px",
              borderRadius: 6,
            }}
          >
            Open source
          </span>
          <span style={{ fontSize: isDesktop ? 16 : 15, fontWeight: 700 }}>
            Donkey is Apache 2.0-licensed and built in the open.
          </span>
        </div>
        <span
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 6,
            fontSize: 14,
            fontWeight: 800,
          }}
        >
          View on GitHub <ArrowRight size={14} />
        </span>
      </a>
    </section>
  );
}
