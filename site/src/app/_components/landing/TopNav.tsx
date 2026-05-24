"use client";

import Image from "next/image";
import { ArrowRight } from "lucide-react";

import { PillButton } from "@/app/_components/landing/LandingPrimitives";
import { DONKEY_DOWNLOAD_URL } from "@/app/_components/landing/data";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { BLACK } from "@/app/_components/landing/theme";

type Props = {
  ctaHref?: string;
  ctaLabel?: string;
  homeHref?: string;
};

export function TopNav({
  ctaHref = DONKEY_DOWNLOAD_URL,
  ctaLabel = "Download",
  homeHref = "/",
}: Props) {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  return (
    <nav
      style={{
        display: "flex",
        alignItems: "center",
        boxSizing: "border-box",
        justifyContent: "space-between",
        padding: isDesktop ? "28px 48px" : "24px 24px",
        maxWidth: 1400,
        margin: "0 auto",
        width: "100%",
      }}
    >
      <a
        href={homeHref}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 0,
          color: BLACK,
          textDecoration: "none",
        }}
      >
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: 8,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            overflow: "hidden",
          }}
        >
          <Image
            src="/donkey-site-mark.webp"
            alt=""
            width={36}
            height={36}
            sizes="36px"
            style={{
              display: "block",
              width: "100%",
              height: "100%",
              objectFit: "cover",
            }}
          />
        </div>
        <span style={{ fontWeight: 900, fontSize: 24 }}>donkey</span>
      </a>
      <PillButton href={ctaHref} variant="dark" size="sm">
        {ctaLabel} <ArrowRight size={14} />
      </PillButton>
    </nav>
  );
}
