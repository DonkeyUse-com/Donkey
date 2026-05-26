"use client";

import {
  Headline,
  NumberBadge,
  TapedCard,
} from "@/app/_components/landing/LandingPrimitives";
import { agentCards } from "@/app/_components/landing/data";
import { useMediaQuery } from "@/app/_components/landing/useMediaQuery";
import { BLACK, tagPill } from "@/app/_components/landing/theme";

export function Agents() {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  return (
    <section
      style={{
        padding: isDesktop ? "96px 48px" : "80px 24px",
        maxWidth: 1400,
        margin: "0 auto",
      }}
    >
      <Headline>
        A team of specialised agents.
        <br />
        <span style={{ fontStyle: "italic" }}>Always on your Mac.</span>
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
        Each Donkey agent is purpose-built for one slice of your day. They share
        context, hand off cleanly, and live quietly in the notch until you need
        them.
      </p>
      <div style={{ marginTop: 48 }}>
        <TapedCard color="coral" tapeColor="yellow">
          <div style={{ padding: isDesktop ? 48 : 28 }}>
            <div style={tagPill}>AI agents - The main act</div>
            <h3
              style={{
                fontWeight: 600,
                fontSize: isDesktop ? 42 : 32,
                lineHeight: 1.05,
                margin: "0 0 32px",
                maxWidth: 720,
              }}
            >
              Four agents, controlled by you, delivering better outcomes,
              faster.
            </h3>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: isDesktop ? "1fr 1fr" : "1fr",
                gap: 16,
              }}
            >
              {agentCards.map((agent) => (
                <div
                  key={agent.n}
                  style={{
                    borderRadius: 16,
                    background: "#fff",
                    border: `2px solid ${BLACK}`,
                    padding: 24,
                  }}
                >
                  <div
                    style={{
                      display: "flex",
                      alignItems: "flex-start",
                      gap: 16,
                    }}
                  >
                    <NumberBadge n={agent.n} color={agent.color} />
                    <div style={{ flex: 1, paddingTop: 4 }}>
                      <div
                        style={{
                          fontSize: 11,
                          fontWeight: 600,
                          letterSpacing: "0.1em",
                          textTransform: "uppercase",
                          color: "#666",
                          marginBottom: 6,
                        }}
                      >
                        {agent.tag}
                      </div>
                      <h4
                        style={{
                          fontWeight: 600,
                          fontSize: 22,
                          lineHeight: 1.15,
                          margin: "0 0 12px",
                        }}
                      >
                        {agent.title}
                      </h4>
                      <p
                        style={{
                          fontSize: 15,
                          lineHeight: 1.55,
                          color: "#333",
                          margin: 0,
                        }}
                      >
                        {agent.body}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </TapedCard>
      </div>
    </section>
  );
}
