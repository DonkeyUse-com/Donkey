"use client";

import { ArrowRight, Smile } from "lucide-react";

import { PillButton } from "@/app/_components/landing/LandingPrimitives";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { BLACK } from "@/app/_components/landing/theme";

export function TopNav() {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  return (
    <nav
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: isDesktop ? "28px 48px" : "24px 24px",
        maxWidth: 1400,
        margin: "0 auto",
      }}
    >
      <a
        href="https://www.donkeyuse.com"
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          color: BLACK,
          textDecoration: "none",
        }}
      >
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: 8,
            background: BLACK,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Smile color="#fff" size={20} />
        </div>
        <span style={{ fontWeight: 900, fontSize: 24 }}>donkey</span>
      </a>
      <PillButton href="#download" variant="dark" size="sm">
        Download <ArrowRight size={14} />
      </PillButton>
    </nav>
  );
}
